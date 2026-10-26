import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Pulse

/// The Token spend pane's "Token activity" series, on a fixed clock and a UTC
/// calendar: the twelve-month window, which column a day falls in with the week
/// starting on Monday or on Sunday, the running total, the difference between a
/// quiet day and a day nothing was recorded for, and the colour steps.
@Suite("Token activity")
struct TokenActivityTests {
    /// Monday 5 October 2026.
    private static let now = date(2026, 10, 5, hour: 15)

    private static func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private static let monday = calendar(firstWeekday: 2)
    private static let sunday = calendar(firstWeekday: 1)

    private static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        monday.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private static func ledger(
        _ days: [(Date, Int)],
        origin: UsageLedger.Origin = .localTranscripts,
        partial: Bool = false
    ) -> UsageLedger {
        var ledger = UsageLedger(
            origin: origin,
            days: days.map { LedgerDay(date: $0.0, tokens: $0.1, cost: 0, unpricedTokens: 0, models: [:]) },
            earliest: days.map(\.0).min(),
            unpricedModels: [],
            modelNames: [:],
            slots: []
        )
        ledger.hasPartialCounts = partial
        return ledger
    }

    private static func activity(_ days: [(Date, Int)], calendar: Calendar = monday) -> TokenActivity {
        TokenActivity.of([.claudeCode: ledger(days)], now: now, calendar: calendar)
    }

    private static func day(_ activity: TokenActivity, _ date: Date) -> TokenActivity.Day? {
        activity.weeks.flatMap(\.days).compactMap { $0 }.first { $0.date == date }
    }

    // MARK: - The window

    @Test("The window is at most 53 week columns ending today, from the first drawn day a year back")
    func windowBounds() throws {
        let first = Self.date(2024, 1, 1)
        for calendar in [Self.monday, Self.sunday] {
            let result = Self.activity([(first, 5)], calendar: calendar)
            #expect(result.columnCount == 53)
            let drawn = result.weeks.flatMap(\.drawn)
            // 6 October 2025 to 5 October 2026: 365 days, today included.
            #expect(drawn.first?.date == Self.date(2025, 10, 6))
            #expect(drawn.last?.date == Self.date(2026, 10, 5))
            #expect(drawn.count == 365)
            #expect(result.weeks.allSatisfy { $0.days.count == 7 })
            // Every column starts on the calendar's own first weekday.
            #expect(result.weeks.allSatisfy { calendar.component(.weekday, from: $0.start) == calendar.firstWeekday })
        }
    }

    @Test("A leap-year window never needs a 54th column")
    func leapWindow() {
        // Sunday 29 February 2032 is a week's first day for a Sunday calendar.
        for (calendar, today) in [(Self.sunday, Self.date(2032, 2, 29)), (Self.monday, Self.date(2032, 2, 29)),
                                  (Self.monday, Self.date(2028, 2, 29)), (Self.sunday, Self.date(2028, 3, 5))] {
            let result = TokenActivity.of(
                [.codex: Self.ledger([(Self.date(2020, 1, 1), 1)])], now: today, calendar: calendar
            )
            #expect(result.columnCount <= 53)
            #expect(result.weeks.flatMap(\.drawn).last?.date == today)
        }
    }

    @Test("Work older than the window is not in it, but still marks the first record")
    func olderWorkIsOutsideTheWindow() {
        let result = Self.activity([(Self.date(2024, 5, 1), 1_000), (Self.date(2026, 3, 3), 7)])
        #expect(result.total == 7)
        #expect(result.activeDays == 1)
        // Records go back before the window, so every day in it is drawn.
        #expect(result.weeks.flatMap(\.drawn).count == 365)
    }

    // MARK: - Week bucketing

    @Test("With Monday first, Sunday closes the previous column")
    func mondayBuckets() throws {
        let result = Self.activity([(Self.date(2026, 10, 4), 50), (Self.date(2026, 10, 5), 100)])
        let last = try #require(result.weeks.last)
        let before = result.weeks[result.weeks.count - 2]
        #expect(last.days[0]?.tokens == 100)
        #expect(last.tokens == 100)
        #expect(before.days[6]?.tokens == 50)
        #expect(before.tokens == 50)
    }

