import Foundation

/// Pure helpers for classifying input sources, kept separate so they can be
/// unit-tested without Carbon.
public enum InputSourceClassifier {
    private static let cjkvPrimaryLanguages: Set<String> = [
        "zh", "ja", "ko", "vi", "yue",
    ]

    /// Whether an input source's `kTISPropertyInputSourceLanguages` indicates a
    /// CJKV input method. A background `TISSelectInputSource` is unreliable
    /// for these, so they are selected through the app that owns keyboard
    /// focus (`KeyFocusInputSourceSelector`).
    public static func isCJKV(languages: [String]) -> Bool {
        languages.contains { language in
            let primary = language.split(separator: "-").first.map(String.init) ?? language
            return cjkvPrimaryLanguages.contains(primary.lowercased())
        }
    }
}
