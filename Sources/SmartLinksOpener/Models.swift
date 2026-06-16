import Foundation

/// A routing rule: every URL whose host matches `domain` opens in the browser
/// identified by `bundleID`.
struct Rule: Codable, Identifiable, Equatable {
    var id = UUID()
    var domain: String
    var bundleID: String
}

/// An installed browser discovered via LaunchServices.
struct Browser: Identifiable, Equatable {
    var id: String { bundleID }
    var name: String
    var bundleID: String
    var appURL: URL
}
