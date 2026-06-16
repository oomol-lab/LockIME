import Foundation
import Testing

@testable import LockIMEKit

/// Tests for the `lockime://` URL-scheme command parser and callback builder.
@Suite("URLCommandParser")
struct URLCommandParserTests {
    private let abc: InputSourceID = "com.apple.keylayout.ABC"

    // MARK: Helpers

    private func parse(_ string: String) -> Result<ParsedURLCommand, URLCommandError> {
        guard let url = URL(string: string) else {
            return .failure(.malformedURL)
        }
        return URLCommandParser.parse(url)
    }

    private func command(_ string: String) -> URLCommand? {
        if case .success(let parsed) = parse(string) { return parsed.command }
        return nil
    }

    private func failure(_ string: String) -> URLCommandError? {
        if case .failure(let error) = parse(string) { return error }
        return nil
    }

    // MARK: Master lock

    @Test("master-lock verbs and aliases parse")
    func masterLock() {
        #expect(command("lockime://lock") == .lock)
        #expect(command("lockime://unlock") == .unlock)
        #expect(command("lockime://toggle-lock") == .toggleLock)
        #expect(command("lockime://toggle") == .toggleLock)
    }

    @Test("the command token is case-insensitive")
    func caseInsensitiveToken() {
        #expect(command("lockime://LOCK") == .lock)
        #expect(command("lockime://Toggle-Lock") == .toggleLock)
    }

    // MARK: Global source targeting

    @Test("lock-to-source accepts id, name, and the source alias")
    func lockToSource() {
        #expect(command("lockime://lock-to-source?id=com.apple.keylayout.ABC") == .lockToSource(.id(abc)))
        #expect(command("lockime://lock-to-source?source=com.apple.keylayout.ABC") == .lockToSource(.id(abc)))
        #expect(command("lockime://lock-to-source?name=ABC") == .lockToSource(.name("ABC")))
        #expect(command("lockime://lock-to-source?source-name=ABC") == .lockToSource(.name("ABC")))
    }

    @Test("lock-to-source without a source is a missing-parameter error")
    func lockToSourceMissing() {
        #expect(failure("lockime://lock-to-source") == .missingParameter("id"))
    }

    @Test("set-default-source with no selector clears the default")
    func setDefaultSourceClear() {
        #expect(command("lockime://set-default-source") == .setDefaultSource(nil))
        #expect(command("lockime://set-default-source?id=com.apple.keylayout.ABC") == .setDefaultSource(.id(abc)))
    }

    @Test("cycle-source parses direction and its aliases")
    func cycleSource() {
        #expect(command("lockime://cycle-source?direction=next") == .cycleSource(.next))
        #expect(command("lockime://cycle-source?direction=previous") == .cycleSource(.previous))
        #expect(command("lockime://cycle-source?direction=prev") == .cycleSource(.previous))
        #expect(failure("lockime://cycle-source") == .missingParameter("direction"))
        #expect(failure("lockime://cycle-source?direction=sideways") == .invalidParameter(name: "direction", value: "sideways"))
    }

    @Test("switch-source requires a source")
    func switchSource() {
        #expect(command("lockime://switch-source?id=com.apple.keylayout.ABC") == .switchSource(.id(abc)))
        #expect(failure("lockime://switch-source") == .missingParameter("id"))
    }

    // MARK: App rules

