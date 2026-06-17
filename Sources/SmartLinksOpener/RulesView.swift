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

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            rulesPane
        }
        .frame(minWidth: 560, minHeight: 420)
        .onAppear {
            if newBundleID.isEmpty { newBundleID = store.pickerBrowsers.first?.bundleID ?? "" }
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

    private var brandHeader: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.36, blue: 0.48), Color(red: 1.0, green: 0.18, blue: 0.33)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: "link")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                )
                .shadow(color: Color(red: 1.0, green: 0.18, blue: 0.33).opacity(0.34), radius: 3, y: 2)
            Text("Smart Links Opener")
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
            Text("Routing rules")
                .font(.system(size: 15, weight: .bold))
                .padding(.horizontal, 20)
                .padding(.top, 15)
                .padding(.bottom, 11)
            defaultBrowserBanner
            columnHeader
            rulesList
            Divider()
            addRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // Status of the system default-browser handoff. Until the app is the default,
    // rules never fire, so the warning is prominent with a one-click fix.
    // [REF:fr:default-browser]
    @ViewBuilder
    private var defaultBrowserBanner: some View {
        if store.isDefaultBrowser() {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Default browser in the system")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 10)
        } else {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(red: 0.72, green: 0.53, blue: 0.04))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not the system default browser")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Rules apply only when macOS hands links to this app.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button("Make default") { store.setAsDefaultBrowser() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(red: 1.0, green: 0.97, blue: 0.90))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color(red: 0.94, green: 0.83, blue: 0.53), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
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
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(store.rules) { rule in
                        ruleRow(rule)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func ruleRow(_ rule: Rule) -> some View {
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
                    .font(.system(size: 13.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            browserPicker(
                selection: Binding(
                    get: { rule.bundleID },
                    set: { store.updateRuleBrowser(rule, bundleID: $0) }
                ),
                currentID: rule.bundleID
            )
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

    // MARK: - Add row (pinned at the bottom of the rules pane)

    private var addRow: some View {
        HStack(spacing: 10) {
            TextField("", text: $newDomain, prompt: Text(verbatim: "github.com"))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                .onSubmit(addRule)
            browserPicker(selection: $newBundleID, currentID: newBundleID)
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

    // A browser dropdown listing only enabled (non-hidden) browsers, matching the
    // sidebar toggles. A rule pointing at a now-hidden or uninstalled browser keeps
    // showing its current target so the choice is never silently lost.
    // [REF:fr:browser-visibility]
    @ViewBuilder
    private func browserPicker(selection: Binding<String>, currentID: String) -> some View {
        let enabled = store.pickerBrowsers
        Picker("", selection: selection) {
            ForEach(enabled) { Text(verbatim: $0.name).tag($0.bundleID) }
            if !enabled.contains(where: { $0.bundleID == currentID }) {
                if let b = store.browser(forBundleID: currentID) {
                    Text(verbatim: b.name).tag(currentID)
                } else if !currentID.isEmpty {
                    Text(verbatim: "⚠️ \(currentID)").tag(currentID)
                }
            }
        }
        .labelsHidden()
    }

    private func addRule() {
        let domain = newDomain.trimmingCharacters(in: .whitespaces)
        guard !domain.isEmpty, !newBundleID.isEmpty else { return }
        store.addRule(domain: domain, bundleID: newBundleID)
        newDomain = ""
    }
}
