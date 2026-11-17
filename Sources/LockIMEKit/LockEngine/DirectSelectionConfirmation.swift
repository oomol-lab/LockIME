import Foundation

/// Guards the private key-focus selection (`KeyFocusInputSourceSelector`) with
/// a "never worse than the public API" rule.
///
/// The focused app acknowledges a key-focus selection, but that reply cannot
/// prove the source actually changed. So a successful direct selection stays
/// *unconfirmed* until the system reports that source as current. If the lock
/// asks for the same source again while it is still unconfirmed — its trailing
/// reconcile found the switch did not take — the retry skips the private path
/// and uses the public `TISSelectInputSource`, exactly as before the private
/// path existed.
///
/// Confirmation matters as much as the fallback: a *confirmed* selection must
/// not demote the next one, or a user toggling the source twice in a row would
/// push the second revert back onto the unreliable public path.
struct DirectSelectionConfirmation {
    /// The source of the last direct selection, until it is seen as current.
    private(set) var pending: InputSourceID?

    /// Record a direct selection the focused app acknowledged.
    mutating func didSelectDirectly(_ id: InputSourceID) {
        pending = id
    }

    /// Feed every read of the current source; seeing the pending one confirms it.
    mutating func observed(current: InputSourceID?) {
        if let pending, current == pending { self.pending = nil }
    }

    /// Whether a selection of `id` should try the direct path. `false` exactly
    /// once for a repeat of an unconfirmed direct selection (the caller then
    /// falls back), after which the slate is clean again.
    mutating func shouldTryDirect(for id: InputSourceID) -> Bool {
        guard pending == id else { return true }
        pending = nil
        return false
    }
}