    @Test("With Sunday first, Sunday and Monday share a column")
    func sundayBuckets() throws {
        let result = Self.activity([(Self.date(2026, 10, 4), 50), (Self.date(2026, 10, 5), 100)], calendar: Self.sunday)
        let last = try #require(result.weeks.last)
        #expect(last.days[0]?.tokens == 50)
        #expect(last.days[1]?.tokens == 100)
        #expect(last.tokens == 150)
        #expect(result.total == 150)
    }

    @Test("A week's range is clipped to the drawn days")
    func clippedRange() throws {
        let result = Self.activity([(Self.date(2020, 1, 1), 1), (Self.date(2026, 10, 5), 9)], calendar: Self.sunday)
        let last = try #require(result.weeks.last)
        #expect(last.range == Self.date(2026, 10, 4)...Self.date(2026, 10, 5))
        let first = try #require(result.weeks.first)
        #expect(first.range?.lowerBound == Self.date(2025, 10, 6))
    }

    // MARK: - Quiet days, days with no data

    @Test("Days before the first record and after today are not drawn; days in between are quiet")
    func quietIsNotMissing() throws {
        let first = Self.date(2026, 1, 15)
        let result = Self.activity([(first, 40), (Self.date(2026, 1, 17), 60)])

        #expect(Self.day(result, Self.date(2026, 1, 14)) == nil)
        #expect(Self.day(result, first)?.tokens == 40)
        // Nothing was worked on the 16th and that is a measurement.
        #expect(Self.day(result, Self.date(2026, 1, 16)) == TokenActivity.Day(date: Self.date(2026, 1, 16), tokens: 0))
        #expect(Self.day(result, Self.date(2026, 10, 5)) == TokenActivity.Day(date: Self.date(2026, 10, 5), tokens: 0))
        #expect(Self.day(result, Self.date(2026, 10, 6)) == nil)
        // Columns before the first record are not columns of data.
        let early = try #require(result.weeks.first)
        #expect(!early.hasData)
        #expect(early.range == nil)
        // In the last column only Monday (today) is drawn.
        let last = try #require(result.weeks.last)
        #expect(last.days.compactMap { $0 }.count == 1)
    }

    @Test("A midnight DST start does not knock the days after it off their keys")
    func midnightDaylightSaving() throws {
        // Cairo springs forward at 00:00 on the last Friday of April: that day
        // starts at 01:00, and stepping by a day used to stay at 01:00.
        var cairo = Calendar(identifier: .gregorian)
        cairo.timeZone = try #require(TimeZone(identifier: "Africa/Cairo"))
        cairo.firstWeekday = 2
        let september = try #require(cairo.date(from: DateComponents(year: 2026, month: 9, day: 1)))
        let now = try #require(cairo.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 15)))
        let result = TokenActivity.of([.claudeCode: Self.ledger([(september, 70)])], now: now, calendar: cairo)
        let drawn = result.weeks.flatMap(\.drawn)
        #expect(drawn.first { $0.date == september }?.tokens == 70)
        #expect(result.total == 70)
        #expect(drawn.last?.date == cairo.startOfDay(for: now))
    }

    @Test("Days in the window before the first record are outlines, never days with a count")
    func unrecordedOutlines() throws {
        let first = Self.date(2026, 1, 15)
        let result = Self.activity([(first, 40)])
        let early = try #require(result.weeks.first)
        #expect(early.unrecorded == Array(repeating: true, count: 7))
        // The column holding the first record: Mon 12 – Wed 14 outlined, Thu 15 on drawn.
        let column = try #require(result.weeks.first { $0.days.contains { $0?.date == first } })
        #expect(column.unrecorded == [true, true, true, false, false, false, false])
        // Today's column: today is drawn, the days after it are nothing at all.
        let last = try #require(result.weeks.last)
        #expect(last.unrecorded == Array(repeating: false, count: 7))
        // A history longer than the window has nothing to outline.
        let long = Self.activity([(Self.date(2020, 1, 1), 1)])
        #expect(long.weeks.allSatisfy { !$0.unrecorded.contains(true) })
    }

