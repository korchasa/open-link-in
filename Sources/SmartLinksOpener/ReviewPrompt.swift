import Foundation

/// When to ask macOS for an App Store rating: after the 3rd link actually
/// routed to a browser, not on the calendar day of the first one, at the moment
/// the user closes the rules window, at most once per app version. A later
/// version needs 3 successes of its own. Pure and `Codable` so the gate is unit
/// tested and persisted as one value; whether a sheet is drawn stays macOS's
/// decision. [REF:fr:rating-request]
struct ReviewPrompt: Codable, Equatable {
    static let threshold = 3

    /// The moments the app consults the gate. Only closing the rules window can
    /// carry a request: the user has finished what they came to do there, so
    /// the sheet interrupts nothing. Opening it starts a task and never asks.
    enum Moment {
        case rulesWindowOpened
        case rulesWindowClosed
    }

    /// Successful routings since the last request.
    private(set) var successes = 0
    /// `CFBundleShortVersionString` of the version that last made a request.
    private(set) var requestedVersion: String?
    /// When the first counted success happened — the first day of use. Kept
    /// across requests and versions. Absent in state stored before it existed;
    /// then the next success records it.
    private(set) var firstSuccess: Date?

    /// A link reached a browser. Not counted in a version that already asked,
    /// so the next version starts from zero.
    mutating func noteSuccess(version: String, at now: Date) {
        guard requestedVersion != version else { return }
        if firstSuccess == nil { firstSuccess = now }
        successes += 1
    }

    /// Due only on closing the rules window, after `threshold` successes, in a
    /// version that has not asked, and never on the day of the first success
    /// (an unknown first day counts as not over yet).
    func isDue(at moment: Moment, version: String, now: Date, calendar: Calendar) -> Bool {
        moment == .rulesWindowClosed
            && successes >= Self.threshold
            && requestedVersion != version
            && !isFirstDayOfUse(now: now, calendar: calendar)
    }

    /// True while `now` is the calendar day of the first success, or that day
    /// is not known yet. Also feeds the gate's log lines.
    func isFirstDayOfUse(now: Date, calendar: Calendar) -> Bool {
        guard let firstSuccess else { return true }
        return calendar.isDate(now, inSameDayAs: firstSuccess)
    }

    mutating func markRequested(version: String) {
        requestedVersion = version
        successes = 0
    }
}
