import Foundation

/// FIFO of links awaiting a picker decision, plus the rules that retire a
/// picker the user walked away from. Pure and clock-injected (`now:`) so the
/// timing rules are unit tested without AppKit; `AppStore` owns the real clock
/// and the panel. [REF:fr:picker]
///
/// The head's activity clock starts when the head is shown and restarts on any
/// sign of the user at the picker. A picker idle for `abandonAfter` counts as
/// abandoned: the next link replaces the whole queue. Idle for `idleTimeout`,
/// it expires and the whole queue goes.
struct PickerQueue {
    /// Links arriving closer together than this are one burst and queue up;
    /// a link arriving after it finds the picker abandoned.
    static let abandonAfter: TimeInterval = 3
    /// An untouched picker closes itself after this long.
    static let idleTimeout: TimeInterval = 60

    enum Arrival: Equatable {
        /// The link is the new head; raise its picker.
        case showHead
        /// The link waits behind a picker that is still in use.
        case queued
    }

    private(set) var urls: [URL] = []
    /// When the head was shown or last touched; nil while the queue is empty.
    private(set) var lastActivity: Date?

    var head: URL? { urls.first }
    var count: Int { urls.count }

    private func idle(_ now: Date) -> TimeInterval? {
        guard !urls.isEmpty, let last = lastActivity else { return nil }
        return now.timeIntervalSince(last)
    }

    private mutating func clear() {
        urls.removeAll()
        lastActivity = nil
    }

    /// Queue an unmatched link. An abandoned picker gives way: its whole
    /// queue is dropped and the new link is shown.
    mutating func enqueue(_ url: URL, now: Date) -> Arrival {
        _ = dropIfAbandoned(now: now)
        urls.append(url)
        if urls.count == 1 {
            lastActivity = now
            return .showHead
        }
        return .queued
    }

    /// Drop the whole queue if its picker is abandoned. Used when a matched
    /// link arrives, so it does not open under a stale panel.
    mutating func dropIfAbandoned(now: Date) -> Bool {
        guard let idle = idle(now), idle >= Self.abandonAfter else { return false }
        clear()
        return true
    }

    /// The user touched the picker (key, ⇧, mouse); restarts the head's clock.
    mutating func noteActivity(now: Date) {
        guard !urls.isEmpty else { return }
        lastActivity = now
    }

    /// Seconds until the head expires if nobody touches it; nil when empty.
    func secondsUntilExpiry(now: Date) -> TimeInterval? {
        guard let idle = idle(now) else { return nil }
        return max(0, Self.idleTimeout - idle)
    }

    /// Drop the whole queue once the picker has been idle for `idleTimeout`.
    mutating func expireIfIdle(now: Date) -> Bool {
        guard let idle = idle(now), idle >= Self.idleTimeout else { return false }
        clear()
        return true
    }

    /// The head was decided (chosen or cancelled): pop it, then reroute the
    /// rest. Returns the links a rule now covers, to open silently.
    mutating func advance(now: Date, isRouted: (URL) -> Bool) -> [URL] {
        guard !urls.isEmpty else { return [] }
        urls.removeFirst()
        lastActivity = urls.isEmpty ? nil : now
        return reroute(now: now, isRouted: isRouted)
    }

    /// Remove every link a rule now covers — the shown head included — and
    /// return them in queue order. A new head gets a fresh clock; a kept head
    /// counts the rule change as activity.
    mutating func reroute(now: Date, isRouted: (URL) -> Bool) -> [URL] {
        let routed = urls.filter(isRouted)
        urls.removeAll(where: isRouted)
        lastActivity = urls.isEmpty ? nil : now
        return routed
    }
}
