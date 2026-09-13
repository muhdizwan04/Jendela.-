import XCTest
@testable import Jendela

/// The hub renders `visibleSections` in order, so that array is the
/// arrangement. Re-enabling a tab used to rewrite the whole thing back into the
/// built-in order, which would silently undo an arrangement the user had set.
@MainActor
final class SectionOrderTests: XCTestCase {
    func testMovingATabChangesWhereItSits() {
        let state = JendelaState()
        state.enabledSections = [.home, .clipboard, .music, .sound]

        state.moveSection(.sound, to: .clipboard)

        XCTAssertEqual(state.visibleSections, [.home, .sound, .clipboard, .music])
    }

    func testMovingForwardsLandsInTheTargetsPlace() {
        let state = JendelaState()
        state.enabledSections = [.home, .clipboard, .music, .sound]

        state.moveSection(.home, to: .music)

        XCTAssertEqual(state.visibleSections, [.clipboard, .home, .music, .sound])
    }

    func testReEnablingDoesNotRewriteTheArrangement() {
        let state = JendelaState()
        state.enabledSections = [.music, .home, .clipboard]

        state.setSection(.shelf, enabled: true)

        XCTAssertEqual(state.visibleSections.prefix(3).map(\.rawValue),
                       ["Music", "Home", "Clipboard"],
                       "adding a tab reordered the ones already there")
        XCTAssertEqual(state.visibleSections.last, .shelf)
    }

    func testTheLastTabCannotBeTurnedOff() {
        let state = JendelaState()
        state.enabledSections = [.home]
        state.setSection(.home, enabled: false)
        XCTAssertEqual(state.visibleSections, [.home], "the hub was left with no tabs")
    }

    func testOrderedSectionsListsEnabledFirstThenTheRest() {
        let state = JendelaState()
        state.enabledSections = [.sound, .home]
        let ordered = state.orderedSections
        XCTAssertEqual(ordered.prefix(2), [.sound, .home])
        XCTAssertEqual(Set(ordered), Set(JendelaState.NotchSection.allCases), "a tab went missing")
        XCTAssertEqual(ordered.count, JendelaState.NotchSection.allCases.count)
    }

    func testDraggingAHiddenTabTurnsItOnAtThatPosition() {
        let state = JendelaState()
        state.enabledSections = [.home, .clipboard]
        state.moveSection(.day, to: .clipboard)
        XCTAssertEqual(state.visibleSections, [.home, .day, .clipboard])
    }
}
