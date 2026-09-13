import AppKit
import Combine
import SwiftUI

/// Native chat UI over the supported Codex app-server protocol. The runtime is
/// started on demand with a separate auth store; no browser or server at launch.
@MainActor
final class QuickChatClient: ObservableObject {
    struct Message: Identifiable {
        let id: UUID
        let role: String
        var text: String
        init(role: String, text: String) { id = UUID(); self.role = role; self.text = text }
    }
    /// A finished conversation, kept so you can look back at an answer.
    ///
    /// Deliberately shallow: the last few conversations only. Codex threads are
    /// started `ephemeral`, so nothing can be resumed server-side — reopening
    /// one loads the transcript for reading, and carrying on starts a fresh
    /// thread seeded with it as context.
    struct Conversation: Identifiable, Codable {
        var id: UUID
        var title: String
        var date: Date
        var messages: [Stored]

        struct Stored: Codable {
            var role: String
            var text: String
        }
    }

    static let historyLimit = 8

    @Published private(set) var history: [Conversation] = []
    @Published var draft = ""
    @Published private(set) var messages: [Message] = []
    @Published private(set) var signedIn = false
    @Published private(set) var busy = false
    @Published private(set) var connecting = false
    @Published private(set) var loginPending = false
    @Published private(set) var status = "Sign in with ChatGPT to ask here."
    @Published private(set) var error: String?
    @Published private(set) var modelName = ""

    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var errorOutput: FileHandle?
    private var errorBuffer = Data()
    private var buffer = Data()
    private var nextID = 0
    private var replies: [Int: CheckedContinuation<Data, Error>] = [:]
    private var initialized = false
    private var generation = UUID()
    private var threadID: String?
    private var turnID: String?
    private var loginID: String?
    private var model: String?
    private var effort = "low"
    private var idleWork: DispatchWorkItem?
    private var visible = false
    private var operation: Task<Void, Never>?
    private let runtimeURL: URL?
    private let storageDirectory: URL?

    init(runtimeURL: URL? = QuickChatClient.runtime, storageDirectory: URL? = nil) {
        self.runtimeURL = runtimeURL
        self.storageDirectory = storageDirectory
    }

    nonisolated static var runtime: URL? {
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex"
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map(URL.init(fileURLWithPath:))
    }

    private var directory: URL {
        if let storageDirectory { return storageDirectory }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Jendela/QuickChat", isDirectory: true)
    }

    func activate() {
        visible = true
        idleWork?.cancel()
        if history.isEmpty { loadHistory() }
        guard !initialized, !connecting else { return }
        connecting = true
        operation = Task {
            do { try await connect(); try await readAccount() }
            catch { self.error = error.localizedDescription }
            connecting = false
            scheduleIdleShutdown()
        }
    }

    func deactivate() { visible = false; scheduleIdleShutdown() }

    private func connect() async throws {
        if initialized { return }
        guard let runtime = runtimeURL else {
            throw failure("Install the Codex CLI or ChatGPT desktop app to enable quick chat.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let accountHome = directory.appendingPathComponent("Account", isDirectory: true)
        try FileManager.default.createDirectory(at: accountHome, withIntermediateDirectories: true)
        let workspace = directory.appendingPathComponent("Empty", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let proc = Process()
        proc.executableURL = runtime
        proc.currentDirectoryURL = workspace
        proc.arguments = ["app-server", "--stdio", "-c", "features.shell_tool=false",
            "-c", "features.shell_snapshot=false", "-c", "features.multi_agent=false",
            "-c", "web_search=\"disabled\"", "-c", "approval_policy=\"never\""]
        var environment = ProcessInfo.processInfo.environment
        // Use the runtime's supported home setting for app-owned sign-in. Never
        // inspect or copy the host Codex app's credentials or config.
        environment["CODEX_HOME"] = accountHome.path
        proc.environment = environment
        let stdin = Pipe(), stdout = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        let stderr = Pipe()
        proc.standardError = stderr
        let token = UUID()
        generation = token
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            guard !bytes.isEmpty else { handle.readabilityHandler = nil; return }
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.receive(bytes)
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            guard !bytes.isEmpty else { handle.readabilityHandler = nil; return }
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.errorBuffer.append(bytes)
                if self.errorBuffer.count > 4_096 { self.errorBuffer.removeFirst(self.errorBuffer.count - 4_096) }
            }
        }
        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                let details = String(data: self.errorBuffer, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                self.failPending(details.isEmpty ? "Quick chat disconnected. Reopen AI to reconnect." : details)
                self.initialized = false
                self.process = nil
                self.input = nil; self.output = nil; self.errorOutput = nil; self.threadID = nil; self.turnID = nil
                self.busy = false
                self.connecting = false
            }
        }
        try proc.run()
        process = proc
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        errorOutput = stderr.fileHandleForReading
        _ = try await request("initialize", ["clientInfo": ["name": "widgetmac", "title": "Jendela Quick Chat", "version": "0.3.0"]])
        try write(["method": "initialized"])
        initialized = true
    }

