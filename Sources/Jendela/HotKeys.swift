import AppKit
import Carbon.HIToolbox

/// A key combination, stored in a form that survives a settings file.
struct HotKeyBinding: Codable, Equatable {
    var keyCode: UInt32
    /// `NSEvent.ModifierFlags` raw value, masked to the device-independent bits.
    var modifiers: UInt
    var enabled: Bool

    static let none = HotKeyBinding(keyCode: 0, modifiers: 0, enabled: false)

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// A combination is only usable if it carries a modifier — otherwise it
    /// would swallow an ordinary keystroke system-wide.
    var isValid: Bool {
        enabled && keyCode != 0 && isSafeForGlobalUse
    }

    /// Whether this is safe to register system-wide.
    ///
    /// These are Carbon hot keys, which take the combination away from *every*
    /// app on the Mac. A single modifier is never enough: ⌘V bound here stops
    /// paste working anywhere, and ⇧V or ⌥V swallow ordinary typing. Requiring
    /// two modifiers keeps a global shortcut clear of everything macOS and
    /// other apps already own — which is what the defaults do.
    var isSafeForGlobalUse: Bool {
        let modifiers = flags.intersection([.command, .option, .control, .shift])
        return modifiers.rawValue.nonzeroBitCount >= 2
    }

    var display: String {
        guard keyCode != 0 else { return "Not set" }
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + HotKeyBinding.name(for: keyCode)
    }

    static func name(for keyCode: UInt32) -> String {
        let named: [UInt32: String] = [
            49: "Space", 36: "Return", 48: "Tab", 53: "Esc", 51: "Delete",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
        ]
        if let name = named[keyCode] { return name }

        // Ask the current layout what this key produces, so a French or Malay
        // keyboard shows the character the user actually presses.
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "Key \(keyCode)" }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data

        var dead: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                &dead, chars.count, &length, &chars
            )
        }
        guard status == noErr, length > 0 else { return "Key \(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

/// What a hot key can do.
enum HotKeyAction: String, CaseIterable, Identifiable, Codable {
    case toggleHub, clipboard, notes, ai, shelf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggleHub: "Open the hub"
        case .clipboard: "Open clipboard"
        case .notes: "Open notes"
        case .ai: "Ask AI"
        case .shelf: "Open shelf"
        }
    }

    /// Defaults avoid combinations macOS already owns.
    var defaultBinding: HotKeyBinding {
        let command = NSEvent.ModifierFlags.command.rawValue
        let shift = NSEvent.ModifierFlags.shift.rawValue
        switch self {
        case .toggleHub: return .init(keyCode: 49, modifiers: command | shift, enabled: true)   // ⌘⇧Space
        case .clipboard: return .init(keyCode: 9, modifiers: command | shift, enabled: true)    // ⌘⇧V
        case .notes:     return .init(keyCode: 45, modifiers: command | shift, enabled: true)   // ⌘⇧N
        case .ai:        return .init(keyCode: 0, modifiers: command | shift, enabled: false)
        case .shelf:     return .init(keyCode: 0, modifiers: command | shift, enabled: false)
        }
    }
}

/// System-wide hot keys.
///
/// Carbon's `RegisterEventHotKey` is used rather than a global `NSEvent`
/// monitor because it needs no Accessibility permission: the app should not ask
/// to observe every keystroke on the machine just to own three shortcuts.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var installed = false

    private init() {}

    /// Replaces every registration with the given set. Returns the actions that
    /// could not be registered, usually because another app already owns the
    /// combination.
    @discardableResult
    func apply(_ bindings: [HotKeyAction: HotKeyBinding], perform: @escaping (HotKeyAction) -> Void) -> [HotKeyAction] {
        installHandlerIfNeeded()
        unregisterAll()

        var failed: [HotKeyAction] = []
        for (index, action) in HotKeyAction.allCases.enumerated() {
            guard let binding = bindings[action], binding.isValid else { continue }
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x4A4E_444C), id: id)   // 'JNDL'
            let status = RegisterEventHotKey(
                binding.keyCode,
                HotKeyCenter.carbonModifiers(binding.flags),
                hotKeyID,
                GetEventDispatcherTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                refs[id] = ref
                actions[id] = { perform(action) }
            } else {
                failed.append(action)
            }
        }
        return failed
    }

    func unregisterAll() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
        actions.removeAll()
    }

    fileprivate func fire(_ id: UInt32) { actions[id]?() }

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), hotKeyHandler, 1, &spec, nil, nil)
    }
}

/// Carbon hands back a C callback with no context, so this bounces to the
/// shared centre. Hot-key events are delivered on the main thread.
private func hotKeyHandler(
    _ next: EventHandlerCallRef?,
    _ event: EventRef?,
    _ context: UnsafeMutableRawPointer?
) -> OSStatus {
    var id = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &id
    )
    guard status == noErr else { return status }
    MainActor.assumeIsolated { HotKeyCenter.shared.fire(id.id) }
    return noErr
}
