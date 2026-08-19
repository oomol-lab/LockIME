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
            // `bundleURL` is nil for a process launched from a bare executable
            // rather than an `.app` wrapper — e.g. Minecraft's `java`, whose
            // bundle ID comes from the binary's embedded Info.plist. Those are
            // exactly the processes a user can't find anywhere else, so fall
            // back to the executable path instead of dropping them.
            guard let id = running.bundleIdentifier,
                  let url = running.bundleURL ?? running.executableURL
            else { continue }
            // …but not XPC service helpers (WebKit's per-app "Web Content"
            // renderers and the like, which also surface as bare processes):
            // they can never become the frontmost app, so a rule could never
            // apply — listing them would only mislead. Matched structurally by
            // the `.xpc` bundle in the executable path, plus the WebKit helper
            // ID prefix — some WebContent processes report only a *relative*
            // executable path, which the structural check cannot see.
            if running.bundleURL == nil,
               url.path.contains(".xpc/") || id.hasPrefix("com.apple.WebKit.") {
                continue
            }
            guard seen.insert(id).inserted else { continue }
            apps.append(InstalledApp(bundleID: id, name: running.localizedName ?? id, path: url.path))
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