    @Test("set-app-rule maps every mode keyword")
    func setAppRuleModes() {
        #expect(command("lockime://set-app-rule?bundle=com.foo.Bar&mode=lock&source=com.apple.keylayout.ABC")
            == .setAppRule(bundleID: "com.foo.Bar", mode: .locked, source: .id(abc)))
        #expect(command("lockime://set-app-rule?bundle=com.foo.Bar&mode=switch&source=com.apple.keylayout.ABC")
            == .setAppRule(bundleID: "com.foo.Bar", mode: .switched, source: .id(abc)))
        #expect(command("lockime://set-app-rule?bundle=com.foo.Bar&mode=ignore")
            == .setAppRule(bundleID: "com.foo.Bar", mode: .ignored, source: nil))
        #expect(command("lockime://set-app-rule?bundle=com.foo.Bar&mode=default")
            == .setAppRule(bundleID: "com.foo.Bar", mode: .useDefault, source: nil))
    }

    @Test("set-app-rule defaults to lock mode and then needs a source")
    func setAppRuleDefaultMode() {
        #expect(command("lockime://set-app-rule?bundle=com.foo.Bar&source=com.apple.keylayout.ABC")
            == .setAppRule(bundleID: "com.foo.Bar", mode: .locked, source: .id(abc)))
        #expect(failure("lockime://set-app-rule?bundle=com.foo.Bar") == .missingParameter("source"))
        #expect(failure("lockime://set-app-rule?bundle=com.foo.Bar&mode=lock") == .missingParameter("source"))
    }

    @Test("set-app-rule rejects an unknown mode and a missing bundle")
    func setAppRuleErrors() {
        #expect(failure("lockime://set-app-rule?bundle=com.foo.Bar&mode=spin")
            == .invalidParameter(name: "mode", value: "spin"))
        #expect(failure("lockime://set-app-rule?mode=ignore") == .missingParameter("bundle"))
    }

    @Test("remove / cycle / clear app-rule commands parse")
    func appRuleManagement() {
        #expect(command("lockime://remove-app-rule?bundle=com.foo.Bar") == .removeAppRule(bundleID: "com.foo.Bar"))
        #expect(failure("lockime://remove-app-rule") == .missingParameter("bundle"))
        #expect(command("lockime://cycle-app-source?direction=next")
            == .cycleAppSource(bundleID: nil, direction: .next))
        #expect(command("lockime://cycle-app-source?direction=next&bundle=com.foo.Bar")
            == .cycleAppSource(bundleID: "com.foo.Bar", direction: .next))
        #expect(command("lockime://remove-frontmost-app-rule") == .removeFrontmostAppRule)
        #expect(command("lockime://clear-app-rules") == .clearAppRules)
    }

    // MARK: Enhanced mode + URL rules

    @Test("set-enhanced-mode parses the tri-state flag")
    func enhancedModeFlag() {
        #expect(command("lockime://set-enhanced-mode?enabled=true") == .setEnhancedMode(.on))
        #expect(command("lockime://set-enhanced-mode?enabled=on") == .setEnhancedMode(.on))
        #expect(command("lockime://set-enhanced-mode?enabled=1") == .setEnhancedMode(.on))
        #expect(command("lockime://set-enhanced-mode?enabled=false") == .setEnhancedMode(.off))
        #expect(command("lockime://set-enhanced-mode?enabled=toggle") == .setEnhancedMode(.toggle))
        #expect(failure("lockime://set-enhanced-mode") == .missingParameter("enabled"))
        #expect(failure("lockime://set-enhanced-mode?enabled=maybe") == .invalidParameter(name: "enabled", value: "maybe"))
    }

    @Test("set-url-rule parses host, source, action, and an optional id")
    func setURLRule() {
        #expect(command("lockime://set-url-rule?host=github.com&source=com.apple.keylayout.ABC")
            == .setURLRule(id: nil, host: "github.com", source: .id(abc), action: .lock))
        #expect(command("lockime://set-url-rule?host=github.com&source=com.apple.keylayout.ABC&action=switch")
            == .setURLRule(id: nil, host: "github.com", source: .id(abc), action: .switchOnce))

        let uuid = UUID()
        #expect(command("lockime://set-url-rule?host=github.com&source=com.apple.keylayout.ABC&id=\(uuid.uuidString)")
            == .setURLRule(id: uuid, host: "github.com", source: .id(abc), action: .lock))
    }

    @Test("set-url-rule reports missing host/source and invalid id/action")
    func setURLRuleErrors() {
        #expect(failure("lockime://set-url-rule?source=com.apple.keylayout.ABC") == .missingParameter("host"))
        #expect(failure("lockime://set-url-rule?host=github.com") == .missingParameter("source"))
        // `id` is the rule UUID here, NOT a source selector: it must not satisfy
        // the required source (the bare-`id` collision the review caught).
        #expect(failure("lockime://set-url-rule?host=github.com&id=\(UUID().uuidString)") == .missingParameter("source"))
        #expect(failure("lockime://set-url-rule?host=github.com&source=com.apple.keylayout.ABC&action=hop")
            == .invalidParameter(name: "action", value: "hop"))
        #expect(failure("lockime://set-url-rule?host=github.com&source=com.apple.keylayout.ABC&id=not-a-uuid")
            == .invalidParameter(name: "id", value: "not-a-uuid"))
    }

    @Test("remove-url-rule accepts an id or a host, else errors")
    func removeURLRule() {
        let uuid = UUID()
        #expect(command("lockime://remove-url-rule?id=\(uuid.uuidString)") == .removeURLRule(.id(uuid)))
        #expect(command("lockime://remove-url-rule?host=github.com") == .removeURLRule(.host("github.com")))
        #expect(failure("lockime://remove-url-rule") == .missingParameter("id"))
        #expect(failure("lockime://remove-url-rule?id=nope") == .invalidParameter(name: "id", value: "nope"))
        #expect(command("lockime://clear-url-rules") == .clearURLRules)
    }

    // MARK: App / windows

    @Test("quit parses")
    func quitParses() {
        #expect(command("lockime://quit") == .quit)
    }

    @Test("set-language resolves exact codes, lenient aliases, and the system sentinel")
    func setLanguage() {
        #expect(command("lockime://set-language?code=en") == .setLanguage(.english))
        #expect(command("lockime://set-language?code=zh-Hans") == .setLanguage(.simplifiedChinese))
        #expect(command("lockime://set-language?code=zh-CN") == .setLanguage(.simplifiedChinese))
        #expect(command("lockime://set-language?code=zh-TW") == .setLanguage(.traditionalChinese))
        #expect(command("lockime://set-language?code=fr-CA") == .setLanguage(.french))
        // The sentinel clears the override (follow the system language).
        #expect(command("lockime://set-language?code=system") == .setLanguage(nil))
        #expect(command("lockime://set-language?code=auto") == .setLanguage(nil))
        #expect(failure("lockime://set-language?code=xx") == .invalidParameter(name: "code", value: "xx"))
        #expect(failure("lockime://set-language") == .missingParameter("code"))
    }

    @Test("set-launch-at-login parses the tri-state flag")
    func launchAtLogin() {
        #expect(command("lockime://set-launch-at-login?enabled=on") == .setLaunchAtLogin(.on))
        #expect(command("lockime://set-launch-at-login?enabled=off") == .setLaunchAtLogin(.off))
        #expect(command("lockime://set-launch-at-login?enabled=toggle") == .setLaunchAtLogin(.toggle))
        #expect(command("lockime://launch-at-login?enabled=true") == .setLaunchAtLogin(.on))
        #expect(failure("lockime://set-launch-at-login") == .missingParameter("enabled"))
    }

    // MARK: Queries

    @Test("query commands and their aliases parse")
    func queries() {
        #expect(command("lockime://status") == .status)
        #expect(command("lockime://current-source") == .currentSource)
        #expect(command("lockime://list-sources") == .listSources)
        #expect(command("lockime://sources") == .listSources)
        #expect(command("lockime://list-app-rules") == .listAppRules)
        #expect(command("lockime://app-rules") == .listAppRules)
        #expect(command("lockime://list-url-rules") == .listURLRules)
        #expect(command("lockime://list-log") == .listLog)
        #expect(command("lockime://log") == .listLog)
        #expect(command("lockime://recent-activations") == .listLog)
        #expect(command("lockime://get-config") == .getConfig)
        #expect(command("lockime://config") == .getConfig)
        #expect(command("lockime://version") == .version)
        #expect(command("lockime://ping") == .ping)
    }

    @Test("isQuery flags only the read commands")
    func isQueryFlag() {
        #expect(URLCommand.status.isQuery)
        #expect(URLCommand.listSources.isQuery)
        #expect(URLCommand.listLog.isQuery)
        #expect(URLCommand.ping.isQuery)
        #expect(!URLCommand.lock.isQuery)
        #expect(!URLCommand.setEnhancedMode(.on).isQuery)
        #expect(!URLCommand.setLaunchAtLogin(.on).isQuery)
    }

    // MARK: Unknown / malformed

    @Test("an unknown command and an empty command are reported")
    func unknownCommands() {
        #expect(failure("lockime://frobnicate") == .unknownCommand("frobnicate"))
        #expect(failure("lockime://") == .notACommand)
    }

    @Test("directional aliases up/down/forward/back resolve")
    func directionAliases() {
        #expect(command("lockime://cycle-source?direction=down") == .cycleSource(.next))
        #expect(command("lockime://cycle-source?direction=forward") == .cycleSource(.next))
        #expect(command("lockime://cycle-source?direction=up") == .cycleSource(.previous))
        #expect(command("lockime://cycle-source?direction=back") == .cycleSource(.previous))
    }

    @Test("the x-callback-url path form selects the command")
    func xCallbackPathForm() {
        #expect(command("lockime://x-callback-url/status") == .status)
        #expect(command("lockime://x-callback-url/lock") == .lock)
        // Triple-slash (empty host) also falls back to the path.
        #expect(command("lockime:///status") == .status)
    }

    // MARK: Callback target extraction

    @Test("x-callback targets are parsed off any command")
    func callbackTargets() {
        let success = "myapp%3A%2F%2Fok"   // myapp://ok
        let error = "myapp%3A%2F%2Ffail"   // myapp://fail
        let string = "lockime://status?x-source=Shortcuts&x-success=\(success)&x-error=\(error)"
        guard case .success(let parsed) = parse(string) else {
            Issue.record("expected a parsed command")
            return
        }
        #expect(parsed.command == .status)
        #expect(parsed.callback.source == "Shortcuts")
        #expect(parsed.callback.success == URL(string: "myapp://ok"))
        #expect(parsed.callback.error == URL(string: "myapp://fail"))
    }

    @Test("callbackTargets(from:) works even when the command is invalid")
    func callbackTargetsOnFailure() {
        let url = URL(string: "lockime://frobnicate?x-error=myapp%3A%2F%2Ffail")!
        let targets = URLCommandParser.callbackTargets(from: url)
        #expect(targets.error == URL(string: "myapp://fail"))
        #expect(targets.success == nil)
    }

    @Test("parameter names are matched case-insensitively, values preserved")
    func caseInsensitiveParamNames() {
        #expect(command("lockime://lock-to-source?ID=com.apple.keylayout.ABC") == .lockToSource(.id(abc)))
        // A bundle value keeps its original case.
        #expect(command("lockime://remove-app-rule?Bundle=Com.Foo.Bar") == .removeAppRule(bundleID: "Com.Foo.Bar"))
    }
}

