import Foundation
import IOKit
import IOKit.ps

/// Battery levels for this Mac and for connected Bluetooth accessories.
///
/// Read on demand — when the hub opens — rather than on a timer. A battery
/// percentage that nobody is looking at is not worth a wakeup, and neither
/// source pushes changes.
@MainActor
final class Batteries: ObservableObject {
    struct Device: Identifiable, Equatable {
        var id: String { name }
        var name: String
        /// Left, right and case are separate on earbuds; a single device
        /// reports only `combined`.
        var combined: Int?
        var left: Int?
        var right: Int?
        var caseLevel: Int?
        var symbol: String

        var lowest: Int? {
            [combined, left, right, caseLevel].compactMap { $0 }.min()
        }
    }

    struct Mac: Equatable {
        var percent: Int
        var charging: Bool
        var minutesRemaining: Int?

        var timeText: String? {
            guard let minutes = minutesRemaining, minutes > 0 else { return nil }
            return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m left" : "\(minutes)m left"
        }
    }

    @Published private(set) var mac: Mac?
    @Published private(set) var devices: [Device] = []

    func refresh() {
        mac = Self.readMac()
        devices = Self.readBluetooth()
    }

    // MARK: - This Mac

    private static func readMac() -> Mac? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue()
                as? [String: Any],
                  let current = info[kIOPSCurrentCapacityKey] as? Int,
                  let max = info[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }

            let charging = (info[kIOPSIsChargingKey] as? Bool) ?? false
            let minutes = info[kIOPSTimeToEmptyKey] as? Int
            return Mac(
                percent: Int((Double(current) / Double(max) * 100).rounded()),
                charging: charging,
                // -1 means "still calculating"; showing that would be worse
                // than showing nothing.
                minutesRemaining: (minutes ?? -1) > 0 ? minutes : nil
            )
        }
        return nil
    }

    // MARK: - Bluetooth accessories

    /// AirPods and similar publish their levels through the HID event service
    /// in the IO registry. This is the same data the Bluetooth menu shows, read
    /// directly rather than by shelling out to `system_profiler`, which takes
    /// seconds and spawns a process.
    private static func readBluetooth() -> [Device] {
        var iterator = io_iterator_t()
        let matching = IOServiceMatching("AppleDeviceManagementHIDEventService")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }

        var found: [Device] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }

            func number(_ key: String) -> Int? {
                guard let value = IORegistryEntryCreateCFProperty(
                    service, key as CFString, kCFAllocatorDefault, 0
                )?.takeRetainedValue() as? NSNumber else { return nil }
                let level = value.intValue
                return (1...100).contains(level) ? level : nil
            }

            let name = (IORegistryEntryCreateCFProperty(
                service, "Product" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? String) ?? "Accessory"

            let device = Device(
                name: name,
                combined: number("BatteryPercentCombined") ?? number("BatteryPercent"),
                left: number("BatteryPercentLeft"),
                right: number("BatteryPercentRight"),
                caseLevel: number("BatteryPercentCase"),
                symbol: Self.symbol(for: name)
            )
            // Plenty of HID services report no level at all; skip those.
            guard device.lowest != nil else { continue }
            found.append(device)
        }
        return found
    }

    private static func symbol(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpodsmax" }
        if lower.contains("airpods pro") { return "airpodspro" }
        if lower.contains("airpod") { return "airpods" }
        if lower.contains("beats") || lower.contains("head") { return "headphones" }
        if lower.contains("mouse") { return "magicmouse" }
        if lower.contains("trackpad") { return "magictrackpad" }
        if lower.contains("keyboard") { return "keyboard" }
        return "battery.100"
    }
}
