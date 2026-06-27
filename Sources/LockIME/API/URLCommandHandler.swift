import AppKit
import Foundation
import LockIMEKit
import OSLog

/// Executes a parsed `lockime://` URL-scheme command against the live `AppState`
/// and reports the outcome through the optional x-callback-url targets.
///
/// All control logic that can be tested without AppKit lives in the kit
/// (`URLCommandParser`, `CallbackURLBuilder`); this type is the thin AppKit glue
/// that maps a validated command onto `AppState` mutations / queries, builds the
/// JSON result payloads, and opens the success/error callbacks.
@MainActor
final class URLCommandHandler {
    private let state: AppState
    private static let log = Logger(subsystem: LogSubsystem.current, category: "URLAPI")

    init(state: AppState) {
        self.state = state
    }

    /// Entry point for `application(_:open:)`. Parses, executes, and replies.
    func handle(_ url: URL) {
        Self.log.info("URL command received: \(url.absoluteString, privacy: .public)")
        // The API is opt-in: until the user enables it (Settings ▸ General ▸
        // Automation), no command — not even a query — takes effect. Reply with a
        // stable `api_disabled` error so a caller can detect the gate.
        guard state.apiEnabled else {
            respondFailure(.apiDisabled, callback: URLCommandParser.callbackTargets(from: url))
            return
        }
        switch URLCommandParser.parse(url) {
        case .success(let parsed):
            switch perform(parsed.command) {
            case .success(let payload):
                respondSuccess(payload, callback: parsed.callback)
            case .failure(let error):
                respondFailure(error, callback: parsed.callback)
            }
        case .failure(let error):
            // A parse failure still carries usable x-callback targets.
            respondFailure(error, callback: URLCommandParser.callbackTargets(from: url))
        }
    }

    // MARK: - Execution

    /// Carry out one command. Returns a JSON value (a `[String: Any]` object or
    /// `[[String: Any]]` array) for query commands, `nil` for actions.
    private func perform(_ command: URLCommand) -> Result<Any?, URLCommandError> {
        switch command {
        // Master ("Enable LockIME") — gates the whole app.
        case .lock:
            state.setMasterEnabled(true); return .success(nil)
        case .unlock:
            state.setMasterEnabled(false); return .success(nil)
        case .toggleLock:
            state.setMasterEnabled(!state.isAppEnabled); return .success(nil)
        // Lock sub-toggle ("Enable locking").
        case .setLocking(let flag):
            state.setLockingEnabled(resolve(flag, current: state.config.lockingEnabled)); return .success(nil)

        // Global source targeting
        case .lockToSource(let selector):
            return withResolved(selector) { state.lockToSource($0) }
        case .setDefaultSource(let selector):
            guard let selector else { state.setDefaultSource(nil); return .success(nil) }
            return withResolved(selector) { state.setDefaultSource($0) }
        case .cycleSource(let direction):
            state.cycleGlobalSource(direction); return .success(nil)
        case .switchSource(let selector):
            return withResolved(selector) { state.switchSourceOnce($0) }

        // Per-app rules
        case .setAppRule(let bundleID, let mode, let selector):
            return performSetAppRule(bundleID: bundleID, mode: mode, selector: selector)
        case .removeAppRule(let bundleID):
            guard state.config.rule(for: bundleID) != nil else { return .failure(.ruleNotFound(bundleID)) }
            state.removeRule(bundleID: bundleID); return .success(nil)
        case .cycleAppSource(let bundleID, let direction):
            guard let target = bundleID ?? state.liveFrontmostBundleID else {
                return .failure(.ruleNotFound("frontmost"))
            }
            // Distinguish "no rule" from "rule exists but nowhere to cycle".
            guard state.config.rule(for: target) != nil else { return .failure(.ruleNotFound(target)) }
            guard state.cycleAppSource(bundleID: target, direction: direction) else {
                return .failure(.notSupported("no other input source to cycle to"))
            }
            return .success(nil)
        case .removeFrontmostAppRule:
            guard let bundleID = state.liveFrontmostBundleID, state.config.rule(for: bundleID) != nil else {
                return .failure(.ruleNotFound("frontmost"))
            }
            state.removeRule(bundleID: bundleID); return .success(nil)
        case .clearAppRules:
            state.clearAppRules(); return .success(nil)

        // Login item
        case .setLaunchAtLogin(let flag):
            state.setLaunchAtLogin(resolve(flag, current: state.launchAtLoginActive)); return .success(nil)

        // Enhanced mode + per-URL rules
        case .setEnhancedMode(let flag):
            state.setEnhancedMode(resolve(flag, current: state.config.enhancedModeEnabled)); return .success(nil)
        case .setURLRule(let id, let host, let selector, let action, let matchType):
            return performSetURLRule(id: id, host: host, selector: selector, action: action, matchType: matchType)
        case .removeURLRule(let selector):
            return performRemoveURLRule(selector)
        case .clearURLRules:
            state.clearURLRules(); return .success(nil)

        // App
        case .setLanguage(let language):
            // nil means "follow the system language" (clear the override).
            state.setLanguagePreference(language.map(LanguagePreference.specific) ?? .system)
            return .success(nil)
        case .quit:
            // Defer past the synchronous reply so an x-success callback still
            // fires before the app tears down.
            Task { @MainActor in NSApp.terminate(nil) }
            return .success(nil)

        // Queries
        case .status:
            return .success(statusPayload())
        case .currentSource:
            if let id = state.currentSourceID { return .success(sourceDict(id)) }
            return .success(["id": NSNull(), "name": state.currentSourceName])
        case .listSources:
            return .success(state.availableSources.map(Self.sourceListItem))
        case .listAppRules:
            return .success(state.config.appRules.map(appRuleDict))
        case .listURLRules:
            return .success(state.config.urlRules.map(urlRuleDict))
        case .listLog:
            return .success(state.recentActivationLog().map(Self.logEntryDict))
        case .getConfig:
            return configPayload()
        case .version:
            return .success(versionPayload())
        case .ping:
            var payload = versionPayload()
            payload["ok"] = true
            payload["app"] = "LockIME"
            return .success(payload)
        }
    }

