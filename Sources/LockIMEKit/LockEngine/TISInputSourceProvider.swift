import Carbon
import Foundation
import os

/// Real `InputSourceProviding` backed by Carbon Text Input Services.
///
/// All `Copy`/`Create` results are released via `takeRetainedValue()`;
/// `TISGetInputSourceProperty` follows the "get" rule (`takeUnretainedValue`).
@MainActor
public final class TISInputSourceProvider: InputSourceProviding {
    private static let logger = Logger(subsystem: LogSubsystem.current, category: "TISInputSourceProvider")

    public init() {}

    /// Tracks a key-focus selection the system has not confirmed yet (see
    /// `DirectSelectionConfirmation`).
    private var directSelection = DirectSelectionConfirmation()

    public func currentSourceID() -> InputSourceID? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        let id = Self.string(source, kTISPropertyInputSourceID).map { InputSourceID($0) }
        directSelection.observed(current: id)
        return id
    }

    public func selectableSources() -> [InputSource] {
        Self.allSources()
            .filter { Self.string($0, kTISPropertyInputSourceCategory) == keyboardCategory }
            .compactMap(Self.makeInputSource)
            .filter { $0.isEnabled && $0.isSelectCapable }
    }

    private let keyboardCategory = kTISCategoryKeyboardInputSource as String

    public func source(for id: InputSourceID) -> InputSource? {
        Self.findSource(id).flatMap(Self.makeInputSource)
    }

    @discardableResult
    public func select(_ id: InputSourceID) -> Bool {
        guard let source = Self.findSource(id) else { return false }
        guard Self.bool(source, kTISPropertyInputSourceIsSelectCapable),
              Self.bool(source, kTISPropertyInputSourceIsEnabled)
        else { return false }

        let isCJKV = InputSourceClassifier.isCJKV(languages: Self.languages(source))

        // A background `TISSelectInputSource` for an input *method* can leave
        // the focused app half-switched: the menu bar and every read-back show
        // the IME while the app keeps typing Latin (issue #69). Have the app
        // that owns keyboard focus perform the selection itself instead. Any
        // failure — and a retry of a selection the system never confirmed —
        // falls through to the public API below, i.e. the previous behavior.
        //
        // Unlike `TISSelectInputSource`, a key-focus selection is not visible
        // to our own `currentSourceID()` until the "selected source changed"
        // notification has been delivered, so don't read it back here.
        if isCJKV {
            if !directSelection.shouldTryDirect(for: id) {
                Self.logger.debug("Key-focus selection of \(id.rawValue, privacy: .public) was never confirmed; using TISSelectInputSource")
            } else {
                switch KeyFocusInputSourceSelector.select(source) {
                case .success:
                    directSelection.didSelectDirectly(id)
                    return true
                case let .failure(error):
                    Self.logger.debug("Key-focus selection failed (\(String(describing: error), privacy: .public)); using TISSelectInputSource")
                }
            }
        }

        guard TISSelectInputSource(source) == noErr else { return false }

        // Fallback path only. A CJKV `TISSelectInputSource` can also fail
        // outright: `noErr`, but the active source doesn't flip. Only nudge
        // when a read-back confirms that — the old code nudged on *every* CJKV
        // switch, and the nudge re-activated the frontmost app, which reset
        // the mouse pointer in Chromium/Electron apps (issue #1).
        if isCJKV, currentSourceID() != id {
            FocusNudge.perform()
        }
        return true
    }

    // MARK: - TIS plumbing

    private static func allSources() -> [TISInputSource] {
        guard let array = TISCreateInputSourceList(nil, false)?.takeRetainedValue()
            as? [TISInputSource]
        else { return [] }
        return array
    }

    private static func findSource(_ id: InputSourceID) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id.rawValue] as CFDictionary
        guard let array = TISCreateInputSourceList(filter, false)?.takeRetainedValue()
            as? [TISInputSource]
        else { return nil }
        return array.first
    }

    private static func makeInputSource(_ source: TISInputSource) -> InputSource? {
        guard let id = string(source, kTISPropertyInputSourceID) else { return nil }
        return InputSource(
            id: InputSourceID(id),
            localizedName: string(source, kTISPropertyLocalizedName) ?? id,
            isSelectCapable: bool(source, kTISPropertyInputSourceIsSelectCapable),
            isEnabled: bool(source, kTISPropertyInputSourceIsEnabled),
            isCJKV: InputSourceClassifier.isCJKV(languages: languages(source))
        )
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private static func bool(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }

    private static func languages(_ source: TISInputSource) -> [String] {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return []
        }
        return Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String] ?? []
    }
}
