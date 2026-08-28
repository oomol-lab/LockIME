import AppKit
import Foundation

/// A discoverable installed application, for the per-app rule picker.
public struct InstalledApp: Identifiable, Sendable, Hashable {
    public let bundleID: String
    public let name: String
    public let path: String
    public var id: String { bundleID }

    public init(bundleID: String, name: String, path: String) {
        self.bundleID = bundleID
        self.name = name
        self.path = path
    }
}

/// Enumerates installed apps from the standard application directories plus
/// currently-running apps. Needs no special permission (unlike a global
/// Spotlight scan, which may require Full Disk Access).
public enum InstalledAppsScanner {
    private static let directories: [String] = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        (NSString(string: "~/Applications").expandingTildeInPath),
    ]

    @MainActor
    public static func scan() -> [InstalledApp] {
        var seen = Set<String>()
        var apps: [InstalledApp] = []
        let fileManager = FileManager.default

        for directory in directories {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: directory) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let path = (directory as NSString).appendingPathComponent(entry)
                guard let bundle = Bundle(path: path),
                      let id = bundle.bundleIdentifier,
                      seen.insert(id).inserted
                else { continue }
                apps.append(InstalledApp(bundleID: id, name: displayName(bundle, fallback: entry), path: path))
            }
        }

        for running in NSWorkspace.shared.runningApplications {
            // `ruleIdentity`, not `bundleIdentifier`: a process launched from a
            // bare executable rather than an `.app` wrapper — e.g. Minecraft's
            // `java`, spawned by a third-party launcher — has NO bundle ID (and
            // no `bundleURL`), yet is exactly the process a user can't find
            // anywhere else. It gets the same synthetic `process:<name>`
            // identity the frontmost monitor reports, so a rule keyed on this
            // row actually matches at runtime.
            guard let id = running.ruleIdentity else { continue }
            // Purely informational (`InstalledApp.path` has no consumer beyond
            // construction — the manual bundle-ID escape hatch passes "" too),
            // so a URL-less process still gets its row rather than vanishing
            // from the picker while the monitor would happily match it.
            let url = running.bundleURL ?? running.executableURL
            // A bundle-less process that can't be activated can never be the
            // frontmost app, so a rule could never apply (same argument as the
            // XPC helpers below). Bundled apps keep the old behavior — listed
            // regardless of policy.
            if running.bundleIdentifier == nil, running.activationPolicy == .prohibited { continue }
            // …but not XPC service helpers (WebKit's per-app "Web Content"
            // renderers and the like): they can never become the frontmost
            // app, so a rule could never apply — listing them would only
            // mislead. Matched structurally by an `.xpc` bundle in *either*
            // URL (some services do report a bundle URL), plus the WebKit
            // helper ID prefix — some WebContent processes report only a
            // *relative* executable path, which the structural check cannot see.
            let isXPCService = [running.bundleURL, running.executableURL].contains { candidate in
                candidate?.pathComponents.contains { $0.hasSuffix(".xpc") } ?? false
            }
            if isXPCService || id.hasPrefix("com.apple.WebKit.") { continue }
            guard seen.insert(id).inserted else { continue }
            apps.append(
                InstalledApp(
                    bundleID: id,
                    // For a nameless bundle-less process, the bare executable
                    // name reads better than the raw `process:`-prefixed ID.
                    name: running.localizedName ?? ProcessIdentity.executableName(from: id) ?? id,
                    path: url?.path ?? ""
                )
            )
        }

        // Launcher overlays are rule targets even when their process is not
        // running and they live outside the scanned directories. Spotlight is
        // the case that matters: it was only ever discoverable as a *running*
        // app (`/System/Library/CoreServices` is not scanned), and macOS 27 no
        // longer runs it at all — the Siri AI process draws its panel — yet
        // `com.apple.Spotlight` remains the identity a Spotlight rule keys on
        // (`LauncherOverlayCatalog`). Resolve each catalog entry through Launch
        // Services so an installed-but-idle launcher still gets its row.
        for bundleID in LauncherOverlayCatalog.bundleIDs where !seen.contains(bundleID) {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
                  let bundle = Bundle(url: url)
            else { continue }
            seen.insert(bundleID)
            apps.append(
                InstalledApp(
                    bundleID: bundleID,
                    name: displayName(bundle, fallback: url.lastPathComponent),
                    path: url.path
                )
            )
        }

        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func displayName(_ bundle: Bundle, fallback entry: String) -> String {
        (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? (entry as NSString).deletingPathExtension
    }
}
