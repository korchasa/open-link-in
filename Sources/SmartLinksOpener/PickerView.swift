import SwiftUI

/// Shown when an incoming link matches no rule: pick a browser, optionally
/// remembering the choice as a new rule.
struct PickerView: View {
    @EnvironmentObject var store: AppStore
    let url: URL
    @State private var remember = true

    private var domain: String {
        store.ruleDomain(for: url) ?? url.host ?? url.absoluteString
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Open link")
                    .font(.headline)
                Text(url.absoluteString)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Divider()

            Text("Choose a browser")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(store.browsers) { browser in
                        Button {
                            store.choose(browser, for: url, remember: remember)
                        } label: {
                            HStack(spacing: 10) {
                                Image(nsImage: store.icon(for: browser))
                                    .resizable()
                                    .frame(width: 26, height: 26)
                                Text(browser.name)
                                Spacer()
                            }
                            .padding(.vertical, 7)
                            .padding(.horizontal, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                    }
                }
                .padding(.vertical, 2)
            }

            Toggle("Remember choice for \(domain)", isOn: $remember)

            HStack {
                Spacer()
                Button("Cancel") { store.cancelPending() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
    }
}
