import XCTest
@testable import Jendela

final class InteropTest: XCTestCase {
    /// The end of the chain: a licence the server issued through the purchase
    /// webhook must unlock the app. If the two ever disagree on key format,
    /// every customer would pay and then be refused.
    @MainActor func testServerIssuedLicenceUnlocksTheApp() throws {
        let key = "JNDL1.eyJlbWFpbCI6ImJ1eWVyQGV4YW1wbGUuY29tIiwiaWQiOiI4M2MwOWIzYS0xOTFlLTQyMzktYjFjYy1hYzA2OTM3OTBkMDYiLCJpc3N1ZWQiOjE3ODkzMDc4NjEsInByb2R1Y3QiOiJqZW5kZWxhIn0.u2ylN6qN-zuITCeSy8rg7qULT85yoWSCmC_F_VznQmc72f5S8dTZHqdvGb2_4bpdR14laVRvrSqXCUBlQn7wDg"
        try XCTSkipIf(key.isEmpty, "run server/test.mjs first")

        let licence = try XCTUnwrap(Licensing.verify(key),
                                    "a licence issued by the server was rejected by the app")
        XCTAssertEqual(licence.email, "buyer@example.com")
        XCTAssertTrue(licence.isLifetime)

        let licensing = Licensing()
        defer { licensing.deactivate() }
        XCTAssertTrue(licensing.activate(key), "activation failed for a genuine server licence")
        XCTAssertTrue(licensing.isPro)

        // And gating actually lifts.
        let state = JendelaState()
        state.licensing.activate(key)
        XCTAssertFalse(state.requiresLicence(.clipboard))
        XCTAssertFalse(state.requiresLicence(.ai))
        XCTAssertEqual(state.effectiveClipboardLimit, state.clipboardLimit)
        state.licensing.deactivate()
    }
}
