import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global shortcut that toggles LockIME ("Enable LockIME") on/off.
    /// `KeyboardShortcuts.Name` is an immutable name wrapper; safe as a constant.
    nonisolated(unsafe) static let toggleLock = Self("toggleLock")

    /// Global: lock to the previous / next entry in the input-source list,
    /// wrapping around the ends. Always lands on a valid source (never "none").
    nonisolated(unsafe) static let globalPreviousSource = Self("globalPreviousSource")
    nonisolated(unsafe) static let globalNextSource = Self("globalNextSource")

    /// Frontmost-app scoped: cycle *that app's* rule to the previous / next
    /// input source. A no-op when the frontmost app has no rule of its own.
    nonisolated(unsafe) static let appPreviousSource = Self("appPreviousSource")
    nonisolated(unsafe) static let appNextSource = Self("appNextSource")

    /// Frontmost-app scoped: remove that app's rule entirely. A no-op when the
    /// frontmost app has no rule.
    nonisolated(unsafe) static let removeFrontmostAppRule = Self("removeFrontmostAppRule")
}