    // MARK: - Command helpers

    private func performSetAppRule(
        bundleID: String, mode: AppRuleMode, selector: SourceSelector?
    ) -> Result<Any?, URLCommandError> {
        var sourceID: InputSourceID?
        if mode.pinsSource {
            guard let selector else { return .failure(.missingParameter("source")) }
            switch resolve(selector) {
            case .success(let id): sourceID = id
            case .failure(let error): return .failure(error)
            }
        }
        state.upsertRule(AppRule(bundleID: bundleID, mode: mode, lockedSourceID: sourceID))
        return .success(nil)
    }

    private func performSetURLRule(
        id: UUID?, host: String, selector: SourceSelector, action: RuleAction, matchType: URLMatchType
    ) -> Result<Any?, URLCommandError> {
        switch resolve(selector) {
        case .failure(let error):
            return .failure(error)
        case .success(let sourceID):
            // With no explicit id, update an existing rule for the same host
            // (case-insensitive) rather than appending a duplicate.
            let ruleID = id
                ?? state.config.urlRules.first { Self.sameHost($0.hostPattern, host) }?.id
                ?? UUID()
            // Refuse a write that would leave two rules sharing a pattern (the
            // portable identity backups/import key on) — that pair collapses,
            // losing one, on the next export→import. The no-id path resolves onto
            // the same-host rule above (so it's never "different"); this guards an
            // explicit id whose host belongs to *another* rule.
            if state.config.urlRules.contains(where: { $0.id != ruleID && Self.sameHost($0.hostPattern, host) }) {
                return .failure(.invalidParameter(name: "host", value: host))
            }
            state.upsertURLRule(URLRule(id: ruleID, hostPattern: host, lockedSourceID: sourceID, action: action, matchType: matchType))
            return .success(nil)
        }
    }

    private func performRemoveURLRule(_ selector: URLRuleSelector) -> Result<Any?, URLCommandError> {
        switch selector {
        case .id(let id):
            guard state.config.urlRules.contains(where: { $0.id == id }) else {
                return .failure(.ruleNotFound(id.uuidString))
            }
            state.removeURLRule(id: id)
        case .host(let host):
            let matches = state.config.urlRules.filter { Self.sameHost($0.hostPattern, host) }
            guard !matches.isEmpty else { return .failure(.ruleNotFound(host)) }
            for rule in matches { state.removeURLRule(id: rule.id) }
        }
        return .success(nil)
    }

    /// Resolve a source selector, run `body` on success, and report an empty
    /// (action) result — collapsing the success/failure plumbing for the source-
    /// targeting commands.
    private func withResolved(
        _ selector: SourceSelector, _ body: (InputSourceID) -> Void
    ) -> Result<Any?, URLCommandError> {
        switch resolve(selector) {
        case .success(let id): body(id); return .success(nil)
        case .failure(let error): return .failure(error)
        }
    }

    /// Resolve an API source selector to an installed source id, or a typed error.
    private func resolve(_ selector: SourceSelector) -> Result<InputSourceID, URLCommandError> {
        guard !state.availableSources.isEmpty else { return .failure(.noInputSources) }
        if let id = state.resolveSourceID(selector) { return .success(id) }
        switch selector {
        case .id(let id): return .failure(.unknownSource(id.rawValue))
        case .name(let name): return .failure(.unknownSource(name))
        }
    }

    private func resolve(_ flag: FlagArg, current: Bool) -> Bool {
        switch flag {
        case .on: return true
        case .off: return false
        case .toggle: return !current
        }
    }

