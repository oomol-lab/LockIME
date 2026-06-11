import Foundation

/// Which way to step through the ordered input-source list.
public enum CycleDirection: Sendable {
    case previous
    case next
}

/// Pure index math for the "lock to previous/next input source" shortcuts.
///
/// Cycling stays inside the *valid* sources (the caller passes the enabled,
/// selectable list), wraps around at both ends, and never yields a "none"
/// target. With fewer than two sources there is nowhere to move, so it returns
/// `nil` and the caller does nothing — which is also why pressing the shortcut
/// with a single input source installed is a deliberate no-op.
public enum SourceCycler {
    /// The source `direction` steps from `reference` within `sources`, wrapping
    /// around the ends.
    ///
    /// - Returns `nil` when cycling is a no-op: fewer than two sources.
    /// - When `reference` is absent from `sources` (nothing locked yet, or the
    ///   locked source was removed), the first press lands on the first source
    ///   for `.next` and the last for `.previous`, so it still moves predictably.
    public static func step(
        from reference: InputSourceID?,
        in sources: [InputSourceID],
        direction: CycleDirection
    ) -> InputSourceID? {
        guard sources.count >= 2 else { return nil }
        guard let reference, let index = sources.firstIndex(of: reference) else {
            return direction == .next ? sources.first : sources.last
        }
        let count = sources.count
        let offset = direction == .next ? 1 : -1
        // Euclidean modulo so `.previous` from index 0 wraps to the last source.
        let next = ((index + offset) % count + count) % count
        return sources[next]
    }
}
