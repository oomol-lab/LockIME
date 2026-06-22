import Foundation
import Testing

@testable import LockIMEKit

@Suite("AddressBarHeuristic")
struct AddressBarHeuristicTests {
    // The address bar lives in the browser chrome: under an AXToolbar, never
    // inside the page's AXWebArea.
    private let chromeAncestors = ["AXGroup", "AXToolbar", "AXGroup", "AXWindow"]
    // A page <input> is rooted in the web content.
    private let webAreaAncestors = ["AXWebArea", "AXScrollArea", "AXGroup", "AXWindow"]

    @Test("Safari's address field is detected by its AXIdentifier")
    func safari() {
        #expect(AddressBarHeuristic.isAddressBar(
            identifier: "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD",
            domIdentifier: nil, domClassList: [], ancestorRoles: chromeAncestors
        ))
    }

    @Test("Chromium's omnibox is detected by its AXDOMClassList")
    func chromium() {
        #expect(AddressBarHeuristic.isAddressBar(
            identifier: nil, domIdentifier: nil,
            domClassList: ["OmniboxViewViews"], ancestorRoles: chromeAncestors
        ))
    }

    @Test("Firefox's urlbar is detected by its AXDOMIdentifier")
    func firefox() {
        #expect(AddressBarHeuristic.isAddressBar(
            identifier: nil, domIdentifier: "urlbar-input",
            domClassList: [], ancestorRoles: chromeAncestors
        ))
    }

    @Test("a page input matching no identifier is not the address bar")
    func pageInput() {
        #expect(!AddressBarHeuristic.isAddressBar(
            identifier: nil, domIdentifier: "pageinput",
            domClassList: [], ancestorRoles: webAreaAncestors
        ))
    }

    @Test("a matching identifier inside the web area is rejected by the structural gate")
    func identifierInsideWebAreaRejected() {
        // Even if a page element somehow carried the omnibox class, being rooted
        // in the AXWebArea (not the toolbar chrome) disqualifies it.
        #expect(!AddressBarHeuristic.isAddressBar(
            identifier: "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD",
            domIdentifier: "urlbar-input",
            domClassList: ["OmniboxViewViews"],
            ancestorRoles: webAreaAncestors
        ))
    }

    @Test("a toolbar element without any known identifier is not the address bar")
    func toolbarButNoIdentifier() {
        // A different toolbar text field (e.g. a find bar) sits under the toolbar
        // but carries none of the per-engine address-bar identifiers.
        #expect(!AddressBarHeuristic.isAddressBar(
            identifier: "SOME_OTHER_FIELD", domIdentifier: nil,
            domClassList: ["FindBarView"], ancestorRoles: chromeAncestors
        ))
    }

    @Test("no toolbar ancestor at all is not the address bar")
    func noToolbar() {
        #expect(!AddressBarHeuristic.isAddressBar(
            identifier: "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD",
            domIdentifier: nil, domClassList: [],
            ancestorRoles: ["AXGroup", "AXWindow"]
        ))
    }
}
