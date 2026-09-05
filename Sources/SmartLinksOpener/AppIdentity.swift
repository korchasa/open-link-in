import Foundation

/// What this copy of the app calls itself, read from its own bundle: the
/// locally installed "Reroute Dev" copy carries a `.dev` bundle id and a
/// version suffixed with its commit, and the UI shows both so a build under
/// test is never mistaken for the store build sitting next to it.
enum AppIdentity {
    static var isDev: Bool { Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true }

    static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Reroute"
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}
