// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import Testing
@testable import Pulse

/// The automatic update check interval: what is stored, what a length is in
/// seconds, and which timer a change arms. Sparkle itself is not started.
@MainActor
@Suite("Update check cadence")
struct UpdateCheckCadenceTests {
    @Test("Twelve hours is the default, which is what a fresh install checks at")
    func twelveHoursIsTheDefault() {
        let (defaults, cleanup) = TestDefaults.make("UpdateCheckCadence")
        defer { cleanup() }
        let settings = AppSettings(defaults: defaults)

        #expect(settings.updateCheckCadence == .default)
        #expect(settings.updateCheckCadence.amount == 12)
        #expect(settings.updateCheckCadence.unit == .hour)
        #expect(settings.updateCheckCadence.timeInterval == 12 * 3_600)
        #expect(defaults.object(forKey: "settings.updateCheckAmount") == nil)
        #expect(defaults.object(forKey: "settings.updateCheckUnit") == nil)
    }

    @Test("Nothing stored, an unknown unit, or an amount outside 1...9999 is twelve hours")
    func invalidStorageRestoresTheDefault() {
        let cases: [(Any?, String?)] = [
            (nil, nil),
            (nil, "hour"),
            (12, nil),
            (12, "seconds"),
            (12, "fortnight"),
            (0, "minute"),
            (-3, "day"),
            (10_000, "week"),
            ("12", "hour"),
            (1.5, "day"),
        ]
        for (amount, unit) in cases {
            let (defaults, cleanup) = TestDefaults.make("UpdateCheckCadence")
            defer { cleanup() }
            if let amount { defaults.set(amount, forKey: "settings.updateCheckAmount") }
            if let unit { defaults.set(unit, forKey: "settings.updateCheckUnit") }

            let back = AppSettings.restoredSettings(from: defaults, detected: [], scan: ExtensionCatalog.Scan())

            #expect(back.updateCheckCadence == .default)
        }
    }

    @Test("A saved amount and unit are the interval a relaunch uses")
    func savedCadenceRoundTrips() {
        let (defaults, cleanup) = TestDefaults.make("UpdateCheckCadence")
        defer { cleanup() }
        let settings = AppSettings(defaults: defaults)
        settings.updateCheckCadence = UpdateCheckCadence(amount: 45, unit: .minute)

        let back = AppSettings.restoredSettings(from: defaults, detected: [], scan: ExtensionCatalog.Scan())

        #expect(back.updateCheckCadence == UpdateCheckCadence(amount: 45, unit: .minute))
        #expect(back.updateCheckCadence.timeInterval == 45 * 60)
        #expect(defaults.object(forKey: "settings.updateCheckAmount") as? Int == 45)
        #expect(defaults.string(forKey: "settings.updateCheckUnit") == "minute")
    }

    @Test("An amount the stepper cannot set is left as it was")
    func unstorableAmountIsRejected() {
        let (defaults, cleanup) = TestDefaults.make("UpdateCheckCadence")
        defer { cleanup() }
        let settings = AppSettings(defaults: defaults)
        settings.updateCheckCadence = UpdateCheckCadence(amount: 3, unit: .day)
        var changes = 0
        settings.onUpdateCheckCadenceChange = { changes += 1 }

        settings.updateCheckCadence = UpdateCheckCadence(amount: 0, unit: .minute)
        settings.updateCheckCadence = UpdateCheckCadence(amount: 10_000, unit: .week)

        #expect(settings.updateCheckCadence == UpdateCheckCadence(amount: 3, unit: .day))
        #expect(changes == 0)
        #expect(defaults.object(forKey: "settings.updateCheckAmount") as? Int == 3)
        #expect(defaults.string(forKey: "settings.updateCheckUnit") == "day")
    }

    @Test("Minutes, hours, days, and weeks are exact second counts")
    func unitsConvertToSeconds() {
        #expect(UpdateCheckCadence(amount: 1, unit: .minute).timeInterval == 60)
        #expect(UpdateCheckCadence(amount: 30, unit: .minute).timeInterval == 1_800)
        #expect(UpdateCheckCadence(amount: 59, unit: .minute).timeInterval == 3_540)
        #expect(UpdateCheckCadence(amount: 60, unit: .minute).timeInterval == 3_600)
        #expect(UpdateCheckCadence(amount: 1, unit: .hour).timeInterval == 3_600)
        #expect(UpdateCheckCadence(amount: 12, unit: .hour).timeInterval == 43_200)
        #expect(UpdateCheckCadence(amount: 1, unit: .day).timeInterval == 86_400)
        #expect(UpdateCheckCadence(amount: 24, unit: .hour).timeInterval == UpdateCheckCadence(amount: 1, unit: .day).timeInterval)
        #expect(UpdateCheckCadence(amount: 1, unit: .week).timeInterval == 604_800)
        #expect(UpdateCheckCadence(amount: 2, unit: .week).timeInterval == 1_209_600)
        #expect(UpdateCheckCadence(amount: 7, unit: .day).timeInterval == UpdateCheckCadence(amount: 1, unit: .week).timeInterval)
    }

