import Foundation

/// Pure domain-name helpers — reduce a host to its registrable (second-level)
/// domain and test rule matching. No I/O, no AppKit: safe to unit-test in
/// isolation. [REF:fr:subdomain]
enum Domain {
    /// Multi-label public suffixes where the registrable domain needs 3+ labels.
    /// Curated subset of the Public Suffix List (common ccTLD second levels +
    /// popular hosting suffixes). Not exhaustive by design — unknown suffixes
    /// fall back to the last two labels.
    static let multiLabelSuffixes: Set<String> = [
        // ccTLD second levels
        "co.uk", "org.uk", "ac.uk", "gov.uk", "me.uk", "ltd.uk", "plc.uk", "net.uk", "sch.uk",
        "com.au", "net.au", "org.au", "edu.au", "gov.au", "id.au",
        "co.jp", "or.jp", "ne.jp", "ac.jp", "go.jp", "ad.jp",
        "co.nz", "net.nz", "org.nz", "govt.nz", "ac.nz",
        "com.br", "net.br", "org.br", "gov.br",
        "co.in", "net.in", "org.in", "gen.in", "firm.in", "ind.in",
        "com.cn", "net.cn", "org.cn", "gov.cn",
        "co.kr", "or.kr", "ne.kr",
        "co.za", "org.za", "gov.za",
        "com.mx", "com.tr", "com.ar", "com.sg", "com.hk", "com.tw", "com.ua", "com.pl",
        "co.il", "co.id", "co.th", "com.vn", "com.ph", "com.my",
        // popular hosting / dynamic-DNS public suffixes (each subdomain is its own site)
        "github.io", "gitlab.io", "pages.dev", "vercel.app", "netlify.app",
        "herokuapp.com", "web.app", "firebaseapp.com", "workers.dev", "r2.dev",
        "s3.amazonaws.com",
    ]

    /// Normalize a host or full URL: lowercase, trim, drop a trailing dot and a
    /// leading `www.`.
    static func normalizeHost(_ raw: String) -> String {
        var h = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let host = URLComponents(string: h)?.host, !host.isEmpty {
            h = host.lowercased()
        }
        if h.hasSuffix(".") { h = String(h.dropLast()) }
        if h.hasPrefix("www.") { h = String(h.dropFirst(4)) }
        return h
    }

    /// Reduce a host to its registrable (second-level) domain.
    /// `mail.google.com` → `google.com`; `a.b.news.bbc.co.uk` → `bbc.co.uk`;
    /// `user.github.io` → `user.github.io`.
    static func registrable(_ rawHost: String) -> String {
        let host = normalizeHost(rawHost)
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count > 2 else { return host }

        // Match the longest known multi-label public suffix, then keep one more
        // label in front of it as the registrable domain.
        let maxSuffix = min(3, labels.count - 1)
        var suffixLen = maxSuffix
        while suffixLen >= 2 {
            let suffix = labels.suffix(suffixLen).joined(separator: ".")
            if multiLabelSuffixes.contains(suffix) {
                return labels.suffix(suffixLen + 1).joined(separator: ".")
            }
            suffixLen -= 1
        }
        // Default: last two labels.
        return labels.suffix(2).joined(separator: ".")
    }

    /// Does `rawHost` fall under `ruleDomain` — exact match or any subdomain?
    static func host(_ rawHost: String, matchesRule ruleDomain: String) -> Bool {
        let host = normalizeHost(rawHost)
        let rule = ruleDomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !rule.isEmpty else { return false }
        return host == rule || host.hasSuffix("." + rule)
    }
}
