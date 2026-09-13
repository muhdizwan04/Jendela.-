import AppKit
import SwiftUI

/// Click, then press a combination. A local monitor is enough — the field only
/// listens while it is recording, so the app never observes keys otherwise.
struct HotKeyRecorder: View {
    let action: HotKeyAction
    @ObservedObject var state: JendelaState
    @State private var recording = false
    @State private var monitor: Any?
    /// Set when the last combination pressed was rejected as unsafe.
    @State private var unsafeAttempt = false

    private var binding: HotKeyBinding { state.hotKeys[action] ?? .none }
    private var rejected: Bool { state.rejectedHotKeys.contains(action) }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Press keys…" : binding.display)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 108, height: 26)
                    .background(
                        recording ? state.appliedTheme.accentColor.opacity(0.25)
                                  : Color.white.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 7)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(recording ? state.appliedTheme.accentColor
                                              : (rejected ? Color.orange : .clear))
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if binding.enabled, binding.keyCode != 0 {
                Button {
                    state.setHotKey(action, to: .none)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
                .help("Clear this shortcut")
            }

            if unsafeAttempt {
                Text("Add ⇧, ⌥ or ⌃")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .help("A system-wide shortcut needs two modifiers, or it takes the combination away from every app")
            } else if rejected {
                Text("In use")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .help("Another app already owns this combination")
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        unsafeAttempt = false
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard event.type == .keyDown else { return event }
            if event.keyCode == 53 { stop(); return nil }   // Esc cancels

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .intersection([.command, .option, .control, .shift])

            // Keep listening rather than storing something that would take the
            // combination away from the whole Mac. ⌘V recorded here stopped
            // paste working in every app.
            let candidate = HotKeyBinding(keyCode: UInt32(event.keyCode),
                                          modifiers: flags.rawValue, enabled: true)
            guard candidate.isSafeForGlobalUse else {
                unsafeAttempt = true
                return nil
            }
            unsafeAttempt = false

            state.setHotKey(action, to: HotKeyBinding(
                keyCode: UInt32(event.keyCode),
                modifiers: flags.rawValue,
                enabled: true
            ))
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        unsafeAttempt = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
