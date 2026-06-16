import Testing

@testable import LockIMEKit

@Suite("URLMatcher")
struct URLMatcherTests {
    private let pinyin: InputSourceID = "com.apple.inputmethod.SCIM.ITABC"
    private let us: InputSourceID = "com.apple.keylayout.US"

    @Test("extracts and lowercases the host", arguments: [
        ("https://Gist.GitHub.com/foo", "gist.github.com"),
        ("http://example.com/path?q=1", "example.com"),
        ("https://docs.google.com", "docs.google.com"),
    ])
    func hostExtraction(url: String, expected: String) {
        #expect(URLMatcher.host(from: url) == expected)
    }

    @Test("empty / invalid / authority-less URLs have no host")
    func noHost() {
        #expect(URLMatcher.host(from: "") == nil)
        #expect(URLMatcher.host(from: "not a url") == nil)
        // Browser placeholder pages carry no authority, so a domain rule can
        // never false-match them — a Firefox new tab surfaces as about:newtab,
        // not a real host. (We rely on a nil host here rather than normalizing
        // these scheme-by-scheme.)
        #expect(URLMatcher.host(from: "about:newtab") == nil)
        #expect(URLMatcher.host(from: "about:blank") == nil)
    }

    // MARK: Domain-suffix (the default, original behavior)

    @Test("domain suffix matches the host and its subdomains (default type)")
    func domainSuffix() {
        let rules = [URLRule(hostPattern: "github.com", lockedSourceID: us)]
        #expect(URLMatcher.match(urlString: "https://github.com/x", rules: rules) == us)
        #expect(URLMatcher.match(urlString: "https://gist.github.com/y", rules: rules) == us)
        #expect(URLMatcher.match(urlString: "https://notgithub.com/", rules: rules) == nil)
        #expect(URLMatcher.match(urlString: "https://example.com/", rules: rules) == nil)
        // The default match type is domainSuffix, so a rule built without one
        // behaves exactly as before this feature existed.
        #expect(URLRule(hostPattern: "x", lockedSourceID: us).matchType == .domainSuffix)
    }

    @Test("wildcard suffix pattern matches base and subdomains")
    func wildcard() {
        let rules = [URLRule(hostPattern: "*.google.com", lockedSourceID: pinyin)]
        #expect(URLMatcher.match(urlString: "https://google.com", rules: rules) == pinyin)
        #expect(URLMatcher.match(urlString: "https://mail.google.com", rules: rules) == pinyin)
        #expect(URLMatcher.match(urlString: "https://evilgoogle.com", rules: rules) == nil)
    }

    // MARK: Exact domain

    @Test("exact domain matches only the host, never a subdomain")
    func exactDomain() {
        let rules = [URLRule(hostPattern: "github.com", lockedSourceID: us, matchType: .domain)]
        #expect(URLMatcher.match(urlString: "https://github.com/x", rules: rules) == us)
        #expect(URLMatcher.match(urlString: "https://gist.github.com/x", rules: rules) == nil)
        // Host comparison is case-insensitive; a leading `*.` normalizes away too.
        #expect(URLMatcher.match(urlString: "https://GitHub.com/x", rules: rules) == us)
        let wild = [URLRule(hostPattern: "*.github.com", lockedSourceID: us, matchType: .domain)]
        #expect(URLMatcher.match(urlString: "https://github.com/x", rules: wild) == us)
    }

    @Test("an exact-domain rule with a blank or `*.`-only pattern never matches (fails closed)")
    func exactDomainBlankPattern() {
        // "  " and "*." both normalize to an empty host pattern. A non-empty host can
        // never equal "", and crucially an empty host must NOT match either — mirror
        // domain-suffix's empty-pattern guard so a blank rule can't silently match.
        for pat in ["  ", "*.", ""] {
            let rules = [URLRule(hostPattern: pat, lockedSourceID: us, matchType: .domain)]
            #expect(URLMatcher.match(urlString: "https://github.com/x", rules: rules) == nil)
            // Directly exercise the empty-host short-circuit (the regression):
            // without the guard, "" == "" would true-match.
            #expect(!URLMatcher.matches(rule: rules[0], urlString: "", host: ""))
        }
    }

    // MARK: Domain keyword

    @Test("domain keyword matches any host containing the keyword")
    func domainKeyword() {
        let rules = [URLRule(hostPattern: "google", lockedSourceID: pinyin, matchType: .domainKeyword)]
        #expect(URLMatcher.match(urlString: "https://google.com", rules: rules) == pinyin)
        #expect(URLMatcher.match(urlString: "https://mail.google.com", rules: rules) == pinyin)
        #expect(URLMatcher.match(urlString: "https://googleapis.com", rules: rules) == pinyin)
        #expect(URLMatcher.match(urlString: "https://example.com", rules: rules) == nil)
        // An empty/whitespace keyword never matches (it would otherwise match all).
        let blank = [URLRule(hostPattern: "  ", lockedSourceID: us, matchType: .domainKeyword)]
        #expect(URLMatcher.match(urlString: "https://example.com", rules: blank) == nil)
    }