    private func readAccount() async throws {
        let result = try await request("account/read", ["refreshToken": false])
        let account = result["account"] as? [String: Any]
        signedIn = account?["type"] as? String == "chatgpt"
        status = signedIn ? "ChatGPT connected · via Codex" : "Sign in with ChatGPT to ask here."
        if signedIn {
            let catalog = try await request("model/list", ["includeHidden": false, "limit": 100])
            let models = catalog["data"] as? [[String: Any]] ?? []
            if let selected = models.first(where: { $0["isDefault"] as? Bool == true }) ?? models.first {
                model = selected["model"] as? String
                modelName = selected["displayName"] as? String ?? model ?? ""
                let efforts = selected["supportedReasoningEfforts"] as? [[String: Any]] ?? []
                effort = efforts.contains(where: { $0["reasoningEffort"] as? String == "low" }) ? "low" : (selected["defaultReasoningEffort"] as? String ?? "medium")
            }
        }
    }

    func signIn() {
        guard !connecting, !loginPending else { return }
        error = nil
        connecting = true
        operation = Task {
            do {
                try await connect()
                let result = try await request("account/login/start", ["type": "chatgpt"])
                guard let link = result["authUrl"] as? String, let url = URL(string: link),
                      url.scheme == "https" else { throw failure("The sign-in link was unavailable. Try again.") }
                loginID = result["loginId"] as? String
                loginPending = true
                status = "Finish signing in in your browser."
                NSWorkspace.shared.open(url)
            } catch { self.error = error.localizedDescription }
            connecting = false
        }
    }

    func cancelLogin() {
        operation = Task {
            if let loginID { _ = try? await request("account/login/cancel", ["loginId": loginID]) }
            loginPending = false; loginID = nil
            status = "Sign-in cancelled."
            scheduleIdleShutdown()
        }
    }

    func signOut() {
        guard !busy, !connecting else { return }
        connecting = true
        operation = Task {
            do {
                try await connect()
                _ = try await request("account/logout", [:])
                signedIn = false; messages = []; threadID = nil
                status = "Signed out of Jendela."
            } catch { self.error = error.localizedDescription }
            connecting = false
        }
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy, !connecting, signedIn else { return }
        idleWork?.cancel()
        draft = ""; error = nil; busy = true
        let history = messages.suffix(12).map { "\($0.role): \($0.text)" }.joined(separator: "\n\n")
        messages.append(Message(role: "You", text: text))
        messages.append(Message(role: "AI", text: ""))
        status = "Thinking…"
        operation = Task {
            do {
                try await connect()
                var prompt = text
                if threadID == nil {
                    var params: [String: Any] = ["cwd": directory.appendingPathComponent("Empty").path,
                        "approvalPolicy": "never", "sandbox": "read-only", "ephemeral": true,
                        "baseInstructions": "You are the quick chat assistant in Jendela. Answer conversationally and concisely. This is a text-only conversation. Do not use tools, run commands, inspect files, or act on the computer. Ask for pasted context if needed."]
                    if let model { params["model"] = model }
                    let result = try await request("thread/start", params)
                    threadID = (result["thread"] as? [String: Any])?["id"] as? String
                    if !history.isEmpty { prompt = "Previous conversation:\n\(history)\n\nNew message:\n\(text)" }
                }
                guard let threadID else { throw failure("Could not start a chat. Try again.") }
                let result = try await request("turn/start", ["threadId": threadID,
                    "input": [["type": "text", "text": prompt]], "effort": effort,
                    // Note the casing difference, which is not a typo: the
                    // runtime spells this field camelCase (`readOnly`) while
                    // `thread/start` above spells its own kebab-case
                    // (`read-only`). Each rejects the other's spelling.
                    // `readOnly` takes no `access` any more — the runtime
                    // replies "readOnly.access is no longer supported; use
                    // permissionProfile". This chat never touches the
                    // filesystem, so plain `readOnly` is what it wants.
                    "sandboxPolicy": ["type": "readOnly"]])
                turnID = (result["turn"] as? [String: Any])?["id"] as? String
            } catch {
                self.error = error.localizedDescription
                busy = false; status = "Could not send. Your question is kept below."
                draft = text
                if messages.last?.text.isEmpty == true { messages.removeLast() }
                scheduleIdleShutdown()
            }
        }
    }

    func stop() {
        operation?.cancel()
        // Closing this app-owned process is immediate even during turn setup.
        shutdown()
        busy = false
        status = "Stopped"
    }

    func newChat() {
        guard !busy else { return }
        archiveCurrent()
        messages = []; threadID = nil; error = nil
    }

