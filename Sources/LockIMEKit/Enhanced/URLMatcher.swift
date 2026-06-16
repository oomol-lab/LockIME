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
///
/// Matching is **type-directed** (`URLRule.matchType`): the three domain types
/// look only at the URL's host, while `urlRegex` matches the *whole* URL string
/// (scheme/host/path/query/fragment) — the only type that can tell two pages of
/// one site apart. Rules are evaluated top-to-bottom; the first that matches
/// wins, so list order is the rule priority.
public enum URLMatcher {
    /// The host of a URL string, lowercased (`https://Gist.GitHub.com/x` → `gist.github.com`).
    public static func host(from urlString: String) -> String? {
        guard !urlString.isEmpty else { return nil }
        let host = URLComponents(string: urlString)?.host ?? URL(string: urlString)?.host
        return host?.lowercased()
    }

    /// The first rule (in list order) matching `urlString`, or `nil`.
    ///
    /// The host is derived once and shared by the domain-family types; `urlRegex`
    /// ignores it and matches the raw URL. An empty/authority-less URL still lets
    /// a `urlRegex` rule run (it may match `about:`-style URLs), but the domain
    /// types short-circuit to no-match without a host.
    public static func matchedRule(urlString: String, rules: [URLRule]) -> URLRule? {
        let host = host(from: urlString)
        return rules.first { matches(rule: $0, urlString: urlString, host: host) }
    }

    /// The locked source of the first rule matching `urlString`.
    public static func match(urlString: String, rules: [URLRule]) -> InputSourceID? {
        matchedRule(urlString: urlString, rules: rules)?.lockedSourceID
    }

    /// Whether `rule` matches the URL, dispatching on the rule's match type.
    /// `host` is the pre-extracted, lowercased host (or `nil` when the URL has no
    /// authority) so callers iterating many rules extract it once.
    static func matches(rule: URLRule, urlString: String, host: String?) -> Bool {
        switch rule.matchType {
        case .domainSuffix:
            guard let host else { return false }
            return matchesSuffix(host: host, pattern: rule.hostPattern)
        case .domain:
            guard let host else { return false }
            let pattern = normalizedHostPattern(rule.hostPattern)
            // An empty normalized pattern (a blank or `*.`-only rule) must not match
            // an empty-host URL — fail closed, mirroring `matchesSuffix`.
            guard !pattern.isEmpty else { return false }
            return host == pattern
        case .domainKeyword:
            guard let host else { return false }
            let keyword = rule.hostPattern.lowercased().trimmingCharacters(in: .whitespaces)
            return !keyword.isEmpty && host.contains(keyword)
        case .urlRegex:
            return matchesRegex(urlString, pattern: rule.hostPattern)
        }
    }

    /// A pattern matches a host if equal, a parent domain, or a `*.` wildcard.
    /// `github.com` matches `github.com` and `gist.github.com`.
    static func matchesSuffix(host: String, pattern rawPattern: String) -> Bool {
        let pattern = normalizedHostPattern(rawPattern)
        guard !pattern.isEmpty else { return false }
        return host == pattern || host.hasSuffix("." + pattern)
    }

    /// Lowercase + trim a host pattern and drop a leading `*.` so `*.google.com`
    /// and `google.com` normalize alike.
    private static func normalizedHostPattern(_ rawPattern: String) -> String {
        var pattern = rawPattern.lowercased().trimmingCharacters(in: .whitespaces)
        if pattern.hasPrefix("*.") { pattern.removeFirst(2) }
        return pattern
    }

    /// Upper bound on the URL length a `urlRegex` rule will match against. Real
    /// URLs are far shorter; this only caps the regex engine's worst-case
    /// backtracking against a pathologically long input.
    static let maxRegexURLLength = 8192

    /// Whether `urlString` contains a match for `pattern` (unanchored,
    /// case-insensitive). An empty or invalid pattern never matches — a
    /// half-typed or broken regex must not silently match every URL.
    ///
    /// The match is **length-bounded**: a user-authored pattern runs against the
    /// live browser URL synchronously on the main actor (the URL poll), so an
    /// absurdly long URL is rejected outright (fail-closed — no match) to bound
    /// the engine's backtracking cost. The bound counts **UTF-16 code units** —
    /// the unit `NSRange`/the ICU engine actually scans — not graphemes, so a
    /// short-grapheme/long-code-unit string can't slip past it. This caps the
    /// long-input amplification vector; it is *not* full ReDoS protection — a
    /// pathological pattern (e.g. `(a+)+$`) can still backtrack for a long time on a
    /// *short* URL, blocking the poll's main actor. The pattern is the user's own,
    /// so this is an accepted residual; bounding *that* would require evaluating the
    /// match off the main actor with a wall-clock deadline.
    static func matchesRegex(_ urlString: String, pattern: String) -> Bool {
        guard !pattern.isEmpty, !urlString.isEmpty, urlString.utf16.count <= maxRegexURLLength,
              let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else { return false }
        let range = NSRange(urlString.startIndex..., in: urlString)
        return regex.firstMatch(in: urlString, range: range) != nil
    }

    /// Whether `pattern` is a valid regular expression — for the editor to warn
    /// before a `urlRegex` rule is saved (an invalid pattern matches nothing).
    public static func isValidRegex(_ pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern)) != nil
    }
}
