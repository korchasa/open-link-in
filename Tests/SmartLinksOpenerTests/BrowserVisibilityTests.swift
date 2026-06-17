import Foundation
import XCTest

@testable import SmartLinksOpener

/// [REF:fr:browser-visibility]
final class BrowserVisibilityTests: XCTestCase {
    private func b(_ name: String, _ id: String) -> Browser {
        Browser(name: name, bundleID: id, appURL: URL(fileURLWithPath: "/Applications/\(name).app"))
    }

    func testHiddenExcludedFromPicker() {
        let list = [b("Safari", "a"), b("Chrome", "b"), b("Firefox", "c")]
        let visible = BrowserVisibility.visible(list, hidden: ["b"])
        XCTAssertEqual(visible.map(\.bundleID), ["a", "c"])  // order preserved, "b" dropped
    }

    func testCannotHideLastVisible() {
        let all = [b("Safari", "a"), b("Chrome", "b")]
        // One already hidden → only "a" visible → hiding "a" would empty the picker.
        XCTAssertFalse(BrowserVisibility.canHide("a", hidden: ["b"], all: all))
        // None hidden → either can be hidden (one remains).
        XCTAssertTrue(BrowserVisibility.canHide("a", hidden: [], all: all))
        // Already-hidden id cannot be "hidden" again.
        XCTAssertFalse(BrowserVisibility.canHide("b", hidden: ["b"], all: all))
    }
}
