import Foundation

/// Pure keyboard logic for the picker: hotkey labels, number-key → selection
/// mapping, and wrapping arrow navigation. Side-effect-free so it can be unit
/// tested without a running view. [REF:fr:picker]
enum PickerKeys {
    /// Label on a row's key badge: 1–9 for the first nine rows, "0" for the
    /// tenth, none beyond (no keyboard digit maps there).
    static func hotkey(index: Int) -> String? {
        if index < 0 { return nil }
        if index < 9 { return "\(index + 1)" }
        if index == 9 { return "0" }
        return nil
    }

    /// Map a pressed number key (0–9) to the list index it selects: 1–9 → rows
    /// 0–8, the "0" key → row 9 (the tenth). Returns nil when out of range for a
    /// list of `count` browsers.
    static func selection(forKey key: Int, count: Int) -> Int? {
        guard (0...9).contains(key) else { return nil }
        let index = key == 0 ? 9 : key - 1
        return index < count ? index : nil
    }

    /// Move the highlight by `delta` (±1) with wrap-around. Returns `current`
    /// unchanged when the list is empty.
    static func move(_ current: Int, by delta: Int, count: Int) -> Int {
        guard count > 0 else { return current }
        return ((current + delta) % count + count) % count
    }
}
