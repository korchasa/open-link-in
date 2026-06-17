import AppKit
import SwiftUI

/// Compact, keyboard-first picker shown for every link without a rule.
/// Browsers are a vertical list (most-used first) with 1–9 quick-keys (and 0 for
/// the tenth); ↑/↓ move the highlight (wrapping), Return opens it, Esc or the ✕
/// cancels. Choosing a browser **creates a rule for the second-level domain and
/// opens** by default; holding **⇧ Shift** switches to a one-time open (orange
/// accent, header changes, no rule). [REF:fr:picker]
struct PickerView: View {
    @EnvironmentObject var store: AppStore
    let url: URL
    @State private var selected = 0
    @State private var shiftHeld = false

    private var browsers: [Browser] { store.pickerBrowsers }
    private var title: String { LinkLabel.title(for: url) }
    /// A local file has no domain → no rule can be created, so the picker is
    /// always in one-time-open mode for files (⇧ is irrelevant). [REF:fr:file-open]
    private var isFile: Bool { url.isFileURL }
    private var openOnce: Bool { shiftHeld || isFile }
    private var selectedBrowser: Browser? {
        browsers.indices.contains(selected) ? browsers[selected] : nil
    }

    /// Blue = "open & remember" (default); orange = "open once" while ⇧ is held.
    /// Fixed semantic colors (not the user accent) so the mode reads at a glance.
    private var accent: Color { shiftHeld ? Color(nsColor: .systemOrange) : Color(nsColor: .systemBlue) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 320)
        .background(
            KeyCatcher { command in handle(command) }
        )
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .topTrailing) { closeButton }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Header — mode label + domain

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(openOnce ? "Open once — no rule created" : "Open & remember")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(shiftHeld ? Color(nsColor: .systemOrange) : Color.secondary)
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.trailing, 26)  // clear of the ✕
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 15)
        .padding(.bottom, 13)
    }

    // MARK: Vertical list of browsers

    private var list: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(Array(browsers.enumerated()), id: \.element.id) { index, browser in
                    row(index: index, browser: browser)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(maxHeight: 360)
    }

    private func row(index: Int, browser: Browser) -> some View {
        let isSelected = index == selected
        return Button {
            store.choose(browser, for: url, remember: !openOnce)
        } label: {
            HStack(spacing: 11) {
                Image(nsImage: store.icon(for: browser))
                    .resizable()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                Text(browser.name)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Spacer(minLength: 0)
                if isSelected {
                    Text(verbatim: "↩")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                if let key = PickerKeys.hotkey(index: index) {
                    keyBadge(key, selected: isSelected)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isSelected ? accent : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help(browser.name)
    }

    private func keyBadge(_ key: String, selected: Bool) -> some View {
        Text(verbatim: key)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(selected ? Color.white : Color.secondary)
            .frame(minWidth: 20, minHeight: 20)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(selected ? Color.white.opacity(0.25) : Color(nsColor: .controlBackgroundColor))
            )
    }

    // MARK: Footer — ⇧ Shift hint + queue depth

    private var footer: some View {
        HStack(spacing: 8) {
            // The ⇧ open-once toggle is meaningless for local files (no domain,
            // so no rule can ever be created). [REF:fr:file-open]
            if !isFile {
                Text(verbatim: "⇧ Shift")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(shiftHeld ? Color.white : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(shiftHeld ? Color(nsColor: .systemOrange) : Color(nsColor: .controlBackgroundColor))
                    )
                Text("open once, without creating a rule")
                    .font(.system(size: 11.5))
                    .foregroundStyle(shiftHeld ? Color(nsColor: .systemOrange) : Color.secondary)
            }
            Spacer(minLength: 4)
            if store.pendingCount > 1 {
                Text(verbatim: "+\(store.pendingCount - 1)")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.quaternary))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var closeButton: some View {
        Button {
            store.cancelPending()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .padding(13)
        .help("Cancel")
    }

    // MARK: Keyboard

    private func handle(_ command: KeyCommand) {
        if case .shift(let held) = command {
            shiftHeld = held
            return
        }
        guard !browsers.isEmpty else {
            if case .cancel = command { store.cancelPending() }
            return
        }
        let n = browsers.count
        switch command {
        case .up: selected = PickerKeys.move(selected, by: -1, count: n)
        case .down: selected = PickerKeys.move(selected, by: 1, count: n)
        case .confirm:
            if let b = selectedBrowser { store.choose(b, for: url, remember: !openOnce) }
        case .cancel:
            store.cancelPending()
        case .digit(let key):  // raw number key 0–9
            if let i = PickerKeys.selection(forKey: key, count: n) {
                store.choose(browsers[i], for: url, remember: !openOnce)
            }
        case .shift:
            break  // handled above
        }
    }
}

// MARK: - Key capture (works on macOS 13; no onKeyPress dependency)

enum KeyCommand {
    case up, down, confirm, cancel
    case digit(Int)  // raw number key, 0–9 (PickerKeys maps "0" to the tenth row)
    case shift(Bool)
}

struct KeyCatcher: NSViewRepresentable {
    let onCommand: (KeyCommand) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = KeyCatcherNSView()
        v.onCommand = onCommand
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? KeyCatcherNSView)?.onCommand = onCommand
    }

    private final class KeyCatcherNSView: NSView {
        var onCommand: ((KeyCommand) -> Void)?
        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.window?.makeFirstResponder(self)
            }
        }

        // Live ⇧ feedback: the picker switches to "open once" while Shift is held.
        override func flagsChanged(with event: NSEvent) {
            onCommand?(.shift(event.modifierFlags.contains(.shift)))
            super.flagsChanged(with: event)
        }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 125: onCommand?(.down)
            case 126: onCommand?(.up)
            case 36, 76: onCommand?(.confirm)  // return, enter
            case 53: onCommand?(.cancel)  // esc
            default:
                if let s = event.charactersIgnoringModifiers, let n = Int(s), (0...9).contains(n) {
                    onCommand?(.digit(n))  // raw key; PickerKeys maps 1–9/0 to rows
                } else {
                    super.keyDown(with: event)
                }
            }
        }
    }
}
