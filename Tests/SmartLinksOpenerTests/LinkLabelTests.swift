import XCTest

@testable import SmartLinksOpener

/// Acceptance for FR-FILE-OPEN: the picker header title is derived purely from
/// the URL — a local file shows its filename (no domain exists), a web URL
/// shows its registrable second-level domain.
final class LinkLabelTests: XCTestCase {
    func testFileURLShowsFilename() {
        let url = URL(fileURLWithPath: "/Users/someone/Documents/report.html")
        XCTAssertEqual(LinkLabel.title(for: url), "report.html")
    }

    func testWebURLShowsRegistrableDomain() {
        let url = URL(string: "https://mail.google.com/inbox?x=1")!
        XCTAssertEqual(LinkLabel.title(for: url), "google.com")
    }
}
