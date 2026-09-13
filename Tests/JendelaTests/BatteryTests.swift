import XCTest
@testable import Jendela

final class BatteryTests: XCTestCase {
    @MainActor func testReadsThisMac() throws {
        let batteries = Batteries()
        batteries.refresh()
        guard let mac = batteries.mac else {
            throw XCTSkip("no battery (desktop Mac)")
        }
        print("MAC: \(mac.percent)% charging=\(mac.charging) time=\(mac.timeText ?? "—")")
        XCTAssertTrue((1...100).contains(mac.percent), "percentage out of range: \(mac.percent)")
    }

    @MainActor func testReadsAccessories() {
        let batteries = Batteries()
        batteries.refresh()
        print("ACCESSORIES: \(batteries.devices.count)")
        for device in batteries.devices {
            print("  \(device.name) combined=\(device.combined.map(String.init) ?? "—") "
                  + "L=\(device.left.map(String.init) ?? "—") R=\(device.right.map(String.init) ?? "—") "
                  + "case=\(device.caseLevel.map(String.init) ?? "—") symbol=\(device.symbol)")
            XCTAssertNotNil(device.lowest, "a listed device must report at least one level")
        }
    }
}
