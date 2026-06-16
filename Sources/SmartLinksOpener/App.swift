import AppKit
import SwiftUI

@main
struct SmartLinksOpenerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore.shared

    var body: some Scene {
        // The only persistent UI of a background agent: a menu-bar item.
        MenuBarExtra("Smart Links Opener", systemImage: "link.circle.fill") {
            MenuContent(store: store)
        }
    }
}

/// Contents of the menu-bar dropdown.
struct MenuContent: View {
    @ObservedObject var store: AppStore

    var body: some View {
        Button("Rules…") { store.requestShowRules() }
            .keyboardShortcut(",", modifiers: .command)

        Divider()

        if store.isDefaultBrowser() {
            Label("Default browser", systemImage: "checkmark.seal.fill")
        } else {
            Button("Set as default browser") { store.setAsDefaultBrowser() }
        }
        Toggle(
            "Launch at login",
            isOn: Binding(
                get: { store.launchAtLogin },
                set: { store.launchAtLogin = $0 }
            ))

        Divider()

        Button("Quit") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}

/// Owns the Apple Event URL handler and the on-demand AppKit windows. Keeping
/// windows here (rather than as SwiftUI scenes) lets the agent stay window-less
/// in the background and present UI only when needed.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = AppStore.shared
    private var rulesWindow: NSWindow?
    private var pickerWindow: NSWindow?
    private var handledURLAtLaunch = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as a background agent: no Dock icon, no app-switcher entry.
        NSApp.setActivationPolicy(.accessory)

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        store.onShowRules = { [weak self] in self?.showRules() }
        store.onShowPicker = { [weak self] in self?.showPicker() }
        store.onClosePicker = { [weak self] in self?.closePicker() }

        // Launched by the user (not by a link) → reveal the rules window so the
        // app isn't invisible on first run.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            if !self.handledURLAtLaunch && self.pickerWindow == nil {
                self.showRules()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false  // stay resident in the background
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showRules()
        return true
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        handledURLAtLaunch = true
        guard let str = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
            let url = URL(string: str)
        else { return }
        store.handleIncoming(url)
    }

    // MARK: - Windows

    func showRules() {
        if rulesWindow == nil {
            let host = NSHostingController(rootView: RulesView().environmentObject(store))
            let window = NSWindow(contentViewController: host)
            window.title = "Smart Links Opener"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 500, height: 480))
            window.center()
            rulesWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        rulesWindow?.makeKeyAndOrderFront(nil)
    }

    func showPicker() {
        guard let url = store.pendingURL else { return }
        closePicker()
        let host = NSHostingController(rootView: PickerView(url: url).environmentObject(store))
        let window = NSWindow(contentViewController: host)
        window.title = String(localized: "Choose browser")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 460, height: 440))
        window.center()
        window.level = .floating
        pickerWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func closePicker() {
        pickerWindow?.orderOut(nil)
        pickerWindow = nil
    }
}
