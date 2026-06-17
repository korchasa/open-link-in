import Foundation

/// Pure picker-visibility logic: which browsers the picker may show, and whether
/// a given browser may still be hidden. Side-effect-free for unit testing.
/// The "hidden" set is stored (not "visible"), so newly installed browsers
/// appear by default. [REF:fr:browser-visibility]
enum BrowserVisibility {
    /// Browsers eligible for the picker — all real browsers minus hidden ones,
    /// order preserved.
    static func visible(_ browsers: [Browser], hidden: Set<String>) -> [Browser] {
        browsers.filter { !hidden.contains($0.bundleID) }
    }

    /// `true` iff hiding `id` is allowed: it is not already hidden AND at least
    /// one browser would remain visible afterwards. Prevents an empty picker.
    static func canHide(_ id: String, hidden: Set<String>, all: [Browser]) -> Bool {
        guard !hidden.contains(id) else { return false }
        return visible(all, hidden: hidden).count > 1
    }
}
