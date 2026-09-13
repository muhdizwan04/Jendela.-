import AppKit
import CryptoKit
import Foundation

/// On-disk clipboard history.
///
/// Encrypted, because a clipboard is the single most sensitive file a utility
/// like this can keep: passwords that slipped past the concealed-type filter,
/// private keys, addresses, whole documents. The key lives in the login
/// Keychain, so the file is useless if copied off the machine, and it is never
/// written anywhere the user has to think about.
enum ClipboardStore {
    /// Plenty of scrollback without letting the file grow without bound.
    static let maxEntries = 200
    /// Images are the only entries big enough to matter; keep the recent ones.
    static let maxStoredImages = 25
    static let maxImageBytes = 8_000_000

    private static let keychainAccount = "clipboard-history-key"
    private static let keychainService = "com.jendela.desktop"

    private static var fileURL: URL {
        let base = SupportDirectory.root
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("clipboard.dat")
    }

    // MARK: - Key management

    /// Fetches the symmetric key, creating one on first run. Stored with
    /// `ThisDeviceOnly` so it is never carried to another Mac by a backup.
    /// Set when the Keychain refuses us, so history quietly stops persisting
    /// instead of blocking or throwing away the user's clipboard.
    nonisolated(unsafe) private(set) static var keychainUnavailable = false

    /// The encryption key, from the data-protection keychain.
    ///
    /// The legacy macOS keychain binds each item to the signing identity that
    /// created it, so a re-signed build can neither read the item nor replace
    /// it without putting a prompt in front of the user — which for a
    /// background app means history silently stops persisting.
    /// `kSecUseDataProtectionKeychain` uses the team-scoped keychain instead,
    /// which survives re-signing and never prompts.
    private static func key() -> SymmetricKey? {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecUseDataProtectionKeychain as String: true
        ]

        var read = base
        read[kSecReturnData as String] = true
        var item: CFTypeRef?
        if SecItemCopyMatching(read as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data {
            keychainUnavailable = false
            return SymmetricKey(data: data)
        }

        SecItemDelete(base as CFDictionary)
        let fresh = SymmetricKey(size: .bits256)
        var insert = base
        insert[kSecValueData as String] = fresh.withUnsafeBytes { Data($0) }
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if SecItemAdd(insert as CFDictionary, nil) == errSecSuccess {
            keychainUnavailable = false
            return fresh
        }

        // No keychain available to us at all (unsigned build, missing
        // entitlement). Fall back to a key file readable only by this user, so
        // history still persists; it is a weaker guarantee than the keychain
        // and is the reason `keychainUnavailable` is surfaced.
        keychainUnavailable = true
        return fileKey()
    }

    private static var keyFileURL: URL { SupportDirectory.root.appendingPathComponent("clipboard.key") }

    private static func fileKey() -> SymmetricKey? {
        let manager = FileManager.default
        if let data = try? Data(contentsOf: keyFileURL), data.count == 32 {
            return SymmetricKey(data: data)
        }
        let fresh = SymmetricKey(size: .bits256)
        let raw = fresh.withUnsafeBytes { Data($0) }
        guard (try? raw.write(to: keyFileURL, options: [.atomic, .completeFileProtection])) != nil
        else { return nil }
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFileURL.path)
        return fresh
    }

    // MARK: - Codable form

    private struct Stored: Codable {
        var kind: String
        var title: String
        var subtitle: String
        var data: Data?
        var type: String?
        var pinned: Bool
        var date: Date
    }

    // MARK: - Load / save

    /// Loads off the main thread.
    ///
    /// Keychain reads can block: if the item's ACL no longer matches the running
    /// binary — which happens whenever the app is re-signed — macOS wants to
    /// prompt, and a synchronous call during start-up hangs the whole app before
    /// it can draw anything. Nothing here is needed to show the first frame, so
    /// it arrives when it arrives.
    static func loadAsync(_ completion: @escaping @MainActor ([ClipboardEntry]) -> Void) {
        queue.async {
            let entries = load()
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(entries) } }
        }
    }

    static func load() -> [ClipboardEntry] {
        guard let key = key(),
              let blob = try? Data(contentsOf: fileURL),
              let box = try? AES.GCM.SealedBox(combined: blob),
              let plain = try? AES.GCM.open(box, using: key),
              let rows = try? JSONDecoder().decode([Stored].self, from: plain)
        else { return [] }

        return rows.compactMap { row in
            guard let kind = ClipboardEntry.Kind(rawValue: row.kind) else { return nil }
            return ClipboardEntry(
                kind: kind,
                title: row.title,
                subtitle: row.subtitle,
                data: row.data,
                pasteboardType: row.type.map(NSPasteboard.PasteboardType.init(rawValue:)),
                pinned: row.pinned
            )
        }
    }

    /// Writes on a serial queue: two saves in quick succession on a concurrent
    /// queue can land out of order and leave an older history as the final
    /// state.
    private static let queue = DispatchQueue(label: "com.jendela.clipboard.store")

    static func save(_ entries: [ClipboardEntry]) {
        var imagesKept = 0
        let rows: [Stored] = entries.prefix(maxEntries).map { entry in
            var payload = entry.data
            if entry.kind == .image {
                imagesKept += 1
                // Older images are remembered as entries but without their
                // bytes, so the file cannot grow without limit.
                if imagesKept > maxStoredImages || (payload?.count ?? 0) > maxImageBytes {
                    payload = nil
                }
            }
            return Stored(
                kind: entry.kind.rawValue,
                title: entry.title,
                subtitle: entry.subtitle,
                data: payload,
                type: entry.pasteboardType?.rawValue,
                pinned: entry.pinned,
                date: .now
            )
        }

        let url = fileURL
        queue.async {
            guard let key = key(),
                  let plain = try? JSONEncoder().encode(rows),
                  let box = try? AES.GCM.seal(plain, using: key),
                  let blob = box.combined
            else { return }
            try? blob.write(to: url, options: [.atomic, .completeFileProtection])
        }
    }

    /// Blocks until pending writes land. Called on quit.
    static func flush() { queue.sync {} }

    static func wipe() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
