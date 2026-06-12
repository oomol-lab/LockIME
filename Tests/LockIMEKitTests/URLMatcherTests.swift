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
        // Browser placeholder pages carry no authority, so a per-URL rule can
        // never false-match them — a Firefox new tab surfaces as about:newtab,
        // not a real host. (We rely on a nil host here rather than normalizing
        // these scheme-by-scheme.)
        #expect(URLMatcher.host(from: "about:newtab") == nil)
        #expect(URLMatcher.host(from: "about:blank") == nil)
    }

    @Test("exact and subdomain matches")
    func exactAndSubdomain() {
        let rules = [URLRule(hostPattern: "github.com", lockedSourceID: us)]
        #expect(URLMatcher.match(host: "github.com", rules: rules) == us)
        #expect(URLMatcher.match(host: "gist.github.com", rules: rules) == us)
        #expect(URLMatcher.match(host: "notgithub.com", rules: rules) == nil)
        #expect(URLMatcher.match(host: "example.com", rules: rules) == nil)
    }

    @Test("wildcard pattern matches base and subdomains")
    func wildcard() {
        let rules = [URLRule(hostPattern: "*.google.com", lockedSourceID: pinyin)]
        #expect(URLMatcher.match(host: "google.com", rules: rules) == pinyin)
        #expect(URLMatcher.match(host: "mail.google.com", rules: rules) == pinyin)
        #expect(URLMatcher.match(host: "evilgoogle.com", rules: rules) == nil)
    }

    @Test("first matching rule wins")
    func firstWins() {
        let rules = [
            URLRule(hostPattern: "docs.github.com", lockedSourceID: pinyin),
            URLRule(hostPattern: "github.com", lockedSourceID: us),
        ]
        #expect(URLMatcher.match(host: "docs.github.com", rules: rules) == pinyin)
        #expect(URLMatcher.match(host: "api.github.com", rules: rules) == us)
    }

    @Test("nil host or no rules yields no match")
    func noMatch() {
        #expect(URLMatcher.match(host: nil, rules: [URLRule(hostPattern: "x.com", lockedSourceID: us)]) == nil)
        #expect(URLMatcher.match(host: "x.com", rules: []) == nil)
    }

    @Test("matchedRule surfaces the winning rule (host pattern + source)")
    func matchedRuleReturnsRule() {
        let rules = [
            URLRule(hostPattern: "docs.github.com", lockedSourceID: pinyin),
            URLRule(hostPattern: "github.com", lockedSourceID: us),
        ]
        #expect(URLMatcher.matchedRule(host: "docs.github.com", rules: rules)?.hostPattern == "docs.github.com")
        #expect(URLMatcher.matchedRule(host: "api.github.com", rules: rules)?.hostPattern == "github.com")
        #expect(URLMatcher.matchedRule(host: "example.com", rules: rules) == nil)
        #expect(URLMatcher.matchedRule(host: nil, rules: rules) == nil)
    }

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
