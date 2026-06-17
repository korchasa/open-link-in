import Foundation

/// Pure title logic for the picker header. A local file has no domain, so it is
/// labelled by its filename; a web link is labelled by its registrable
/// (second-level) domain, falling back to the host then the full string.
/// [REF:fr:file-open]
enum LinkLabel {
    static func title(for url: URL) -> String {
        if url.isFileURL { return url.lastPathComponent }
        guard let host = url.host, !host.isEmpty else { return url.absoluteString }
        let domain = Domain.registrable(host)
        return domain.isEmpty ? host : domain
    }
}
