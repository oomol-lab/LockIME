import Foundation

/// Known browser bundle identifiers, used to decide when to read a URL.
///
/// URL reading is **Accessibility-based** and therefore browser-dependent. Each
/// supported engine exposes the active tab's URL as `AXURL` on its `AXWebArea`;
/// they differ only in how that tree is brought up for a non-VoiceOver client:
/// - **Safari** keeps its accessibility tree live — no opt-in needed.
/// - **Chromium** browsers (Chrome, Edge, Brave, Arc, Vivaldi, Opera) build it
///   lazily and expose it once `AXManualAccessibility` is set on the app
///   element. See `chromium`.
/// - **Gecko** browsers (Firefox and forks such as Zen) also build it lazily,
///   but honor a different wake signal — `AXEnhancedUserInterface` on the app
///   element — and do not implement `AXManualAccessibility`. The tree is built
///   asynchronously after the wake, so the first read may be empty. See `gecko`.
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

    /// Gecko-based browsers (Firefox and current-Firefox forks such as Zen,
    /// Floorp, and Waterfox). These need `AXEnhancedUserInterface` set on the
    /// app element to wake their lazily-built accessibility tree before `AXURL`
    /// becomes readable; they do not implement Chromium's `AXManualAccessibility`.
    public static let gecko: Set<String> = [
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",
        "app.zen-browser.zen",
        "app.floorp.Floorp",
        "net.waterfox.waterfox",
        // Privacy/anonymity-focused Firefox forks. Same current-Gecko engine, so
        // the `AXEnhancedUserInterface` wake applies; reading their URL requires
        // waking accessibility, which these users may not expect — included here
        // deliberately so per-URL rules can cover them.
        "io.gitlab.librewolf-community.librewolf",
        "org.torproject.torbrowser",
        "net.mullvad.mullvadbrowser",
    ]

    /// Browsers whose URL we can read via Accessibility (Safari + Chromium + Gecko).
    public static let all: Set<String> = chromium.union(gecko).union([
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

    public static func isGecko(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return gecko.contains(bundleID)
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
