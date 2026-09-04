import Foundation
import XCTest

@testable import SmartLinksOpener

/// Acceptance for the always-ask rule mode and its place in matching.
/// [REF:fr:always-ask]
final class RoutingTests: XCTestCase {
    private let safari = "com.apple.Safari"
    private let chrome = "com.google.Chrome"

    func testAskRuleRaisesThePickerInsteadOfOpening() {
        let rules = [Rule(domain: "github.com", bundleID: "", mode: .ask)]
        XCTAssertEqual(
            Routing.decide(host: "gist.github.com", rules: rules, installed: [safari]), .ask)
    }

    func testOpenRuleStillOpensSilently() {
        let rules = [Rule(domain: "github.com", bundleID: safari)]
        XCTAssertEqual(
            Routing.decide(host: "github.com", rules: rules, installed: [safari]),
            .open(bundleID: safari))
    }

    func testNoRuleIsUnmatched() {
        XCTAssertEqual(Routing.decide(host: "example.com", rules: [], installed: [safari]), .unmatched)
    }

    func testLongestDomainWinsAcrossModes() {
        let rules = [
            Rule(domain: "co.uk", bundleID: safari),
            Rule(domain: "bbc.co.uk", bundleID: "", mode: .ask),
        ]
        XCTAssertEqual(Routing.decide(host: "news.bbc.co.uk", rules: rules, installed: [safari]), .ask)
        XCTAssertEqual(
            Routing.decide(host: "other.co.uk", rules: rules, installed: [safari]), .open(bundleID: safari))
    }

    func testAskRuleNeedsNoInstalledBrowser() {
        let rules = [Rule(domain: "github.com", bundleID: chrome, mode: .ask)]
        XCTAssertEqual(Routing.decide(host: "github.com", rules: rules, installed: []), .ask)
    }

    func testRuleWithMissingBrowserIsSkipped() {
        let rules = [Rule(domain: "github.com", bundleID: chrome)]
        XCTAssertEqual(Routing.decide(host: "github.com", rules: rules, installed: [safari]), .unmatched)
    }

    func testStoredRulesWithoutModeDecodeAsOpen() throws {
        let json = #"[{"id":"6E1D2C1E-0000-4000-8000-000000000001","domain":"github.com","bundleID":"com.apple.Safari"}]"#
        let rules = try JSONDecoder().decode([Rule].self, from: Data(json.utf8))
        XCTAssertEqual(rules.first?.mode, .open)
    }

    func testModeRoundTripsThroughJSON() throws {
        let rule = Rule(domain: "github.com", bundleID: "", mode: .ask)
        let data = try JSONEncoder().encode([rule])
        XCTAssertEqual(try JSONDecoder().decode([Rule].self, from: data), [rule])
    }
}
