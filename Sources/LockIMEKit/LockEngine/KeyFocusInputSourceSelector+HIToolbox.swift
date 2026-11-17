import Carbon
import Foundation

/// The private HIToolbox half of `KeyFocusInputSourceSelector`: resolving the
/// key-focus process, flattening the input source, and the synchronous message
/// round trip. Only reachable against a live window server and a focused app,
/// so (like `TISInputSourceProvider`) it is exercised on hardware, not in the
/// CI-safe unit tests.
extension KeyFocusInputSourceSelector {
    /// HIToolbox's "input source selected" message ID.
    nonisolated static let selectedMessageID: Int32 = 7
    /// Bounds on the synchronous round trip. The focused app answers from its
    /// main run loop, typically within a few milliseconds; a hung app must not
    /// stall our main thread for long, so both are kept short. A timed-out
    /// request falls back to `TISSelectInputSource`.
    nonisolated static let sendTimeout: CFTimeInterval = 0.1
    nonisolated static let replyTimeout: CFTimeInterval = 0.3

    fileprivate nonisolated static let portName = "com.apple.tsm.portname"
    /// A private run-loop mode for the reply wait. `CFMessagePortSendRequest`
    /// spins the current (main) run loop in the reply mode; in the default
    /// mode that would deliver unrelated sources mid-selection — notably the
    /// "selected source changed" notification, re-entering the lock state
    /// machine from inside its own `force`.
    fileprivate nonisolated static let replyMode = "com.oomol.LockIME.tsm-reply"

    /// Ask the key-focus process to select `source`.
    static func select(_ source: TISInputSource) -> Result<Void, Failure> {
        guard let api = PrivateAPI.shared else { return .failure(.unavailable) }
        return select(
            flatten: { api.flatten(source) },
            transport: Transport(
                keyFocusPID: { api.keyFocusPID() },
                ownPID: { ProcessInfo.processInfo.processIdentifier },
                send: { pid, request in api.send(request, to: pid) }
            )
        )
    }
}

private struct PrivateAPI: Sendable {
    private typealias GetKeyFocusProcess = @convention(c) (
        UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>
    ) -> Int32
    private typealias GetProcessPID = @convention(c) (
        UnsafePointer<ProcessSerialNumber>, UnsafeMutablePointer<pid_t>
    ) -> OSStatus
    private typealias CreatePerProcessRemote = @convention(c) (
        CFAllocator?, CFString, pid_t
    ) -> Unmanaged<CFMessagePort>?
    private typealias CreateFlattenedInputSource = @convention(c) (
        TISInputSource, UnsafeMutablePointer<Unmanaged<CFTypeRef>?>
    ) -> UInt8

    private let getKeyFocusProcess: GetKeyFocusProcess
    private let getProcessPID: GetProcessPID
    private let createPerProcessRemote: CreatePerProcessRemote
    private let createFlattenedInputSource: CreateFlattenedInputSource

    /// `nil` when any symbol is missing, which disables the whole path.
    static let shared = PrivateAPI()

    private init?() {
        let handle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let focus = dlsym(handle, "CPSGetKeyFocusProcess"),
              let pid = dlsym(handle, "GetProcessPID"),
              let port = dlsym(handle, "CFMessagePortCreatePerProcessRemote"),
              let flatten = dlsym(handle, "_CreateFlattenedInputSource")
        else { return nil }
        getKeyFocusProcess = unsafeBitCast(focus, to: GetKeyFocusProcess.self)
        getProcessPID = unsafeBitCast(pid, to: GetProcessPID.self)
        createPerProcessRemote = unsafeBitCast(port, to: CreatePerProcessRemote.self)
        createFlattenedInputSource = unsafeBitCast(flatten, to: CreateFlattenedInputSource.self)
    }

    func keyFocusPID() -> pid_t? {
        var process = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kNoProcess))
        var ignored: UInt8 = 0
        var pid: pid_t = 0
        guard getKeyFocusProcess(&process, &ignored) == 0,
              getProcessPID(&process, &pid) == noErr,
              pid > 0
        else { return nil }
        return pid
    }

    func flatten(_ source: TISInputSource) -> Any? {
        var flattened: Unmanaged<CFTypeRef>?
        let ok = createFlattenedInputSource(source, &flattened)
        let value = flattened?.takeRetainedValue()
        return ok != 0 ? value : nil
    }

    func send(_ request: Data, to pid: pid_t) -> Result<Data?, KeyFocusInputSourceSelector.Failure> {
        guard let port = createPerProcessRemote(nil, KeyFocusInputSourceSelector.portName as CFString, pid)?.takeRetainedValue() else {
            return .failure(.noPort)
        }
        var reply: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(
            port,
            KeyFocusInputSourceSelector.selectedMessageID,
            request as CFData,
            KeyFocusInputSourceSelector.sendTimeout,
            KeyFocusInputSourceSelector.replyTimeout,
            KeyFocusInputSourceSelector.replyMode as CFString,
            &reply
        )
        let data = reply?.takeRetainedValue() as Data?
        guard status == kCFMessagePortSuccess else { return .failure(.transport(status)) }
        return .success(data)
    }
}
