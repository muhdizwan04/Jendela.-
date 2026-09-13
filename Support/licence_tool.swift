import CryptoKit
import Foundation

// Offline licence tooling.
//
//   swift Support/licence_tool.swift genkey
//   swift Support/licence_tool.swift sign <private-key-file> <email> [days]
//
// The private key never belongs in the app or the repository: anyone holding it
// can mint licences. Keep the file somewhere safe and backed up — losing it
// means every future licence must be signed by a new key, which would strand
// existing customers on an old public key.

struct Payload: Codable {
    var email: String
    var id: String
    var issued: Double
    /// Absent for a lifetime licence.
    var expires: Double?
    var product: String
}

func base64url(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

let arguments = CommandLine.arguments

switch arguments.count > 1 ? arguments[1] : "" {
case "genkey":
    let key = Curve25519.Signing.PrivateKey()
    let privatePath = "jendela-licence-private.key"
    try! key.rawRepresentation.base64EncodedString().write(
        toFile: privatePath, atomically: true, encoding: .utf8
    )
    print("private key written to \(privatePath) — keep it out of git and back it up")
    print("public key (embed this in Licensing.swift):")
    print(key.publicKey.rawRepresentation.base64EncodedString())

case "sign":
    guard arguments.count >= 4 else {
        print("usage: sign <private-key-file> <email> [days]")
        exit(1)
    }
    let raw = try! String(contentsOfFile: arguments[2], encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let key = try! Curve25519.Signing.PrivateKey(rawRepresentation: Data(base64Encoded: raw)!)

    var payload = Payload(
        email: arguments[3],
        id: UUID().uuidString,
        issued: Date().timeIntervalSince1970,
        expires: nil,
        product: "jendela"
    )
    if arguments.count > 4, let days = Double(arguments[4]) {
        payload.expires = Date().addingTimeInterval(days * 86400).timeIntervalSince1970
    }

    let body = try! JSONEncoder().encode(payload)
    let signature = try! key.signature(for: body)
    print("JNDL1.\(base64url(body)).\(base64url(signature))")

default:
    print("usage: genkey | sign <private-key-file> <email> [days]")
}
