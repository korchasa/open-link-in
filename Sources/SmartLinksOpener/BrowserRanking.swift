import Foundation

/// Pure ordering for the picker: most-used browsers first, ties broken by name.
/// Kept side-effect-free for unit testing. [REF:fr:picker]
enum BrowserRanking {
    static func sorted(_ browsers: [Browser], counts: [String: Int]) -> [Browser] {
        browsers.sorted { a, b in
            let ca = counts[a.bundleID] ?? 0
            let cb = counts[b.bundleID] ?? 0
            if ca != cb { return ca > cb }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}
