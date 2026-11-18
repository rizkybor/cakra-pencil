import XCTest
@testable import CakraCore

final class LicenseValidityTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func check(expiresIn: TimeInterval?, offlineIn: TimeInterval = 20 * 86_400, issuedAgo: TimeInterval = 86_400,
                       lastSeenAgo: TimeInterval? = 3600, updatesMajor: Int? = nil, appMajor: Int = 1, at t: Date? = nil) -> LicenseValidity {
        LicenseValidity.evaluate(expiresAt: expiresIn.map { now.addingTimeInterval($0) },
                                 offlineUntil: now.addingTimeInterval(offlineIn),
                                 issuedAt: now.addingTimeInterval(-issuedAgo),
                                 lastSeen: lastSeenAgo.map { now.addingTimeInterval(-$0) },
                                 updatesMajor: updatesMajor, appMajor: appMajor, now: t ?? now)
    }

    /// Trial, Professional and Organization are term licenses: active before the end date, not after.
    func testTermLicenseActiveUntilItsEndDate() {
        XCTAssertTrue(check(expiresIn: 14 * day).isActive, "Trial with 14 days left")
        XCTAssertTrue(check(expiresIn: 60).isActive, "One minute before the end")
        let ended = check(expiresIn: 0)
        XCTAssertTrue(ended.expired)
        XCTAssertFalse(ended.isActive, "At the end date exactly")
        XCTAssertFalse(check(expiresIn: -day).isActive, "A day after the end")
    }

    func testLifetimeNeverExpires() {
        XCTAssertTrue(check(expiresIn: nil).isActive)
        XCTAssertFalse(check(expiresIn: nil).expired)
    }

    /// The server caps offline_until at the end date: offline use never runs past the end.
    func testOfflineLimit() {
        XCTAssertTrue(check(expiresIn: nil, offlineIn: day).isActive)
        let tooLong = check(expiresIn: nil, offlineIn: -1)
        XCTAssertTrue(tooLong.offlineTooLong)
        XCTAssertFalse(tooLong.isActive)
    }

    /// Turning the clock back can't bring an ended trial or an offline period back.
    func testClockTurnedBack() {
        XCTAssertTrue(check(expiresIn: nil, issuedAgo: -2 * day).clockTurnedBack, "Earlier than the token's issue time")
        XCTAssertTrue(check(expiresIn: nil, lastSeenAgo: -3 * day).clockTurnedBack, "Earlier than the latest time seen")
        XCTAssertFalse(check(expiresIn: nil, issuedAgo: -3600, lastSeenAgo: -3600).clockTurnedBack, "Within the 6 h tolerance")
        XCTAssertFalse(check(expiresIn: nil, lastSeenAgo: -3 * day).isActive)
    }

    func testLifetimeCoversItsMajorVersionOnly() {
        XCTAssertTrue(check(expiresIn: nil, updatesMajor: 1, appMajor: 1).isActive)
        XCTAssertTrue(check(expiresIn: nil, updatesMajor: 2, appMajor: 1).isActive)
        XCTAssertTrue(check(expiresIn: nil, updatesMajor: 1, appMajor: 2).majorNotCovered)
        XCTAssertTrue(check(expiresIn: 30 * day, updatesMajor: nil, appMajor: 5).isActive, "Term plans get every version")
    }

    func testNextChangeIsTheEarliestFutureMoment() {
        let end = now.addingTimeInterval(2 * day), offline = now.addingTimeInterval(5 * day)
        XCTAssertEqual(LicenseValidity.nextChange(expiresAt: end, offlineUntil: offline, after: now), end)
        XCTAssertEqual(LicenseValidity.nextChange(expiresAt: nil, offlineUntil: offline, after: now), offline)
        XCTAssertNil(LicenseValidity.nextChange(expiresAt: now.addingTimeInterval(-1), offlineUntil: now.addingTimeInterval(-1), after: now))
    }
}
