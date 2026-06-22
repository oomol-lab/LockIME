import Foundation

/// Pure decision of whether a focused Accessibility element is a browser's
/// address bar (omnibox / unified URL field), kept separate from the AX plumbing
/// so it is unit-testable without a live Accessibility tree.
///
/// The signal is **structural + per-engine identifier**, never localized text.
/// Empirically (macOS 26, real AX API across Chrome/Safari/Firefox), each
/// engine's address bar exposes a stable, language-independent identifier, and
/// the element lives in the browser's native chrome (under an `AXToolbar`),
/// **not** inside the page content (`AXWebArea`). A page `<input>` shares the
/// `AXTextField` role, so the role alone is never enough — the chrome-vs-web-area
/// structure is what separates them. The localized `AXDescription`
/// ("Address and search bar", localized per UI language) is deliberately ignored;
/// matching it would break under the app's in-app language override.
public enum AddressBarHeuristic {
    /// Safari/WebKit exposes the unified field with this `AXIdentifier`.
    public static let safariIdentifier = "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD"
    /// Chromium's omnibox carries this class in its `AXDOMClassList`.
    public static let chromiumDOMClass = "OmniboxViewViews"
    /// Firefox/Gecko's urlbar exposes this `AXDOMIdentifier`.
    public static let geckoDOMIdentifier = "urlbar-input"

    /// Whether the focused element is a browser address bar.
    ///
    /// - `identifier`: the element's `AXIdentifier` (Safari).
    /// - `domIdentifier`: its `AXDOMIdentifier` (Firefox).
    /// - `domClassList`: its `AXDOMClassList` (Chromium).
    /// - `ancestorRoles`: the `AXRole`s of its ancestors, nearest first, used for
    ///   the structural gate (in the toolbar chrome, not in the web area).
    public static func isAddressBar(
        identifier: String?,
        domIdentifier: String?,
        domClassList: [String],
        ancestorRoles: [String]
    ) -> Bool {
        // Structural gate: the element must sit in the native chrome (under an
        // AXToolbar) and NOT inside the page content (AXWebArea). This is what
        // separates the address bar from an in-page text field, which shares the
        // AXTextField role but is rooted in the AXWebArea.
        guard ancestorRoles.contains("AXToolbar"), !ancestorRoles.contains("AXWebArea") else {
            return false
        }
        if identifier == safariIdentifier { return true }
        if domIdentifier == geckoDOMIdentifier { return true }
        if domClassList.contains(chromiumDOMClass) { return true }
        return false
    }
}
