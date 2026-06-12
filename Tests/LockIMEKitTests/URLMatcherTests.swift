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

    @Test("empty / invalid URLs have no host")
    func noHost() {
        #expect(URLMatcher.host(from: "") == nil)
        #expect(URLMatcher.host(from: "not a url") == nil)
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

    @Test("browser bundle detection (Safari + Chromium; Firefox excluded)")
    func browsers() {
        #expect(BrowserBundleIDs.isBrowser("com.apple.Safari"))
        #expect(BrowserBundleIDs.isBrowser("com.google.Chrome"))
        #expect(BrowserBundleIDs.isBrowser("com.microsoft.edgemac"))
        #expect(!BrowserBundleIDs.isBrowser("com.apple.Terminal"))
        #expect(!BrowserBundleIDs.isBrowser(nil))
        // Firefox is intentionally unsupported: no tab URL over the AX API.
        #expect(!BrowserBundleIDs.isBrowser("org.mozilla.firefox"))
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
}
