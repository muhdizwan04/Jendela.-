import XCTest
@testable import Jendela

final class LicensingTests: XCTestCase {
    static let genuine = "JNDL1.eyJwcm9kdWN0IjoiamVuZGVsYSIsImlzc3VlZCI6MTc4OTMwMjk5My43Mjk3NTEsImlkIjoiQjNBRDI4RkUtQjk0OS00NkZBLUFBRUQtRDYxQUUxNEQzQ0E5IiwiZW1haWwiOiJidXllckBleGFtcGxlLmNvbSJ9.Fgb0Mkd-7nqxujiM_Wd3zc8qjOouQT8HTJGvbh6qMBI0B0oyGFbuW6KG8lPscatzD23Azyo-iXzA5gQ8vnKSAg"
    static let expired = "JNDL1.eyJpZCI6IjQxRDY5MjFELTI5MkEtNEExRC04MzAyLTIwQjUyMzIwMUNBRSIsImVtYWlsIjoib2xkQGV4YW1wbGUuY29tIiwicHJvZHVjdCI6ImplbmRlbGEiLCJpc3N1ZWQiOjE3ODkzMDI5OTMuOTM1MDIxOSwiZXhwaXJlcyI6MTc4OTIxNjU5My45MzUwMjR9.7StebAvwvPhkqRr3lHVHNdJcDTJ-ZoFgiwz75FfaQDaD95D9KyS7ydW2gmRC1cABZ02zNN6gd_BQZNBw3LBtCA"

    func testGenuineKeyVerifies() throws {
        let licence = try XCTUnwrap(Licensing.verify(Self.genuine))
        XCTAssertEqual(licence.email, "buyer@example.com")
        XCTAssertTrue(licence.isLifetime)
        XCTAssertFalse(licence.isExpired)
    }

    /// The whole point of signing: a key that has been edited must not pass.
    func testTamperedKeyIsRejected() throws {
        let parts = Self.genuine.split(separator: ".")
        // Swap the payload for one claiming a different owner, keeping the
        // original signature.
        let forgedBody = Data(#"{"email":"free@rider.com","id":"x","issued":0,"product":"jendela"}"#.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let forged = "\(parts[0]).\(forgedBody).\(parts[2])"
        XCTAssertNil(Licensing.verify(forged), "a forged payload must not verify")
    }

    func testGarbageIsRejected() {
        XCTAssertNil(Licensing.verify(""))
        XCTAssertNil(Licensing.verify("JNDL1.not.base64"))
        XCTAssertNil(Licensing.verify("totally made up"))
    }

    func testExpiredKeyVerifiesButIsExpired() throws {
        let licence = try XCTUnwrap(Licensing.verify(Self.expired))
        XCTAssertTrue(licence.isExpired, "a past expiry date must be honoured")
    }

    @MainActor func testActivationRejectsExpiredAndAcceptsGenuine() {
        let licensing = Licensing()
        defer { licensing.deactivate() }

        XCTAssertFalse(licensing.activate(Self.expired))
        XCTAssertNotNil(licensing.lastError)

        XCTAssertTrue(licensing.activate(Self.genuine))
        XCTAssertNil(licensing.lastError)
        XCTAssertTrue(licensing.isPro)
        XCTAssertTrue(licensing.summary.contains("buyer@example.com"))
    }
}

final class GatingTests: XCTestCase {
    /// Free tabs must keep working forever; an app that becomes useless the
    /// moment a trial lapses does not earn a purchase.
    @MainActor func testFreeSectionsStayFree() {
        let state = JendelaState()
        state.licensing.deactivate()
        for section in [JendelaState.NotchSection.home, .music, .sound, .discord] {
            XCTAssertFalse(state.requiresLicence(section), "\(section.rawValue) must stay free")
        }
    }

    @MainActor func testUnlicensedHistoryIsShortNotAbsent() {
        let state = JendelaState()
        if state.isPro {
            XCTAssertEqual(state.effectiveClipboardLimit, state.clipboardLimit)
        } else {
            XCTAssertEqual(state.effectiveClipboardLimit, 5, "history should shorten, not vanish")
        }
    }

    @MainActor func testEveryPaywallHasCopy() {
        let state = JendelaState()
        for section in JendelaState.NotchSection.allCases {
            XCTAssertFalse(state.paywallDetail(for: section).isEmpty)
        }
    }
}

final class TrialTests: XCTestCase {
    /// The trial clock must not restart just because a second instance is made,
    /// or quitting and reopening would hand out an unlimited trial.
    @MainActor func testTrialDoesNotRestart() {
        Keychain.remove(account: "trial-start", service: "com.jendela.desktop")
        Keychain.remove(account: "licence-key", service: "com.jendela.desktop")

        let first = Licensing()
        guard case .trial(let firstDays) = first.status else {
            return XCTFail("a fresh install should be in trial, got \(first.status)")
        }
        XCTAssertEqual(firstDays, Licensing.trialDays)

        // Backdate the stored start, then rebuild: a fresh instance must read
        // the stored date rather than starting the clock again.
        let tenDaysAgo = Date().addingTimeInterval(-10 * 86400).timeIntervalSince1970
        Keychain.set(String(tenDaysAgo), account: "trial-start", service: "com.jendela.desktop")

        let second = Licensing()
        guard case .trial(let secondDays) = second.status else {
            return XCTFail("second launch should still be in trial, got \(second.status)")
        }
        XCTAssertEqual(secondDays, Licensing.trialDays - 10, "the trial clock restarted on relaunch")
        XCTAssertLessThan(secondDays, firstDays)
        XCTAssertTrue(second.isPro, "trial users get everything")

        Keychain.remove(account: "trial-start", service: "com.jendela.desktop")
    }

    @MainActor func testKeychainRoundTrip() {
        Keychain.set("hello", account: "test-item", service: "com.jendela.desktop")
        XCTAssertEqual(Keychain.get(account: "test-item", service: "com.jendela.desktop"), "hello")
        Keychain.remove(account: "test-item", service: "com.jendela.desktop")
        XCTAssertNil(Keychain.get(account: "test-item", service: "com.jendela.desktop"))
    }
}