    private static func sameHost(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: .caseInsensitive) == .orderedSame
    }

    // MARK: - Payloads

    private func statusPayload() -> [String: Any] {
        var payload: [String: Any] = [
            // `enabled` = the master ("Enable LockIME"); `lockingEnabled` = the
            // lock sub-toggle; `locked` = both (a continuous lock is in force).
            "enabled": state.isAppEnabled,
            "lockingEnabled": state.config.lockingEnabled,
            "locked": state.isLocked,
            "enhancedMode": state.config.enhancedModeEnabled,
            "launchAtLogin": state.launchAtLoginActive,
            "accessibilityGranted": state.accessibilityGranted,
            "activationCount": state.activationCount,
            "language": state.languagePreference.effectiveLanguage.localeIdentifier,
            "version": Bundle.main.shortVersion,
            "build": Bundle.main.buildVersion,
        ]
        if let id = state.currentSourceID { payload["currentSource"] = sourceDict(id) }
        if let id = state.config.defaultSourceID { payload["defaultSource"] = sourceDict(id) }
        if let frontmost = state.liveFrontmostBundleID { payload["frontmostApp"] = frontmost }
        return payload
    }

    private func versionPayload() -> [String: Any] {
        ["version": Bundle.main.shortVersion, "build": Bundle.main.buildVersion]
    }

    private func configPayload() -> Result<Any?, URLCommandError> {
        guard let data = try? JSONEncoder().encode(state.config),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return .failure(.notSupported("configuration serialization"))
        }
        return .success(object)
    }

    private func sourceDict(_ id: InputSourceID) -> [String: Any] {
        var dict: [String: Any] = ["id": id.rawValue]
        if let name = state.sourceDisplayName(for: id) { dict["name"] = name }
        return dict
    }

    private static func sourceListItem(_ source: InputSource) -> [String: Any] {
        [
            "id": source.id.rawValue,
            "name": source.localizedName,
            "isCJKV": source.isCJKV,
            "isEnabled": source.isEnabled,
            "isSelectCapable": source.isSelectCapable,
        ]
    }

    private func appRuleDict(_ rule: AppRule) -> [String: Any] {
        var dict: [String: Any] = ["bundleID": rule.bundleID, "mode": rule.mode.rawValue]
        if let id = rule.lockedSourceID { dict["source"] = sourceDict(id) }
        return dict
    }

    private func urlRuleDict(_ rule: URLRule) -> [String: Any] {
        [
            "id": rule.id.uuidString,
            "host": rule.hostPattern,
            "action": rule.action.rawValue,
            "matchType": rule.matchType.rawValue,
            "source": sourceDict(rule.lockedSourceID),
        ]
    }

    private static let iso8601 = ISO8601DateFormatter()

    private static func logEntryDict(_ entry: ActivationLogEntry) -> [String: Any] {
        var dict: [String: Any] = [
            "timestamp": iso8601.string(from: entry.timestamp),
            "inputSource": entry.inputSourceID,
            "inputSourceName": entry.inputSourceName,
            "reason": entry.reasonRaw,
            "durationMs": entry.durationMs,
        ]
        if let from = entry.fromSourceName { dict["fromSourceName"] = from }
        if let app = entry.triggeringAppName ?? entry.triggeringBundleID { dict["app"] = app }
        if let bundle = entry.triggeringBundleID { dict["bundleID"] = bundle }
        if let rule = entry.ruleSourceRaw { dict["ruleSource"] = rule }
        if let host = entry.matchedHost { dict["matchedHost"] = host }
        return dict
    }

    // MARK: - Callbacks

    private func respondSuccess(_ payload: Any?, callback: CallbackTargets) {
        guard let success = callback.success else { return }
        let resultString = payload.flatMap(Self.jsonString(from:))
        if let url = CallbackURLBuilder.success(success, result: resultString) {
            open(url)
        }
    }

    private func respondFailure(_ error: URLCommandError, callback: CallbackTargets) {
        Self.log.error("URL command failed: \(error.code, privacy: .public) — \(error.message, privacy: .public)")
        guard let errorURL = callback.error else { return }
        if let url = CallbackURLBuilder.error(errorURL, code: error.code, message: error.message) {
            open(url)
        }
    }

    /// The app's own registered URL scheme(s) — `lockime` (Release) / `lockime-dev`
    /// (Debug) — read from the running bundle, lowercased. A reflected callback is
    /// refused from re-entering these (see `CallbackURLPolicy`).
    private static let ownSchemes: Set<String> = {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let schemes = types.flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] }
        return Set(schemes.map { $0.lowercased() })
    }()

    private func open(_ url: URL) {
        // The callback target is reflected from the caller, so only open schemes
        // that cannot turn LockIME into a confused-deputy: never a `file://` (which
        // would launch an arbitrary local file/app) and never our own scheme (which
        // would let a callback re-enter the API). See `CallbackURLPolicy`.
        guard CallbackURLPolicy.allows(url, ownSchemes: Self.ownSchemes) else {
            Self.log.error("Refused callback URL with disallowed scheme: \(url.scheme ?? "(none)", privacy: .public)")
            return
        }
        NSWorkspace.shared.open(url)
    }

    private static func jsonString(from value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
