import Foundation
import ServiceManagement

/// Start-at-login, via the modern `SMAppService` registration.
///
/// A background utility that does not come back after a restart gets deleted,
/// so this matters more than it looks. `SMAppService` needs no helper bundle
/// and no deprecated `LSSharedFileList` poking — the app registers itself, and
/// macOS shows it in Login Items where the user can override it.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when the user has switched it off in System Settings; the app
    /// should not fight that.
    static var deniedByUser: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                guard SMAppService.mainApp.status != .enabled else { return true }
                try SMAppService.mainApp.register()
            } else {
                guard SMAppService.mainApp.status == .enabled else { return true }
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
