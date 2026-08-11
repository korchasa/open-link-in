import Foundation
import XCTest

@testable import SmartLinksOpener

/// [REF:fr:rules-search]
final class RuleFilterTests: XCTestCase {
    private func r(_ domain: String) -> Rule {
        Rule(domain: domain, bundleID: "com.apple.Safari")
    }

    private let rules = [
        Rule(domain: "github.com", bundleID: "a"),
        Rule(domain: "gist.github.io", bundleID: "b"),
        Rule(domain: "figma.com", bundleID: "c"),
        Rule(domain: "notion.so", bundleID: "d"),
    ]

    func testBlankQueryKeepsEveryRule() {
        XCTAssertEqual(RuleFilter.matching(rules, query: "").map(\.domain), rules.map(\.domain))
        // A field holding only spaces is still "no search", not "match nothing".
        XCTAssertEqual(RuleFilter.matching(rules, query: "   ").map(\.domain), rules.map(\.domain))
    }

    func testMatchesAnywhereInTheDomain() {
        // Substring, not prefix: the useful search is "which rule mentions github".
        XCTAssertEqual(
            RuleFilter.matching(rules, query: "github").map(\.domain),
            ["github.com", "gist.github.io"])
        XCTAssertEqual(RuleFilter.matching(rules, query: ".so").map(\.domain), ["notion.so"])
    }

    func testIgnoresCaseAndSurroundingSpaces() {
        XCTAssertEqual(RuleFilter.matching(rules, query: "  FIGMA ").map(\.domain), ["figma.com"])
    }

    func testKeepsTheOriginalOrder() {
        let shuffled = [r("zulip.com"), r("apple.com"), r("zoom.us")]
        XCTAssertEqual(
            RuleFilter.matching(shuffled, query: "o").map(\.domain),
            ["zulip.com", "apple.com", "zoom.us"])
    }

    func testNoMatchReturnsEmpty() {
        XCTAssertTrue(RuleFilter.matching(rules, query: "example").isEmpty)
    }
}