    @Test("Nothing read, only future work, or only a provider's own statistics draws nothing")
    func noData() {
        #expect(TokenActivity.of([:], now: Self.now, calendar: Self.monday).isEmpty)
        #expect(Self.activity([(Self.date(2026, 10, 6), 10)]).isEmpty)
        let statistics = TokenActivity.of(
            [.claudeCode: Self.ledger([(Self.date(2026, 3, 3), 10)], origin: .providerStatistics)],
            now: Self.now, calendar: Self.monday
        )
        #expect(statistics.isEmpty)
        #expect(statistics.total == 0)
        #expect(statistics.points.isEmpty)
    }

    @Test("A zero-token row is not a record")
    func zeroRowIsNotARecord() {
        let result = Self.activity([(Self.date(2026, 3, 3), 0)])
        #expect(result.isEmpty)
    }

    @Test("Agents add up on a day, and the earliest record across all of them starts the drawing")
    func agentsAdd() {
        let march = Self.date(2026, 3, 3)
        let result = TokenActivity.of(
            [
                .claudeCode: Self.ledger([(march, 30), (Self.date(2026, 5, 1), 5)]),
                .codex: Self.ledger([(march, 12), (Self.date(2026, 2, 20), 1)]),
            ],
            now: Self.now, calendar: Self.monday
        )
        #expect(Self.day(result, march)?.tokens == 42)
        #expect(Self.day(result, Self.date(2026, 2, 20))?.tokens == 1)
        #expect(Self.day(result, Self.date(2026, 2, 19)) == nil)
        #expect(result.total == 48)
        #expect(result.activeDays == 3)
    }

    @Test("Partial counts are flagged only when a ledger that contributed is partial")
    func partialFlag() {
        let day = Self.date(2026, 3, 3)
        let partial = TokenActivity.of([.codex: Self.ledger([(day, 3)], partial: true)], now: Self.now, calendar: Self.monday)
        #expect(partial.hasPartialCounts)
        // A partial ledger whose work is all outside the window adds nothing to it.
        let outside = TokenActivity.of(
            [.codex: Self.ledger([(Self.date(2023, 1, 1), 3)], partial: true), .claudeCode: Self.ledger([(day, 3)])],
            now: Self.now, calendar: Self.monday
        )
        #expect(!outside.hasPartialCounts)
    }

    // MARK: - Cumulative

    @Test("The running total climbs from the first day to the window's total")
    func cumulative() throws {
        let result = Self.activity([
            (Self.date(2026, 3, 1), 10), (Self.date(2026, 3, 3), 20), (Self.date(2026, 9, 1), 5),
        ])
        let points = result.points
        #expect(points.count == result.weeks.flatMap(\.drawn).count)
        #expect(points.first?.date == Self.date(2026, 3, 1))
        #expect(points.first?.running == 10)
        #expect(points.last?.date == Self.date(2026, 10, 5))
        #expect(points.last?.running == 35)
        #expect(points.last?.running == result.total)
        #expect(zip(points, points.dropFirst()).allSatisfy { $0.running <= $1.running && $0.position < $1.position })
        #expect(points.allSatisfy { $0.position > 0 && $0.position < Double(result.columnCount) })
        // 1 March 2026 is a Sunday: column row 6 with Monday first.
        let row = (Double(points[0].position) - Double(Int(points[0].position))) * 7 - 0.5
        #expect(Int(row.rounded()) == 6)
    }

    // MARK: - Steps

