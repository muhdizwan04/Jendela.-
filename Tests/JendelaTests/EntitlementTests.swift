import XCTest
@testable import Jendela

/// What the free tier gets is a published promise: the pricing page lists
/// "Five clipboard entries" on the free plan and the FAQ says history
/// shortens rather than disappears. A paywall over the whole clipboard tab
/// broke both, and made `effectiveClipboardLimit` unreachable.
@MainActor
final class EntitlementTests: XCTestCase {
    func testClipboardStaysUsableWithoutALicence() {
        let state = JendelaState()
        guard !state.isPro else {
            return   // a real licence is present on this machine
        }
        XCTAssertFalse(state.requiresLicence(.clipboard),
                       "the clipboard is capped for free users, not paywalled")
        XCTAssertEqual(state.effectiveClipboardLimit, 5)
    }

    func testFreeForeverSectionsAreNeverPaywalled() {
        let state = JendelaState()
        for section in [JendelaState.NotchSection.home, .music, .sound, .discord, .clipboard] {
            XCTAssertFalse(state.requiresLicence(section), "\(section.rawValue) must stay free")
        }
    }

    func testPaidSectionsAreGatedWithoutALicence() {
        let state = JendelaState()
        guard !state.isPro else { return }
        for section in [JendelaState.NotchSection.shelf, .day, .ai] {
            XCTAssertTrue(state.requiresLicence(section), "\(section.rawValue) should need a licence")
        }
    }
}