/// Tests for the x-callback-url result/error URL construction.
@Suite("CallbackURLBuilder")
struct CallbackURLBuilderTests {
    private func queryItems(_ url: URL?) -> [String: String] {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [:] }
        var result: [String: String] = [:]
        for item in components.queryItems ?? [] { result[item.name] = item.value }
        return result
    }

    @Test("success appends a result query item")
    func successWithResult() {
        let base = URL(string: "myapp://done")!
        let url = CallbackURLBuilder.success(base, result: #"{"locked":true}"#)
        #expect(queryItems(url)["result"] == #"{"locked":true}"#)
    }

    @Test("success with no result leaves the base URL untouched")
    func successWithoutResult() {
        let base = URL(string: "myapp://done")!
        #expect(CallbackURLBuilder.success(base, result: nil) == base)
    }

    @Test("success preserves a pre-existing query")
    func successPreservesQuery() {
        let base = URL(string: "myapp://done?token=abc")!
        let items = queryItems(CallbackURLBuilder.success(base, result: "{}"))
        #expect(items["token"] == "abc")
        #expect(items["result"] == "{}")
    }

    @Test("error appends a stable code and message")
    func errorAppends() {
        let base = URL(string: "myapp://fail")!
        let items = queryItems(CallbackURLBuilder.error(base, code: "unknown_source", message: "No installed input source matches \"x\"."))
        #expect(items["errorCode"] == "unknown_source")
        #expect(items["errorMessage"] == "No installed input source matches \"x\".")
    }
}

