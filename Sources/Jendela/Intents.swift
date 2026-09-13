import AppIntents
import AppKit

/// Shortcuts actions.
///
/// Small, concrete verbs rather than one catch-all: each does a single thing so
/// they compose in a Shortcut without needing parameters explained.
@MainActor
private func app() -> JendelaState? {
    (NSApp.delegate as? JendelaAppDelegate)?.state
}

struct OpenHubIntent: AppIntent {
    static let title: LocalizedStringResource = "Open the hub"
    static let description = IntentDescription("Opens Jendela's notch hub.")
    static let openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        app()?.openNotch()
        return .result()
    }
}

struct OpenClipboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Show clipboard history"
    static let description = IntentDescription("Opens the hub on the clipboard.")
    static let openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        app()?.openNotch(.clipboard)
        return .result()
    }
}

struct LatestClipboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Get latest copied text"
    static let description = IntentDescription("Returns the most recent text from the clipboard history.")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let text = app()?.clipboardItems.first(where: { $0.kind == .text })?.title ?? ""
        return .result(value: text)
    }
}

struct NewNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "New note"
    static let description = IntentDescription("Creates a note on the desktop and brings it forward.")
    static let openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        app()?.addNote()
        return .result()
    }
}

struct ShowShelfIntent: AppIntent {
    static let title: LocalizedStringResource = "Show the shelf"
    static let description = IntentDescription("Opens the hub on the file shelf.")
    static let openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        app()?.openNotch(.shelf)
        return .result()
    }
}

struct StartFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Start or stop focus timer"
    static let description = IntentDescription("Toggles Jendela's focus timer.")

    @MainActor func perform() async throws -> some IntentResult {
        app()?.toggleFocus()
        return .result()
    }
}

struct JendelaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenClipboardIntent(),
            phrases: ["Show \(.applicationName) clipboard"],
            shortTitle: "Clipboard",
            systemImageName: "doc.on.clipboard"
        )
        AppShortcut(
            intent: NewNoteIntent(),
            phrases: ["New \(.applicationName) note"],
            shortTitle: "New note",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: OpenHubIntent(),
            phrases: ["Open \(.applicationName)"],
            shortTitle: "Open hub",
            systemImageName: "rectangle.topthird.inset.filled"
        )
    }
}
