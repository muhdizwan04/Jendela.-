import AppKit
import ApplicationServices

/// Sends the hardware play/next/previous keys.
///
/// Music and Spotify are driven with Apple Events, which are precise and need
/// no special permission. YouTube Music has no scripting interface at all — it
/// is a web page — so the only way to control it is the same media keys the
/// keyboard sends, which every player listens for, browsers included.
///
/// Posting synthetic events requires Accessibility permission, so this reports
/// whether it is allowed rather than failing silently.
enum MediaKey: Int32 {
    case playPause = 16   // NX_KEYTYPE_PLAY
    case next = 17        // NX_KEYTYPE_NEXT
    case previous = 18    // NX_KEYTYPE_PREVIOUS

    static var isAllowed: Bool { AXIsProcessTrusted() }

    /// Opens the Accessibility pane with the standard system prompt.
    static func requestAccess() {
        // The constant is an imported global var, so reference it by name.
        let options = ["AXTrustedCheckOptionPrompt": true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func send() {
        guard Self.isAllowed else { return }
        post(down: true)
        post(down: false)
    }

    private func post(down: Bool) {
        let state = down ? 0xA : 0xB
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int((rawValue << 16) | Int32(state << 8)),
            data2: -1
        ) else { return }
        event.cgEvent?.post(tap: .cghidEventTap)
    }
}
