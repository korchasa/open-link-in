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

    /// Local files (e.g. `.html`) reach the app as document-open Apple Events
    /// (`kAEOpenDocuments`), which AppKit dispatches here — distinct from the
    /// `kAEGetURL` web-link path (whose manual handler overrides only `GetURL`,
    /// leaving `odoc` to AppKit). Routed through the same picker flow; a file
    /// has no domain, so no rule is created. [REF:fr:file-open]
    func application(_ application: NSApplication, open urls: [URL]) {
        handledURLAtLaunch = true
        for url in urls { store.handleIncoming(url) }
    }

    // MARK: - Windows

    func showRules() {
        if rulesWindow == nil {
            let host = NSHostingController(rootView: RulesView().environmentObject(store))
            let window = NSWindow(contentViewController: host)
            window.title = "Smart Links Opener"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 560, height: 420)
            // Remember the user's size; only apply the default when nothing was restored.
            window.setFrameAutosaveName("RulesWindow")
            if !window.setFrameUsingName("RulesWindow") {
                window.setContentSize(NSSize(width: 720, height: 560))
                window.center()
            }
            rulesWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        rulesWindow?.makeKeyAndOrderFront(nil)
    }

    func showPicker() {
        guard let url = store.pendingURL else { return }
        closePicker()
        let host = NSHostingController(rootView: PickerView(url: url).environmentObject(store))
        let panel = PickerPanel(contentViewController: host)
        panel.styleMask = [.borderless, .nonactivatingPanel]
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.setContentSize(host.view.fittingSize)
        positionNearCursor(panel)
        pickerWindow = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Anchor the panel's top-left corner just right of and below the cursor, so
    /// it reads as a popover hanging off the link the user clicked, then clamp it
    /// fully inside the active screen's visible frame.
    private func positionNearCursor(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let size = window.frame.size
        var x = mouse.x + 12
        var y = mouse.y - 8 - size.height
        if let vf = screen?.visibleFrame {
            x = min(max(vf.minX + 8, x), vf.maxX - size.width - 8)
            y = min(max(vf.minY + 8, y), vf.maxY - size.height - 8)
        }
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func closePicker() {
        pickerWindow?.orderOut(nil)
        pickerWindow = nil
    }
}

/// Borderless panel that can still become key (so the picker receives keystrokes).
final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
