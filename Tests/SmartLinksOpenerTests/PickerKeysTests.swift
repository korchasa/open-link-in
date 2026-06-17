import Foundation
import XCTest

@testable import SmartLinksOpener

/// [REF:fr:picker]
final class PickerKeysTests: XCTestCase {
    func testHotkeyLabelsOneThroughNineThenZeroThenNone() {
        XCTAssertEqual(PickerKeys.hotkey(index: 0), "1")
        XCTAssertEqual(PickerKeys.hotkey(index: 8), "9")
        XCTAssertEqual(PickerKeys.hotkey(index: 9), "0")  // tenth row uses the "0" key
        XCTAssertNil(PickerKeys.hotkey(index: 10))  // eleventh row has no key
        XCTAssertNil(PickerKeys.hotkey(index: -1))
    }

    func testDigitSelectionMapsKeysToRowsAndRespectsCount() {
        XCTAssertEqual(PickerKeys.selection(forKey: 1, count: 6), 0)  // "1" → first
        XCTAssertEqual(PickerKeys.selection(forKey: 6, count: 6), 5)  // "6" → last of six
        XCTAssertNil(PickerKeys.selection(forKey: 7, count: 6))  // beyond the list
        XCTAssertEqual(PickerKeys.selection(forKey: 0, count: 10), 9)  // "0" → tenth
        XCTAssertNil(PickerKeys.selection(forKey: 0, count: 6))  // tenth absent
    }

    func testArrowNavigationWrapsAround() {
        XCTAssertEqual(PickerKeys.move(0, by: -1, count: 6), 5)  // up from first → last
        XCTAssertEqual(PickerKeys.move(5, by: 1, count: 6), 0)  // down from last → first
        XCTAssertEqual(PickerKeys.move(2, by: 1, count: 6), 3)
        XCTAssertEqual(PickerKeys.move(0, by: -1, count: 0), 0)  // empty list: no move
    }
}
