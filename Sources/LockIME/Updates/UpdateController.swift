import Foundation
import LockIMEKit
import Observation
import Sparkle

/// How a finished update check should be surfaced to the user.
enum UpdateCheckOutcome {
    case upToDate
    case failed(UpdateFailure)
    #if DEBUG
    /// A bare `make run` dev build declined to contact the real production feed
    /// (see `UpdateController.updatesDisabledForDevelopment`).
    case disabledInDevelopment
    #endif
}

/// Owns the Sparkle updater wired to our custom user driver.
///
/// Presentation is deferred to the host (`AppState`) via callbacks so a check
/// only opens the full window when an update actually exists; a clean "no
/// update" (or an error) surfaces as a lightweight toast instead — and only for
/// user-initiated checks, never for silent scheduled ones.
@MainActor
@Observable
final class UpdateController {
    let model = UpdateViewModel()

    /// Show the full update window (an update was found / is in progress).
    @ObservationIgnored var onPresentUpdateWindow: (() -> Void)?
    /// Surface the result of a finished user-initiated check (native alert).
    @ObservationIgnored var onCheckOutcome: ((UpdateCheckOutcome) -> Void)?

    /// The version of an update found by a *scheduled* check and awaiting a
    /// decision — drives the gentle "Update Available" menu affordance. `nil`
    /// when no update is pending.
    private(set) var pendingUpdateVersion: String?

    /// When the updater last completed a check (Sparkle-tracked), for the
    /// "Last checked" line in the Updates pane.
    var lastCheckDate: Date? { updater?.lastUpdateCheckDate }

    /// True while an update is actually installing/relaunching. The app's
    /// terminate guard consults this so Sparkle's install-and-relaunch is never
    /// vetoed — even when the menu bar icon is hidden (when a bare `terminate:`
    /// would be cancelled). Deliberately *not* `.readyToInstall`: that phase is the
    /// "install and relaunch?" prompt waiting on the user, which can stay up
    /// indefinitely, and during it a status-item hide must still keep the app alive
    /// (the hidden-icon veto) rather than be mistaken for a sanctioned relaunch.
    /// `.installing` is entered only once the user has committed (see
    /// `LockIMEUserDriver.showInstallingUpdate`).
    var isInstallingUpdate: Bool {
        switch model.phase {
        case .installing: return true
        default: return false
        }
    }

    @ObservationIgnored private let driver: LockIMEUserDriver
    @ObservationIgnored private let updaterDelegate = UpdaterDelegate()
    @ObservationIgnored private var updater: SPUUpdater?

    private(set) var canCheckForUpdates = false

    #if DEBUG
    /// A bare `make run` dev build must never reach the real production feed or
    /// install a stable release over the local build: its version is always
    /// `0.0.0-development`, so every check would "find" the newest stable and
    /// could replace the build under test. The update lab (`make update-test-*`)
    /// is the one exception — it redirects the feed to a loopback server via
    /// `LOCKIME_UPDATE_FEED` and deliberately exercises real download/install,
    /// so the presence of that env var is exactly what tells the lab apart from
    /// a plain run. Release builds never reach this property (compiled out).
    private var updatesDisabledForDevelopment: Bool {
        (ProcessInfo.processInfo.environment["LOCKIME_UPDATE_FEED"] ?? "").isEmpty
    }
    #endif

    init() {
        driver = LockIMEUserDriver(model: model)
        driver.onUpdateAvailable = { [weak self] in
            self?.pendingUpdateVersion = nil
            self?.onPresentUpdateWindow?()
        }
        driver.onGentleUpdateAvailable = { [weak self] version in
            self?.pendingUpdateVersion = version
        }
        driver.onUserCheckFinished = { [weak self] outcome in self?.onCheckOutcome?(outcome) }
        driver.onUpdateSessionEnded = { [weak self] in self?.pendingUpdateVersion = nil }
    }

    /// Build and start the updater. Fails gracefully if `SUPublicEDKey` is
    /// missing/invalid (updates simply stay unavailable).
    func start() {
        #if DEBUG
        if updatesDisabledForDevelopment {
            // Never start Sparkle in a plain dev build: no scheduled check can
            // fire and the production feed is never contacted. The manual
            // "Check for Updates…" button stays enabled and surfaces a
            // "disabled in development" notice instead (see `checkForUpdates`).
            canCheckForUpdates = true
            return
        }
        #endif
        let updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: driver,
            delegate: updaterDelegate
        )
        do {
            try updater.start()
            self.updater = updater
            canCheckForUpdates = true
            #if DEBUG
            // Update lab (`make update-test-*`): kick off a user-style check
            // right after launch so the scenario starts without a menu click.
            if ProcessInfo.processInfo.environment["LOCKIME_UPDATE_CHECK_ON_LAUNCH"] == "1" {
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(1))
                    self?.checkForUpdates()
                }
            }
            #endif
        } catch {
            canCheckForUpdates = false
        }
    }

    /// A user-initiated check. If a scheduled check already found an update
    /// (pending), open the window for it directly; otherwise start a fresh
    /// check — nothing is shown until the result is known (an available update
    /// opens the window; "up to date"/errors surface as a native alert).
    func checkForUpdates() {
        #if DEBUG
        if updatesDisabledForDevelopment {
            onCheckOutcome?(.disabledInDevelopment)
            return
        }
        #endif
        if pendingUpdateVersion != nil {
            onPresentUpdateWindow?()
        } else {
            updater?.checkForUpdates()
        }
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater?.automaticallyChecksForUpdates ?? false }
        set { updater?.automaticallyChecksForUpdates = newValue }
    }

    /// Re-resolve the feed after the channel preference changes. Any update the
    /// previous channel surfaced is now stale: reply-dismiss the gentle prompt
    /// still awaiting a choice (so Sparkle isn't left hanging on an orphaned
    /// reply) and drop the "update available" indicator. Only a fresh check on
    /// the newly selected channel re-badges it — and only if that channel
    /// actually has an update.
    func channelDidChange() {
        model.dismissReply()
        pendingUpdateVersion = nil
        updater?.resetUpdateCycle()
    }
}

/// Reads the beta-channel preference from `UserDefaults` (written by the Updates
/// settings pane via `@AppStorage`) — no shared mutable state.
final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        let usesBeta = UserDefaults.standard.bool(forKey: "usesBetaChannel")
        return UpdateChannel.allowedChannels(for: .from(usesBeta: usesBeta))
    }

    /// Each architecture is its own product with its own feed — we ship
    /// single-arch apps and don't support cross-arch updates — so the feed
    /// choice is pinned at compile time, where no build/CI misconfiguration
    /// can reach it: an x86_64 binary can only ever see x86_64 updates.
    /// arm64 returns `nil` to fall back to the Info.plist `SUFeedURL`
    /// (`appcast.xml`) — the URL every already-shipped arm64 build reads,
    /// which therefore must keep serving arm64-only entries forever (see
    /// docs/RELEASING.md).
    func feedURLString(for updater: SPUUpdater) -> String? {
        #if DEBUG
        // Update lab (`make update-test-*`): point the updater at a loopback
        // feed without touching the shipped `SUFeedURL`. Release builds never
        // consult the environment.
        if let feed = ProcessInfo.processInfo.environment["LOCKIME_UPDATE_FEED"],
           !feed.isEmpty {
            return feed
        }
        #endif
        #if arch(x86_64)
        return "https://oomol-lab.github.io/LockIME/appcast-x86_64.xml"
        #else
        return nil
        #endif
    }
}
