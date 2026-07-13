import Foundation

// MARK: - Selectors

/// How an API caller names an input source: either by its canonical Text Input
/// Source identifier (`id`, e.g. `com.apple.keylayout.ABC`) — the stable, locale-
/// independent form — or by its localized display name (`name`), a convenience
/// resolved against the installed sources at execution time.
public enum SourceSelector: Equatable, Sendable {
    case id(InputSourceID)
    case name(String)
}

/// How an API caller names a URL rule for removal: by its stable `id` (the UUID
/// surfaced via `list-url-rules`) or by its `host` pattern (the first match).
public enum URLRuleSelector: Equatable, Sendable {
    case id(UUID)
    case host(String)
}

/// A tri-state boolean argument. `toggle` flips whatever the current value is and
/// can only be resolved at execution time (the parser can't read live state).
public enum FlagArg: Equatable, Sendable {
    case on
    case off
    case toggle
}

// MARK: - Commands

/// A fully-parsed, syntactically-validated URL-scheme command. Carries only the
/// values present in the URL; whether a referenced source/rule/app actually
/// exists is a runtime question answered by the executor, not the parser.
public enum URLCommand: Equatable, Sendable {
    // The single on/off ("Enable LockIME") — gates the whole app (locking + switching).
    case lock
    case unlock
    case toggleLock

    // Global source targeting
    case lockToSource(SourceSelector)
    // `source` nil clears the global default; `action` picks lock vs one-shot
    // switch (default `.lock`, ignored on the clear path).
    case setDefaultSource(source: SourceSelector?, action: RuleAction)
    case cycleSource(CycleDirection)
    case switchSource(SourceSelector)        // transient one-shot, no standing lock

    // Per-app rules
    case setAppRule(bundleID: String, mode: AppRuleMode, source: SourceSelector?)
    case removeAppRule(bundleID: String)
    case cycleAppSource(bundleID: String?, direction: CycleDirection)   // nil ⇒ frontmost
    case removeFrontmostAppRule
    case clearAppRules

    // Login item
    case setLaunchAtLogin(FlagArg)

    // Enhanced mode + per-URL rules
    case setEnhancedMode(FlagArg)
    case setURLRule(id: UUID?, host: String, source: SourceSelector, action: RuleAction, matchType: URLMatchType)
    case removeURLRule(URLRuleSelector)
    case clearURLRules

    // App
    /// `nil` means "follow the system language" (clears the in-app override).
    case setLanguage(SupportedLanguage?)
    case quit

    // Queries (return data through the x-success callback)
    case status
    case currentSource
    case listSources
    case listAppRules
    case listURLRules
    case listLog
    case getConfig
    case version
    case ping

    /// Whether this command produces a result payload meant for an x-success
    /// callback (vs. a side-effecting action that just signals completion).
    public var isQuery: Bool {
        switch self {
        case .status, .currentSource, .listSources, .listAppRules,
             .listURLRules, .listLog, .getConfig, .version, .ping:
            return true
        default:
            return false
        }
    }
}

// MARK: - x-callback-url targets

/// The [x-callback-url](https://x-callback-url.com) targets carried alongside a
/// command. Any command may include them; queries use `success` to return data.
public struct CallbackTargets: Equatable, Sendable {
    /// `x-source` — a display name for the calling app (informational only).
    public let source: String?
    /// `x-success` — opened on success, with query results appended for queries.
    public let success: URL?
    /// `x-error` — opened on failure, with `errorCode`/`errorMessage` appended.
    public let error: URL?
    /// `x-cancel` — reserved; LockIME commands never cancel, so it is unused.
    public let cancel: URL?

    public init(source: String? = nil, success: URL? = nil, error: URL? = nil, cancel: URL? = nil) {
        self.source = source
        self.success = success
        self.error = error
        self.cancel = cancel
    }

    public static let none = CallbackTargets()
}

/// A parsed command plus its callback targets.
public struct ParsedURLCommand: Equatable, Sendable {
    public let command: URLCommand
    public let callback: CallbackTargets

    public init(command: URLCommand, callback: CallbackTargets = .none) {
        self.command = command
        self.callback = callback
    }
}

// MARK: - Errors

