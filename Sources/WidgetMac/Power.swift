import Combine
import Foundation
import IOKit.ps

extension Notification.Name {
    static let widgetMacPowerSourceChanged = Notification.Name("widgetMacPowerSourceChanged")
}

/// C callbacks carry no context, so this hands off to NotificationCenter and
/// `PowerMonitor` picks it up on the main run loop.
private func powerSourceChanged(_ context: UnsafeMutableRawPointer?) {
    NotificationCenter.default.post(name: .widgetMacPowerSourceChanged, object: nil)
}

/// The app's single source of truth for "should we be doing less right now".
/// Every one of these signals is delivered by the system — nothing here polls.
@MainActor
final class PowerMonitor: ObservableObject {
    @Published private(set) var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published private(set) var thermalState = ProcessInfo.processInfo.thermalState
    @Published private(set) var onBattery = PowerMonitor.readOnBattery()

    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?

    init() {
        let center = NotificationCenter.default
        center.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled }
        }
        center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.thermalState = ProcessInfo.processInfo.thermalState }
        }
        center.addObserver(
            forName: .widgetMacPowerSourceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onBattery = PowerMonitor.readOnBattery() }
        }

        if let source = IOPSNotificationCreateRunLoopSource(powerSourceChanged, nil)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        NotificationCenter.default.removeObserver(self)
    }

    /// True when the machine is asking us to back off: decorative motion stops,
    /// polling intervals stretch, blur is dropped.
    var shouldConserve: Bool {
        lowPowerMode || onBattery || thermalState != .nominal
    }

    var reason: String {
        if lowPowerMode { return "Low Power Mode" }
        if thermalState != .nominal { return "Mac is warm" }
        if onBattery { return "On battery" }
        return "Plugged in"
    }

    private static func readOnBattery() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return false }
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue()
                as? [String: Any] else { continue }
            if let state = info[kIOPSPowerSourceStateKey] as? String {
                return state == kIOPSBatteryPowerValue
            }
        }
        return false
    }
}