    // MARK: URL regex (the only type that sees past the host)

    @Test("url regex matches the whole URL including path, query, and fragment")
    func urlRegex() {
        let pull = [URLRule(hostPattern: "github\\.com/[^/]+/[^/]+/pull/", lockedSourceID: us, matchType: .urlRegex)]
        #expect(URLMatcher.match(urlString: "https://github.com/owner/repo/pull/42", rules: pull) == us)
        #expect(URLMatcher.match(urlString: "https://github.com/owner/repo/issues/42", rules: pull) == nil)
        // Query and fragment are part of the matched string.
        let query = [URLRule(hostPattern: "tab=settings", lockedSourceID: pinyin, matchType: .urlRegex)]
        #expect(URLMatcher.match(urlString: "https://app.example.com/x?tab=settings#a", rules: query) == pinyin)
        let fragment = [URLRule(hostPattern: "#section-3$", lockedSourceID: pinyin, matchType: .urlRegex)]
        #expect(URLMatcher.match(urlString: "https://app.example.com/x#section-3", rules: fragment) == pinyin)
    }

    @Test("url regex is case-insensitive and unanchored")
    func urlRegexFlags() {
        // Uppercase pattern matches a lowercase path (case-insensitive), anywhere
        // in the URL (unanchored).
        let rules = [URLRule(hostPattern: "ADMIN", lockedSourceID: us, matchType: .urlRegex)]
        #expect(URLMatcher.match(urlString: "https://example.com/admin/panel", rules: rules) == us)
    }

    @Test("an invalid or empty regex never matches (and isValidRegex flags it)")
    func urlRegexInvalid() {
        let broken = [URLRule(hostPattern: "[unclosed", lockedSourceID: us, matchType: .urlRegex)]
        #expect(URLMatcher.match(urlString: "https://example.com/", rules: broken) == nil)
        let empty = [URLRule(hostPattern: "", lockedSourceID: us, matchType: .urlRegex)]
        #expect(URLMatcher.match(urlString: "https://example.com/", rules: empty) == nil)
        #expect(!URLMatcher.isValidRegex("[unclosed"))
        #expect(!URLMatcher.isValidRegex("(a"))
        #expect(URLMatcher.isValidRegex("github\\.com/.*/pull"))
    }

    @Test("url regex matching is length-bounded against a pathologically long URL")
    func urlRegexLengthBounded() {
        let rules = [URLRule(hostPattern: "example", lockedSourceID: us, matchType: .urlRegex)]
        // A normal URL containing the pattern still matches.
        #expect(URLMatcher.match(urlString: "https://example.com/", rules: rules) == us)
        // A URL past the cap is rejected outright (fail-closed) rather than fed to
        // the backtracking engine — even though it contains the pattern.
        let huge = "https://example.com/" + String(repeating: "a", count: URLMatcher.maxRegexURLLength)
        #expect(huge.count > URLMatcher.maxRegexURLLength)
        #expect(URLMatcher.match(urlString: huge, rules: rules) == nil)
    }

    @Test("the length bound counts UTF-16 code units at the exact boundary, not graphemes")
    func urlRegexLengthBoundUTF16() {
        let rules = [URLRule(hostPattern: "a", lockedSourceID: us, matchType: .urlRegex)]
        // Exactly at the cap (in UTF-16 units) and containing the pattern → matches.
        let atCap = String(repeating: "a", count: URLMatcher.maxRegexURLLength)
        #expect(atCap.utf16.count == URLMatcher.maxRegexURLLength)
        #expect(URLMatcher.match(urlString: atCap, rules: rules) == us)
        // One code unit over → rejected.
        #expect(URLMatcher.match(urlString: atCap + "a", rules: rules) == nil)
        // Few graphemes but many UTF-16 units (each emoji is 2 units): the bound is
        // in UTF-16, so a grapheme count at the cap is still rejected when its code-
        // unit length exceeds it — a grapheme-based count would have let it through.
        let emoji = String(repeating: "😀", count: URLMatcher.maxRegexURLLength)
        #expect(emoji.count == URLMatcher.maxRegexURLLength)
        #expect(emoji.utf16.count > URLMatcher.maxRegexURLLength)
        #expect(URLMatcher.match(urlString: emoji, rules: [URLRule(hostPattern: "😀", lockedSourceID: us, matchType: .urlRegex)]) == nil)
    }