/// Why a command failed — at parse time (syntax) or execution time (live state).
/// Each case carries a stable machine `code` (for programmatic callers) and an
/// English human `message`. These are deliberately **not** localized: they cross
/// the process boundary into another app via the `x-error` callback and into the
/// unified log, where stable, machine-readable English is the contract.
public enum URLCommandError: Equatable, Sendable, Error {
    case malformedURL
    case notACommand
    case unknownCommand(String)
    case missingParameter(String)
    case invalidParameter(name: String, value: String)
    // Runtime (raised by the executor, not the parser):
    case apiDisabled
    case unknownSource(String)
    case noInputSources
    case ruleNotFound(String)
    case notSupported(String)

    public var code: String {
        switch self {
        case .malformedURL: return "malformed_url"
        case .notACommand: return "no_command"
        case .unknownCommand: return "unknown_command"
        case .missingParameter: return "missing_parameter"
        case .invalidParameter: return "invalid_parameter"
        case .apiDisabled: return "api_disabled"
        case .unknownSource: return "unknown_source"
        case .noInputSources: return "no_input_sources"
        case .ruleNotFound: return "rule_not_found"
        case .notSupported: return "not_supported"
        }
    }

    public var message: String {
        switch self {
        case .malformedURL:
            return "The URL could not be parsed."
        case .notACommand:
            return "No command was specified."
        case .unknownCommand(let name):
            return "Unknown command \"\(name)\"."
        case .missingParameter(let name):
            return "Missing required parameter \"\(name)\"."
        case .invalidParameter(let name, let value):
            return "Invalid value \"\(value)\" for parameter \"\(name)\"."
        case .apiDisabled:
            return "The URL scheme API is disabled. Enable it in LockIME ▸ Settings ▸ General ▸ Automation."
        case .unknownSource(let value):
            return "No installed input source matches \"\(value)\"."
        case .noInputSources:
            return "No selectable input sources are installed."
        case .ruleNotFound(let value):
            return "No rule matches \"\(value)\"."
        case .notSupported(let detail):
            return "Operation not supported: \(detail)."
        }
    }
}

// MARK: - Parser

/// Pure parsing of a `lockime://` URL into a typed, validated command. The
/// concrete scheme string is irrelevant here — LaunchServices only delivers URLs
/// whose scheme the app registered (`lockime`, plus `lockime-dev` for Debug), so
/// the parser keys off the command token and parameters alone.
///
/// Two URL shapes are accepted, both case-insensitive on the command token:
/// - bare:        `lockime://<command>?<params>`
/// - x-callback:  `lockime://x-callback-url/<command>?<params>`
///
/// Parameter *names* are matched case-insensitively; parameter *values*
/// (bundle IDs, source IDs, host patterns) are preserved verbatim.
public enum URLCommandParser {
    public static func parse(_ url: URL) -> Result<ParsedURLCommand, URLCommandError> {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .failure(.malformedURL)
        }
        let params = queryParams(components)
        let callback = callbackTargets(params)

