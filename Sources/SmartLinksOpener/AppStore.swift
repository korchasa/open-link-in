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
    @Published var pendingURL: URL?
    @Published var statusMessage: String?

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
    private var ownBundleID: String { Bundle.main.bundleIdentifier ?? "dev.korchasa.SmartLinksOpener" }

    private init() {
        loadRules()
        refreshBrowsers()
        // Direct assignment in init does not fire the didSet observer.
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    func requestShowRules() {
        onShowRules?()
    }

    // MARK: - Browsers

    /// Ask LaunchServices which apps can open web URLs, minus ourselves.
    func refreshBrowsers() {
        let probe = URL(string: "https://example.com")!
        let urls = NSWorkspace.shared.urlsForApplications(toOpen: probe)

        var result: [Browser] = []
        var seen = Set<String>()
        for u in urls {
            guard let bundle = Bundle(url: u), let bid = bundle.bundleIdentifier else { continue }
            if bid == ownBundleID { continue }
            guard seen.insert(bid).inserted else { continue }
            let name = FileManager.default.displayName(atPath: u.path)
                .replacingOccurrences(of: ".app", with: "")
            result.append(Browser(name: name, bundleID: bid, appURL: u))
        }
        result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        browsers = result
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
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.open(
            [url], withApplicationAt: browser.appURL,
            configuration: cfg, completionHandler: nil)
    }

    /// Entry point for an incoming link from the system. The app stays resident
    /// in the background afterwards — matched links open silently, unmatched
    /// links raise the picker.
    func handleIncoming(_ url: URL) {
        if let b = matchingBrowser(for: url) {
            open(url, in: b)
        } else {
            pendingURL = url
            onShowPicker?()
        }
    }

    func choose(_ browser: Browser, for url: URL, remember: Bool) {
        if remember, let domain = ruleDomain(for: url) {
            addRule(domain: domain, bundleID: browser.bundleID)
        }
        open(url, in: browser)
        pendingURL = nil
        onClosePicker?()
    }

    func cancelPending() {
        pendingURL = nil
        onClosePicker?()
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
