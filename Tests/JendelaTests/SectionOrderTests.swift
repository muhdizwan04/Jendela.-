import SwiftUI
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

/// The drag itself is wired through `JendelaState.draggingSection`.
///
/// It first shipped as a `@State` inside each tile, so the tile being dragged
/// set its own copy and the tile being dropped on read its own — always nil.
/// `dropEntered` returned early every time and reordering did nothing at all,
/// which is exactly what a user saw.
@MainActor
final class SectionDragTests: XCTestCase {
    func testDropOnAnotherTabReordersThroughSharedState() {
        let state = JendelaState()
        state.enabledSections = [.home, .clipboard, .music, .sound]

        // What the tile's onDrag does.
        state.draggingSection = .sound
        // What the drop target does as the pointer passes over it.
        SectionDropDelegate(state: state, target: .clipboard).reorder()

        XCTAssertEqual(state.visibleSections, [.home, .sound, .clipboard, .music],
                       "the drag did not reach the drop target")
    }

    func testDroppingOnItselfDoesNothing() {
        let state = JendelaState()
        state.enabledSections = [.home, .clipboard, .music]
        state.draggingSection = .clipboard
        SectionDropDelegate(state: state, target: .clipboard).reorder()
        XCTAssertEqual(state.visibleSections, [.home, .clipboard, .music])
    }

    func testNothingHappensWithoutADrag() {
        let state = JendelaState()
        state.enabledSections = [.home, .clipboard, .music]
        state.draggingSection = nil
        SectionDropDelegate(state: state, target: .home).reorder()
        XCTAssertEqual(state.visibleSections, [.home, .clipboard, .music])
    }

    func testNudgeMovesOnePlace() {
        let state = JendelaState()
        state.enabledSections = [.home, .clipboard, .music]

        XCTAssertTrue(state.nudgeSection(.music, by: -1))
        XCTAssertEqual(state.visibleSections, [.home, .music, .clipboard])

        XCTAssertTrue(state.nudgeSection(.music, by: 1))
        XCTAssertEqual(state.visibleSections, [.home, .clipboard, .music])
    }

    func testNudgeStopsAtTheEnds() {
        let state = JendelaState()
        state.enabledSections = [.home, .clipboard]
        XCTAssertFalse(state.nudgeSection(.home, by: -1), "moved past the start")
        XCTAssertFalse(state.nudgeSection(.clipboard, by: 1), "moved past the end")
        XCTAssertEqual(state.visibleSections, [.home, .clipboard])
    }

    func testNudgeIgnoresAHiddenTab() {
        let state = JendelaState()
        state.enabledSections = [.home, .clipboard]
        XCTAssertFalse(state.nudgeSection(.day, by: -1))
        XCTAssertEqual(state.visibleSections, [.home, .clipboard])
    }

}
