import AppKit
import SwiftUI
import XCTest
@testable import Jendela

/// `NotchSection.contentHeight` is a table of hand-measured constants, and the
/// hub clips to it. When a section's content grows past its number the bottom
/// of that section is silently cut off on screen, so the numbers are checked
/// against what the views actually lay out to.
@MainActor
final class SectionHeightTests: XCTestCase {
    func testDeclaredHeightsCoverWhatTheViewsActuallyNeed() {
        let state = JendelaState()
        state.appliedTemplateID = "midnight"
        let width = state.hubWidth - NotchMetrics.horizontalInset * 2

        func measure<V: View>(_ view: V) -> CGFloat {
            let host = NSHostingView(rootView: view.frame(width: width))
            return host.fittingSize.height
        }

        let measured: [(JendelaState.NotchSection, CGFloat)] = [
            (.home, measure(HomeNotchSection(state: state))),
            (.music, measure(MusicNotchSection(state: state))),
            (.sound, measure(SoundNotchSection(state: state))),
            (.discord, measure(DiscordNotchSection(state: state))),
            (.day, measure(DayNotchSection(state: state)))
        ]

        var short: [String] = []
        for (section, needed) in measured {
            let declared = section.contentHeight(clipboardCount: 0, shelfCount: 0)
            print(String(format: "%@: declared %.0f, needs %.0f", section.rawValue, declared, needed))
            if needed > declared + 0.5 {
                short.append(String(format: "%@ declares %.0f but needs %.0f",
                                    section.rawValue, declared, needed))
            }
        }
        XCTAssertTrue(short.isEmpty, "sections clipped: " + short.joined(separator: "; "))
    }
}
