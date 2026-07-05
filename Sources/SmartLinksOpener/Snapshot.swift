import AppKit
import SwiftUI

/// Offscreen screenshot mode for App Store assets: `SmartLinksOpener --snapshot <dir>`
/// renders the picker panel and the rules window on a gradient backdrop in a
/// borderless window (never shown to the user) and writes PNGs sized 2880×1800
/// (the Mac App Store 1440×900@2x slot) into `<dir>`. All views are native
/// SwiftUI, so `cacheDisplay` into an explicit 2× bitmap captures them fine.
///
/// Demo rules are seeded in memory only — `saveRules()` is never called, so the
/// user's real rules in `UserDefaults` are untouched.
@MainActor
enum Snapshot {
    /// Points size of the exported frame; pixels are 2× this.
    private static let frame = NSSize(width: 1440, height: 900)

    /// Detects `--snapshot <dir>` on the command line. When present, runs the
    /// capture flow and terminates the app; the caller must skip its normal
    /// launch path. Returns `false` when the flag is absent.
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--snapshot"), args.count > flag + 1 else {
            return false
        }
        let dir = URL(fileURLWithPath: args[flag + 1], isDirectory: true)
        Task { @MainActor in
            do {
                try capture(into: dir)
            } catch {
                FileHandle.standardError.write(Data("snapshot failed: \(error)\n".utf8))
            }
            NSApp.terminate(nil)
        }
        return true
    }

    private static func capture(into dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let store = AppStore.shared
        seedDemoRules(store)

        // 01 — the picker panel (the app's core moment), centered on a backdrop.
        let pickerURL = URL(string: "https://github.com/anthropics/claude-code")!
        let picker = backdrop {
            PickerView(url: pickerURL)
                .environmentObject(store)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.35), radius: 40, y: 18)
        }
        try shoot(picker, to: dir.appendingPathComponent("01-picker.png"))

        // 02 — the rules window content at its natural window size.
        let rules = backdrop {
            RulesView()
                .environmentObject(store)
                .frame(width: 720, height: 560)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.35), radius: 40, y: 18)
        }
        try shoot(rules, to: dir.appendingPathComponent("02-rules.png"))

        // 03 — the picker in one-time "open once" mode (orange accent, no rule).
        let onceURL = URL(string: "https://youtube.com/watch?v=dequ")!
        let pickerOnce = backdrop {
            PickerView(url: onceURL, shiftHeld: true)
                .environmentObject(store)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.35), radius: 40, y: 18)
        }
        try shoot(pickerOnce, to: dir.appendingPathComponent("03-picker-once.png"))
    }

    /// In-memory demo content: keep only well-known browsers (the build machine
    /// registers oddballs like terminal emulators as http handlers) and route a
    /// few recognizable domains across them.
    private static func seedDemoRules(_ store: AppStore) {
        let known = [
            "com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox",
            "com.brave.Browser", "org.chromium.Chromium",
        ]
        let filtered = known.compactMap { id in store.browsers.first { $0.bundleID == id } }
        if !filtered.isEmpty { store.browsers = filtered }
        let browsers = store.browsers
        guard !browsers.isEmpty else { return }
        let domains = ["github.com", "figma.com", "youtube.com", "notion.so", "linear.app"]
        store.rules = domains.enumerated().map { i, domain in
            Rule(domain: domain, bundleID: browsers[i % browsers.count].bundleID)
        }
    }

    private static func backdrop<Content: View>(@ViewBuilder _ content: () -> Content)
        -> some View
    {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.13, green: 0.23, blue: 0.42),
                    Color(red: 0.24, green: 0.14, blue: 0.38),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            content()
        }
        .frame(width: frame.width, height: frame.height)
    }

    private static func shoot(_ view: some View, to url: URL) throws {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: frame)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: frame),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        // Let SwiftUI settle async image/icon loads before capturing.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0))

        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(frame.width) * 2, pixelsHigh: Int(frame.height) * 2,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else {
            throw NSError(
                domain: "Snapshot", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "could not create bitmap"])
        }
        rep.size = frame
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(
                domain: "Snapshot", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "could not encode PNG"])
        }
        try png.write(to: url)
        window.orderOut(nil)
    }
}
