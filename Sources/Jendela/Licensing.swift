import CryptoKit
import Foundation

/// Licence state, verified on this Mac with no server involved.
///
/// A licence is a signed payload: the app carries only the public key, so it can
/// check a key is genuine but can never mint one. That means no activation
/// server to run, no phone-home, and the app keeps working on a plane or in ten
/// years if the company is gone — which is the only honest way to sell a
/// lifetime licence.
@MainActor
final class Licensing: ObservableObject {
    /// The matching private key is held by the seller and never ships.
    nonisolated private static let publicKeyBase64 = "ftUfWMYrQxdmziN9wWF+r3BovOuxkkE397fF1kSdRWQ="

    static let trialDays = 14
    private static let service = "com.jendela.desktop"
    private static let licenceAccount = "licence-key"
    private static let trialAccount = "trial-start"

    struct Licence: Equatable {
        var email: String
        var id: String
        var issued: Date
        var expires: Date?

        var isLifetime: Bool { expires == nil }
        var isExpired: Bool {
            guard let expires else { return false }
            return expires < Date()
        }
    }

    enum Status: Equatable {
        case licensed(Licence)
        case trial(daysLeft: Int)
        case expired

        var isPro: Bool {
            switch self {
            case .licensed(let licence): return !licence.isExpired
            case .trial: return true
            case .expired: return false
            }
        }
    }

    @Published private(set) var status: Status = .expired
    @Published private(set) var lastError: String?

    init() { refresh() }

    // MARK: - Public surface

    var isPro: Bool { status.isPro }

    var summary: String {
        switch status {
        case .licensed(let licence):
            return licence.isLifetime
                ? "Licensed to \(licence.email)"
                : "Licensed to \(licence.email) until \(licence.expires!.formatted(date: .abbreviated, time: .omitted))"
        case .trial(let days):
            return days == 1 ? "Trial · 1 day left" : "Trial · \(days) days left"
        case .expired:
            return "Trial finished"
        }
    }

    /// Stores a key only if it verifies, so an invalid key never looks accepted.
    @discardableResult
    func activate(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let licence = Self.verify(trimmed) else {
            lastError = "That key is not valid."
            return false
        }
        guard !licence.isExpired else {
            lastError = "That licence expired on \(licence.expires!.formatted(date: .abbreviated, time: .omitted))."
            return false
        }
        Keychain.set(trimmed, account: Self.licenceAccount, service: Self.service)
        lastError = nil
        status = .licensed(licence)
        return true
    }

    func deactivate() {
        Keychain.remove(account: Self.licenceAccount, service: Self.service)
        refresh()
    }

    func refresh() {
        if let stored = Keychain.get(account: Self.licenceAccount, service: Self.service),
           let licence = Self.verify(stored), !licence.isExpired {
            status = .licensed(licence)
            return
        }

        // The trial start lives in the keychain rather than the settings file so
        // that clearing preferences does not silently hand out another fortnight.
        let started: Date
        if let raw = Keychain.get(account: Self.trialAccount, service: Self.service),
           let seconds = Double(raw) {
            started = Date(timeIntervalSince1970: seconds)
        } else {
            started = Date()
            Keychain.set(String(started.timeIntervalSince1970),
                         account: Self.trialAccount, service: Self.service)
        }

        let elapsed = Calendar.current.dateComponents([.day], from: started, to: Date()).day ?? 0
        let left = Self.trialDays - elapsed
        status = left > 0 ? .trial(daysLeft: left) : .expired
    }

    // MARK: - Verification

    /// `JNDL1.<payload>.<signature>`, both base64url.
    ///
    /// Pure verification with no state, so it is usable from anywhere.
    nonisolated static func verify(_ key: String) -> Licence? {
        let parts = key.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "JNDL1",
              let body = decode(String(parts[1])),
              let signature = decode(String(parts[2])),
              let keyData = Data(base64Encoded: publicKeyBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              publicKey.isValidSignature(signature, for: body)
        else { return nil }

        struct Payload: Codable {
            var email: String
            var id: String
            var issued: Double
            var expires: Double?
            var product: String
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: body),
              payload.product == "jendela"
        else { return nil }

        return Licence(
            email: payload.email,
            id: payload.id,
            issued: Date(timeIntervalSince1970: payload.issued),
            expires: payload.expires.map(Date.init(timeIntervalSince1970:))
        )
    }

    nonisolated private static func decode(_ text: String) -> Data? {
        var value = text.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while value.count % 4 != 0 { value += "=" }
        return Data(base64Encoded: value)
    }
}

/// Small keychain wrapper over the data-protection keychain, for the same
/// reason the clipboard uses it: the legacy keychain binds items to the signing
/// identity and breaks whenever the app is re-signed.
/// Small keychain wrapper over the data-protection keychain, for the same
/// reason the clipboard uses it: the legacy keychain binds items to the signing
/// identity and breaks whenever the app is re-signed.
///
/// Falls back to a file when no keychain is available — an unsigned build, or a
/// test runner. Without that fallback `set` fails silently and the trial clock
/// restarts on every launch, which quietly hands out an unlimited trial.
enum Keychain {
    static func get(account: String, service: String) -> String? {
        var query = base(account: account, service: service)
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        return try? String(contentsOf: fileURL(account), encoding: .utf8)
    }

    static func set(_ value: String, account: String, service: String) {
        let query = base(account: account, service: service)
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = Data(value.utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if SecItemAdd(insert as CFDictionary, nil) == errSecSuccess { return }

        let url = fileURL(account)
        try? value.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func remove(account: String, service: String) {
        SecItemDelete(base(account: account, service: service) as CFDictionary)
        try? FileManager.default.removeItem(at: fileURL(account))
    }

    private static func fileURL(_ account: String) -> URL {
        SupportDirectory.root.appendingPathComponent(".\(account)")
    }

    private static func base(account: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
    }
}