    @Test("Changing the length asks for a new schedule and does not refresh providers")
    func changingTheLengthReschedules() {
        let (defaults, cleanup) = TestDefaults.make("UpdateCheckCadence")
        defer { cleanup() }
        let settings = AppSettings(defaults: defaults)
        var cadenceChanges = 0
        var providerRefreshes = 0
        settings.onUpdateCheckCadenceChange = { cadenceChanges += 1 }
        settings.onChange = { providerRefreshes += 1 }

        settings.updateCheckCadence = UpdateCheckCadence(amount: 6, unit: .hour)
        settings.updateCheckCadence = UpdateCheckCadence(amount: 6, unit: .hour)
        settings.updateCheckCadence.amount = 2
        settings.updateCheckCadence.unit = .day

        #expect(cadenceChanges == 3)
        #expect(providerRefreshes == 0)
        #expect(settings.updateDiscovery == .notifyFirst)
    }

    @Test("The wait is measured from the last check")
    func delayIsMeasuredFromTheLastCheck() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let halfHour: TimeInterval = 1_800

        #expect(UpdateCheckSchedule.delay(since: nil, now: now, interval: halfHour) == 0)
        #expect(UpdateCheckSchedule.delay(since: now.addingTimeInterval(-10 * 60), now: now, interval: halfHour) == 20 * 60)
        #expect(UpdateCheckSchedule.delay(since: now.addingTimeInterval(-halfHour), now: now, interval: halfHour) == 0)
        #expect(UpdateCheckSchedule.delay(since: now.addingTimeInterval(-(halfHour + 1)), now: now, interval: halfHour) == 0)
        #expect(UpdateCheckSchedule.delay(since: now.addingTimeInterval(60), now: now, interval: halfHour) == halfHour)
        #expect(UpdateCheckSchedule.delay(since: now, now: now, interval: 0) == 0)
    }

    @Test("Under an hour Blinky waits; an hour or more is Sparkle, and the same length does not reset it")
    func scheduleFollowsSparklesFloor() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let last = now.addingTimeInterval(-10 * 60)
        let twelveHours = UpdateCheckCadence.default.timeInterval

        let unchanged = UpdateCheckSchedule.application(
            interval: twelveHours,
            checksAutomatically: true,
            currentSparkleInterval: twelveHours,
            lastCheck: last,
            now: now,
            justFired: false
        )
        #expect(unchanged.sparkleInterval == nil)
        #expect(unchanged.ownTimerDelay == nil)

        let sixHours = UpdateCheckSchedule.application(
            interval: 6 * 3_600,
            checksAutomatically: true,
            currentSparkleInterval: twelveHours,
            lastCheck: last,
            now: now,
            justFired: false
        )
        #expect(sixHours.sparkleInterval == 6 * 3_600)
        #expect(sixHours.ownTimerDelay == nil)

        let halfHour = UpdateCheckSchedule.application(
            interval: 1_800,
            checksAutomatically: true,
            currentSparkleInterval: twelveHours,
            lastCheck: last,
            now: now,
            justFired: false
        )
        #expect(halfHour.sparkleInterval == 1_800)
        #expect(halfHour.ownTimerDelay == 20 * 60)

        let due = UpdateCheckSchedule.application(
            interval: 1_800,
            checksAutomatically: true,
            currentSparkleInterval: 1_800,
            lastCheck: now.addingTimeInterval(-3_600),
            now: now,
            justFired: false
        )
        #expect(due.sparkleInterval == nil)
        #expect(due.ownTimerDelay == UpdateCheckSchedule.alreadyDueDelay)

        let fired = UpdateCheckSchedule.application(
            interval: 1_800,
            checksAutomatically: true,
            currentSparkleInterval: 1_800,
            lastCheck: now.addingTimeInterval(-3_600),
            now: now,
            justFired: true
        )
        #expect(fired.sparkleInterval == nil)
        #expect(fired.ownTimerDelay == 1_800)

        let hour = UpdateCheckSchedule.application(
            interval: UpdateCheckSchedule.sparkleMinimum,
            checksAutomatically: true,
            currentSparkleInterval: twelveHours,
            lastCheck: last,
            now: now,
            justFired: false
        )
        #expect(hour.sparkleInterval == 3_600)
        #expect(hour.ownTimerDelay == nil)

        let checksOff = UpdateCheckSchedule.application(
            interval: 1_800,
            checksAutomatically: false,
            currentSparkleInterval: twelveHours,
            lastCheck: last,
            now: now,
            justFired: false
        )
        #expect(checksOff.sparkleInterval == 1_800)
        #expect(checksOff.ownTimerDelay == nil)

        let noUpdater = UpdateCheckSchedule.application(
            interval: 1_800,
            checksAutomatically: true,
            currentSparkleInterval: nil,
            lastCheck: last,
            now: now,
            justFired: false
        )
        #expect(noUpdater.sparkleInterval == nil)
        #expect(noUpdater.ownTimerDelay == 20 * 60)

        let sameLength = UpdateCheckSchedule.application(
            interval: UpdateCheckCadence(amount: 1, unit: .day).timeInterval,
            checksAutomatically: true,
            currentSparkleInterval: UpdateCheckCadence(amount: 24, unit: .hour).timeInterval,
            lastCheck: last,
            now: now,
            justFired: false
        )
        #expect(sameLength.sparkleInterval == nil)
        #expect(sameLength.ownTimerDelay == nil)
    }

    @Test("The bundle's scheduled interval is the twelve-hour default")
    func bundleMatchesTheDefault() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = try String(contentsOf: root.appendingPathComponent("Scripts/bundle.sh"), encoding: .utf8)
        let seconds = Int(UpdateCheckCadence.default.timeInterval)
        #expect(seconds == 43_200)
        #expect(script.contains("<key>SUScheduledCheckInterval</key><integer>\(seconds)</integer>"))
        #expect(!script.contains("<integer>7200</integer>"))
    }
}
