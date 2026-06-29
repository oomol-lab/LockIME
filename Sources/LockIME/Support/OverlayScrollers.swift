import AppKit
import SwiftUI

extension View {
    /// Forces native macOS **overlay** scrollers — the thin bars that appear only
    /// while scrolling and fade away afterward — on every scroll view in this
    /// view's window, regardless of the system *Appearance ▸ Show scroll bars*
    /// setting (which can pin every app to the wide, always-visible *legacy*
    /// scrollers the user otherwise can't escape).
    ///
    /// SwiftUI exposes scroll-indicator *visibility* (`.scrollIndicators`) but not
    /// scroller *style* — that lives on `NSScrollView.scrollerStyle`. So we drop a
    /// zero-size probe into the background, find its host `NSWindow`, and sweep
    /// every `NSScrollView` in the window to `.overlay`. Overlay scrollers also
    /// float over the content instead of reserving a gutter, so this reclaims the
    /// width the legacy bars ate.
    ///
    /// - Parameter trigger: a value that changes whenever the set of mounted
    ///   scroll views might change (e.g. the selected settings tab), so the sweep
    ///   re-runs and catches scroll views that SwiftUI mounts lazily.
    func overlayScrollers(trigger: AnyHashable = 0) -> some View {
        background(OverlayScrollerSweep(trigger: trigger))
    }
}

private struct OverlayScrollerSweep: NSViewRepresentable {
    let trigger: AnyHashable

    func makeNSView(context: Context) -> SweepProbe { SweepProbe(frame: .zero) }
    func updateNSView(_ probe: SweepProbe, context: Context) { probe.sweep() }
}

/// Zero-size, event-transparent probe that re-styles its window's scroll views.
private final class SweepProbe: NSView {
    // The probe sits behind the content, but never intercept events meant for it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        // AppKit resets every scroller to the system style when the user flips
        // the "Show scroll bars" preference, so re-assert overlay when it does.
        NotificationCenter.default.removeObserver(
            self, name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(sweep),
            name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
        sweep()
    }

    /// Sweep now, then once more on the next runloop turn — a scroll view for a
    /// tab or sheet mounted in this same update pass may not be in the tree yet.
    @objc func sweep() {
        applyOverlayStyle()
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.applyOverlayStyle() }
        }
    }

    private func applyOverlayStyle() {
        guard let root = window?.contentView else { return }
        Self.forEachScrollView(in: root) { scrollView in
            if scrollView.scrollerStyle != .overlay { scrollView.scrollerStyle = .overlay }
        }
    }

    private static func forEachScrollView(in view: NSView, _ body: (NSScrollView) -> Void) {
        if let scrollView = view as? NSScrollView { body(scrollView) }
        for subview in view.subviews { forEachScrollView(in: subview, body) }
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
