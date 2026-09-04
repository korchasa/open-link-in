import Foundation

/// Pure routing decision for an incoming link: which rule covers the host and
/// what it asks for. Side-effect-free so the matching order and the
/// always-ask mode are unit tested without AppKit. [REF:fr:route] [REF:fr:always-ask]
enum Routing {
    enum Decision: Equatable {
        /// A rule names an installed browser → open silently.
        case open(bundleID: String)
        /// The covering rule is in `.ask` mode → raise the picker, remember nothing.
        case ask
        /// No rule covers the host (or the rule's browser is gone) → raise the
        /// picker with the usual "open & remember" default.
        case unmatched
    }

    /// The rule covering `host`: longest domain wins (`bbc.co.uk` beats
    /// `co.uk`). A rule whose browser is no longer installed is skipped so the
    /// next-longest one still applies; an `.ask` rule needs no browser.
    static func rule(for host: String, in rules: [Rule], installed: Set<String>) -> Rule? {
        rules
            .filter { Domain.host(host, matchesRule: $0.domain) }
            .sorted { $0.domain.count > $1.domain.count }
            .first { $0.mode == .ask || installed.contains($0.bundleID) }
    }

    static func decide(host: String, rules: [Rule], installed: Set<String>) -> Decision {
        guard let r = rule(for: host, in: rules, installed: installed) else { return .unmatched }
        switch r.mode {
        case .ask: return .ask
        case .open: return .open(bundleID: r.bundleID)
        }
    }
}
