import Foundation

/// Pure search logic behind the rules window's search field: which rules match
/// what the user typed. Side-effect-free so the matching behaviour is unit
/// tested without a view. [REF:fr:rules-search]
enum RuleFilter {
    /// Rules whose domain contains `query`, compared case-insensitively and
    /// ignoring accents, with the list order preserved.
    ///
    /// A blank (or whitespace-only) query matches everything — focusing the
    /// field must never look like it deleted the rules.
    static func matching(_ rules: [Rule], query: String) -> [Rule] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return rules }
        return rules.filter {
            $0.domain.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