    @Test("a regex can match an authority-less URL a domain rule never could")
    func urlRegexNoAuthority() {
        let suffix = [URLRule(hostPattern: "x.com", lockedSourceID: us)]
        #expect(URLMatcher.match(urlString: "about:newtab", rules: suffix) == nil)
        let regex = [URLRule(hostPattern: "^about:", lockedSourceID: pinyin, matchType: .urlRegex)]
        #expect(URLMatcher.match(urlString: "about:newtab", rules: regex) == pinyin)
        // …but an empty URL still matches nothing, regex or not.
        #expect(URLMatcher.match(urlString: "", rules: regex) == nil)
    }

    // MARK: Ordering / precedence

    @Test("first matching rule wins — list order is the priority, across match types")
    func firstWins() {
        // A specific regex above a broad suffix: the /pull page goes to `us`,
        // everything else on github.com goes to `pinyin`.
        let rules = [
            URLRule(hostPattern: "/pull/", lockedSourceID: us, matchType: .urlRegex),
            URLRule(hostPattern: "github.com", lockedSourceID: pinyin),
        ]
        #expect(URLMatcher.match(urlString: "https://github.com/o/r/pull/1", rules: rules) == us)
        #expect(URLMatcher.match(urlString: "https://github.com/o/r/issues/1", rules: rules) == pinyin)
        // Reversing the priority makes the broad suffix win everywhere — the only
        // thing that changed is order, which is exactly what reordering controls.
        let reversed = Array(rules.reversed())
        #expect(URLMatcher.match(urlString: "https://github.com/o/r/pull/1", rules: reversed) == pinyin)
    }

    @Test("matchedRule surfaces the winning rule")
    func matchedRuleReturnsRule() {
        let rules = [
            URLRule(hostPattern: "docs.github.com", lockedSourceID: pinyin),
            URLRule(hostPattern: "github.com", lockedSourceID: us),
        ]
        #expect(URLMatcher.matchedRule(urlString: "https://docs.github.com/x", rules: rules)?.hostPattern == "docs.github.com")
        #expect(URLMatcher.matchedRule(urlString: "https://api.github.com/x", rules: rules)?.hostPattern == "github.com")
        #expect(URLMatcher.matchedRule(urlString: "https://example.com/", rules: rules) == nil)
        #expect(URLMatcher.matchedRule(urlString: "", rules: rules) == nil)
    }

    @Test("no rules yields no match")
    func noRules() {
        #expect(URLMatcher.match(urlString: "https://x.com", rules: []) == nil)
    }

    // MARK: Browser detection (unchanged)

    @Test("browser bundle detection (Safari + Chromium + Gecko)")
    func browsers() {
        #expect(BrowserBundleIDs.isBrowser("com.apple.Safari"))
        #expect(BrowserBundleIDs.isBrowser("com.google.Chrome"))
        #expect(BrowserBundleIDs.isBrowser("com.microsoft.edgemac"))
        #expect(BrowserBundleIDs.isBrowser("org.mozilla.firefox"))
        #expect(BrowserBundleIDs.isBrowser("app.zen-browser.zen"))
        #expect(!BrowserBundleIDs.isBrowser("com.apple.Terminal"))
        #expect(!BrowserBundleIDs.isBrowser(nil))
    }

    @Test("Chromium detection (needs AXManualAccessibility opt-in)")
    func chromium() {
        #expect(BrowserBundleIDs.isChromium("com.google.Chrome"))
        #expect(BrowserBundleIDs.isChromium("com.brave.Browser"))
        #expect(BrowserBundleIDs.isChromium("company.thebrowser.Browser"))
        // Safari is a browser but not Chromium — it needs no opt-in.
        #expect(!BrowserBundleIDs.isChromium("com.apple.Safari"))
        #expect(!BrowserBundleIDs.isChromium("org.mozilla.firefox"))
        #expect(!BrowserBundleIDs.isChromium(nil))
    }

    @Test("Gecko detection (needs AXEnhancedUserInterface opt-in)")
    func gecko() {
        #expect(BrowserBundleIDs.isGecko("org.mozilla.firefox"))
        #expect(BrowserBundleIDs.isGecko("org.mozilla.firefoxdeveloperedition"))
        #expect(BrowserBundleIDs.isGecko("app.zen-browser.zen"))
        #expect(BrowserBundleIDs.isGecko("app.floorp.Floorp"))
        #expect(BrowserBundleIDs.isGecko("net.waterfox.waterfox"))
        #expect(BrowserBundleIDs.isGecko("io.gitlab.librewolf-community.librewolf"))
        #expect(BrowserBundleIDs.isGecko("org.torproject.torbrowser"))
        #expect(BrowserBundleIDs.isGecko("net.mullvad.mullvadbrowser"))
        // Gecko and Chromium are disjoint; Safari is neither.
        #expect(!BrowserBundleIDs.isGecko("com.google.Chrome"))
        #expect(!BrowserBundleIDs.isChromium("org.mozilla.firefox"))
        #expect(!BrowserBundleIDs.isGecko("com.apple.Safari"))
        #expect(!BrowserBundleIDs.isGecko(nil))
    }
}