/// Tests for the reflected-callback scheme safety policy.
@Suite("CallbackURLPolicy")
struct CallbackURLPolicyTests {
    private let own: Set<String> = ["lockime", "lockime-dev"]

    @Test("allows the caller's own app scheme and http(s) callbacks (the round-trip is the feature)")
    func allowsSafe() {
        #expect(CallbackURLPolicy.allows(URL(string: "myapp://got-status")!, ownSchemes: own))
        #expect(CallbackURLPolicy.allows(URL(string: "https://example.com/cb")!, ownSchemes: own))
        #expect(CallbackURLPolicy.allows(URL(string: "shortcuts://run-shortcut?name=x")!, ownSchemes: own))
    }

    @Test("blocks file:// — no laundering an arbitrary local open through LockIME")
    func blocksFile() {
        #expect(!CallbackURLPolicy.allows(URL(string: "file:///Users/x/secret.pdf")!, ownSchemes: own))
        #expect(!CallbackURLPolicy.allows(URL(string: "FILE:///x")!, ownSchemes: own)) // scheme match is case-insensitive
    }

    @Test("blocks the app's own scheme(s) — a callback can never re-enter the API")
    func blocksOwnScheme() {
        #expect(!CallbackURLPolicy.allows(URL(string: "lockime://clear-app-rules")!, ownSchemes: own))
        #expect(!CallbackURLPolicy.allows(URL(string: "lockime-dev://quit")!, ownSchemes: own))
        #expect(!CallbackURLPolicy.allows(URL(string: "LOCKIME://quit")!, ownSchemes: own)) // case-insensitive
    }