    @Test("Steps are the quartiles of the days with work; a quiet day is step 0")
    func steps() {
        let days = (1...8).map { (Self.date(2026, 4, $0), $0 * 10) }
        let result = Self.activity(days + [(Self.date(2026, 4, 9), 0)])
        #expect(result.cuts == [20, 40, 60])
        #expect(result.step(for: 0) == 0)
        let steps = [10, 20, 30, 40, 50, 60, 70, 80].map { result.step(for: $0) }
        #expect(steps == [1, 1, 2, 2, 3, 3, 4, 4])
    }

    @Test("One huge day does not flatten the rest into the palest step")
    func outlierDoesNotFlatten() {
        let days = (1...7).map { (Self.date(2026, 4, $0), $0 * 100) } + [(Self.date(2026, 4, 8), 1_000_000_000)]
        let result = Self.activity(days)
        #expect(result.step(for: 1_000_000_000) == 4)
        #expect(result.step(for: 700) >= 3)
        #expect(result.step(for: 100) == 1)
    }

    @Test("A single active day is the palest step, and nothing but zeros has no steps")
    func fewDays() {
        let one = Self.activity([(Self.date(2026, 4, 1), 9)])
        #expect(one.cuts == [9, 9, 9])
        #expect(one.step(for: 9) == 1)
        #expect(one.activeDays == 1)
    }

    // MARK: - Month labels

    @Test("Month labels sit at each month's first day, evenly as the calendar, and drop one that would crowd")
    func monthLabels() {
        let result = Self.activity([(Self.date(2024, 1, 1), 1)])
        let marks = result.monthMarks(calendar: Self.monday)
        let months = marks.map { Self.monday.component(.month, from: $0.date) }
        // October 2025 through the running October 2026, which is named even
        // though it starts in the last columns.
        #expect(months == [10, 11, 12, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        #expect(marks.first?.position == 0)
        // Thursday 1 October 2026 is the fourth day of the column before today's.
        #expect(marks.last?.column == result.weeks.count - 2)
        #expect(marks.last?.position == Double(result.weeks.count - 2) + 3.0 / 7)
        // Every whole month is 28 to 31 days: 4 to 4 3/7 columns, never 5.
        let gaps = zip(marks.dropFirst(), marks.dropFirst(2)).map { $1.position - $0.position }
        #expect(gaps.allSatisfy { $0 >= 4 && $0 <= 31.0 / 7 + 1e-9 })
    }

    @Test("A partial first month too short to hold its label is not labelled")
    func crowdedFirstLabel() {
        // Asked on Wednesday 28 October, the window starts on Wednesday 29
        // October 2025: three days of October before Saturday 1 November.
        let wednesday = Self.date(2026, 10, 28, hour: 9)
        let result = TokenActivity.of(
            [.claudeCode: Self.ledger([(Self.date(2020, 1, 1), 1)])], now: wednesday, calendar: Self.monday
        )
        let marks = result.monthMarks(calendar: Self.monday)
        #expect(marks.first.map { Self.monday.component(.month, from: $0.date) } == 11)
        #expect(marks.first?.position == 5.0 / 7)
    }
}

/// Persistence of the chart's view, on an isolated suite like the span's.
@Suite("Token activity preference")
struct TokenActivityPreferenceTests {
    private func withIsolatedDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let (defaults, cleanup) = TestDefaults.make("activityView")
        defer { cleanup() }
        try body(defaults)
    }

    @Test("Nothing chosen opens the daily grid; every view round-trips; an unknown value falls back")
    func roundTrip() {
        withIsolatedDefaults { defaults in
            #expect(ActivityView.default == .daily)
            #expect(AppSettings.storedSpendActivityView(in: defaults) == .daily)
            for view in ActivityView.allCases {
                AppSettings.storeSpendActivityView(view, in: defaults)
                #expect(AppSettings.storedSpendActivityView(in: defaults) == view)
                #expect(AppSettings(spendActivityView: AppSettings.storedSpendActivityView(in: defaults)).spendActivityView == view)
            }
            defaults.set("monthly", forKey: AppSettings.spendActivityViewDefaultsKey)
            #expect(AppSettings.storedSpendActivityView(in: defaults) == .daily)
        }
    }
}