    // MARK: - History

    private var historyURL: URL { directory.appendingPathComponent("history.json") }

    /// Serial on purpose. On a concurrent queue two saves in quick succession
    /// can finish out of order and leave an older snapshot as the final state —
    /// archiving several chats in a row lost the newest ones.
    private static let historyQueue = DispatchQueue(label: "com.widgetmac.quickchat.history")

    func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL),
              let saved = try? JSONDecoder().decode([Conversation].self, from: data)
        else { return }
        history = saved
    }

    private func saveHistory() {
        let snapshot = history
        let url = historyURL
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Self.historyQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Files the current exchange away, if there is one worth keeping.
    func archiveCurrent() {
        guard messages.contains(where: { $0.role == "assistant" }),
              let first = messages.first(where: { $0.role == "user" })
        else { return }

        let title = first.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        let entry = Conversation(
            id: UUID(),
            title: title.count > 60 ? String(title.prefix(60)) + "…" : title,
            date: .now,
            messages: messages.map { .init(role: $0.role, text: $0.text) }
        )
        history.insert(entry, at: 0)
        if history.count > Self.historyLimit { history = Array(history.prefix(Self.historyLimit)) }
        saveHistory()
    }

    /// Loads a past conversation back into view. The thread is cleared, so the
    /// next question starts fresh with this transcript as context.
    func open(_ conversation: Conversation) {
        guard !busy else { return }
        archiveCurrent()
        messages = conversation.messages.map { Message(role: $0.role, text: $0.text) }
        threadID = nil
        error = nil
    }

    func clearHistory() {
        history = []
        saveHistory()
    }

    private func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        try Task.checkCancellation()
        nextID += 1
        let id = nextID
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            replies[id] = continuation
            do { try write(["id": id, "method": method, "params": params]) }
            catch { replies.removeValue(forKey: id)?.resume(throwing: error) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
                guard let self else { return }
                self.replies.removeValue(forKey: id)?.resume(throwing:
                    self.failure("Quick chat timed out. Check your connection and retry."))
            }
        }
        try Task.checkCancellation()
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    private func write(_ value: [String: Any]) throws {
        guard let input else { throw failure("Quick chat is disconnected.") }
        var data = try JSONSerialization.data(withJSONObject: value)
        data.append(10)
        try input.write(contentsOf: data)
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let id = event["id"] as? Int, event["method"] == nil {
                guard let continuation = replies.removeValue(forKey: id) else { continue }
                if let error = event["error"] as? [String: Any] {
                    continuation.resume(throwing: failure(error["message"] as? String ?? "Quick chat request failed."))
                } else {
                    do { continuation.resume(returning: try JSONSerialization.data(withJSONObject: event["result"] as? [String: Any] ?? [:])) }
                    catch { continuation.resume(throwing: error) }
                }
                continue
            }
            if let id = event["id"] { // Never approve tool actions from a quick chat.
                try? write(["id": id, "error": ["code": -32601, "message": "Jendela quick chat does not execute tools."]])
                continue
            }
            let params = event["params"] as? [String: Any] ?? [:]
            switch event["method"] as? String {
            case "account/login/completed":
                loginPending = false; loginID = nil
                if params["success"] as? Bool == true {
                    Task { do { try await readAccount() } catch { self.error = error.localizedDescription } }
                } else { error = params["error"] as? String ?? "Sign-in did not finish." }
            case "item/agentMessage/delta":
                guard params["threadId"] as? String == threadID,
                      let delta = params["delta"] as? String, !messages.isEmpty else { continue }
                messages[messages.count - 1].text += delta
                status = "Replying…"
            case "item/completed":
                guard params["threadId"] as? String == threadID,
                      let item = params["item"] as? [String: Any], item["type"] as? String == "agentMessage",
                      let text = item["text"] as? String, !messages.isEmpty else { continue }
                messages[messages.count - 1].text = text
            case "turn/completed":
                guard params["threadId"] as? String == threadID else { continue }
                let turn = params["turn"] as? [String: Any] ?? [:]
                if let problem = turn["error"] as? [String: Any] { error = problem["message"] as? String }
                busy = false; turnID = nil
                status = error == nil ? "ChatGPT connected · via Codex" : "Reply failed"
                scheduleIdleShutdown()
            case "error":
                if let problem = params["error"] as? [String: Any] { error = problem["message"] as? String }
            default: break
            }
        }
    }

    private func scheduleIdleShutdown() {
        idleWork?.cancel()
        guard !visible, !busy, !loginPending else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.visible, !self.busy, !self.loginPending else { return }
            self.shutdown()
        }
        idleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)
    }

    func shutdown() {
        archiveCurrent()
        // Quitting must not outrun the last write.
        Self.historyQueue.sync {}
        generation = UUID()
        output?.readabilityHandler = nil
        errorOutput?.readabilityHandler = nil
        try? input?.close()
        if let process, process.isRunning { process.terminate() }
        process = nil; input = nil; output = nil; errorOutput = nil; initialized = false
        threadID = nil; turnID = nil; buffer = Data()
        loginPending = false; loginID = nil
        failPending("Quick chat stopped.")
    }

    private func failPending(_ message: String) {
        let pending = Array(replies.values); replies.removeAll()
        for continuation in pending { continuation.resume(throwing: failure(message)) }
    }
    private func failure(_ message: String) -> NSError {
        NSError(domain: "Jendela.QuickChat", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

struct QuickChatView: View {
    @ObservedObject var client: QuickChatClient
    /// Reported upward so the hub stays open while the field has focus, instead
    /// of pinning the whole tab open forever. Declared after `client` so the
    /// memberwise init keeps `client` first and the trailing closure binds here.
    var onFocusChange: ((Bool) -> Void)?
    /// Every keystroke, so the hub can tell typing apart from a focused field
    /// that has been abandoned.
    var onActivity: (() -> Void)?
    @FocusState private var inputFocused: Bool
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Quick AI").font(.headline)
                    Text(client.status).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                if client.signedIn {
                    Button("New chat") { client.newChat() }.disabled(client.busy)
                    if !client.history.isEmpty {
                        Menu {
                            ForEach(client.history) { past in
                                Button {
                                    client.open(past)
                                } label: {
                                    Text("\(past.title)  ·  \(past.date, format: .relative(presentation: .numeric))")
                                }
                            }
                            Divider()
                            Button("Clear history", role: .destructive) { client.clearHistory() }
                        } label: {
                            Image(systemName: "clock.arrow.circlepath").frame(width: 28, height: 28)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Recent conversations")
                        .disabled(client.busy)
                    }
                    Menu {
                        Text(client.modelName)
                        Button("Sign out of Jendela") { client.signOut() }
                        Button("Open ChatGPT") { NSWorkspace.shared.open(URL(string: "https://chatgpt.com")!) }
                    } label: { Image(systemName: "ellipsis.circle").frame(width: 28, height: 28) }
                    .menuStyle(.borderlessButton).fixedSize()
                }
            }
            if !client.signedIn {
                Spacer()
                Image(systemName: "sparkle.magnifyingglass").font(.system(size: 30)).foregroundStyle(.mint)
                Text("Ask right from your notch").font(.headline)
                Text("Sign in once in your browser. Answers stream here using your ChatGPT account’s Codex access.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if client.loginPending {
                    Button("Cancel sign-in") { client.cancelLogin() }
                } else {
                    Button(client.connecting ? "Connecting…" : "Sign in with ChatGPT") { client.signIn() }
                        .buttonStyle(.borderedProminent).tint(.mint).disabled(client.connecting)
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if client.messages.isEmpty {
                                Text("Ask a question, rewrite a sentence, or paste something to summarize.")
                                    .font(.caption).foregroundStyle(.secondary).padding(.top, 12)
                            }
                            ForEach(client.messages) { message in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(message.role).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                        Spacer()
                                        if !message.text.isEmpty {
                                            Button {
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString(message.text, forType: .string)
                                            } label: { Image(systemName: "doc.on.doc").frame(width: 24, height: 24) }
                                            .accessibilityLabel("Copy answer").buttonStyle(.plain)
                                        }
                                    }
                                    Text(message.text.isEmpty ? "Thinking…" : message.text)
                                        .font(.system(size: 12)).textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                            }
                            Color.clear.frame(height: 1).id("end")
                        }
                    }
                    .onChange(of: client.messages.last?.text) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
                }
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Ask anything…", text: $client.draft, axis: .vertical)
                        .lineLimit(1...3).textFieldStyle(.plain).font(.system(size: 12))
                        .focused($inputFocused)
                        .onChange(of: inputFocused) { _, focused in onFocusChange?(focused) }
                        .onChange(of: client.draft) { _, _ in onActivity?() }
                        .onSubmit { client.send() }
                        .padding(10).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    Button { client.busy ? client.stop() : client.send() } label: {
                        Image(systemName: client.busy ? "stop.fill" : "arrow.up")
                            .frame(width: 34, height: 34).contentShape(Rectangle())
                    }.buttonStyle(.borderedProminent).tint(.mint)
                        .accessibilityLabel(client.busy ? "Stop reply" : "Send question")
                        .disabled(!client.busy && (client.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || client.connecting))
                }
            }
            if let error = client.error {
                Text(error).font(.caption2).foregroundStyle(.orange).lineLimit(3).textSelection(.enabled)
            }
        }
        .onAppear { client.activate() }
        .onDisappear { client.deactivate() }
    }
}
