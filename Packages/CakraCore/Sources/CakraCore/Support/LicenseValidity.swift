import Foundation

/// Whether a verified license token unlocks the app right now, from its dates alone (the signature and device are
/// checked before). Trial, Professional and Organization licenses end at `expiresAt`; Lifetime has none. A token is
/// also only good until `offlineUntil` (the server caps it at the end date) and not when the device clock was turned
/// back. The app re-checks this at launch, when it becomes active, and when the earliest of these moments arrives.
public struct LicenseValidity: Equatable, Sendable {
    /// The end date has passed.
    public var expired: Bool
    /// Not checked online for too long (`offline_until` passed).
    public var offlineTooLong: Bool
    /// The device clock is earlier than the token's issue time or the latest time seen (beyond the tolerance).
    public var clockTurnedBack: Bool
    /// A Lifetime license for an older major version than this app.
    public var majorNotCovered: Bool

    /// Every check passed: the license's plan applies.
    public var isActive: Bool { !expired && !offlineTooLong && !clockTurnedBack && !majorNotCovered }

    /// Clock corrections (time zone, network time) up to this much are fine.
    public static let clockTolerance: TimeInterval = 6 * 3600

    public static func evaluate(expiresAt: Date?, offlineUntil: Date, issuedAt: Date, lastSeen: Date?,
                                updatesMajor: Int?, appMajor: Int, now: Date) -> LicenseValidity {
        let turnedBack = now < issuedAt.addingTimeInterval(-clockTolerance)
            || (lastSeen.map { now < $0.addingTimeInterval(-clockTolerance) } ?? false)
        return LicenseValidity(expired: expiresAt.map { $0 <= now } ?? false,
                               offlineTooLong: offlineUntil <= now,
                               clockTurnedBack: turnedBack,
                               majorNotCovered: updatesMajor.map { appMajor > $0 } ?? false)
    }

    /// The next moment the answer can change by itself (end date or offline limit), for a re-check while the app runs.
    public static func nextChange(expiresAt: Date?, offlineUntil: Date, after now: Date) -> Date? {
        [expiresAt, offlineUntil].compactMap { $0 }.filter { $0 > now }.min()
    }
}
