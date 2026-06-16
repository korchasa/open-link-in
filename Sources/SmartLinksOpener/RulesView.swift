import SwiftUI

/// The management window: default-browser status, rule list, and a row to add
/// new rules.
struct RulesView: View {
    @EnvironmentObject var store: AppStore
    @State private var newDomain = ""
    @State private var newBundleID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            rulesSection
            Divider()
            addRow
            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.launchAtLogin = $0 }
                )
            )
            .font(.subheadline)
        }
        .padding(20)
        .onAppear {
            if newBundleID.isEmpty { newBundleID = store.browsers.first?.bundleID ?? "" }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Smart Links Opener")
                    .font(.title2).bold()
                Text("Route links by domain")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            defaultBrowserControl
        }
    }

    @ViewBuilder
    private var defaultBrowserControl: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if store.isDefaultBrowser() {
                Label("Default browser", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            } else {
                Button("Set as default browser") {
                    store.setAsDefaultBrowser()
                }
            }
            if let status = store.statusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Rules").font(.headline)
                Spacer()
                Button {
                    store.refreshBrowsers()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh browser list")
            }

            if store.rules.isEmpty {
                Text("No rules yet. When you open a link, pick a browser and enable Remember, or add a rule below.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(store.rules) { rule in
                            ruleRow(rule)
                        }
                    }
                }
                .frame(minHeight: 120)
            }
        }
    }

    private func ruleRow(_ rule: Rule) -> some View {
        HStack(spacing: 8) {
            Text(rule.domain)
                .frame(width: 170, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
                .font(.caption)
            Picker(
                "",
                selection: Binding(
                    get: { rule.bundleID },
                    set: { store.updateRuleBrowser(rule, bundleID: $0) }
                )
            ) {
                ForEach(store.browsers) { Text($0.name).tag($0.bundleID) }
                if store.browser(forBundleID: rule.bundleID) == nil {
                    Text(verbatim: "⚠️ \(rule.bundleID)").tag(rule.bundleID)
                }
            }
            .labelsHidden()
            Spacer()
            Button(role: .destructive) {
                store.deleteRule(rule)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            TextField("domain, e.g. github.com", text: $newDomain)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit(addRule)
            Picker("", selection: $newBundleID) {
                ForEach(store.browsers) { Text(verbatim: $0.name).tag($0.bundleID) }
            }
            .labelsHidden()
            .frame(width: 160)
            Button("Add", action: addRule)
                .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty || newBundleID.isEmpty)
            Spacer()
        }
    }

    private func addRule() {
        let domain = newDomain.trimmingCharacters(in: .whitespaces)
        guard !domain.isEmpty, !newBundleID.isEmpty else { return }
        store.addRule(domain: domain, bundleID: newBundleID)
        newDomain = ""
    }
}
