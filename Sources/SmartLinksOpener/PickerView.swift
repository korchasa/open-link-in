import AppKit
import SwiftUI

/// Compact, keyboard-first picker shown for every link without a rule.
/// Browsers are a grid of icons (most-used first) with 1–9 quick-keys; arrows
/// move the highlight, Return opens it, Esc cancels. Remembering is ON by
/// default and shown explicitly. [REF:fr:picker]
struct PickerView: View {
    @EnvironmentObject var store: AppStore
    let url: URL
    @State private var remember = true
    @State private var selected = 0

    private var browsers: [Browser] { store.browsers }
    private var columns: Int { max(1, min(browsers.count, 4)) }
    private var domain: String { store.ruleDomain(for: url) ?? url.host ?? url.absoluteString }
    private var selectedBrowser: Browser? {
        browsers.indices.contains(selected) ? browsers[selected] : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            grid
            rememberRow
            footer
        }
        .padding(18)
        .frame(width: 360)
        .background(
            KeyCatcher { command in handle(command) }
        )
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Header — domain first, full URL secondary

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Open in…")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(domain)
                .font(.title3).bold()
                .lineLimit(1)
                .truncationMode(.middle)
            Text(url.absoluteString)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    // MARK: Grid of browser icons

    private var grid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns),
            spacing: 8
        ) {
            ForEach(Array(browsers.enumerated()), id: \.element.id) { index, browser in
                browserCell(index: index, browser: browser)
            }
        }
    }

    private func browserCell(index: Int, browser: Browser) -> some View {
        Button {
            store.choose(browser, for: url, remember: remember)
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: store.icon(for: browser))
                        .resizable()
                        .frame(width: 40, height: 40)
                    if index < 9 {
                        Text(verbatim: "\(index + 1)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 14, height: 14)
                            .background(Circle().fill(.black.opacity(0.55)))
                            .offset(x: 5, y: -5)
                    }
                }
                Text(browser.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(index == selected ? Color.accentColor.opacity(0.22) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(index == selected ? Color.accentColor : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .help(browser.name)
    }

    // MARK: Explicit remember

    private var rememberRow: some View {
        Toggle(isOn: $remember) {
            if remember {
                Text("Remember for \(domain)")
                    .font(.callout)
            } else {
                Text("Open once")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .tint(.accentColor)
    }

    // MARK: Footer — key hints + queue depth + cancel

    private var footer: some View {
        HStack(spacing: 8) {
            Text(verbatim: "1–9  ·  ↩  ·  esc")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if store.pendingCount > 1 {
                Text(verbatim: "+\(store.pendingCount - 1)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.quaternary))
            }
            Spacer()
            Button("Cancel") { store.cancelPending() }
                .controlSize(.small)
        }
    }

    // MARK: Keyboard

    private func handle(_ command: KeyCommand) {
        guard !browsers.isEmpty else {
            if case .cancel = command { store.cancelPending() }
            return
        }
        switch command {
        case .left: selected = max(0, selected - 1)
        case .right: selected = min(browsers.count - 1, selected + 1)
        case .up: selected = max(0, selected - columns)
        case .down: selected = min(browsers.count - 1, selected + columns)
        case .confirm:
            if let b = selectedBrowser { store.choose(b, for: url, remember: remember) }
        case .cancel:
            store.cancelPending()
        case .digit(let n):
            if n >= 1, n <= browsers.count {
                store.choose(browsers[n - 1], for: url, remember: remember)
            }
        }
    }
}

// MARK: - Key capture (works on macOS 13; no onKeyPress dependency)

enum KeyCommand {
    case up, down, left, right, confirm, cancel
    case digit(Int)
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

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 123: onCommand?(.left)
            case 124: onCommand?(.right)
            case 125: onCommand?(.down)
            case 126: onCommand?(.up)
            case 36, 76: onCommand?(.confirm)  // return, enter
            case 53: onCommand?(.cancel)  // esc
            default:
                if let s = event.charactersIgnoringModifiers, let n = Int(s), (1...9).contains(n) {
                    onCommand?(.digit(n))
                } else {
                    super.keyDown(with: event)
                }
            }
        }
    }
}
