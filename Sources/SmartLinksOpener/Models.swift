import Foundation

/// What a rule does with a link whose host it covers. [REF:fr:always-ask]
enum RuleMode: String, Codable {
    /// Open silently in the rule's browser (the original behaviour).
    case open
    /// Raise the picker every time; the choice is never remembered.
    case ask
}

/// A routing rule: every URL whose host matches `domain` either opens in the
/// browser identified by `bundleID` or, in `.ask` mode, raises the picker.
struct Rule: Codable, Identifiable, Equatable {
    var id = UUID()
    var domain: String
    var bundleID: String
    /// Absent in data written before the mode existed → `.open`, so stored
    /// rules keep working unchanged. [REF:fr:always-ask]
    var mode: RuleMode = .open

    init(id: UUID = UUID(), domain: String, bundleID: String, mode: RuleMode = .open) {
        self.id = id
        self.domain = domain
        self.bundleID = bundleID
        self.mode = mode
    }

    private enum CodingKeys: String, CodingKey { case id, domain, bundleID, mode }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        domain = try c.decode(String.self, forKey: .domain)
        bundleID = try c.decode(String.self, forKey: .bundleID)
        mode = try c.decodeIfPresent(RuleMode.self, forKey: .mode) ?? .open
    }
}

/// Where a rule sends its links — chosen in the rules window's "Open in"
/// control. [REF:fr:always-ask]
enum RuleTarget: Hashable {
    case browser(String)
    case ask
}

extension Rule {
    var target: RuleTarget { mode == .ask ? .ask : .browser(bundleID) }
}

/// An installed browser discovered via LaunchServices.
struct Browser: Identifiable, Equatable {
    var id: String { bundleID }
    var name: String
    var bundleID: String
    var appURL: URL
}
