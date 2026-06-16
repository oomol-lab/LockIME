import Foundation
import LockIMEKit
import OSLog
import Sparkle

/// Custom Sparkle user driver: maps the closure-based `SPUUserDriver` callbacks
/// onto our SwiftUI `UpdateViewModel`. (`SPUUserDriver` is `NS_SWIFT_UI_ACTOR`.)
@MainActor
final class LockIMEUserDriver: NSObject, SPUUserDriver {
    private static let log = Logger(subsystem: LogSubsystem.current, category: "Updater")

    private let model: UpdateViewModel
    private var expectedLength: UInt64 = 0
    private var receivedLength: UInt64 = 0
    /// When the first download bytes arrived, for the average-speed readout.
    private var downloadStart: ContinuousClock.Instant?
    /// When the byte/speed readout was last pushed to the model. The bar
    /// fraction updates on every chunk, but the textual readout only ticks
    /// once a second (Apple-style) so the line doesn't flicker and resize.
    private var lastReadoutAt: ContinuousClock.Instant?
    private let clock = ContinuousClock()

    /// Whether the in-flight check was started by the user (vs. a silent
    /// scheduled check). Only user checks surface a "no update"/error toast.
    private var userInitiated = false

    /// Fired when a *user-initiated* check finds an update and the full window
    /// should be shown immediately.
    var onUpdateAvailable: (() -> Void)?
    /// Fired when a *scheduled/background* check finds an update — surface it
    /// gently (badge the menu) instead of stealing focus with a window.
    var onGentleUpdateAvailable: ((String) -> Void)?
    /// Fired when a *user-initiated* check finishes with no update or an error.
    var onUserCheckFinished: ((UpdateCheckOutcome) -> Void)?
    /// Fired when an update session ends (installed or dismissed) so any pending
    /// "update available" indicator can be cleared.
    var onUpdateSessionEnded: (() -> Void)?

    /// Opt into Sparkle's gentle scheduled-reminder model: scheduled finds are
    /// handed to us to surface non-modally rather than auto-presented.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    #if DEBUG
    /// Update lab (`UPDATE_LAB_AUTO=1 make update-test-…`): auto-accept the
    /// install prompts so the success scenario runs hands-free.
    private let autoInstall =
        ProcessInfo.processInfo.environment["LOCKIME_UPDATE_AUTO_INSTALL"] == "1"
    #endif

    init(model: UpdateViewModel) {
        self.model = model
    }

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        userInitiated = true
        model.phase = .checking
        model.dismissAction = cancellation
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        // A prior (gentle, scheduled) "update found" prompt may still be awaiting
        // a reply — e.g. two scheduled checks find updates before the user acts.
        // Reply-dismiss it before installing the new reply blocks so Sparkle never
        // hangs on an orphaned reply (it requires exactly one reply per prompt).
        model.dismissReply()

        userInitiated = false
        model.availableVersion = appcastItem.displayVersionString
        model.publishedDate = appcastItem.date
        model.isBetaChannel = appcastItem.channel == UpdateChannel.beta.rawValue
        if let notes = appcastItem.itemDescription, !notes.isEmpty {
            model.releaseNotesMarkdown = notes
        }
        model.phase = .found(version: appcastItem.displayVersionString)
        model.installAction = { reply(.install) }
        model.skipAction = { reply(.skip) }
        model.dismissAction = { reply(.dismiss) }
        if state.userInitiated {
            onUpdateAvailable?()
        } else {
            onGentleUpdateAvailable?(appcastItem.displayVersionString)
        }
        #if DEBUG
        if autoInstall { model.install() }
        #endif
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        if let text = String(data: downloadData.data, encoding: .utf8), !text.isEmpty {
            model.releaseNotesMarkdown = text
        }
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error) async {
        model.phase = .upToDate
        if userInitiated { onUserCheckFinished?(.upToDate) }
        userInitiated = false
    }

    func showUpdaterError(_ error: any Error) async {
        // Sparkle's `localizedDescription` follows the *system* language, not
        // the in-app override — never display it. Map to a semantic category
        // (resolved in the app language at render time) and log the original.
        Self.log.error("Updater error: \(error as NSError, privacy: .public)")
        let failure = UpdateFailure(error)
        model.phase = .error(failure)
        if userInitiated { onUserCheckFinished?(.failed(failure)) }
        userInitiated = false
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        expectedLength = 0
        receivedLength = 0
        downloadStart = nil
        lastReadoutAt = nil
        model.downloadedBytes = 0
        model.expectedBytes = 0
        model.downloadSpeed = 0
        model.phase = .downloading(fraction: 0)
        model.dismissAction = cancellation
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedLength = expectedContentLength
        model.expectedBytes = expectedContentLength
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        let now = clock.now
        if downloadStart == nil { downloadStart = now }
        receivedLength += length

        if lastReadoutAt == nil || lastReadoutAt!.duration(to: now) >= .seconds(1) {
            lastReadoutAt = now
            model.downloadedBytes = receivedLength
            if let start = downloadStart {
                let elapsed = start.duration(to: now)
                let seconds = Double(elapsed.components.seconds)
                    + Double(elapsed.components.attoseconds) / 1e18
                // Wait for a sane sample window so the first chunks don't read
                // as an absurd burst speed.
                if seconds > 0.5 {
                    model.downloadSpeed = Double(receivedLength) / seconds
                }
            }
        }

        let fraction = expectedLength > 0 ? Double(receivedLength) / Double(expectedLength) : 0
        model.phase = .downloading(fraction: min(1, fraction))
    }

    func showDownloadDidStartExtractingUpdate() {
        model.phase = .extracting(fraction: 0)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        model.phase = .extracting(fraction: progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        model.phase = .readyToInstall
        model.installAction = { reply(.install) }
        model.dismissAction = { reply(.dismiss) }
        #if DEBUG
        if autoInstall { model.install() }
        #endif
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        model.phase = .installing
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool) async {
        model.reset()
        onUpdateSessionEnded?()
    }

    func dismissUpdateInstallation() {
        // Sparkle ends the session right after `showUpdaterError`; a full reset
        // here would blank the window back to idle before the user can read
        // the message, so keep a just-shown error on screen.
        if case .error = model.phase {
            model.clearReplies()
        } else {
            model.reset()
        }
        onUpdateSessionEnded?()
    }

    func showUpdateInFocus() {}
}