        guard let token = commandToken(from: components) else {
            return .failure(.notACommand)
        }
        return resolve(token: token, params: params)
            .map { ParsedURLCommand(command: $0, callback: callback) }
    }

    /// Extract just the x-callback-url targets, regardless of whether the command
    /// itself parses. The executor needs these on the failure path so a malformed
    /// or unknown command can still report back through `x-error`.
    public static func callbackTargets(from url: URL) -> CallbackTargets {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .none
        }
        return callbackTargets(queryParams(components))
    }

    private static func queryParams(_ components: URLComponents) -> [String: String] {
        var params: [String: String] = [:]
        for item in components.queryItems ?? [] {
            params[item.name.lowercased()] = item.value ?? ""
        }
        return params
    }

    private static func callbackTargets(_ params: [String: String]) -> CallbackTargets {
        CallbackTargets(
            source: params["x-source"],
            success: params["x-success"].flatMap { URL(string: $0) },
            error: params["x-error"].flatMap { URL(string: $0) },
            cancel: params["x-cancel"].flatMap { URL(string: $0) }
        )
    }

    /// The command identifier: the host, or the first path segment when the host
    /// is the `x-callback-url` sentinel (or absent, e.g. `lockime:///status`).
    private static func commandToken(from components: URLComponents) -> String? {
        let host = components.host?.lowercased()
        if let host, host != "x-callback-url", !host.isEmpty {
            return host
        }
        let segment = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .first
            .map { $0.lowercased() }
        if let segment, !segment.isEmpty { return segment }
        return nil
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func resolve(token: String, params: [String: String])
        -> Result<URLCommand, URLCommandError>
    {
        switch token {
        case "lock":
            return .success(.lock)
        case "unlock":
            return .success(.unlock)
        case "toggle-lock", "toggle":
            return .success(.toggleLock)

        case "lock-to-source":
            return requiredSource(params).map { .lockToSource($0) }
        case "set-default-source":
            let source = optionalSource(params)
            let rawAction = params["action"] ?? "lock"
            let action: RuleAction
            switch rawAction.lowercased() {
            case "lock": action = .lock
            case "switch", "switchonce", "switch-once": action = .switchOnce
            default: return .failure(.invalidParameter(name: "action", value: rawAction))
            }
            return .success(.setDefaultSource(source: source, action: action))
        case "cycle-source":
            return direction(params).map { .cycleSource($0) }
        case "switch-source":
            return requiredSource(params).map { .switchSource($0) }

        case "set-app-rule":
            return parseSetAppRule(params)
        case "remove-app-rule":
            return require(params, "bundle").map { .removeAppRule(bundleID: $0) }
        case "cycle-app-source":
            return direction(params).map {
                .cycleAppSource(bundleID: nonEmpty(params["bundle"]), direction: $0)
            }
        case "remove-frontmost-app-rule":
            return .success(.removeFrontmostAppRule)
        case "clear-app-rules":
            return .success(.clearAppRules)

        case "set-launch-at-login", "launch-at-login":
            return flag(params, "enabled").map { .setLaunchAtLogin($0) }

        case "set-enhanced-mode":
            return flag(params, "enabled").map { .setEnhancedMode($0) }
        case "set-url-rule":
            return parseSetURLRule(params)
        case "remove-url-rule":
            return parseRemoveURLRule(params)
        case "clear-url-rules":
            return .success(.clearURLRules)

        case "set-language":
            return parseSetLanguage(params)
        case "quit":
            return .success(.quit)

        case "status":
            return .success(.status)
        case "current-source":
            return .success(.currentSource)
        case "list-sources", "sources":
            return .success(.listSources)
        case "list-app-rules", "app-rules":
            return .success(.listAppRules)
        case "list-url-rules", "url-rules":
            return .success(.listURLRules)
        case "list-log", "log", "recent-activations":
            return .success(.listLog)
        case "get-config", "config":
            return .success(.getConfig)
        case "version":
            return .success(.version)
        case "ping":
            return .success(.ping)

        default:
            return .failure(.unknownCommand(token))
        }
    }

    // MARK: Sub-parsers

    private static func parseSetAppRule(_ params: [String: String]) -> Result<URLCommand, URLCommandError> {
        switch require(params, "bundle") {
        case .failure(let e):
            return .failure(e)
        case .success(let bundle):
            let mode: AppRuleMode
            switch (params["mode"] ?? "lock").lowercased() {
            case "lock", "locked": mode = .locked
            case "switch", "switched": mode = .switched
            case "ignore", "ignored": mode = .ignored
            case "default", "usedefault", "use-default": mode = .useDefault
            case let other: return .failure(.invalidParameter(name: "mode", value: other))
            }
            // A pinning mode needs a source; the deferring modes must not carry one.
            if mode.pinsSource {
                guard let selector = ruleSource(params) else { return .failure(.missingParameter("source")) }
                return .success(.setAppRule(bundleID: bundle, mode: mode, source: selector))
            }
            return .success(.setAppRule(bundleID: bundle, mode: mode, source: nil))
        }
    }

    private static func parseSetURLRule(_ params: [String: String]) -> Result<URLCommand, URLCommandError> {
        // The pattern rides in `host` for historical reasons; `pattern` is an
        // alias that reads better for keyword/regex rules.
        guard let rawHost = nonEmpty(params["host"]) ?? nonEmpty(params["pattern"]) else {
            return .failure(.missingParameter("host"))
        }
        // Which param the pattern actually came from, so an error names what the
        // caller sent (`host` wins when both are given).
        let patternParam = nonEmpty(params["host"]) != nil ? "host" : "pattern"
        // Trim (mirroring the editor) so a whitespace-only value can't persist a
        // rule that normalizes to empty and silently matches nothing.
        let host = rawHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return .failure(.missingParameter(patternParam)) }
        guard let selector = ruleSource(params) else { return .failure(.missingParameter("source")) }
        let action: RuleAction
        switch (params["action"] ?? "lock").lowercased() {
        case "lock": action = .lock
        case "switch", "switchonce", "switch-once": action = .switchOnce
        case let other: return .failure(.invalidParameter(name: "action", value: other))
        }
        let matchType: URLMatchType
        switch (params["match-type"] ?? params["matchtype"] ?? "domain-suffix").lowercased() {
        case "domain-suffix", "domainsuffix", "suffix": matchType = .domainSuffix
        case "domain", "domain-exact", "exact": matchType = .domain
        case "domain-keyword", "domainkeyword", "keyword": matchType = .domainKeyword
        case "url-regex", "urlregex", "regex": matchType = .urlRegex
        case let other: return .failure(.invalidParameter(name: "match-type", value: other))
        }
        // A regex rule whose pattern doesn't compile would silently match
        // nothing — reject it at parse time, naming the param the caller used.
        if matchType == .urlRegex, !URLMatcher.isValidRegex(host) {
            return .failure(.invalidParameter(name: patternParam, value: host))
        }
        var ruleID: UUID?
        if let raw = nonEmpty(params["id"]) {
            guard let parsed = UUID(uuidString: raw) else {
                return .failure(.invalidParameter(name: "id", value: raw))
            }
            ruleID = parsed
        }
        return .success(.setURLRule(id: ruleID, host: host, source: selector, action: action, matchType: matchType))
    }

    private static func parseRemoveURLRule(_ params: [String: String]) -> Result<URLCommand, URLCommandError> {
        if let raw = nonEmpty(params["id"]) {
            guard let parsed = UUID(uuidString: raw) else {
                return .failure(.invalidParameter(name: "id", value: raw))
            }
            return .success(.removeURLRule(.id(parsed)))
        }
        if let host = nonEmpty(params["host"]) {
            return .success(.removeURLRule(.host(host)))
        }
        return .failure(.missingParameter("id"))
    }

    private static func parseSetLanguage(_ params: [String: String]) -> Result<URLCommand, URLCommandError> {
        switch require(params, "code") {
        case .failure(let e):
            return .failure(e)
        case .success(let raw):
            // Sentinel to clear the override and follow the system language.
            switch raw.lowercased() {
            case "system", "auto", "follow": return .success(.setLanguage(nil))
            default: break
            }
            if let exact = SupportedLanguage(rawValue: raw) { return .success(.setLanguage(exact)) }
            if let matched = SupportedLanguage.match(raw) { return .success(.setLanguage(matched)) }
            return .failure(.invalidParameter(name: "code", value: raw))
        }
    }

    // MARK: Param helpers

    private static func require(_ params: [String: String], _ name: String)
        -> Result<String, URLCommandError>
    {
        if let value = nonEmpty(params[name]) { return .success(value) }
        return .failure(.missingParameter(name))
    }

    /// A source selector from `source`/`id` (canonical TIS id) or
    /// `name`/`source-name` (localized display name), or `nil` when none is
    /// present (used to *clear* a target, e.g. `set-default-source`).
    private static func optionalSource(_ params: [String: String]) -> SourceSelector? {
        if let id = nonEmpty(params["source"]) ?? nonEmpty(params["id"]) {
            return .id(InputSourceID(id))
        }
        if let name = nonEmpty(params["name"]) ?? nonEmpty(params["source-name"]) {
            return .name(name)
        }
        return nil
    }

    /// Like `optionalSource`, but a missing source is a `missing_parameter("id")`
    /// error. For the source-*targeting* commands, whose canonical key is `id`.
    private static func requiredSource(_ params: [String: String])
        -> Result<SourceSelector, URLCommandError>
    {
        if let selector = optionalSource(params) { return .success(selector) }
        return .failure(.missingParameter("id"))
    }

    /// Source selector for RULE commands (`set-app-rule`, `set-url-rule`). Unlike
    /// `optionalSource`, this deliberately excludes the bare `id` key — on a URL
    /// rule `id` names the *rule's own UUID*, not a source — so a rule source must
    /// come from `source` (a TIS id) or `source-name` / `name` (a display name).
    private static func ruleSource(_ params: [String: String]) -> SourceSelector? {
        if let id = nonEmpty(params["source"]) { return .id(InputSourceID(id)) }
        if let name = nonEmpty(params["source-name"]) ?? nonEmpty(params["name"]) { return .name(name) }
        return nil
    }

    private static func direction(_ params: [String: String]) -> Result<CycleDirection, URLCommandError> {
        switch (params["direction"] ?? "").lowercased() {
        case "next", "forward", "down": return .success(.next)
        case "previous", "prev", "back", "backward", "up": return .success(.previous)
        case "": return .failure(.missingParameter("direction"))
        case let other: return .failure(.invalidParameter(name: "direction", value: other))
        }
    }

    private static func flag(_ params: [String: String], _ name: String) -> Result<FlagArg, URLCommandError> {
        switch (params[name] ?? "").lowercased() {
        case "true", "1", "on", "yes", "enable", "enabled": return .success(.on)
        case "false", "0", "off", "no", "disable", "disabled": return .success(.off)
        case "toggle": return .success(.toggle)
        case "": return .failure(.missingParameter(name))
        case let other: return .failure(.invalidParameter(name: name, value: other))
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

// MARK: - Callback URL construction

/// Builds the `x-success` / `x-error` callback URLs by appending result/error
/// parameters to the caller-supplied base URL (per the x-callback-url contract).
public enum CallbackURLBuilder {
    /// Append a `result` query item (a JSON string, percent-encoded) to a success
    /// callback. `result` is `nil` for side-effecting actions that merely signal
    /// completion.
    public static func success(_ base: URL, result: String?) -> URL? {
        let items = result.map { [URLQueryItem(name: "result", value: $0)] } ?? []
        return appending(items, to: base)
    }

    /// Append the stable `errorCode` and human `errorMessage` query items to an
    /// error callback.
    public static func error(_ base: URL, code: String, message: String) -> URL? {
        appending(
            [URLQueryItem(name: "errorCode", value: code),
             URLQueryItem(name: "errorMessage", value: message)],
            to: base
        )
    }

    private static func appending(_ items: [URLQueryItem], to base: URL) -> URL? {
        guard !items.isEmpty else { return base }
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return base
        }
        var existing = components.queryItems ?? []
        existing.append(contentsOf: items)
        components.queryItems = existing
        return components.url ?? base
    }
}

// MARK: - Callback safety policy

/// Decides whether a caller-supplied `x-success` / `x-error` callback URL is safe
/// for LockIME to open. The callback is **reflected** — LockIME opens whatever URL
/// the caller put in the query — so an unrestricted open turns the app into a
/// confused-deputy: a web origin that can only get the browser to prompt for a
/// `lockime://` URL could otherwise launder an open of a `file://` URL (launching
/// a local file/app it cannot reach directly) through LockIME's process.
///
/// The x-callback-url round-trip back into the *caller's own* app scheme is the
/// whole feature, so arbitrary custom schemes (and `http`/`https`) stay allowed;
/// only `file:` and the app's own scheme(s) are refused — the latter so a callback
/// can never re-enter the API (no reentrancy ping-pong).
public enum CallbackURLPolicy {
    /// Schemes never allowed for a reflected callback, regardless of bundle.
    public static let blockedSchemes: Set<String> = ["file"]

    /// Whether `url` may be opened as a callback. `ownSchemes` are the app's own
    /// registered URL schemes (lowercased); a callback into one of them is refused.
    /// A schemeless (relative) URL is refused too — there is nothing safe to open.
    public static func allows(_ url: URL, ownSchemes: Set<String>) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        if blockedSchemes.contains(scheme) { return false }
        if ownSchemes.contains(scheme) { return false }
        return true
    }
}
