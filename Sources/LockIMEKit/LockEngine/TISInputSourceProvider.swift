import Carbon
import Foundation

/// Real `InputSourceProviding` backed by Carbon Text Input Services.
///
/// All `Copy`/`Create` results are released via `takeRetainedValue()`;
/// `TISGetInputSourceProperty` follows the "get" rule (`takeUnretainedValue`).
@MainActor
public final class TISInputSourceProvider: InputSourceProviding {
    public init() {}

    public func currentSourceID() -> InputSourceID? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return Self.string(source, kTISPropertyInputSourceID).map { InputSourceID($0) }
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

        guard TISSelectInputSource(source) == noErr else { return false }

        // CJKV input methods sometimes ignore a background `TISSelectInputSource`:
        // the call returns `noErr` but the active source doesn't actually flip.
        // Only nudge when a read-back confirms the switch didn't take — the old
        // code nudged on *every* CJKV switch, and the nudge re-activated the
        // frontmost app, which reset the mouse pointer in Chromium/Electron
        // apps (issue #1).
        if InputSourceClassifier.isCJKV(languages: Self.languages(source)),
           currentSourceID() != id {
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
