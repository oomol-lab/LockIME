import Foundation

/// Known browser bundle identifiers, used to decide when to read a URL.
///
/// URL reading is **Accessibility-based** and therefore browser-dependent:
/// - **Safari** exposes the active tab's URL on its `AXWebArea` (`AXURL`).
/// - **Chromium** browsers (Chrome, Edge, Brave, Arc, Vivaldi, Opera) expose it
///   too, but only after their accessibility tree is enabled via the
///   `AXManualAccessibility` attribute (they build it lazily). See `chromium`.
/// - **Firefox is not supported**: it does not expose the tab URL through the
///   macOS Accessibility API at all.
public enum BrowserBundleIDs {
    /// Chromium-based browsers. These need `AXManualAccessibility` set on the
    /// app element before `AXURL` becomes readable.
    public static let chromium: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser", // Arc
        "com.brave.Browser",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
    ]

    /// Browsers whose URL we can read via Accessibility (Safari + Chromium).
    /// Firefox is intentionally excluded — it exposes no tab URL over AX.
    public static let all: Set<String> = chromium.union([
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
    ])

    public static func isBrowser(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return all.contains(bundleID)
    }

    public static func isChromium(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return chromium.contains(bundleID)
    }
}

/// Pure host extraction and pattern matching for per-URL rules.
public enum URLMatcher {
    /// The host of a URL string, lowercased (`https://Gist.GitHub.com/x` → `gist.github.com`).
    public static func host(from urlString: String) -> String? {
        guard !urlString.isEmpty else { return nil }
        let host = URLComponents(string: urlString)?.host ?? URL(string: urlString)?.host
        return host?.lowercased()
    }

    /// The first rule whose pattern matches `host`, or `nil`.
    public static func matchedRule(host: String?, rules: [URLRule]) -> URLRule? {
        guard let host = host?.lowercased(), !host.isEmpty else { return nil }
        return rules.first { matches(host: host, pattern: $0.hostPattern) }
    }

    /// The locked source of the first rule whose pattern matches `host`.
    public static func match(host: String?, rules: [URLRule]) -> InputSourceID? {
        matchedRule(host: host, rules: rules)?.lockedSourceID
    }

    /// A pattern matches a host if equal, a parent domain, or a `*.` wildcard.
    /// `github.com` matches `github.com` and `gist.github.com`.
    static func matches(host: String, pattern rawPattern: String) -> Bool {
        var pattern = rawPattern.lowercased().trimmingCharacters(in: .whitespaces)
        if pattern.hasPrefix("*.") { pattern.removeFirst(2) }
        guard !pattern.isEmpty else { return false }
        return host == pattern || host.hasSuffix("." + pattern)
    }
}
