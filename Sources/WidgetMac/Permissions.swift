import AppKit
import ApplicationServices
import AVFoundation

/// Opening the exact Privacy pane the user needs, rather than telling them to
/// go and find it. macOS will not grant these programmatically, so the most an
/// app can do is prompt where a prompt exists and deep-link where it does not.
enum Permissions {
    enum Kind: String, CaseIterable, Identifiable {
        case automation
        case accessibility
        case inputMonitoring

        var id: String { rawValue }

        var title: String {
            switch self {
            case .automation: "Automation"
            case .accessibility: "Accessibility"
            case .inputMonitoring: "Input Monitoring"
            }
        }

        var reason: String {
            switch self {
            case .automation: "Control playback in Music and Spotify"
            case .accessibility: "Send media keys to YouTube Music"
            case .inputMonitoring: "Global shortcuts for the hub"
            }
        }

        /// The anchor names are Apple's own and are what System Settings uses to
        /// select a pane; without one macOS opens the Privacy root instead.
        var settingsURL: URL? {
            let anchor: String
            switch self {
            case .automation: anchor = "Privacy_Automation"
            case .accessibility: anchor = "Privacy_Accessibility"
            case .inputMonitoring: anchor = "Privacy_ListenEvent"
            }
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
        }
    }

    static func isGranted(_ kind: Kind) -> Bool {
        switch kind {
        case .accessibility, .inputMonitoring: AXIsProcessTrusted()
        case .automation: true // only knowable by attempting an Apple Event
        }
    }

    /// Prompts where macOS offers one, then opens the pane so the switch is
    /// already in front of the user.
    static func request(_ kind: Kind) {
        switch kind {
        case .accessibility, .inputMonitoring:
            let options = ["AXTrustedCheckOptionPrompt": true]
            if AXIsProcessTrustedWithOptions(options as CFDictionary) { return }
        case .automation:
            break
        }
        openSettings(kind)
    }

    static func openSettings(_ kind: Kind) {
        guard let url = kind.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }
}