    @Test("refuses a schemeless callback — nothing safe to open")
    func refusesSchemeless() {
        #expect(!CallbackURLPolicy.allows(URL(string: "got-status?x=1")!, ownSchemes: own))
    }
}

/// Tests for the stable error code / message contract.
@Suite("URLCommandError")
struct URLCommandErrorTests {
    @Test("each error exposes a stable machine code")
    func codes() {
        #expect(URLCommandError.malformedURL.code == "malformed_url")
        #expect(URLCommandError.notACommand.code == "no_command")
        #expect(URLCommandError.unknownCommand("x").code == "unknown_command")
        #expect(URLCommandError.missingParameter("x").code == "missing_parameter")
        #expect(URLCommandError.invalidParameter(name: "x", value: "y").code == "invalid_parameter")
        #expect(URLCommandError.apiDisabled.code == "api_disabled")
        #expect(URLCommandError.unknownSource("x").code == "unknown_source")
        #expect(URLCommandError.noInputSources.code == "no_input_sources")
        #expect(URLCommandError.ruleNotFound("x").code == "rule_not_found")
        #expect(URLCommandError.notSupported("x").code == "not_supported")
    }

    @Test("messages name the offending parameter")
    func messages() {
        #expect(URLCommandError.missingParameter("bundle").message.contains("bundle"))
        #expect(URLCommandError.invalidParameter(name: "mode", value: "spin").message.contains("spin"))
        #expect(URLCommandError.unknownSource("xyz").message.contains("xyz"))
    }
}
