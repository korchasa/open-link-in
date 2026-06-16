import XCTest

@testable import SmartLinksOpener

/// Acceptance tests for subdomain routing + registrable-domain persistence.
/// [REF:fr:subdomain]
final class DomainTests: XCTestCase {

    // MARK: registrable() — what gets saved into the data

    func testRegistrableReducesToSecondLevel() {
        XCTAssertEqual(Domain.registrable("mail.google.com"), "google.com")
        XCTAssertEqual(Domain.registrable("a.b.c.example.com"), "example.com")
        XCTAssertEqual(Domain.registrable("google.com"), "google.com")
    }

    func testRegistrableStripsWWWAndCase() {
        XCTAssertEqual(Domain.registrable("www.example.com"), "example.com")
        XCTAssertEqual(Domain.registrable("Mail.GOOGLE.com"), "google.com")
    }

    func testRegistrableAcceptsFullURL() {
        XCTAssertEqual(Domain.registrable("https://gist.github.com/user/x?y=1"), "github.com")
        XCTAssertEqual(Domain.registrable("http://news.ycombinator.com/item?id=1"), "ycombinator.com")
    }

    func testRegistrableHandlesMultiLabelPublicSuffixes() {
        XCTAssertEqual(Domain.registrable("news.bbc.co.uk"), "bbc.co.uk")
        XCTAssertEqual(Domain.registrable("a.b.bbc.co.uk"), "bbc.co.uk")
        XCTAssertEqual(Domain.registrable("shop.example.com.au"), "example.com.au")
        // hosting suffixes: each subdomain is its own registrable site
        XCTAssertEqual(Domain.registrable("user.github.io"), "user.github.io")
        XCTAssertEqual(Domain.registrable("bucket.s3.amazonaws.com"), "bucket.s3.amazonaws.com")
    }

    func testRegistrableEdgeCases() {
        XCTAssertEqual(Domain.registrable("localhost"), "localhost")
        XCTAssertEqual(Domain.registrable(""), "")
    }

    // MARK: host(_:matchesRule:) — every subdomain routes to the rule's browser

    func testAllSubdomainsMatchTheRule() {
        XCTAssertTrue(Domain.host("google.com", matchesRule: "google.com"))
        XCTAssertTrue(Domain.host("mail.google.com", matchesRule: "google.com"))
        XCTAssertTrue(Domain.host("deep.a.b.google.com", matchesRule: "google.com"))
        XCTAssertTrue(Domain.host("https://drive.google.com/x", matchesRule: "google.com"))
    }

    func testUnrelatedHostsDoNotMatch() {
        XCTAssertFalse(Domain.host("notgoogle.com", matchesRule: "google.com"))
        XCTAssertFalse(Domain.host("google.com.evil.com", matchesRule: "google.com"))
        XCTAssertFalse(Domain.host("example.org", matchesRule: "google.com"))
        XCTAssertFalse(Domain.host("anything.com", matchesRule: ""))
    }
}