/// The section drawn to PNG, for a person to look at.
///
///     PULSE_ACTIVITY_PREVIEW=/tmp/activity swift test --filter TokenActivityRenderTests
///
/// Hosted in a window that is never shown and drawn with `cacheDisplay`, from a
/// synthetic year (a long quiet stretch, a busy autumn, one huge day). Pins
/// nothing about pixels.
@MainActor
@Suite("Token activity render", .serialized)
struct TokenActivityRenderTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PULSE_ACTIVITY_PREVIEW"] != nil))
    func renderTheViews() throws {
        let destination = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PULSE_ACTIVITY_PREVIEW"]))
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let held = LocalizationSource.hold(.english)
        defer { held.end() }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))!

        // Deterministic and a little lumpy: weekdays busier than weekends, a
        // pause in the summer, one huge day.
        var days: [(Date, Int)] = []
        var state: UInt64 = 7
        func next() -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int(state >> 33)
        }
        let first = calendar.date(from: DateComponents(year: 2025, month: 12, day: 8))!
        var cursor = first
        while cursor <= today {
            let weekday = calendar.component(.weekday, from: cursor)
            let month = calendar.component(.month, from: cursor)
            let weekend = weekday == 1 || weekday == 7
            let paused = month == 7 && calendar.component(.day, from: cursor) < 20
            if !paused, next() % (weekend ? 4 : 10) < (weekend ? 1 : 8) {
                days.append((cursor, (next() % 900 + 40) * 100_000 * (month >= 9 ? 3 : 1)))
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
        }
        days.append((calendar.date(from: DateComponents(year: 2026, month: 4, day: 14))!, 4_800_000_000))
        var ledger = UsageLedger(
            days: days.map { LedgerDay(date: $0.0, tokens: $0.1, cost: 0, unpricedTokens: 0, models: [:]) },
            earliest: first, unpricedModels: [], modelNames: [:], slots: []
        )
        ledger.hasPartialCounts = false
        let activity = TokenActivity.of([.claudeCode: ledger], now: today, calendar: calendar)
        #expect(!activity.isEmpty)

        let languages: [(String, AppLanguage)] = [("zh-Hans", .chineseSimplified), ("en", .english)]
        for (code, language) in languages {
            for scheme in [ColorScheme.light, .dark] {
                for view in ActivityView.allCases {
                    LocalizationSource.use(language)
                    // The narrowest settings window leaves about 450pt of pane
                    // and the widest the render tries is 900.
                    for width in [460.0, 900.0] {
                        let host = NSHostingView(rootView: Harness(
                            activity: activity, view: view, calendar: calendar, scheme: scheme, width: width
                        ))
                        let window = NSWindow(
                            contentRect: NSRect(x: 0, y: 0, width: width, height: 250), styleMask: [.titled],
                            backing: .buffered, defer: false
                        )
                        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                        window.contentView = host
                        window.setContentSize(NSSize(width: width, height: 250))
                        host.layoutSubtreeIfNeeded()
                        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                        host.layoutSubtreeIfNeeded()
                        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                        host.cacheDisplay(in: host.bounds, to: rep)
                        let png = try #require(rep.representation(using: .png, properties: [:]))
                        let name = "\(view.rawValue)-\(code)-\(scheme == .dark ? "dark" : "light")-\(Int(width))"
                        try png.write(to: destination.appendingPathComponent("\(name).png"))
                    }
                }
            }
        }
    }

    private struct Harness: View {
        let activity: TokenActivity
        @State var view: ActivityView
        let calendar: Calendar
        let scheme: ColorScheme
        let width: CGFloat

        init(activity: TokenActivity, view: ActivityView, calendar: Calendar, scheme: ColorScheme, width: CGFloat) {
            self.width = width
            self.activity = activity
            _view = State(initialValue: view)
            self.calendar = calendar
            self.scheme = scheme
        }

        var body: some View {
            TokenActivitySection(activity: activity, view: $view, calendar: calendar)
                .padding(24)
                .frame(width: width, height: 250, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, scheme)
        }
    }
}
