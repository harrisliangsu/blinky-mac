import Foundation
import SwiftUI
import Testing
@testable import Pulse

/// The exhaustion line and the Codex windows that feed it.
@Suite("Burn rate")
struct BurnRateTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func window(
        kind: UsageWindow.Kind = .weekly,
        scope: String? = nil,
        used: Double,
        seconds: Int = 604_800,
        resetsAt: Date?,
        reportsLength: Bool = true
    ) -> UsageWindow {
        UsageWindow(
            id: "window",
            kind: kind,
            scope: scope,
            usedFraction: used,
            windowSeconds: seconds,
            resetsAt: resetsAt,
            reportsLength: reportsLength
        )
    }

    /// Half a week already gone, unless a test says otherwise.
    private static func weekly(used: Double, elapsed: Double = 0.5) -> UsageWindow {
        Self.window(
            used: used,
            resetsAt: Self.now.addingTimeInterval(604_800 * (1 - elapsed))
        )
    }

    private static func pace(remaining: TimeInterval, length: Double = 604_800, elapsed: Double = 0.5) -> Double {
        let elapsedSeconds = length * elapsed
        return elapsedSeconds / (remaining + elapsedSeconds)
    }

    @Test("A time is returned whenever the pace runs out before the reset")
    func readingKeepsTheTimePastSixHours() {
        let far = BurnRate.reading(for: Self.weekly(used: Self.pace(remaining: 37 * 3600)), now: Self.now)
        #expect(far?.exhaustsBeforeReset == true)
        let seconds = far?.timeToExhaustion ?? 0
        #expect(abs(seconds - 37 * 3600) < 60)

        let close = BurnRate.reading(for: Self.weekly(used: Self.pace(remaining: 4 * 3600)), now: Self.now)
        #expect(close?.exhaustsBeforeReset == true)
        #expect(abs((close?.timeToExhaustion ?? 0) - 4 * 3600) < 60)
    }

    @Test("A window that lasts, or that has barely opened with little spent, says nothing about a time")
    func readingRefusesWhatItCannotDivide() {
        let lasts = BurnRate.reading(for: Self.weekly(used: 0.2), now: Self.now)
        #expect(lasts?.exhaustsBeforeReset == false)
        #expect(lasts?.timeToExhaustion == nil)
        #expect(lasts?.earlyPace == false)

        let barely = Self.window(used: 0.01, resetsAt: Self.now.addingTimeInterval(598_752))
        let quiet = BurnRate.reading(for: barely, now: Self.now)
        #expect(quiet?.exhaustsBeforeReset == false)
        #expect(quiet?.timeToExhaustion == nil)
        #expect(quiet?.earlyPace == false)
        let quietLine = BurnRate.cardLine(
            for: barely, reading: quiet!, horizon: 6 * 3600, softHint: true, beforeReset: true
        )
        #expect(quietLine?.tone == .lasts)
        #expect(quietLine?.note == nil)

        let unstated = Self.window(used: 0.8, resetsAt: Self.now.addingTimeInterval(302_400), reportsLength: false)
        #expect(BurnRate.reading(for: unstated, now: Self.now) == nil)

        let noReset = Self.window(used: 0.8, resetsAt: nil)
        #expect(BurnRate.reading(for: noReset, now: Self.now) == nil)
    }

    @Test("The card states a time only inside the horizon, then the reset sentence, then the hint")
    func cardLineFollowsTheSwitches() {
        let held = LocalizationSource.hold(.english)
        defer { held.end() }

        let week = Self.weekly(used: Self.pace(remaining: 37 * 3600))
        let reading = BurnRate.reading(for: week, now: Self.now)!
        let horizon = 6.0 * 3600

        let countdown = BurnRate.cardLine(
            for: week, reading: reading, horizon: 48 * 3600, softHint: true, beforeReset: true
        )
        #expect(countdown?.tone == .countdown)
        #expect(countdown?.text == "Weekly · may run out in 1d 13h")

        let tied = BurnRate.cardLine(
            for: week, reading: reading, horizon: horizon, softHint: true, beforeReset: true
        )
        #expect(tied?.tone == .beforeReset)
        #expect(tied?.text == "At the current pace, about 1d 13h before the next reset.")

        let hint = BurnRate.cardLine(
            for: week, reading: reading, horizon: horizon, softHint: true, beforeReset: false
        )
        #expect(hint?.tone == .hint)
        #expect(hint?.text == "Weekly · may run out before the reset")

        #expect(BurnRate.cardLine(
            for: week, reading: reading, horizon: horizon, softHint: false, beforeReset: false
        ) == nil)

        let close = Self.weekly(used: Self.pace(remaining: 4 * 3600))
        let closeReading = BurnRate.reading(for: close, now: Self.now)!
        let soon = BurnRate.cardLine(
            for: close, reading: closeReading, horizon: horizon, softHint: false, beforeReset: false
        )
        #expect(soon?.tone == .countdown)
        #expect(soon?.text == "Weekly · may run out in about 4 hours")
        #expect(soon?.note == nil)
        #expect(countdown?.note == nil)

        let steady = Self.weekly(used: 0.2)
        let steadyReading = BurnRate.reading(for: steady, now: Self.now)!
        #expect(BurnRate.cardLine(
            for: steady, reading: steadyReading, horizon: horizon, softHint: true, beforeReset: true
        )?.tone == .lasts)

        let fiveHour = Self.window(
            kind: .fiveHour,
            scope: "GPT",
            used: 0.7,
            seconds: 18_000,
            resetsAt: Self.now.addingTimeInterval(4 * 3600)
        )
        let scoped = BurnRate.reading(for: fiveHour, now: Self.now)!
        let named = BurnRate.cardLine(
            for: fiveHour, reading: scoped, horizon: horizon, softHint: true, beforeReset: true
        )
        #expect(named?.text.hasPrefix("5-hour · GPT · ") == true)

        LocalizationSource.use(.chineseSimplified)
        #expect(BurnRate.approximate(37 * 3600) == "约 1天13小时")
        #expect(BurnRate.span(37 * 3600) == "1天13小时")
        let chinese = BurnRate.cardLine(
            for: week, reading: reading, horizon: 48 * 3600, softHint: true, beforeReset: true
        )
        #expect(chinese?.text == "每周 · 约 1天13小时后用尽")
        #expect(chinese?.note == nil)
    }

    @Test("A fast start still states the estimate, and says the early pace is only a guide")
    func earlyElevatedPaceStillForecasts() {
        let held = LocalizationSource.hold(.english)
        defer { held.end() }

        // One percent of a week left to run: 598_752 seconds of a 604_800-second week.
        let opened = Self.now.addingTimeInterval(598_752)

        let light = Self.window(used: 0.04, resetsAt: opened)
        let quiet = BurnRate.reading(for: light, now: Self.now)
        #expect(quiet?.exhaustsBeforeReset == false)
        #expect(quiet?.timeToExhaustion == nil)
        #expect(quiet?.earlyPace == false)
        #expect(BurnRate.cardLine(
            for: light, reading: quiet!, horizon: 6 * 3600, softHint: true, beforeReset: true
        )?.note == nil)

        let burst = Self.window(used: BurnRate.earlyQuietUsed, resetsAt: opened)
        let burstReading = BurnRate.reading(for: burst, now: Self.now)
        #expect(burstReading?.earlyPace == true)
        #expect(burstReading?.exhaustsBeforeReset == true)
        #expect(abs((burstReading?.timeToExhaustion ?? 0) - 31.92 * 3600) < 60)
        let burstLine = BurnRate.cardLine(
            for: burst, reading: burstReading!, horizon: 6 * 3600, softHint: true, beforeReset: true
        )
        #expect(burstLine?.tone == .beforeReset)
        #expect(burstLine?.text == "At the current pace, about 1d 8h before the next reset.")
        #expect(burstLine?.note == "A fast start. The estimate is only a guide.")
        #expect(burstLine?.spoken.hasSuffix("A fast start. The estimate is only a guide.") == true)

        let hintOnly = BurnRate.cardLine(
            for: burst, reading: burstReading!, horizon: 6 * 3600, softHint: true, beforeReset: false
        )
        #expect(hintOnly?.tone == .hint)
        #expect(hintOnly?.note == burstLine?.note)
        #expect(BurnRate.cardLine(
            for: burst, reading: burstReading!, horizon: 6 * 3600, softHint: false, beforeReset: false
        ) == nil)

        let heavy = Self.window(used: 0.4, resetsAt: opened)
        let heavyReading = BurnRate.reading(for: heavy, now: Self.now)
        #expect(heavyReading?.earlyPace == true)
        #expect(abs((heavyReading?.timeToExhaustion ?? 0) - 2.52 * 3600) < 60)
        let countdown = BurnRate.cardLine(
            for: heavy, reading: heavyReading!, horizon: 6 * 3600, softHint: false, beforeReset: false
        )
        #expect(countdown?.tone == .countdown)
        #expect(countdown?.text == "Weekly · may run out in about 2.5 hours")
        #expect(countdown?.note == "A fast start. The estimate is only a guide.")

        let almostGone = Self.window(used: 0.9, resetsAt: opened)
        let almost = BurnRate.reading(for: almostGone, now: Self.now)
        #expect(almost?.earlyPace == true)
        #expect((almost?.timeToExhaustion ?? .infinity) < 15 * 60)
        #expect(BurnRate.cardLine(
            for: almostGone, reading: almost!, horizon: 6 * 3600, softHint: true, beforeReset: true
        )?.text == "Weekly · may run out in under 15 minutes")

        let later = Self.window(used: 0.4, resetsAt: Self.now.addingTimeInterval(604_800 * 0.90))
        let laterReading = BurnRate.reading(for: later, now: Self.now)
        #expect(laterReading != nil)
        #expect(laterReading?.earlyPace == false)
        #expect(BurnRate.cardLine(
            for: later, reading: laterReading!, horizon: 48 * 3600, softHint: true, beforeReset: true
        )?.note == nil)

        let unopened = Self.window(used: 0.4, resetsAt: Self.now.addingTimeInterval(604_800))
        #expect(BurnRate.reading(for: unopened, now: Self.now) == nil)

        let week = Self.named(
            "week", kind: .weekly, used: 0.4, seconds: 604_800,
            resetsAt: opened, reportsLength: true
        )
        let five = Self.named(
            "five", kind: .fiveHour, used: 0.4, seconds: 18_000,
            resetsAt: Self.now.addingTimeInterval(10_000), reportsLength: true
        )
        let shown = BurnRate.forecastLine(
            for: week, among: [five, week], showsForecast: true,
            horizon: 6 * 3600, softHint: false, beforeReset: false, now: Self.now
        )
        #expect(shown?.tone == .countdown)
        #expect(shown?.note == "A fast start. The estimate is only a guide.")
        #expect(BurnRate.forecastLine(
            for: five, among: [five, week], showsForecast: true,
            horizon: 6 * 3600, softHint: true, beforeReset: true, now: Self.now
        ) == nil)
        #expect(BurnRate.forecastLine(
            for: week, among: [five, week], showsForecast: false,
            horizon: 6 * 3600, softHint: true, beforeReset: true, now: Self.now
        ) == nil)

        LocalizationSource.use(.chineseSimplified)
        let chinese = BurnRate.cardLine(
            for: burst, reading: burstReading!, horizon: 6 * 3600, softHint: true, beforeReset: true
        )
        #expect(chinese?.text == "按当前速度，重置前约 1天8小时 会用尽。")
        #expect(chinese?.note == "开头偏快，预估仅供参考。")
        #expect(BurnRate.cardLine(
            for: heavy, reading: heavyReading!, horizon: 6 * 3600, softHint: false, beforeReset: false
        )?.text == "每周 · 约 2.5 小时后用尽")
    }

    @Test("A hold keeps its language, and ending it puts the previous one back")
    func holdRestoresThePreviousLanguage() {
        let outer = LocalizationSource.hold(.english)
        defer { outer.end() }
        #expect(String.localized("A fast start. The estimate is only a guide.") == "A fast start. The estimate is only a guide.")
        let inner = LocalizationSource.hold(.chineseSimplified)
        #expect(String.localized("A fast start. The estimate is only a guide.") == "开头偏快，预估仅供参考。")
        inner.end()
        #expect(String.localized("A fast start. The estimate is only a guide.") == "A fast start. The estimate is only a guide.")
    }

    @Test("Codex 5-hour and weekly windows forecast when the reply states a length and a reset")
    func codexWindowsForecast() {
        let http: [String: Any] = [
            "plan_type": "plus",
            "rate_limit": [
                "primary_window": [
                    "used_percent": 70,
                    "limit_window_seconds": "18000",
                    "reset_at": (Self.now.timeIntervalSince1970 + 4 * 3600) * 1000,
                ],
                "secondary_window": [
                    "used_percent": 40,
                    "limit_window_seconds": 604_800,
                    "reset_after_seconds": 3 * 86_400,
                ],
            ] as [String: Any],
        ]
        let parsed = CodexUsageService.parseUsageResponse(http, for: AccountKey(.codex), now: Self.now)
        #expect(parsed.windows.count == 2)
        let fiveHour = parsed.windows.first { $0.kind == .fiveHour }
        let weekly = parsed.windows.first { $0.kind == .weekly }
        #expect(fiveHour?.reportsLength == true)
        #expect(fiveHour?.windowSeconds == 18_000)
        #expect(fiveHour?.resetsAt == Self.now.addingTimeInterval(4 * 3600))
        let fiveReading = fiveHour.flatMap { BurnRate.reading(for: $0, now: Self.now) }
        #expect(fiveReading?.exhaustsBeforeReset == true)
        #expect((fiveReading?.timeToExhaustion ?? 0) < 6 * 3600)

        #expect(weekly?.reportsLength == true)
        #expect(weekly?.resetsAt == Self.now.addingTimeInterval(3 * 86_400))
        #expect(BurnRate.reading(for: weekly!, now: Self.now) != nil)

        let missing: [String: Any] = [
            "rate_limit": [
                "primary_window": [
                    "used_percent": 70,
                    "reset_at": Self.now.timeIntervalSince1970 + 4 * 3600,
                ],
            ],
        ]
        let quiet = CodexUsageService.parseUsageResponse(missing, for: AccountKey(.codex), now: Self.now)
        #expect(quiet.windows.first?.reportsLength == false)
        #expect(quiet.windows.first.flatMap { BurnRate.reading(for: $0, now: Self.now) } == nil)

        let flagged: [String: Any] = [
            "rate_limit": [
                "primary_window": ["used_percent": true, "limit_window_seconds": 18_000],
            ],
        ]
        #expect(CodexUsageService.parseUsageResponse(flagged, for: AccountKey(.codex), now: Self.now).windows.isEmpty)
    }

    @Test("The app-server reply uses the same length and reset rules")
    func codexAppServerForecast() {
        let server: [String: Any] = [
            "rateLimits": [
                "primary": [
                    "usedPercent": 70,
                    "windowDurationMins": "300",
                    "resetAfterSeconds": 4 * 3600,
                ] as [String: Any],
            ],
        ]
        let parsed = CodexUsageService.parseAppServerResponse(server, now: Self.now)
        let window = parsed.windows.first
        #expect(window?.kind == .fiveHour)
        #expect(window?.reportsLength == true)
        #expect(window?.resetsAt == Self.now.addingTimeInterval(4 * 3600))
        #expect(window.flatMap { BurnRate.reading(for: $0, now: Self.now) }?.exhaustsBeforeReset == true)
    }

    @Test("An idle weekly limit still says it lasts, including when the length is only a sort key")
    func idleWeeklyLastsWithoutAStatedLength() {
        let week = Self.named(
            "week", kind: .weekly, used: 0, seconds: 604_800,
            resetsAt: Self.now.addingTimeInterval(500_000), reportsLength: false
        )
        let five = Self.named(
            "five", kind: .fiveHour, used: 0, seconds: 18_000,
            resetsAt: Self.now.addingTimeInterval(10_000), reportsLength: true
        )
        let line = BurnRate.forecastLine(
            for: week, among: [five, week], showsForecast: true,
            horizon: 6 * 3600, softHint: true, beforeReset: true, now: Self.now
        )
        #expect(line?.tone == .lasts)
        let reading = BurnRate.reading(for: week, now: Self.now)
        #expect(reading?.exhaustsBeforeReset == false)
        #expect(reading?.timeToExhaustion == nil)
        #expect(line?.text.isEmpty == false)

        let english = LocalizationSource.bundle(for: .english)
        let chinese = LocalizationSource.bundle(for: .chineseSimplified)
        #expect(english.localizedString(forKey: "Expected to last the window", value: nil, table: nil) == "Expected to last the window")
        #expect(chinese.localizedString(forKey: "Expected to last the window", value: nil, table: nil) == "预计可维持到本轮重置")

        #expect(BurnRate.forecastLine(
            for: week, among: [five, week], showsForecast: false,
            horizon: 6 * 3600, softHint: true, beforeReset: true, now: Self.now
        ) == nil)
        #expect(BurnRate.forecastLine(
            for: five, among: [five, week], showsForecast: true,
            horizon: 6 * 3600, softHint: true, beforeReset: true, now: Self.now
        ) == nil)

        let light = Self.named(
            "week", kind: .weekly, used: 0.04, seconds: 604_800,
            resetsAt: Self.now.addingTimeInterval(500_000), reportsLength: false
        )
        #expect(BurnRate.forecastLine(
            for: light, among: [light], showsForecast: true,
            horizon: 6 * 3600, softHint: true, beforeReset: true, now: Self.now
        )?.tone == .lasts)

        let edge = Self.named(
            "week", kind: .weekly, used: BurnRate.earlyQuietUsed, seconds: 604_800,
            resetsAt: Self.now.addingTimeInterval(500_000), reportsLength: false
        )
        #expect(BurnRate.reading(for: edge, now: Self.now)?.exhaustsBeforeReset == false)
        #expect(BurnRate.forecastLine(
            for: edge, among: [edge], showsForecast: true,
            horizon: 6 * 3600, softHint: true, beforeReset: true, now: Self.now
        )?.tone == .lasts)

        let spent = Self.named(
            "week", kind: .weekly, used: 0.4, seconds: 604_800,
            resetsAt: Self.now.addingTimeInterval(500_000), reportsLength: false
        )
        #expect(BurnRate.reading(for: spent, now: Self.now) == nil)

        let past = Self.named(
            "week", kind: .weekly, used: 0, seconds: 604_800,
            resetsAt: Self.now.addingTimeInterval(-60), reportsLength: false
        )
        #expect(BurnRate.reading(for: past, now: Self.now) == nil)

        let stated = BurnRate.reading(
            for: Self.window(used: 0, resetsAt: Self.now.addingTimeInterval(302_400)),
            now: Self.now
        )
        #expect(stated?.exhaustsBeforeReset == false)
        #expect(stated?.timeToExhaustion == nil)
    }

    /// The panel Harris opened: Kimi at 89% left on the five-hour limit and
    /// 94% left on the week, reset still days away. The week states no length,
    /// so nothing is divided. Six percent used is light, and the line says the
    /// week lasts. The five-hour row is not that line. The same six percent on
    /// a stated length that has barely opened still divides.
    @Test("A lightly used week with no stated length still says it will last")
    func lightUnstatedWeekStillSaysItLasts() throws {
        let held = LocalizationSource.hold(.english)
        defer { held.end() }

        let fiveReset = Self.now.addingTimeInterval(96 * 60)
        let weekReset = Self.now.addingTimeInterval(2 * 86_400 + 8 * 3_600 + 36 * 60)
        let windows = KimiCodeUsageService.windows(from: try Self.kimiReply(
            fiveReset: fiveReset, weekReset: weekReset
        ))
        let weekly = try #require(windows.first { $0.kind == .weekly })
        let five = try #require(windows.first { $0.kind == .fiveHour })

        #expect(weekly.reportsLength == false)
        #expect(abs(weekly.usedFraction - 0.06) < 0.000_001)
        #expect(weekly.percentText(remaining: true) == "94%")
        #expect(five.reportsLength == true)
        #expect(abs(five.usedFraction - 0.11) < 0.000_001)
        #expect(five.percentText(remaining: true) == "89%")

        let fivePace = BurnRate.reading(for: five, now: Self.now)
        #expect(fivePace?.exhaustsBeforeReset == false)
        #expect(fivePace?.timeToExhaustion == nil)
        #expect(fivePace?.earlyPace == false)

        let line = BurnRate.forecastLine(
            for: weekly, among: windows, showsForecast: true,
            horizon: 6 * 3600, softHint: true, beforeReset: true, now: Self.now
        )
        #expect(line?.tone == .lasts)
        #expect(line?.text == "Expected to last the window")
        #expect(line?.note == nil)
        #expect(BurnRate.forecastLine(
            for: five, among: windows, showsForecast: true,
            horizon: 6 * 3600, softHint: true, beforeReset: true, now: Self.now
        ) == nil)
        #expect(BurnRate.forecastLine(
            for: weekly, among: windows, showsForecast: false,
            horizon: 6 * 3600, softHint: true, beforeReset: true, now: Self.now
        ) == nil)

        let reading = BurnRate.reading(for: weekly, now: Self.now)
        #expect(reading?.exhaustsBeforeReset == false)
        #expect(reading?.timeToExhaustion == nil)
        #expect(reading?.earlyPace == false)

        let mid = Self.window(used: 0.06, resetsAt: Self.now.addingTimeInterval(604_800 * 0.34))
        let midReading = try #require(BurnRate.reading(for: mid, now: Self.now))
        #expect(midReading.exhaustsBeforeReset == false)
        #expect(midReading.earlyPace == false)
        #expect(BurnRate.cardLine(
            for: mid, reading: midReading, horizon: 6 * 3600, softHint: true, beforeReset: true
        )?.tone == .lasts)

        let early = Self.window(used: 0.06, resetsAt: Self.now.addingTimeInterval(604_800 * 0.99))
        let earlyReading = try #require(BurnRate.reading(for: early, now: Self.now))
        #expect(earlyReading.earlyPace == true)
        #expect(earlyReading.exhaustsBeforeReset == true)
        #expect(BurnRate.cardLine(
            for: early, reading: earlyReading, horizon: 6 * 3600, softHint: true, beforeReset: true
        )?.note == "A fast start. The estimate is only a guide.")

        #expect(BurnRate.lightUnstatedUsed > 0.11)
        let stillLight = Self.window(used: 0.11, resetsAt: weekReset, reportsLength: false)
        #expect(BurnRate.forecastLine(
            for: stillLight, among: [stillLight], showsForecast: true,
            horizon: 6 * 3600, softHint: true, beforeReset: true, now: Self.now
        )?.tone == .lasts)

        let under = Self.window(
            used: BurnRate.lightUnstatedUsed - 0.001,
            resetsAt: weekReset,
            reportsLength: false
        )
        #expect(BurnRate.reading(for: under, now: Self.now)?.exhaustsBeforeReset == false)

        let ceiling = Self.window(
            used: BurnRate.lightUnstatedUsed, resetsAt: weekReset, reportsLength: false
        )
        #expect(BurnRate.reading(for: ceiling, now: Self.now) == nil)

        let spent = Self.window(used: 0.4, resetsAt: weekReset, reportsLength: false)
        #expect(BurnRate.reading(for: spent, now: Self.now) == nil)

        let past = Self.window(
            used: 0.06, resetsAt: Self.now.addingTimeInterval(-60), reportsLength: false
        )
        #expect(BurnRate.reading(for: past, now: Self.now) == nil)

        #expect(BurnRate.reading(
            for: Self.window(used: 0.06, resetsAt: nil, reportsLength: false), now: Self.now
        ) == nil)
        #expect(BurnRate.reading(
            for: Self.window(used: 0.04, resetsAt: nil, reportsLength: false), now: Self.now
        )?.exhaustsBeforeReset == false)

        LocalizationSource.use(.chineseSimplified)
        let chinese = BurnRate.forecastLine(
            for: weekly, among: windows, showsForecast: true,
            horizon: 6 * 3600, softHint: true, beforeReset: true, now: Self.now
        )
        #expect(chinese?.text == "预计可维持到本轮重置")
        #expect(chinese?.note == nil)
    }

    /// The panel Harris opened after 1.5.31: Kimi at about 18% left on the
    /// five-hour limit and about 70% left on the week, both resets still
    /// ahead. The week states no length and is already past light use, so
    /// that row stays quiet. The five-hour window states five hours and runs
    /// out before its reset, so the card writes a time under that row. A
    /// light week beside the same five-hour pace still says it lasts. A
    /// five-hour window that will last stays quiet. Notices still follow
    /// the weekly limit only.
    @Test("A fast length-stated window shows when it runs out, and a light week still says it lasts")
    func fastStatedWindowShowsExhaustionBesideAQuietWeek() throws {
        let held = LocalizationSource.hold(.english)
        defer { held.end() }

        let fiveReset = Self.now.addingTimeInterval(4 * 3_600)
        let weekReset = Self.now.addingTimeInterval(2 * 86_400 + 6 * 3_600)
        let windows = KimiCodeUsageService.windows(from: try Self.kimiReply(
            fiveRemaining: "18", weekUsed: "30", fiveReset: fiveReset, weekReset: weekReset
        ))
        let weekly = try #require(windows.first { $0.kind == .weekly })
        let five = try #require(windows.first { $0.kind == .fiveHour })

        #expect(weekly.reportsLength == false)
        #expect(abs(weekly.usedFraction - 0.30) < 0.000_001)
        #expect(weekly.percentText(remaining: true) == "70%")
        #expect(five.reportsLength == true)
        #expect(abs(five.usedFraction - 0.82) < 0.000_001)
        #expect(five.percentText(remaining: true) == "18%")
        #expect(weekly.resetsAt.map { $0 > Self.now } == true)
        #expect(five.resetsAt.map { $0 > Self.now } == true)

        #expect(ExhaustionEstimate.windows(in: windows).map(\.id) == [weekly.id])
        #expect(!ExhaustionEstimate.includes(five, among: windows))
        #expect(BurnRate.reading(for: weekly, now: Self.now) == nil)

        let pace = try #require(BurnRate.reading(for: five, now: Self.now))
        #expect(pace.exhaustsBeforeReset == true)
        #expect(pace.earlyPace == false)
        let untilEmpty = try #require(pace.timeToExhaustion)
        #expect(untilEmpty < fiveReset.timeIntervalSince(Self.now))
        #expect(untilEmpty < 15 * 60)

        let line = BurnRate.forecastLine(
            for: five, among: windows, showsForecast: true,
            horizon: 6 * 3600, softHint: true, beforeReset: true, now: Self.now
        )
        #expect(line?.tone == .countdown)
        #expect(line?.text == "5-hour · may run out in under 15 minutes")
        #expect(line?.note == nil)
        #expect(BurnRate.forecastLine(
            for: weekly, among: windows, showsForecast: true,
            horizon: 6 * 3600, softHint: true, beforeReset: true, now: Self.now
        ) == nil)
        #expect(BurnRate.forecastLine(
            for: five, among: windows, showsForecast: false,
            horizon: 6 * 3600, softHint: true, beforeReset: true, now: Self.now
        ) == nil)

        let pastHorizon = BurnRate.forecastLine(
            for: five, among: windows, showsForecast: true,
            horizon: 60, softHint: false, beforeReset: true, now: Self.now
        )
        #expect(pastHorizon?.tone == .beforeReset)
        #expect(BurnRate.forecastLine(
            for: five, among: windows, showsForecast: true,
            horizon: 60, softHint: false, beforeReset: false, now: Self.now
        ) == nil)

        let lightWindows = KimiCodeUsageService.windows(from: try Self.kimiReply(
            fiveRemaining: "18", weekUsed: "6", fiveReset: fiveReset, weekReset: weekReset
        ))
        let lightWeek = try #require(lightWindows.first { $0.kind == .weekly })
        let lightFive = try #require(lightWindows.first { $0.kind == .fiveHour })
        let lasts = BurnRate.forecastLine(
            for: lightWeek, among: lightWindows, showsForecast: true,
            horizon: 6 * 3600, softHint: true, beforeReset: true, now: Self.now
        )
        #expect(lasts?.tone == .lasts)
        #expect(lasts?.text == "Expected to last the window")
        #expect(BurnRate.forecastLine(
            for: lightFive, among: lightWindows, showsForecast: true,
            horizon: 6 * 3600, softHint: true, beforeReset: true, now: Self.now
        )?.tone == .countdown)

        let calmFiveReset = Self.now.addingTimeInterval(96 * 60)
        let calm = KimiCodeUsageService.windows(from: try Self.kimiReply(
            fiveRemaining: "89", weekUsed: "30", fiveReset: calmFiveReset, weekReset: weekReset
        ))
        let calmFive = try #require(calm.first { $0.kind == .fiveHour })
        let calmWeek = try #require(calm.first { $0.kind == .weekly })
        #expect(BurnRate.reading(for: calmFive, now: Self.now)?.exhaustsBeforeReset == false)
        #expect(BurnRate.forecastLine(
            for: calmFive, among: calm, showsForecast: true,
            horizon: 6 * 3600, softHint: true, beforeReset: true, now: Self.now
        ) == nil)
        #expect(BurnRate.forecastLine(
            for: calmWeek, among: calm, showsForecast: true,
            horizon: 6 * 3600, softHint: true, beforeReset: true, now: Self.now
        ) == nil)

        let statedWeek = Self.named(
            "week", kind: .weekly,
            used: Self.pace(remaining: 4 * 3600),
            seconds: 604_800,
            resetsAt: Self.now.addingTimeInterval(302_400),
            reportsLength: true
        )
        let fastFive = Self.named(
            "five", kind: .fiveHour, used: 0.82, seconds: 18_000,
            resetsAt: fiveReset, reportsLength: true
        )
        #expect(BurnRate.forecastLine(
            for: statedWeek, among: [fastFive, statedWeek], showsForecast: true,
            horizon: 6 * 3600, softHint: false, beforeReset: false, now: Self.now
        )?.text == "Weekly · may run out in about 4 hours")
        #expect(BurnRate.forecastLine(
            for: fastFive, among: [fastFive, statedWeek], showsForecast: true,
            horizon: 6 * 3600, softHint: true, beforeReset: true, now: Self.now
        )?.text == "5-hour · may run out in under 15 minutes")

        let earlyFive = Self.named(
            "five", kind: .fiveHour, used: 0.20, seconds: 18_000,
            resetsAt: Self.now.addingTimeInterval(17_640), reportsLength: true
        )
        let earlyLine = BurnRate.forecastLine(
            for: earlyFive, among: [earlyFive, lightWeek], showsForecast: true,
            horizon: 6 * 3600, softHint: true, beforeReset: true, now: Self.now
        )
        #expect(earlyLine?.tone == .countdown)
        #expect(earlyLine?.text == "5-hour · may run out in about 30 minutes")
        #expect(earlyLine?.note == "A fast start. The estimate is only a guide.")

        let day = Self.named(
            "day", kind: .daily, used: 0.8, seconds: 86_400,
            resetsAt: Self.now.addingTimeInterval(6 * 3_600), reportsLength: true
        )
        let quietWeek = Self.named(
            "week", kind: .weekly, used: 0.30, seconds: 604_800,
            resetsAt: weekReset, reportsLength: false
        )
        #expect(BurnRate.forecastLine(
            for: day, among: [day, quietWeek], showsForecast: true,
            horizon: 6 * 3600, softHint: true, beforeReset: true, now: Self.now
        )?.text == "Daily · may run out in about 4.5 hours")
        #expect(BurnRate.forecastLine(
            for: quietWeek, among: [day, quietWeek], showsForecast: true,
            horizon: 6 * 3600, softHint: true, beforeReset: true, now: Self.now
        ) == nil)

        let spend = Self.named(
            "spend", kind: .spend, used: 0.9, seconds: 86_400,
            resetsAt: Self.now.addingTimeInterval(3_600), reportsLength: true
        )
        #expect(BurnRate.forecastLine(
            for: spend, among: [spend], showsForecast: true,
            horizon: 6 * 3600, softHint: true, beforeReset: true, now: Self.now
        ) == nil)

        LocalizationSource.use(.chineseSimplified)
        let chinese = BurnRate.forecastLine(
            for: five, among: windows, showsForecast: true,
            horizon: 6 * 3600, softHint: true, beforeReset: true, now: Self.now
        )
        #expect(chinese?.text == "5 小时 · 不到 15 分钟后用尽")
        #expect(chinese?.note == nil)
        #expect(BurnRate.forecastLine(
            for: lightWeek, among: lightWindows, showsForecast: true,
            horizon: 6 * 3600, softHint: true, beforeReset: true, now: Self.now
        )?.text == "预计可维持到本轮重置")
        #expect(BurnRate.forecastLine(
            for: earlyFive, among: [earlyFive], showsForecast: true,
            horizon: 6 * 3600, softHint: true, beforeReset: true, now: Self.now
        )?.note == "开头偏快，预估仅供参考。")
    }

    @Test("Lasting is green and regular; a pace that may not last is amber and a step heavier")
    @MainActor
    func forecastInkFollowsTheTone() {
        let lasts = ForecastLineInk.style(for: .lasts)
        #expect(lasts.hue == .green)
        #expect(lasts.weight == .regular)
        #expect(lasts.usageColor == .pulseGood)
        #expect(lasts.fontWeight == Font.Weight.regular)
        #expect(lasts.usageColor != .pulseWarning)
        #expect(lasts.usageColor != .pulseCaution)

        for tone: BurnRate.CardLine.Tone in [.countdown, .beforeReset, .hint] {
            let ink = ForecastLineInk.style(for: tone)
            #expect(ink.hue == .amber)
            #expect(ink.weight == .medium)
            #expect(ink.usageColor == .pulseCaution)
            #expect(ink.fontWeight == Font.Weight.medium)
            #expect(ink.usageColor != .pulseWarning)
            #expect(ink.usageColor != .pulseGood)
        }

        #expect(ForecastLineInk.opacity > 0)
        #expect(ForecastLineInk.opacity < 1)
        #expect(ForecastLineInk.style(for: .lasts).lineColor != ForecastLineInk.style(for: .countdown).lineColor)
    }

    /// Kimi's two limits as the panel showed them: 89% left on the five-hour
    /// window, 94% left on the week, both resets still ahead. Counts are
    /// strings, the same shape as the live reply.
    private static func kimiReply(
        fiveRemaining: String = "89",
        weekUsed: String = "6",
        fiveReset: Date,
        weekReset: Date
    ) throws -> KimiCodeUsageService.Reply {
        let json = """
        {"limits":[{"window":{"duration":5,"timeUnit":"TIME_UNIT_HOUR"},"detail":{"limit":"100","remaining":"\(fiveRemaining)","resetTime":"\(Self.iso(fiveReset))"}}],"usage":{"limit":"100","used":"\(weekUsed)","resetTime":"\(Self.iso(weekReset))"}}
        """
        return try JSONDecoder().decode(KimiCodeUsageService.Reply.self, from: Data(json.utf8))
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func named(
        _ id: String,
        kind: UsageWindow.Kind,
        used: Double,
        seconds: Int,
        resetsAt: Date?,
        reportsLength: Bool
    ) -> UsageWindow {
        UsageWindow(
            id: id,
            kind: kind,
            scope: nil,
            usedFraction: used,
            windowSeconds: seconds,
            resetsAt: resetsAt,
            reportsLength: reportsLength
        )
    }
}
