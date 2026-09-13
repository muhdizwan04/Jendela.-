import XCTest
@testable import Jendela

/// The Join button opens a link taken out of a calendar invitation, and an
/// invitation is written by whoever sent it. Matching the host with `contains`
/// accepted `zoom.us.example.com`, which let any invite render an
/// attacker-controlled link as a trusted meeting.
@MainActor
final class MeetingLinkTests: XCTestCase {
    func testRealMeetingLinksAreAccepted() {
        for link in [
            "https://zoom.us/j/123456789",
            "https://us02web.zoom.us/j/123456789",
            "https://meet.google.com/abc-defg-hij",
            "https://teams.microsoft.com/l/meetup-join/x",
            "https://company.webex.com/meet/someone",
            "https://meet.jit.si/room",
        ] {
            XCTAssertTrue(Meetings.isMeetingLink(URL(string: link)), "rejected a real link: \(link)")
        }
    }

    func testLookalikeHostsAreRejected() {
        for link in [
            "https://zoom.us.example.com/j/1",        // suffix attack
            "https://evil.com/zoom.us/j/1",           // path only
            "https://notzoom.us.attacker.net/j/1",
            "https://meet.google.com.phish.io/abc",
            "https://webex.com.evil.co/meet",
        ] {
            XCTAssertFalse(Meetings.isMeetingLink(URL(string: link)),
                           "accepted a lookalike: \(link)")
        }
    }

    func testUnrelatedLinksAreRejected() {
        XCTAssertFalse(Meetings.isMeetingLink(URL(string: "https://example.com")))
        XCTAssertFalse(Meetings.isMeetingLink(nil))
    }

    /// A bare host must still match, not only its subdomains.
    func testBareHostMatches() {
        XCTAssertTrue(Meetings.isMeetingLink(URL(string: "https://whereby.com/room")))
    }
}
