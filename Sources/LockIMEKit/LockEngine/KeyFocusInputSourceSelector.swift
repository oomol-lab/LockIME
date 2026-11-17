import Carbon
import Foundation

/// Selects an input source **inside the process that owns keyboard focus**, the
/// way the system Input menu does, instead of from our own background process.
///
/// Why this exists (issue #69): `TISSelectInputSource` called from a process
/// *without* keyboard focus commits the new source system-wide first and only
/// then tells the focused app to switch. For an input *method* (a CJKV IME,
/// third-party ones especially) the focused app activates the IME and drops it
/// again a moment later. The result is a half-switched state that every public
/// API reports as success: the menu bar and `TISCopyCurrentKeyboardInputSource`
/// show the IME, while the focused app keeps typing Latin and the IME's own
/// menu never loads. A read-back cannot see it, so the lock believes it is
/// satisfied and never repairs it.
///
/// Sending HIToolbox's own "input source selected" request (message 7 on the
/// per-process `com.apple.tsm.portname` port) to the key-focus process makes
/// that app perform the selection itself, so the IME is activated where the
/// keystrokes actually go and the system-wide state follows from it.
///
/// The protocol is private. Every symbol is resolved at run time and every
/// step can fail (`Failure`); the caller then falls back to the public
/// `TISSelectInputSource`, so a macOS release that changes the protocol
/// degrades to the previous behavior instead of breaking the lock. Needs no
/// permission (the app is not sandboxed).
///
/// Protocol details adapted from macism (MIT, Copyright (c) 2023
/// https://github.com/laishulu) and MacIMEKit (MIT, Copyright (c) 2026 Haruka,
/// https://github.com/harukawu/MacIMEKit).
///
/// This file holds the transport-independent half (sequencing, request
/// encoding, reply decoding), which is unit-tested. The private HIToolbox calls
/// live in `KeyFocusInputSourceSelector+HIToolbox.swift`.
@MainActor
enum KeyFocusInputSourceSelector {
    enum Failure: Error, Equatable {
        /// A private symbol is missing on this macOS release.
        case unavailable
        /// No process owns keyboard focus right now.
        case noFocus
        /// We own keyboard focus ourselves: a plain `TISSelectInputSource`
        /// from the focused process is already the reliable path.
        case ownProcess
        /// The source could not be flattened / encoded into a request.
        case serialization
        /// The focused process has no Text Services Manager port.
        case noPort
        /// `CFMessagePortSendRequest` failed (timeout, invalid port, …).
        case transport(Int32)
        /// The reply was missing or not the expected property list.
        case invalidReply
        /// The focused app's TSM answered with an error status.
        case rejected(Int32)
    }

    /// The system calls behind a selection, injectable so the sequencing and
    /// the reply handling are unit-testable without touching the keyboard.
    struct Transport {
        /// PID of the process that receives key events. Not always the
        /// frontmost app: a non-activating panel (Spotlight, a launcher) can
        /// hold keyboard focus.
        var keyFocusPID: @MainActor () -> pid_t?
        /// Our own PID.
        var ownPID: @MainActor () -> pid_t
        /// Send the encoded request to `pid`'s TSM port and return the raw reply.
        var send: @MainActor (_ pid: pid_t, _ request: Data) -> Result<Data?, Failure>
    }

    /// Request / reply property-list keys of HIToolbox's selection message.
    nonisolated static let requestKey = "tsmInputSourceSelectedInpSrcKey"
    nonisolated static let replyErrorKey = "tsmInputModeReplyToServerErrorKey"

    /// The transport-independent sequence: resolve focus, encode, send, decode.
    static func select(
        flatten: @MainActor () -> Any?,
        transport: Transport
    ) -> Result<Void, Failure> {
        guard let pid = transport.keyFocusPID() else { return .failure(.noFocus) }
        guard pid != transport.ownPID() else { return .failure(.ownProcess) }
        guard let flattened = flatten(), let request = encodeRequest(flattened) else {
            return .failure(.serialization)
        }
        switch transport.send(pid, request) {
        case let .failure(error): return .failure(error)
        case let .success(reply): return parseReply(reply)
        }
    }

    /// Wrap a flattened input source in the request property list.
    static func encodeRequest(_ flattened: Any) -> Data? {
        let plist: [String: Any] = [requestKey: flattened]
        guard PropertyListSerialization.propertyList(plist, isValidFor: .xml) else { return nil }
        return try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    /// Decode the focused app's reply: a property list carrying an `OSStatus`.
    static func parseReply(_ data: Data?) -> Result<Void, Failure> {
        guard let data,
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any],
              let status = dictionary[replyErrorKey] as? NSNumber,
              CFGetTypeID(status) == CFNumberGetTypeID()
        else { return .failure(.invalidReply) }
        return status.int32Value == noErr ? .success(()) : .failure(.rejected(status.int32Value))
    }
}
