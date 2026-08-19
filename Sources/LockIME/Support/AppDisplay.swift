import AppKit

extension NSImage {
    /// LockIME's own app icon, loaded robustly from the bundled `AppIcon.icns`
    /// (present whenever the asset-catalog app icon is compiled), falling back to
    /// the running application's icon. Avoids the generic placeholder that
    /// `NSApp.applicationIconImage` can return before LaunchServices registers
    /// the bundle (e.g. when launched directly rather than via Finder).
    @MainActor static var lockIMEAppIcon: NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            return icon
        }
        return NSApp.applicationIconImage ?? NSImage()
    }

    /// The app icon pre-masked to the icon-grid rounded rect, for AppKit
    /// surfaces that draw the image verbatim (NSAlert): the raw `.icns` art is
    /// full-bleed, and an unmasked blue square looks jarring there.
    @MainActor static var lockIMEAppIconRounded: NSImage {
        let base = lockIMEAppIcon
        let side: CGFloat = 256
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: side * 0.2237, yRadius: side * 0.2237).addClip()
            base.draw(in: rect)
            return true
        }
    }
}

/// Resolves a display name and icon for a bundle identifier, for the rules UI.
@MainActor
enum AppDisplay {
    static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            // Not an installed `.app` — a bare-executable process (e.g.
            // Minecraft's `java`) still shows its live name while running.
            return runningApplication(for: bundleID)?.localizedName ?? bundleID
        }
        let bundle = Bundle(url: url)
        return (bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle?.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle?.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
    }

    static func icon(for bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return runningApplication(for: bundleID)?.icon
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private static func runningApplication(for bundleID: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
    }
}
