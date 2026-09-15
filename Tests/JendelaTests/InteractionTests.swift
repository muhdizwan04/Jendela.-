import AppKit
import XCTest
@testable import Jendela

final class InteractionTests: XCTestCase {
    func testHoverRequiresEntry() {
        var gate = NotchHoverGate()
        XCTAssertFalse(gate.canOpen)
        gate.update(inside: true)
        XCTAssertTrue(gate.canOpen)
    }

    func testCloseDoesNotReopenUntilPointerLeaves() {
        var gate = NotchHoverGate()
        gate.update(inside: true)
        gate.dismiss()
        gate.update(inside: true)
        XCTAssertFalse(gate.canOpen)
        gate.update(inside: false)
        XCTAssertFalse(gate.suppressed)
        gate.update(inside: true)
        XCTAssertTrue(gate.canOpen)
    }

    func testDismissWhileOutsideDoesNotBlockNextEntry() {
        var gate = NotchHoverGate()
        gate.dismiss()
        gate.update(inside: true)
        XCTAssertTrue(gate.canOpen)
    }

    @MainActor func testPanelAnchorsToPhysicalScreenTop() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("No GUI screen in this test runner") }
        for section in JendelaState.NotchSection.allCases {
            let size = NotchMetrics.expandedSize(for: section, clipboardCount: 5, size: .standard)
            let frame = NotchMetrics.topAlignedFrame(size, on: screen)
            XCTAssertEqual(frame.maxY, screen.frame.maxY, accuracy: 1)
            XCTAssertEqual(frame.midX, NotchMetrics.notch(on: screen).centreX, accuracy: 1)
        }
        XCTAssertEqual(NotchMetrics.compactSize(on: screen).height,
            (NotchMetrics.notch(on: screen).height + 4).rounded())
    }

    @MainActor func testMissingRuntimeIsActionable() async throws {
        let client = QuickChatClient(runtimeURL: nil)
        client.activate()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(client.connecting)
        XCTAssertTrue(client.error?.contains("Install") == true)
        client.shutdown()
    }

    @MainActor func testActualRuntimeHandshakeWithoutAccountOrPrompt() async throws {
        guard let runtime = QuickChatClient.runtime else { throw XCTSkip("Codex runtime not installed") }
        let store = FileManager.default.temporaryDirectory.appendingPathComponent("widgetmac-chat-test-\(UUID())")
        let client = QuickChatClient(runtimeURL: runtime, storageDirectory: store)
        defer { client.shutdown() }
        client.activate()
        for _ in 0..<150 {
            if !client.connecting { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(client.connecting, "Handshake should complete without polling the protocol")
        XCTAssertNil(client.error)
        XCTAssertFalse(client.signedIn)
        XCTAssertTrue(client.messages.isEmpty)
    }

    @MainActor func testQuickChatHistoryIsEncryptedAndRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jendela-history-test-\(UUID())", isDirectory: true)
        let conversation = QuickChatClient.Conversation(
            id: UUID(), title: "Private question", date: .now,
            messages: [.init(role: "user", text: "secret-value"),
                       .init(role: "assistant", text: "private-answer")]
        )
        XCTAssertTrue(QuickChatHistoryStore.save([conversation], in: directory))
        let raw = try Data(contentsOf: QuickChatHistoryStore.dataURL(in: directory))
        XCTAssertNil(raw.range(of: Data("secret-value".utf8)))
        XCTAssertEqual(QuickChatHistoryStore.load(in: directory).first?.title, "Private question")
        QuickChatHistoryStore.wipe(in: directory)
    }

    /// A deleted note used to come back: ordering its window out made it resign
    /// key, and the resign handler re-showed it. Guards against a duplicate.
    @MainActor func testDeletedNoteDoesNotComeBack() {
        let state = JendelaState()
        let coordinator = DesktopNoteCoordinator(state: state)
        _ = coordinator
        state.noteVisible = true
        state.addNote()
        state.addNote()
        XCTAssertEqual(state.notes.count, 3)

        let victim = state.notes[1].id
        state.deleteNote(victim)
        XCTAssertEqual(state.notes.count, 2)
        XCTAssertFalse(state.notes.contains { $0.id == victim })

        // Deleting everything still leaves somewhere to write.
        while state.notes.count > 1 { state.deleteNote(state.notes.last!.id) }
        state.deleteNote(state.notes[0].id)
        XCTAssertEqual(state.notes.count, 1)
    }
}
