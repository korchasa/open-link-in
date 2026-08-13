import SwiftUI

/// The management window, redesigned as two panes (Claude Design "Variant 2"):
/// a narrow left sidebar of browser availability toggles + launch-at-login, and
/// a full-height right pane that gives routing rules the space they need —
/// default-browser banner, column header, rule list, and a pinned add row.
/// [REF:fr:rules-mgmt]
struct RulesView: View {
    @EnvironmentObject var store: AppStore
    @State private var newDomain = ""
    @State private var newBundleID = ""
    /// What the user typed into the rules search field. [REF:fr:rules-search]
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    /// Blur applied to the window content while Reroute is not the default
    /// browser — enough to signal "locked" without hiding the data. Constant per
    /// spec. [REF:fr:default-browser]
    private let lockedContentBlur: CGFloat = 3
    /// Opacity of the desaturated content behind the lock overlay.
    private let lockedContentOpacity: CGFloat = 0.5

    var body: some View {
        ZStack {
            // Normal UI stays visible (and current) beneath the lock, so the user
            // sees their data is intact — but fully greyed out, non-interactive,
            // and hidden from VoiceOver while Reroute isn't the default browser.
            HStack(spacing: 0) {
                sidebar
                Divider()
                rulesPane
            }
            .saturation(store.isDefault ? 1 : 0)
            .opacity(store.isDefault ? 1 : lockedContentOpacity)
            .blur(radius: store.isDefault ? 0 : lockedContentBlur)
            .disabled(!store.isDefault)
            .allowsHitTesting(store.isDefault)
            .accessibilityHidden(!store.isDefault)

            if !store.isDefault {
                notDefaultOverlay
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 560, minHeight: 420)
        .animation(.easeInOut(duration: 0.25), value: store.isDefault)
        .onAppear {
            if newBundleID.isEmpty { newBundleID = store.pickerBrowsers.first?.bundleID ?? "" }
        }
    }

    // MARK: - Locked state (not the system default browser) — [REF:fr:default-browser]

    /// Full-content lock shown while Reroute is not the system default browser:
    /// routing can't fire, so every control is disabled and the only action is to
    /// become default. This is a window-content state, not a modal — the window
    /// still closes/minimizes normally and the title bar stays live.
    private var notDefaultOverlay: some View {
        ZStack {
            // Translucent veil over the whole content area. Adaptive (not a fixed
            // light fill) so it — and the card's adaptive text — stay legible in
            // dark mode; a fixed-light surface under adaptive text is exactly what
            // got 1.0 rejected for contrast.
            Rectangle()
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.6))

            VStack(spacing: 13) {
                brandTile(size: 56, cornerRadius: 14)
                    .shadow(
                        color: Color(red: 1.0, green: 0.18, blue: 0.33).opacity(0.34),
                        radius: 6, y: 3)
                Text("Reroute isn't your default browser")
                    .font(.system(size: 16, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(
                    "Routing rules only work when macOS hands links to Reroute. Until then, every link keeps opening in your usual browser."
                )
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)
                Button("Set as default browser") { store.setAsDefaultBrowser() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .padding(.top, 2)
                Text("macOS will ask you to confirm the change.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(28)
            .frame(width: 380)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .shadow(color: .black.opacity(0.18), radius: 22, y: 10)
            )
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: - Sidebar (browser availability + launch-at-login)

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader
            sectionLabel("Browsers")
            browserList
            Divider()
            sidebarFooter
        }
        .frame(width: 236)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// The Reroute brand tile (pink gradient rounded square + link glyph). Shared
    /// by the sidebar header and the not-default lock card so both render the same
    /// mark at any size — and offscreen (it's drawn, not loaded from the icon).
    private func brandTile(size: CGFloat, cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(red: 1.0, green: 0.36, blue: 0.48), Color(red: 1.0, green: 0.18, blue: 0.33)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "link")
                    .font(.system(size: size * 0.47, weight: .bold))
                    .foregroundStyle(.white)
            )
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            brandTile(size: 30, cornerRadius: 8)
                .shadow(color: Color(red: 1.0, green: 0.18, blue: 0.33).opacity(0.34), radius: 3, y: 2)
            Text("Reroute")
                .font(.system(size: 13.5, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func sectionLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 11, weight: .semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Each row toggles whether the browser is offered in the picker and rule
    // dropdowns. Hiding the last visible one is blocked at the toggle
    // (store.canHideBrowser). [REF:fr:browser-visibility]
    private var browserList: some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(store.browsers) { browser in
                    browserRow(browser)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
        }
        .frame(maxHeight: .infinity)
    }

    private func browserRow(_ browser: Browser) -> some View {
        let shown = !store.hiddenBrowserIDs.contains(browser.bundleID)
        return HStack(spacing: 9) {
            Image(nsImage: store.icon(for: browser))
                .resizable()
                .frame(width: 19, height: 19)
            Text(verbatim: browser.name)
                .font(.system(size: 12.5))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Toggle(
                "",
                isOn: Binding(
                    get: { shown },
                    set: { store.setBrowserHidden(browser.bundleID, !$0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(shown && !store.canHideBrowser(browser.bundleID))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .help(browser.name)
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Disabled browsers aren't offered in rules.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // [REF:fr:login-item]
            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.launchAtLogin = $0 }
                )
            )
            .toggleStyle(.checkbox)
            .font(.system(size: 12.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Rules pane

    private var rulesPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneHeader
            columnHeader
            rulesList
            Divider()
            addRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }

    /// Pane title with the search field beside it. The field only appears once
    /// there is something to search — an empty list needs no filter, and the
    /// first-run window stays as bare as it was.
    private var paneHeader: some View {
        HStack(spacing: 12) {
            Text("Routing rules")
                .font(.system(size: 15, weight: .bold))
            Spacer(minLength: 8)
            if !store.rules.isEmpty {
                searchField
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 15)
        .padding(.bottom, 11)
    }

    /// Compact search field: glyph, text, and a clear button that only shows
    /// while there is something to clear. [REF:fr:rules-search]
    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("", text: $query, prompt: Text("Search domains"))
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($searchFocused)
                .frame(width: 150)
            if !query.isEmpty {
                Button {
                    query = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                )
        )
    }

    /// The rules the list shows: everything, or what the search matches.
    private var visibleRules: [Rule] {
        RuleFilter.matching(store.rules, query: query)
    }

    private var columnHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Domain")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Open in")
                    .frame(width: 170, alignment: .leading)
                Spacer().frame(width: 28)
            }
            .font(.system(size: 10.5, weight: .semibold))
            .textCase(.uppercase)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 20)
            .padding(.vertical, 5)
            Divider()
        }
    }

    @ViewBuilder
    private var rulesList: some View {
        if store.rules.isEmpty {
            Text("No rules yet. When you open a link, pick a browser and enable Remember, or add a rule below.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if visibleRules.isEmpty {
            // Rules exist, the search just hides them — say so, so an empty pane
            // is never read as "my rules are gone". [REF:fr:rules-search]
            Text("No rules match “\(query)”.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView {
                // Lazy: a rule row costs about 12 ms to build, almost all of it
                // the browser dropdown, so building the rows below the fold is
                // what made typing in the search field stutter.
                LazyVStack(spacing: 0) {
                    ForEach(visibleRules) { rule in
                        RuleRow(rule: rule)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Add row (pinned at the bottom of the rules pane)

    private var addRow: some View {
        HStack(spacing: 10) {
            TextField("", text: $newDomain, prompt: Text(verbatim: "github.com"))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                .onSubmit(addRule)
            BrowserPicker(selection: $newBundleID)
                .frame(width: 150)
            Button("Add", action: addRule)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty || newBundleID.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
    }

    private func addRule() {
        let domain = newDomain.trimmingCharacters(in: .whitespaces)
        guard !domain.isEmpty, !newBundleID.isEmpty else { return }
        store.addRule(domain: domain, bundleID: newBundleID)
        newDomain = ""
        // Drop any active search — otherwise the rule just added can land
        // outside the filter and look like it was not saved.
        query = ""
    }
}

/// One rule: icon, domain, browser dropdown, delete.
///
/// A view of its own rather than a method on `RulesView`, because the only thing
/// it stores is the rule. Typing in the search field re-evaluates `RulesView`'s
/// body, and SwiftUI can skip re-building the rows whose rule did not change —
/// which it cannot do for a view built inline in the parent's body.
private struct RuleRow: View {
    @EnvironmentObject var store: AppStore
    let rule: Rule

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 9) {
                if let b = store.browser(forBundleID: rule.bundleID) {
                    Image(nsImage: store.icon(for: b))
                        .resizable()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "questionmark.square.dashed")
                        .frame(width: 20, height: 20)
                        .foregroundStyle(.secondary)
                }
                Text(verbatim: rule.domain)
                    .font(.system(size: 13.5, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            BrowserMenuButton(currentID: rule.bundleID) {
                store.updateRuleBrowser(rule, bundleID: $0)
            }
            .frame(width: 170)

            Button(role: .destructive) {
                store.deleteRule(rule)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .frame(width: 28)
            .help("Delete")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
    }
}

/// The rule rows' browser control: drawn as a popup button, but only *drawn*.
///
/// A real `Picker` costs about 12.6 ms to build against 0.36 ms for this — with
/// one per rule that is the difference between a list that scrolls and one that
/// stutters, even though at most one dropdown is ever open. The click opens a
/// real `NSMenu` at the same place, so the interaction is unchanged.
///
/// Browsers offered match the sidebar toggles; a rule pointing at a now-hidden
/// or uninstalled browser keeps showing its target. [REF:fr:browser-visibility]
private struct BrowserMenuButton: View {
    @EnvironmentObject var store: AppStore
    let currentID: String
    let onSelect: (String) -> Void

    @State private var anchor = MenuAnchor.Holder()
    @State private var handler = MenuHandler()

    private var title: String {
        store.browser(forBundleID: currentID)?.name ?? (currentID.isEmpty ? "" : "⚠️ \(currentID)")
    }

    var body: some View {
        Button(action: present) {
            HStack(spacing: 5) {
                Text(verbatim: title)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 2)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(nsColor: .controlColor))
                    .shadow(color: .black.opacity(0.10), radius: 0.5, y: 0.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(MenuAnchor(holder: anchor))
        .accessibilityLabel(Text("Open in"))
        .accessibilityValue(Text(verbatim: title))
    }

    private func present() {
        guard let view = anchor.view else { return }
        let menu = NSMenu()
        var listed = store.pickerBrowsers.map { ($0.name, $0.bundleID) }
        if !listed.contains(where: { $0.1 == currentID }), !currentID.isEmpty {
            listed.append((title, currentID))
        }
        handler.onSelect = onSelect
        for (name, id) in listed {
            let item = NSMenuItem(
                title: name, action: #selector(MenuHandler.pick(_:)), keyEquivalent: "")
            item.target = handler
            item.representedObject = id
            item.state = id == currentID ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(
            positioning: menu.items.first { $0.state == .on },
            at: NSPoint(x: 0, y: view.bounds.height), in: view)
    }
}

/// Captures the backing `NSView` so the menu can be positioned over the button.
private struct MenuAnchor: NSViewRepresentable {
    final class Holder { var view: NSView? }
    let holder: Holder

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        holder.view = v
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) { holder.view = nsView }
}

/// Menu-item target. `NSMenuItem` needs an ObjC target/action pair, so the
/// SwiftUI closure is parked here for the lifetime of the button.
private final class MenuHandler: NSObject {
    var onSelect: ((String) -> Void)?

    @objc func pick(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        onSelect?(id)
    }
}

/// A real browser dropdown, used by the add row — there is only one of it, so
/// the cost that rules out a `Picker` per rule row does not apply.
/// [REF:fr:browser-visibility]
private struct BrowserPicker: View {
    @EnvironmentObject var store: AppStore
    @Binding var selection: String

    var body: some View {
        let enabled = store.pickerBrowsers
        Picker("", selection: $selection) {
            ForEach(enabled) { Text(verbatim: $0.name).tag($0.bundleID) }
            if !enabled.contains(where: { $0.bundleID == selection }) {
                if let b = store.browser(forBundleID: selection) {
                    Text(verbatim: b.name).tag(selection)
                } else if !selection.isEmpty {
                    Text(verbatim: "⚠️ \(selection)").tag(selection)
                }
            }
        }
        .labelsHidden()
    }
}
