import CryptoKit
import Foundation
import Security

/// A device-local encryption key. The preferred key lives in the data-
/// protection Keychain and never migrates to another Mac. Development builds
/// that cannot use that Keychain fall back to a 0600 file so private data does
/// not silently stop persisting.
enum DeviceSecret {
    struct Resolution {
        let key: SymmetricKey
        let protectedByKeychain: Bool
    }

    /// What reading the Keychain item means for the key.
    enum ReadOutcome: Equatable {
        /// A well-formed key is there.
        case use
        /// There is no usable key: make one.
        case create
        /// The Keychain is locked right now. The key may well exist.
        case unavailable
        /// This process cannot use the data-protection Keychain at all.
        case fileFallback
    }

    /// Decides from the read alone.
    ///
    /// Any failed read used to fall straight through to deleting the item and
    /// minting a new key. For a missing item that is right. For a Keychain that
    /// is only locked at this moment it destroyed the one key the existing
    /// encrypted clipboard and chat history can be opened with, leaving both
    /// permanently unreadable. Only a missing or malformed item is replaced now.
    static func outcome(forReadStatus status: OSStatus, keyLength: Int?) -> ReadOutcome {
        switch status {
        case errSecSuccess:
            return keyLength == 32 ? .use : .create
        case errSecItemNotFound:
            return .create
        case errSecInteractionNotAllowed:
            return .unavailable
        default:
            // Unsigned and unentitled processes land here. They could never
            // delete the item either, so the file is what they already used.
            return .fileFallback
        }
    }

    private static let service = "com.jendela.desktop"

    static func resolve(account: String, fallbackFileName: String) -> Resolution? {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
        var read = base
        read[kSecReturnData as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &item)
        let data = item as? Data

        switch outcome(forReadStatus: status, keyLength: data?.count) {
        case .use:
            guard let data else { return nil }
            return Resolution(key: SymmetricKey(data: data), protectedByKeychain: true)
        case .unavailable:
            return nil
        case .fileFallback:
            return fileKey(named: fallbackFileName)
        case .create:
            SecItemDelete(base as CFDictionary)
            let fresh = SymmetricKey(size: .bits256)
            var insert = base
            insert[kSecValueData as String] = fresh.withUnsafeBytes { Data($0) }
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            if SecItemAdd(insert as CFDictionary, nil) == errSecSuccess {
                return Resolution(key: fresh, protectedByKeychain: true)
            }
            return fileKey(named: fallbackFileName)
        }
    }

    private static func fileKey(named name: String) -> Resolution? {
        let url = SupportDirectory.root.appendingPathComponent(name)
        if let data = try? Data(contentsOf: url), data.count == 32 {
            return Resolution(key: SymmetricKey(data: data), protectedByKeychain: false)
        }
        let fresh = SymmetricKey(size: .bits256)
        let raw = fresh.withUnsafeBytes { Data($0) }
        guard (try? raw.write(to: url, options: [.atomic, .completeFileProtection])) != nil else { return nil }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return Resolution(key: fresh, protectedByKeychain: false)
    }
}
