// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// How often a scheduled update check runs.
///
/// Minutes, hours, days, and weeks are the whole of the choice: an amount and
/// one of those units, never a free-form duration. Twelve hours is the
/// shipped default. Through 1.5.24 the bundle fixed the check at two hours.
///
/// **This type describes the interval. It does not talk to Sparkle.**
/// `UpdateCheckSchedule` turns it into the two timers, and `AppUpdate` arms
/// them. Check for Updates… and About's Check now are not this interval.
enum UpdateCheckUnit: String, CaseIterable, Identifiable, Sendable {
    case minute
    case hour
    case day
    case week

    var id: String { rawValue }

    /// One form for every count. A `.strings` value cannot agree with the number.
    var title: String {
        switch self {
        case .minute: String.localized("Minutes")
        case .hour: String.localized("Hours")
        case .day: String.localized("Days")
        case .week: String.localized("Weeks")
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .minute: 60
        case .hour: 3_600
        case .day: 86_400
        case .week: 604_800
        }
    }
}

struct UpdateCheckCadence: Equatable, Sendable {
    /// The smallest amount the stepper and the store accept.
    static let minimumAmount = 1
    /// Far past any interval a reader would choose, and still an exact `TimeInterval`.
    static let maximumAmount = 9_999

    var amount: Int
    var unit: UpdateCheckUnit

    static let `default` = UpdateCheckCadence(amount: 12, unit: .hour)

    /// The length Sparkle is given, in seconds.
    var timeInterval: TimeInterval {
        TimeInterval(amount) * unit.seconds
    }

    /// A stored pair the picker can show. Anything else is the default:
    /// a missing key, a unit a later version removed, an amount of zero,
    /// or a fraction (12.5 must not become 12).
    static func restored(amount: Any?, unit rawUnit: String?) -> UpdateCheckCadence {
        guard
            let number = integerAmount(amount),
            (minimumAmount...maximumAmount).contains(number),
            let rawUnit,
            let unit = UpdateCheckUnit(rawValue: rawUnit)
        else { return .default }
        return UpdateCheckCadence(amount: number, unit: unit)
    }

    /// `UserDefaults` hands a number back as an `NSNumber`, and a Swift `Int`
    /// bridges to one too. A fraction is not an amount: 12.5 must not become 12.
    /// A boolean is an `NSNumber` as well, and it is not an amount either.
    private static func integerAmount(_ amount: Any?) -> Int? {
        if amount is Bool { return nil }
        guard let number = amount as? NSNumber else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double == double.rounded(), abs(double) <= Double(Int.max) else { return nil }
        return Int(double)
    }

    static func isStorable(_ cadence: UpdateCheckCadence) -> Bool {
        (minimumAmount...maximumAmount).contains(cadence.amount)
    }
}

/// What to do with the two timers when the interval or the check switch changes.
///
/// Sparkle 2.9 will not arm a timer under an hour
/// (`SPUUpdaterSettings.minimumUpdateCheckInterval`). The length is still
/// stored as the reader chose it. At an hour or longer, Sparkle's own timer
/// is the schedule: assigning `updateCheckInterval` resets that cycle, so the
/// same length must not be assigned again. Under an hour, Blinky's timer
/// waits the real interval and calls the background check, which is the
/// scheduled path Install silently and Notify first already use.
///
/// The wait is measured from the last check, as Sparkle measures it, so a
/// relaunch does not check again early. A last check dated in the future
/// waits a full interval. A check that is already due waits one second, so
/// the timer cannot schedule another zero-delay fire on top of itself.
enum UpdateCheckSchedule {
    /// Sparkle's floor, in seconds. Not a policy of ours: the framework's.
    static let sparkleMinimum: TimeInterval = 3_600
    /// How long a check that is already due waits before it runs.
    static let alreadyDueDelay: TimeInterval = 1

    struct Application: Equatable, Sendable {
        /// Assigned to Sparkle only when it differs from the interval Sparkle
        /// already has. Nil when there is no updater, or the length is unchanged.
        /// Assigning always resets Sparkle's cycle.
        var sparkleInterval: TimeInterval?
        /// Blinky's timer. Nil when automatic checks are off, or the interval
        /// is at least an hour and Sparkle's timer is enough.
        var ownTimerDelay: TimeInterval?
    }

    /// Seconds until the next check. Zero means the interval has already passed.
    static func delay(since lastCheck: Date?, now: Date, interval: TimeInterval) -> TimeInterval {
        guard interval > 0 else { return 0 }
        guard let lastCheck else { return 0 }
        let elapsed = now.timeIntervalSince(lastCheck)
        if elapsed < 0 { return interval }
        if elapsed >= interval { return 0 }
        return interval - elapsed
    }

    static func application(
        interval: TimeInterval,
        checksAutomatically: Bool,
        currentSparkleInterval: TimeInterval?,
        lastCheck: Date?,
        now: Date,
        justFired: Bool
    ) -> Application {
        let sparkleInterval: TimeInterval? = {
            guard let currentSparkleInterval else { return nil }
            return same(currentSparkleInterval, interval) ? nil : interval
        }()
        let ownTimerDelay: TimeInterval? = {
            guard checksAutomatically, interval > 0, interval < sparkleMinimum else { return nil }
            if justFired { return interval }
            let wait = delay(since: lastCheck, now: now, interval: interval)
            return wait == 0 ? alreadyDueDelay : wait
        }()
        return Application(sparkleInterval: sparkleInterval, ownTimerDelay: ownTimerDelay)
    }

    /// Sparkle treats a thousandth of a second as the same interval. So do we,
    /// so a value read back from the updater does not reset the cycle.
    static func same(_ lhs: TimeInterval, _ rhs: TimeInterval) -> Bool {
        abs(lhs - rhs) < 0.001
    }
}
