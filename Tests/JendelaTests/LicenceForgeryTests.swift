import CryptoKit
import Foundation
import XCTest
@testable import Jendela

/// Licences verify offline against a public key compiled into the app, so the
/// only thing standing between a customer and a free copy is this signature
/// check. These are the forgeries worth trying.
final class LicenceForgeryTests: XCTestCase {
    private func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func key(signedWith signer: Curve25519.Signing.PrivateKey,
                     product: String = "jendela",
                     expires: Double? = nil) throws -> String {
        var payload: [String: Any] = [
            "email": "forger@example.com",
            "id": UUID().uuidString,
            "issued": Date().timeIntervalSince1970,
            "product": product
        ]
        if let expires { payload["expires"] = expires }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let signature = try signer.signature(for: body)
        return "JNDL1.\(base64url(body)).\(base64url(signature))"
    }

    /// The obvious attack: generate your own key pair and sign yourself a
    /// licence. It is well formed and correctly signed — just not by us.
    func testALicenceSignedByAnotherKeyIsRejected() throws {
        let attacker = Curve25519.Signing.PrivateKey()
        let forged = try key(signedWith: attacker)
        XCTAssertNil(Licensing.verify(forged), "anyone could mint their own licence")
    }

    /// A genuine signature lifted onto a different genuine body.
    func testSignaturesCannotBeMovedBetweenLicences() throws {
        let a = LicensingTests.genuine.split(separator: ".")
        let b = LicensingTests.expired.split(separator: ".")
        XCTAssertNil(Licensing.verify("\(a[0]).\(a[1]).\(b[2])"))
        XCTAssertNil(Licensing.verify("\(b[0]).\(b[1]).\(a[2])"))
    }

    func testAnEmptyOrTruncatedSignatureIsRejected() {
        let parts = LicensingTests.genuine.split(separator: ".")
        XCTAssertNil(Licensing.verify("\(parts[0]).\(parts[1])."))
        XCTAssertNil(Licensing.verify("\(parts[0]).\(parts[1]).\(parts[2].dropLast(4))"))
    }

    func testTheVersionPrefixMustMatch() {
        let parts = LicensingTests.genuine.split(separator: ".")
        XCTAssertNil(Licensing.verify("JNDL2.\(parts[1]).\(parts[2])"))
        XCTAssertNil(Licensing.verify("\(parts[1]).\(parts[2])"))
        XCTAssertNil(Licensing.verify("JNDL1.\(parts[1]).\(parts[2]).extra"))
    }

    /// A key for a different product, correctly signed, must not unlock this
    /// one — it matters the moment a second product shares the signing key.
    func testAnotherProductsKeyIsRejected() throws {
        let attacker = Curve25519.Signing.PrivateKey()
        XCTAssertNil(Licensing.verify(try key(signedWith: attacker, product: "somethingelse")))
    }

    func testProductMatchingIsExact() throws {
        let attacker = Curve25519.Signing.PrivateKey()
        for name in ["Jendela", "JENDELA", "jendela ", " jendela", "jendela2"] {
            XCTAssertNil(Licensing.verify(try key(signedWith: attacker, product: name)))
        }
    }

    /// Verification must not trap on rubbish, whatever shape it arrives in.
    func testMalformedInputDoesNotCrash() {
        for candidate in ["JNDL1..", "JNDL1...", ".", "..", "JNDL1.%%%.%%%",
                          "JNDL1.\u{1F600}.\u{1F600}", String(repeating: "JNDL1.", count: 200)] {
            XCTAssertNil(Licensing.verify(candidate), "accepted \(candidate)")
        }
    }
}
