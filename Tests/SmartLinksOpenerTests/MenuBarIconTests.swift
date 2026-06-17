import AppKit
import XCTest

@testable import SmartLinksOpener

/// Acceptance for FR-APP-ICON (menu-bar branding): `MenuBarIcon.render` is the
/// pure core that normalizes any source art to the fixed menu-bar point size and
/// keeps it full-color (non-template) so the brand icon shows in the menu bar.
final class MenuBarIconTests: XCTestCase {
    func testRenderProducesFixedPointSize() {
        let source = NSImage(size: NSSize(width: 1024, height: 1024))
        let out = MenuBarIcon.render(from: source)
        XCTAssertEqual(out.size.width, MenuBarIcon.pointSize)
        XCTAssertEqual(out.size.height, MenuBarIcon.pointSize)
    }

    func testRenderKeepsFullColorNotTemplate() {
        let source = NSImage(size: NSSize(width: 512, height: 512))
        XCTAssertFalse(MenuBarIcon.render(from: source).isTemplate)
    }
}
