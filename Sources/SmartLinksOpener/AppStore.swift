import AppKit
import ServiceManagement
import SwiftUI
import os

/// Central state: installed browsers, routing rules, and the link currently
/// awaiting a decision.
@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var rules: [Rule] = []
    @Published var browsers: [Browser] = []
    @Published var statusMessage: String?

    /// Whether this app is the system default http(s) handler. Published so the
    /// UI updates when the default changes; refreshed on app activation, since
    /// LaunchServices posts no reliable public "default handler changed"
    /// notification and the user changes it in System Settings (leaving and
    /// returning to this app). [REF:fr:default-browser]
    @Published private(set) var isDefault: Bool = false

    /// Links awaiting a picker decision. A burst queues; a picker the user
    /// walked away from expires or gives way to the next link. Not published:
    /// activity (mouse moves) updates it constantly, so only the two values the
    /// picker shows are published, and only when they change. [REF:fr:picker]
    private var queue = PickerQueue()
    @Published private(set) var pendingURL: URL?
    @Published private(set) var pendingCount: Int = 0
    /// Closes an idle picker; replaced whenever a head is shown, cancelled
    /// when the queue empties.
    private var expiryTask: Task<Void, Never>?

    /// Per-browser open counts, used to order the picker by frequency.
    @Published private(set) var usageCounts: [String: Int] = [:]

    /// Bundle IDs the user has hidden from the picker list. Stored as the
    /// hidden set (not the visible one) so newly installed browsers show by
    /// default. [REF:fr:browser-visibility]
    @Published private(set) var hiddenBrowserIDs: Set<String> = []

    /// Toggling this registers/unregisters the app as a login item via the
    /// modern ServiceManagement API (the Apple-sanctioned replacement for the
    /// deprecated SMLoginItemSetEnabled).
    @Published var launchAtLogin: Bool = false {
        didSet { applyLaunchAtLogin() }
    }

    // Wired up by the AppDelegate so the model can drive window presentation
    // without holding AppKit references itself.
    var onShowRules: (() -> Void)?
    var onShowPicker: (() -> Void)?
    var onClosePicker: (() -> Void)?

    /// Browser icons keyed by bundle ID — see `icon(for:)`. Not `@Published`:
    /// filling it is memoisation, not a state change.
    private var iconCache: [String: NSImage] = [:]

    private let defaultsKey = "rules.v1"
    private let usageKey = "usage.v1"
    private let hiddenKey = "hiddenBrowsers.v1"
    private let reviewKey = "reviewPrompt.v1"

    /// Successful routings toward the App Store rating request; asked when the
    /// user closes the rules window, never over the browser a link just went to.
    /// [REF:fr:rating-request]
    private var reviewPrompt = ReviewPrompt()
    /// Local log of the rating gate only — counts and version, never a URL.
    private let reviewLog = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "dev.korchasa.SmartLinksOpener", category: "review")
    private var ownBundleID: String { Bundle.main.bundleIdentifier ?? "dev.korchasa.SmartLinksOpener" }

    private init() {
        loadRules()
        loadUsage()
        loadHidden()
        loadReviewPrompt()
        refreshBrowsers()
        refreshDefaultBrowserStatus()
        // Direct assignment in init does not fire the didSet observer.
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
        // Re-check the default handler whenever the app regains focus: the user
        // changes it in System Settings (or another browser's prompt), then
        // returns here, and the banner/menu must reflect the new state.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshDefaultBrowserStatus() }
        }
    }

    /// Re-queries LaunchServices for the current default http(s) handler and
    /// publishes the result. Cheap; safe to call on every activation.
    func refreshDefaultBrowserStatus() {
        isDefault = isDefaultBrowser()
    }

    func requestShowRules() {
        onShowRules?()
    }

    // MARK: - Browsers

    /// Real web browsers only: apps that handle BOTH `http` and `https` (a plain
    /// `https` query also returns non-browsers that registered the scheme). Sorted
    /// by usage frequency. [REF:fr:picker]
    func refreshBrowsers() {
        let httpsIDs = Set(handlerBundleIDs(forScheme: "https"))
        let httpURLs = NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "http://example.com")!)

        var result: [Browser] = []
        var seen = Set<String>()
        for u in httpURLs {
            guard let bundle = Bundle(url: u), let bid = bundle.bundleIdentifier else { continue }
            if bid == ownBundleID { continue }
            guard httpsIDs.contains(bid) else { continue }  // must also handle https
            guard seen.insert(bid).inserted else { continue }
            let name = FileManager.default.displayName(atPath: u.path)
                .replacingOccurrences(of: ".app", with: "")
            result.append(Browser(name: name, bundleID: bid, appURL: u))
        }
        browsers = BrowserRanking.sorted(result, counts: usageCounts)
    }

    private func handlerBundleIDs(forScheme scheme: String) -> [String] {
        NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "\(scheme)://example.com")!)
            .compactMap { Bundle(url: $0)?.bundleIdentifier }
    }

    /// Browsers the picker renders: visible (non-hidden) browsers ordered by
    /// usage frequency. [REF:fr:browser-visibility]
    var pickerBrowsers: [Browser] {
        BrowserRanking.sorted(BrowserVisibility.visible(browsers, hidden: hiddenBrowserIDs), counts: usageCounts)
    }

    func browser(forBundleID id: String) -> Browser? {
        browsers.first { $0.bundleID == id }
    }

    /// App icon for a browser, memoised per bundle ID.
    ///
    /// `NSWorkspace.icon(forFile:)` hands back a fresh `NSImage` on every call,
    /// so an uncached lookup both costs a LaunchServices round-trip (~0.1–0.7 ms)
    /// and denies SwiftUI the identity it needs to skip redrawing an unchanged
    /// row. Icons are stable for the life of the process.
    func icon(for browser: Browser) -> NSImage {
        if let cached = iconCache[browser.bundleID] { return cached }
        let image = NSWorkspace.shared.icon(forFile: browser.appURL.path)
        iconCache[browser.bundleID] = image
        return image
    }

    // MARK: - Rules persistence

    func loadRules() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode([Rule].self, from: data)
        else { return }
        rules = decoded
    }

    func saveRules() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    // MARK: - Usage frequency

    private func loadUsage() {
        if let data = UserDefaults.standard.data(forKey: usageKey),
            let decoded = try? JSONDecoder().decode([String: Int].self, from: data)
        {
            usageCounts = decoded
        }
    }

    private func recordUse(_ bundleID: String) {
        usageCounts[bundleID, default: 0] += 1
        if let data = try? JSONEncoder().encode(usageCounts) {
            UserDefaults.standard.set(data, forKey: usageKey)
        }
        browsers = BrowserRanking.sorted(browsers, counts: usageCounts)
    }

    // MARK: - Picker visibility

    private func loadHidden() {
        if let data = UserDefaults.standard.data(forKey: hiddenKey),
            let decoded = try? JSONDecoder().decode([String].self, from: data)
        {
            hiddenBrowserIDs = Set(decoded)
        }
    }

    /// Whether `id` may still be hidden without emptying the picker. [REF:fr:browser-visibility]
    func canHideBrowser(_ id: String) -> Bool {
        BrowserVisibility.canHide(id, hidden: hiddenBrowserIDs, all: browsers)
    }

    /// Show/hide a browser in the picker; hiding the last visible one is refused.
    /// [REF:fr:browser-visibility]
    func setBrowserHidden(_ id: String, _ hidden: Bool) {
        if hidden {
            guard canHideBrowser(id) else { return }
            hiddenBrowserIDs.insert(id)
        } else {
            hiddenBrowserIDs.remove(id)
        }
        if let data = try? JSONEncoder().encode(Array(hiddenBrowserIDs)) {
            UserDefaults.standard.set(data, forKey: hiddenKey)
        }
    }

    func addRule(domain: String, bundleID: String) {
        addRule(domain: domain, target: .browser(bundleID))
    }

    /// Add (or replace) the rule for `domain`, pointing at a browser or at the
    /// picker itself (always ask). [REF:fr:always-ask]
    func addRule(domain: String, target: RuleTarget) {
        storeRule(domain: domain, target: target)
        rerouteQueue()
    }

    /// Add (or replace) a rule without touching the queue — `choose` opens and
    /// advances on its own, so rerouting here would open the chosen link twice.
    private func storeRule(domain: String, target: RuleTarget) {
        // Persist the registrable (second-level) domain so every subdomain
        // routes to the chosen browser. [REF:fr:subdomain]
        let d = Domain.registrable(domain)
        guard !d.isEmpty else { return }
        rules.removeAll { $0.domain == d }
        rules.append(rule(domain: d, target: target))
        rules.sort { $0.domain < $1.domain }
        saveRules()
    }

    private func rule(domain: String, target: RuleTarget) -> Rule {
        switch target {
        case .browser(let id): return Rule(domain: domain, bundleID: id)
        case .ask: return Rule(domain: domain, bundleID: "", mode: .ask)
        }
    }

    func deleteRule(_ rule: Rule) {
        rules.removeAll { $0.id == rule.id }
        saveRules()
    }

    func updateRuleBrowser(_ rule: Rule, bundleID: String) {
        updateRule(rule, target: .browser(bundleID))
    }

    /// Re-point a rule at a browser or switch it to always ask. [REF:fr:always-ask]
    func updateRule(_ rule: Rule, target: RuleTarget) {
        if let i = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[i] = self.rule(domain: rule.domain, target: target)
            rules[i].id = rule.id
            saveRules()
            rerouteQueue()
        }
    }

    // MARK: - Matching

    /// The registrable (second-level) domain stored as a rule when the user
    /// remembers a choice — e.g. `mail.google.com` → `google.com`. [REF:fr:subdomain]
    func ruleDomain(for url: URL) -> String? {
        guard let host = url.host, !host.isEmpty else { return nil }
        let domain = Domain.registrable(host)
        return domain.isEmpty ? nil : domain
    }

    /// What the rules say about this URL: open silently, always ask, or no
    /// rule at all. Longest-domain match wins (`bbc.co.uk` beats `co.uk`).
    /// [REF:fr:subdomain] [REF:fr:always-ask]
    func decision(for url: URL) -> Routing.Decision {
        guard let host = url.host, !host.isEmpty else { return .unmatched }
        return Routing.decide(host: host, rules: rules, installed: Set(browsers.map(\.bundleID)))
    }

    /// The installed browser a rule routes this URL to, if any.
    func matchingBrowser(for url: URL) -> Browser? {
        if case .open(let id) = decision(for: url) { return browser(forBundleID: id) }
        return nil
    }

    /// Whether an always-ask rule covers this URL, so the picker must not
    /// remember the choice. [REF:fr:always-ask]
    func alwaysAsks(_ url: URL) -> Bool {
        decision(for: url) == .ask
    }

    // MARK: - Opening

    func open(_ url: URL, in browser: Browser) {
        recordUse(browser.bundleID)
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        // Only a link macOS confirms it handed over counts toward the rating
        // request. [REF:fr:rating-request]
        NSWorkspace.shared.open(
            [url], withApplicationAt: browser.appURL,
            configuration: cfg
        ) { [weak self] _, error in
            // Domain and code only: a description can name the opened file.
            let failure = error.map { e -> String in
                let ns = e as NSError
                return "\(ns.domain) \(ns.code)"
            }
            Task { @MainActor in self?.noteRoutingResult(failure: failure) }
        }
    }

    // MARK: - Rating request

    private func loadReviewPrompt() {
        if let data = UserDefaults.standard.data(forKey: reviewKey),
            let decoded = try? JSONDecoder().decode(ReviewPrompt.self, from: data)
        {
            reviewPrompt = decoded
        }
    }

    private func saveReviewPrompt() {
        if let data = try? JSONEncoder().encode(reviewPrompt) {
            UserDefaults.standard.set(data, forKey: reviewKey)
        }
    }

    /// Count a routing macOS confirmed; a failed open is logged, not counted.
    /// [REF:fr:rating-request]
    private func noteRoutingResult(failure: String?) {
        if let failure {
            reviewLog.info("routing failed, not counted: \(failure, privacy: .public)")
            return
        }
        let version = AppIdentity.version
        reviewPrompt.noteSuccess(version: version, at: Date())
        saveReviewPrompt()
        reviewLog.info(
            "routing succeeded: \(self.reviewPrompt.successes, privacy: .public)/\(ReviewPrompt.threshold, privacy: .public) toward a rating request in \(version, privacy: .public)"
        )
    }

    /// Called when the user closes the rules window: true when a rating
    /// request is due, which also records it for the running version so it is
    /// made once. The caller must make the request whenever this returns true.
    /// [REF:fr:rating-request]
    func takeReviewRequest(at moment: ReviewPrompt.Moment) -> Bool {
        let version = AppIdentity.version
        guard reviewPrompt.isDue(at: moment, version: version, now: Date(), calendar: .current) else {
            logReviewGate(moment, "no rating request")
            return false
        }
        reviewPrompt.markRequested(version: version)
        saveReviewPrompt()
        reviewLog.info("\(Self.describe(moment), privacy: .public), rating requested in \(version, privacy: .public)")
        return true
    }

    /// Opening the rules window starts a task there, so it never asks; this
    /// only logs where the gate stands. [REF:fr:rating-request]
    func noteRulesWindowOpened() {
        logReviewGate(.rulesWindowOpened, "no rating request on open")
    }

    private func logReviewGate(_ moment: ReviewPrompt.Moment, _ outcome: String) {
        let firstDay = reviewPrompt.isFirstDayOfUse(now: Date(), calendar: .current)
        reviewLog.info(
            "\(Self.describe(moment), privacy: .public), \(outcome, privacy: .public): \(self.reviewPrompt.successes, privacy: .public)/\(ReviewPrompt.threshold, privacy: .public), first day of use \(firstDay ? "yes" : "no", privacy: .public), requested in \(self.reviewPrompt.requestedVersion ?? "none", privacy: .public)"
        )
    }

    private static func describe(_ moment: ReviewPrompt.Moment) -> String {
        switch moment {
        case .rulesWindowOpened: "rules window opened"
        case .rulesWindowClosed: "rules window closed"
        }
    }

    /// Entry point for an incoming link from the system. The app stays resident
    /// in the background afterwards — matched links open silently, unmatched
    /// links are queued and raise the picker.
    /// An abandoned picker never outlives the next link: a matched link closes
    /// it before opening, an unmatched one replaces it. [REF:fr:picker]
    func handleIncoming(_ url: URL) {
        let now = Date()
        if let b = matchingBrowser(for: url) {
            if queue.dropIfAbandoned(now: now) { pickerHeadChanged() }
            open(url, in: b)
            return
        }
        if queue.enqueue(url, now: now) == .showHead {
            pickerHeadChanged()
        } else {
            publishQueue()
        }
    }

    func choose(_ browser: Browser, for url: URL, remember: Bool) {
        // An always-ask domain keeps asking: remembering would silently replace
        // the rule the user set. [REF:fr:always-ask]
        if remember, !alwaysAsks(url), let domain = ruleDomain(for: url) {
            storeRule(domain: domain, target: .browser(browser.bundleID))
        }
        open(url, in: browser)
        advanceQueue()
    }

    func cancelPending() {
        advanceQueue()
    }

    /// The user touched the picker (key, ⇧, mouse over it): keeps it from
    /// counting as abandoned. [REF:fr:picker]
    func notePickerActivity() {
        queue.noteActivity(now: Date())
    }

    /// Drop the handled link, open every queued link a rule now covers, then
    /// show the next one or close.
    private func advanceQueue() {
        let routed = queue.advance(now: Date()) { self.matchingBrowser(for: $0) != nil }
        openRouted(routed)
        pickerHeadChanged()
    }

    /// A rule was added or re-pointed: queued links it covers — the shown one
    /// included — open by themselves. [REF:fr:picker]
    private func rerouteQueue() {
        guard queue.count > 0 else { return }
        let before = queue.head
        let routed = queue.reroute(now: Date()) { self.matchingBrowser(for: $0) != nil }
        openRouted(routed)
        if queue.head != before { pickerHeadChanged() } else { publishQueue() }
    }

    private func openRouted(_ urls: [URL]) {
        for u in urls {
            if let b = matchingBrowser(for: u) { open(u, in: b) }
        }
    }

    /// The queue's head changed (shown, replaced, or gone): sync the panel and
    /// restart the idle timer.
    private func pickerHeadChanged() {
        publishQueue()
        if queue.head == nil {
            expiryTask?.cancel()
            expiryTask = nil
            onClosePicker?()
        } else {
            onShowPicker?()
            scheduleExpiryCheck()
        }
    }

    /// Publish only real changes, so activity updates do not re-render the picker.
    private func publishQueue() {
        if pendingURL != queue.head { pendingURL = queue.head }
        if pendingCount != queue.count { pendingCount = queue.count }
    }

    /// Wake when the head would expire; if it was touched meanwhile, sleep
    /// again for the rest. The sleep runs on `ContinuousClock`, which keeps
    /// counting while the Mac sleeps. [REF:fr:picker]
    private func scheduleExpiryCheck() {
        expiryTask?.cancel()
        guard let delay = queue.secondsUntilExpiry(now: Date()) else {
            expiryTask = nil
            return
        }
        expiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            // `try?` swallows the cancellation; this guard is what stops a
            // timer that was replaced while it slept.
            guard !Task.isCancelled, let self else { return }
            if self.queue.expireIfIdle(now: Date()) {
                self.pickerHeadChanged()
            } else {
                self.scheduleExpiryCheck()
            }
        }
    }

    // MARK: - Login item

    private func applyLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if launchAtLogin {
                if service.status != .enabled { try service.register() }
            } else {
                if service.status == .enabled { try service.unregister() }
            }
        } catch {
            statusMessage = String(localized: "Launch at login: \(error.localizedDescription)")
        }
    }

    // MARK: - Default browser

    /// macOS shows an asynchronous consent dialog for http/https before the
    /// change takes effect; the completion handler fires after the user answers.
    func setAsDefaultBrowser() {
        statusMessage = String(localized: "Waiting for system confirmation…")
        let appURL = Bundle.main.bundleURL
        NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "http") { [weak self] httpError in
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "https") { httpsError in
                DispatchQueue.main.async {
                    let error = httpError ?? httpsError
                    self?.refreshDefaultBrowserStatus()
                    if let error {
                        self?.statusMessage = String(localized: "Failed: \(error.localizedDescription)")
                    } else if self?.isDefault == true {
                        self?.statusMessage = nil
                    } else {
                        self?.statusMessage = String(localized: "Change not confirmed.")
                    }
                }
            }
        }
    }

    func isDefaultBrowser() -> Bool {
        let probe = URL(string: "https://example.com")!
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: probe),
            let bid = Bundle(url: appURL)?.bundleIdentifier
        else { return false }
        return bid.caseInsensitiveCompare(ownBundleID) == .orderedSame
    }
}
