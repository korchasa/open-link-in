import Foundation

/// When to ask macOS for an App Store rating: after the 3rd link actually
/// routed to a browser, at most once per app version. A later version needs 3
/// successes of its own. Pure and `Codable` so the gate is unit tested and
/// persisted as one value; whether a sheet is drawn stays macOS's decision.
/// [REF:fr:rating-request]
struct ReviewPrompt: Codable, Equatable {
    static let threshold = 3

    /// Successful routings since the last request.
    private(set) var successes = 0
    /// `CFBundleShortVersionString` of the version that last made a request.
    private(set) var requestedVersion: String?

    /// A link reached a browser. Not counted in a version that already asked,
    /// so the next version starts from zero.
    mutating func noteSuccess(version: String) {
        guard requestedVersion != version else { return }
        successes += 1
    }

    func isDue(version: String) -> Bool {
        successes >= Self.threshold && requestedVersion != version
    }

    mutating func markRequested(version: String) {
        requestedVersion = version
        successes = 0
    }
}
