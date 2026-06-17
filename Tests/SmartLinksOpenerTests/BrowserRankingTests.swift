import Foundation
import XCTest

@testable import SmartLinksOpener

/// [REF:fr:picker]
final class BrowserRankingTests: XCTestCase {
    private func b(_ name: String, _ id: String) -> Browser {
        Browser(name: name, bundleID: id, appURL: URL(fileURLWithPath: "/Applications/\(name).app"))
    }

    func testMostUsedFirst() {
        let list = [b("Safari", "a"), b("Chrome", "b"), b("Firefox", "c")]
        let counts = ["b": 10, "c": 3]
        let sorted = BrowserRanking.sorted(list, counts: counts)
        XCTAssertEqual(sorted.map(\.bundleID), ["b", "c", "a"])
    }

    func testTiesBrokenByNameCaseInsensitive() {
        let list = [b("Safari", "a"), b("Arc", "b"), b("brave", "c")]
        let sorted = BrowserRanking.sorted(list, counts: [:])  // all zero
        XCTAssertEqual(sorted.map(\.name), ["Arc", "brave", "Safari"])
    }

    func testStableForEmptyInput() {
        XCTAssertTrue(BrowserRanking.sorted([], counts: ["x": 5]).isEmpty)
    }
}
