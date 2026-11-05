import Foundation
import XCTest

@testable import SmartLinksOpener

/// Acceptance for retiring an abandoned picker: idle expiry, displacement by a
/// new link, and re-routing queued links once a rule covers them.
/// [REF:fr:picker]
final class PickerQueueTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private let a = URL(string: "https://a.example.com/1")!
    private let b = URL(string: "https://b.example.org/2")!
    private let c = URL(string: "https://c.example.net/3")!
    private let d = URL(string: "https://d.example.io/4")!

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    // MARK: Arrival

    func testFirstLinkShowsItsPicker() {
        var q = PickerQueue()
        XCTAssertEqual(q.enqueue(a, now: t0), .showHead)
        XCTAssertEqual(q.head, a)
        XCTAssertEqual(q.count, 1)
    }

    func testBurstQueuesBehindTheShownLink() {
        var q = PickerQueue()
        _ = q.enqueue(a, now: t0)
        XCTAssertEqual(q.enqueue(b, now: at(0.2)), .queued)
        XCTAssertEqual(q.enqueue(c, now: at(1)), .queued)
        XCTAssertEqual(q.head, a)
        XCTAssertEqual(q.count, 3)
    }

    func testLinkAfterAnAbandonedPickerReplacesTheWholeQueue() {
        var q = PickerQueue()
        _ = q.enqueue(a, now: t0)
        _ = q.enqueue(b, now: at(0.1))
        XCTAssertEqual(q.enqueue(d, now: at(10)), .showHead)
        XCTAssertEqual(q.head, d)
        XCTAssertEqual(q.count, 1)
    }

    func testActivityKeepsThePickerFromBeingAbandoned() {
        var q = PickerQueue()
        _ = q.enqueue(a, now: t0)
        q.noteActivity(now: at(5))
        XCTAssertEqual(q.enqueue(b, now: at(6)), .queued)
        XCTAssertEqual(q.head, a)
    }

    func testMatchedLinkDropsAnAbandonedQueueButNotAnActiveOne() {
        var q = PickerQueue()
        _ = q.enqueue(a, now: t0)
        XCTAssertFalse(q.dropIfAbandoned(now: at(1)))
        XCTAssertEqual(q.count, 1)
        XCTAssertTrue(q.dropIfAbandoned(now: at(3)))
        XCTAssertNil(q.head)
        XCTAssertFalse(q.dropIfAbandoned(now: at(100)))  // empty: nothing to drop
    }

    // MARK: Expiry

    func testIdlePickerExpiresAtSixtySecondsNotBefore() {
        var q = PickerQueue()
        _ = q.enqueue(a, now: t0)
        _ = q.enqueue(b, now: at(0.1))
        XCTAssertFalse(q.expireIfIdle(now: at(59)))
        XCTAssertEqual(q.count, 2)
        XCTAssertTrue(q.expireIfIdle(now: at(60)))
        XCTAssertEqual(q.count, 0)
    }

    func testActivityPostponesExpiry() {
        var q = PickerQueue()
        _ = q.enqueue(a, now: t0)
        q.noteActivity(now: at(50))
        XCTAssertFalse(q.expireIfIdle(now: at(100)))
        XCTAssertTrue(q.expireIfIdle(now: at(110)))
    }

    func testSecondsUntilExpiry() {
        var q = PickerQueue()
        XCTAssertNil(q.secondsUntilExpiry(now: t0))
        _ = q.enqueue(a, now: t0)
        XCTAssertEqual(q.secondsUntilExpiry(now: at(15)), 45)
        XCTAssertEqual(q.secondsUntilExpiry(now: at(90)), 0)
    }

    func testActivityOnAnEmptyQueueIsIgnored() {
        var q = PickerQueue()
        q.noteActivity(now: t0)
        XCTAssertNil(q.secondsUntilExpiry(now: t0))
        XCTAssertEqual(q.enqueue(a, now: at(100)), .showHead)
    }

    // MARK: Advance and reroute

    func testAdvanceShowsTheNextLinkWithAFreshClock() {
        var q = PickerQueue()
        _ = q.enqueue(a, now: t0)
        _ = q.enqueue(b, now: at(0.1))
        XCTAssertEqual(q.advance(now: at(30)) { _ in false }, [])
        XCTAssertEqual(q.head, b)
        XCTAssertFalse(q.expireIfIdle(now: at(60)))
        XCTAssertTrue(q.expireIfIdle(now: at(90)))
    }

    func testAdvanceOpensQueuedLinksThatGainedARule() {
        var q = PickerQueue()
        let a2 = URL(string: "https://a.example.com/other")!
        _ = q.enqueue(a, now: t0)
        _ = q.enqueue(a2, now: at(0.1))
        _ = q.enqueue(c, now: at(0.2))
        let opened = q.advance(now: at(5)) { $0.host == "a.example.com" }
        XCTAssertEqual(opened, [a2])
        XCTAssertEqual(q.head, c)
        XCTAssertEqual(q.count, 1)
    }

    func testAdvanceOfTheLastLinkEmptiesTheQueue() {
        var q = PickerQueue()
        _ = q.enqueue(a, now: t0)
        XCTAssertEqual(q.advance(now: at(1)) { _ in false }, [])
        XCTAssertNil(q.head)
        XCTAssertNil(q.secondsUntilExpiry(now: at(1)))
    }

    func testRerouteOpensAShownLinkThatGainedARule() {
        var q = PickerQueue()
        _ = q.enqueue(a, now: t0)
        _ = q.enqueue(b, now: at(0.1))
        XCTAssertEqual(q.reroute(now: at(20)) { $0 == self.a }, [a])
        XCTAssertEqual(q.head, b)
        XCTAssertEqual(q.secondsUntilExpiry(now: at(20)), 60)
    }

    func testRerouteThatKeepsTheHeadCountsAsActivity() {
        var q = PickerQueue()
        _ = q.enqueue(a, now: t0)
        _ = q.enqueue(b, now: at(0.1))
        XCTAssertEqual(q.reroute(now: at(40)) { $0 == self.b }, [b])
        XCTAssertEqual(q.head, a)
        XCTAssertEqual(q.count, 1)
        XCTAssertEqual(q.secondsUntilExpiry(now: at(40)), 60)
    }
}
