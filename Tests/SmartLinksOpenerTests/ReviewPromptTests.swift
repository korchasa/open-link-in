import Foundation
import XCTest

@testable import SmartLinksOpener

/// Acceptance for the App Store rating request gate: due at the 3rd successful
/// routing, at most once per app version, 3 new successes in a later version.
/// [REF:fr:rating-request]
final class ReviewPromptTests: XCTestCase {
    private func routed(_ n: Int, in version: String, into p: inout ReviewPrompt) {
        for _ in 0..<n { p.noteSuccess(version: version) }
    }

    func testNothingIsDueAtFirstLaunch() {
        XCTAssertFalse(ReviewPrompt().isDue(version: "1.0.4"))
    }

    func testFirstAndSecondSuccessAreNotEnough() {
        var p = ReviewPrompt()
        p.noteSuccess(version: "1.0.4")
        XCTAssertFalse(p.isDue(version: "1.0.4"))
        p.noteSuccess(version: "1.0.4")
        XCTAssertFalse(p.isDue(version: "1.0.4"))
    }

    func testThirdSuccessMakesTheRequestDue() {
        var p = ReviewPrompt()
        routed(3, in: "1.0.4", into: &p)
        XCTAssertTrue(p.isDue(version: "1.0.4"))
    }

    func testOnceRequestedNeverDueAgainInThatVersion() {
        var p = ReviewPrompt()
        routed(3, in: "1.0.4", into: &p)
        p.markRequested(version: "1.0.4")
        XCTAssertFalse(p.isDue(version: "1.0.4"))
        routed(10, in: "1.0.4", into: &p)
        XCTAssertFalse(p.isDue(version: "1.0.4"))
        XCTAssertEqual(p.successes, 0, "successes after a request in the same version must not count")
    }

    func testLaterVersionNeedsThreeNewSuccesses() {
        var p = ReviewPrompt()
        routed(3, in: "1.0.4", into: &p)
        p.markRequested(version: "1.0.4")
        routed(5, in: "1.0.4", into: &p)
        XCTAssertFalse(p.isDue(version: "1.0.5"), "successes from the asked version carry nothing over")
        routed(2, in: "1.0.5", into: &p)
        XCTAssertFalse(p.isDue(version: "1.0.5"))
        p.noteSuccess(version: "1.0.5")
        XCTAssertTrue(p.isDue(version: "1.0.5"))
    }

    func testSuccessesBeforeAnUpdateStillCountIfNeverAsked() {
        var p = ReviewPrompt()
        routed(2, in: "1.0.4", into: &p)
        p.noteSuccess(version: "1.0.5")
        XCTAssertTrue(p.isDue(version: "1.0.5"))
    }

    func testStateSurvivesAJSONRoundTrip() throws {
        var p = ReviewPrompt()
        routed(3, in: "1.0.4", into: &p)
        p.markRequested(version: "1.0.4")
        p.noteSuccess(version: "1.0.5")
        let decoded = try JSONDecoder().decode(ReviewPrompt.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(decoded, p)
        XCTAssertEqual(decoded.requestedVersion, "1.0.4")
        XCTAssertEqual(decoded.successes, 1)
    }
}
