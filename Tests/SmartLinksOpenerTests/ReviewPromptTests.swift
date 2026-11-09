import Foundation
import XCTest

@testable import SmartLinksOpener

/// Acceptance for the App Store rating request gate: due at the 3rd successful
/// routing, never on the calendar day of the first success, asked only when the
/// rules window closes, at most once per app version, 3 new successes in a
/// later version. [REF:fr:rating-request]
final class ReviewPromptTests: XCTestCase {
    /// A fixed calendar, so the day boundary does not depend on the machine.
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Sofia")!
        return c
    }

    private func day(_ d: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: hour))!
    }

    /// Day 9 is the first day of use; checks happen on day 10 unless a test says otherwise.
    private func routed(_ n: Int, in version: String, on date: Date? = nil, into p: inout ReviewPrompt) {
        for _ in 0..<n { p.noteSuccess(version: version, at: date ?? day(9)) }
    }

    private func dueOnClose(_ p: ReviewPrompt, _ version: String, on date: Date? = nil) -> Bool {
        p.isDue(at: .rulesWindowClosed, version: version, now: date ?? day(10), calendar: calendar)
    }

    func testNothingIsDueAtFirstLaunch() {
        XCTAssertFalse(dueOnClose(ReviewPrompt(), "1.0.4"))
    }

    func testFirstAndSecondSuccessAreNotEnough() {
        var p = ReviewPrompt()
        p.noteSuccess(version: "1.0.4", at: day(9))
        XCTAssertFalse(dueOnClose(p, "1.0.4"))
        p.noteSuccess(version: "1.0.4", at: day(9))
        XCTAssertFalse(dueOnClose(p, "1.0.4"))
    }

    func testThirdSuccessMakesTheRequestDue() {
        var p = ReviewPrompt()
        routed(3, in: "1.0.4", into: &p)
        XCTAssertTrue(dueOnClose(p, "1.0.4"))
    }

    // MARK: First day of use

    func testNeverDueOnTheDayOfTheFirstSuccess() {
        var p = ReviewPrompt()
        routed(3, in: "1.0.4", on: day(9, 9), into: &p)
        XCTAssertFalse(dueOnClose(p, "1.0.4", on: day(9, 23)), "same calendar day as the first success")
        XCTAssertTrue(dueOnClose(p, "1.0.4", on: day(10, 0)), "the next calendar day")
    }

    func testTheFirstDayIsTheFirstSuccessNotTheThird() {
        var p = ReviewPrompt()
        p.noteSuccess(version: "1.0.4", at: day(8))
        p.noteSuccess(version: "1.0.4", at: day(9))
        p.noteSuccess(version: "1.0.4", at: day(9))
        XCTAssertTrue(dueOnClose(p, "1.0.4", on: day(9, 18)), "the first success was on day 8")
    }

    func testTheFirstDayIsKeptAcrossARequest() {
        var p = ReviewPrompt()
        routed(3, in: "1.0.4", into: &p)
        p.markRequested(version: "1.0.4")
        routed(3, in: "1.0.5", on: day(20), into: &p)
        XCTAssertTrue(dueOnClose(p, "1.0.5", on: day(20)), "only the very first day of use is excluded")
    }

    func testOldStateWithoutTheFirstDayWaitsForTheNextSuccess() throws {
        // Stored by the first rating build, before the first day was recorded.
        let old = Data(#"{"successes":3}"#.utf8)
        var p = try JSONDecoder().decode(ReviewPrompt.self, from: old)
        XCTAssertEqual(p.successes, 3)
        XCTAssertNil(p.firstSuccess)
        XCTAssertFalse(dueOnClose(p, "1.0.4"), "the first day is unknown, so it is not over yet")
        p.noteSuccess(version: "1.0.4", at: day(10))
        XCTAssertFalse(dueOnClose(p, "1.0.4", on: day(10, 20)))
        XCTAssertTrue(dueOnClose(p, "1.0.4", on: day(11)))
    }

    // MARK: Moment of the request

    func testNeverDueWhenTheRulesWindowOpens() {
        var p = ReviewPrompt()
        routed(3, in: "1.0.4", into: &p)
        XCTAssertFalse(p.isDue(at: .rulesWindowOpened, version: "1.0.4", now: day(10), calendar: calendar))
        XCTAssertTrue(p.isDue(at: .rulesWindowClosed, version: "1.0.4", now: day(10), calendar: calendar))
    }

    // MARK: Once per version

    func testOnceRequestedNeverDueAgainInThatVersion() {
        var p = ReviewPrompt()
        routed(3, in: "1.0.4", into: &p)
        p.markRequested(version: "1.0.4")
        XCTAssertFalse(dueOnClose(p, "1.0.4"))
        routed(10, in: "1.0.4", into: &p)
        XCTAssertFalse(dueOnClose(p, "1.0.4"))
        XCTAssertEqual(p.successes, 0, "successes after a request in the same version must not count")
    }

    func testLaterVersionNeedsThreeNewSuccesses() {
        var p = ReviewPrompt()
        routed(3, in: "1.0.4", into: &p)
        p.markRequested(version: "1.0.4")
        routed(5, in: "1.0.4", into: &p)
        XCTAssertFalse(dueOnClose(p, "1.0.5"), "successes from the asked version carry nothing over")
        routed(2, in: "1.0.5", into: &p)
        XCTAssertFalse(dueOnClose(p, "1.0.5"))
        p.noteSuccess(version: "1.0.5", at: day(9))
        XCTAssertTrue(dueOnClose(p, "1.0.5"))
    }

    func testSuccessesBeforeAnUpdateStillCountIfNeverAsked() {
        var p = ReviewPrompt()
        routed(2, in: "1.0.4", into: &p)
        p.noteSuccess(version: "1.0.5", at: day(9))
        XCTAssertTrue(dueOnClose(p, "1.0.5"))
    }

    func testStateSurvivesAJSONRoundTrip() throws {
        var p = ReviewPrompt()
        routed(3, in: "1.0.4", into: &p)
        p.markRequested(version: "1.0.4")
        p.noteSuccess(version: "1.0.5", at: day(10))
        let decoded = try JSONDecoder().decode(ReviewPrompt.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(decoded, p)
        XCTAssertEqual(decoded.requestedVersion, "1.0.4")
        XCTAssertEqual(decoded.successes, 1)
        XCTAssertEqual(decoded.firstSuccess, day(9))
    }
}
