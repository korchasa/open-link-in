import AppKit
import ServiceManagement
import SwiftUI

/// Central state: installed browsers, routing rules, and the link currently
/// awaiting a decision.
@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var rules: [Rule] = []
    @Published var browsers: [Browser] = []
    @Published var statusMessage: String?

    /// FIFO queue of links awaiting a picker decision, so a burst of links from
    /// another app is never silently dropped. [REF:fr:picker]
    @Published private var pendingURLs: [URL] = []
    var pendingURL: URL? { pendingURLs.first }
    var pendingCount: Int { pendingURLs.count }

    /// Per-browser open counts, used to order the picker by frequency.
    @Published private(set) var usageCounts: [String: Int] = [:]

    /// Bundle IDs the user has hidden from the picker grid. Stored as the
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

    private let defaultsKey = "rules.v1"
    private let usageKey = "usage.v1"
    private let hiddenKey = "hiddenBrowsers.v1"
    private var ownBundleID: String { Bundle.main.bundleIdentifier ?? "dev.korchasa.SmartLinksOpener" }

    private init() {
        loadRules()
        loadUsage()
        loadHidden()
        refreshBrowsers()
        // Direct assignment in init does not fire the didSet observer.
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
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

    func icon(for browser: Browser) -> NSImage {
        NSWorkspace.shared.icon(forFile: browser.appURL.path)
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
        // Persist the registrable (second-level) domain so every subdomain
        // routes to the chosen browser. [REF:fr:subdomain]
        let d = Domain.registrable(domain)
        guard !d.isEmpty else { return }
        rules.removeAll { $0.domain == d }
        rules.append(Rule(domain: d, bundleID: bundleID))
        rules.sort { $0.domain < $1.domain }
        saveRules()
    }

    func deleteRule(_ rule: Rule) {
        rules.removeAll { $0.id == rule.id }
        saveRules()
    }

    func updateRuleBrowser(_ rule: Rule, bundleID: String) {
        if let i = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[i].bundleID = bundleID
            saveRules()
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

    /// Find a rule whose domain covers this URL's host (exact or any subdomain);
    /// longest-domain match wins (`bbc.co.uk` beats `co.uk`). [REF:fr:subdomain]
    func matchingBrowser(for url: URL) -> Browser? {
        guard let host = url.host, !host.isEmpty else { return nil }
        let candidates =
            rules
            .filter { Domain.host(host, matchesRule: $0.domain) }
            .sorted { $0.domain.count > $1.domain.count }
        for c in candidates {
            if let b = browser(forBundleID: c.bundleID) { return b }
        }
        return nil
    }

    // MARK: - Opening

    func open(_ url: URL, in browser: Browser) {
        recordUse(browser.bundleID)
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.open(
            [url], withApplicationAt: browser.appURL,
            configuration: cfg, completionHandler: nil)
    }

    /// Entry point for an incoming link from the system. The app stays resident
    /// in the background afterwards — matched links open silently, unmatched
    /// links are queued and raise the picker.
    func handleIncoming(_ url: URL) {
        if let b = matchingBrowser(for: url) {
            open(url, in: b)
            return
        }
        let wasEmpty = pendingURLs.isEmpty
        pendingURLs.append(url)
        if wasEmpty { onShowPicker?() }
    }

    func choose(_ browser: Browser, for url: URL, remember: Bool) {
        if remember, let domain = ruleDomain(for: url) {
            addRule(domain: domain, bundleID: browser.bundleID)
        }
        open(url, in: browser)
        advanceQueue()
    }

    func cancelPending() {
        advanceQueue()
    }

    /// Drop the handled link and either show the next queued one or close.
    private func advanceQueue() {
        if !pendingURLs.isEmpty { pendingURLs.removeFirst() }
        if pendingURLs.isEmpty {
            onClosePicker?()
        } else {
            onShowPicker?()
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
                    if let error {
                        self?.statusMessage = String(localized: "Failed: \(error.localizedDescription)")
                    } else if self?.isDefaultBrowser() == true {
                        self?.statusMessage = nil
                    } else {
                        self?.statusMessage = String(localized: "Change not confirmed.")
                    }
                    self?.objectWillChange.send()
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
