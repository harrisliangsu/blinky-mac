// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import Pulse

/// The floating Token spend summary: its two-week chart, the money it may
/// say, where the window sits, and that a cancelled read cannot publish.
/// Synthetic ledgers only.
///
/// Sentence assertions name the English table. The checks that go through
/// `String.localized` hold English until they have read it.
@Suite("Token spend glance")
struct SpendGlanceTests {
    private static let english = LocalizationSource.bundle(for: .english)
    private static let englishLocale = Locale(identifier: "en_US")
    private static let calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_780_000_000))

    private static func day(_ daysAgo: Int, tokens: Int, cost: Double = 1) -> LedgerDay {
        LedgerDay(
            date: calendar.date(byAdding: .day, value: -daysAgo, to: today)!,
            tokens: tokens,
            cost: cost,
            unpricedTokens: 0,
            models: tokens > 0 ? ["m": tokens] : [:]
        )
    }

    private static func ledger(
        _ days: [LedgerDay],
        origin: UsageLedger.Origin = .localTranscripts,
        partial: Bool = false
    ) -> UsageLedger {
        var ledger = UsageLedger(
            origin: origin,
            days: days,
            earliest: days.first?.date,
            unpricedModels: [],
            modelNames: [:],
            slots: []
        )
        ledger.hasPartialCounts = partial
        return ledger
    }

    private func request(enabled: Bool = true, open: Bool = true, rescan: Int = 0) -> SpendGlanceRead.Request {
        .init(isEnabled: enabled, isOpen: open, rescan: rescan)
    }

    private func scan(_ action: SpendGlanceRead.Action) throws -> (id: UUID, refresh: Bool) {
        let read: (UUID, Bool)? = if case .scan(let id, let refresh) = action { (id, refresh) } else { nil }
        return try #require(read)
    }

    @Test("Opening asks for a cache-backed read, and a second look reuses it")
    func openingDoesNotForceARescan() throws {
        var state = SpendGlanceRead()
        let first = try scan(state.prepare(request()))
        #expect(!first.refresh)
        state.complete(.init(ledgers: [.codex: Self.ledger([Self.day(0, tokens: 40)])], notes: [.codex: ["unreadable"]]), for: first.id)
        state.finish(first.id)
        #expect(state.prepare(request()) == .retain)
        #expect(state.snapshot?.ledgers[.codex]?.allTime.tokens == 40)
        #expect(state.snapshot?.notes[.codex] == ["unreadable"])
    }

    @Test("Closing or switching reading off releases the snapshot", arguments: [false, true])
    func inactiveReleases(disable: Bool) {
        var state = SpendGlanceRead()
        _ = state.prepare(request())
        let action = state.prepare(request(enabled: !disable, open: disable))
        #expect(action == .release)
        #expect(state.snapshot == nil)
        #expect(state.snapshotID == nil)
    }

    @Test("Refresh is the only forced read, and a late result cannot land")
    func refreshAndStaleResult() throws {
        var state = SpendGlanceRead()
        let first = try scan(state.prepare(request()))
        state.complete(.init(), for: first.id)
        state.finish(first.id)

        let rescan = try scan(state.prepare(request(rescan: 1)))
        #expect(rescan.refresh)
        #expect(state.snapshot == nil)
        // The expectation macro cannot call a mutating method, so the result is taken first.
        let staleComplete = state.complete(
            .init(ledgers: [.codex: Self.ledger([Self.day(0, tokens: 1)])]),
            for: first.id
        )
        #expect(!staleComplete)
        #expect(state.snapshot == nil)
        let staleFinish = state.finish(first.id)
        #expect(!staleFinish)

        state.complete(.init(ledgers: [.claudeCode: Self.ledger([Self.day(0, tokens: 8)])]), for: rescan.id)
        let finished = state.finish(rescan.id)
        #expect(finished)
        #expect(state.prepare(request(rescan: 1)) == .retain)
        #expect(state.snapshot?.ledgers[.claudeCode]?.allTime.tokens == 8)

        let dropped = try scan(state.prepare(request(rescan: 2)))
        state.finish(dropped.id)
        let retry = try scan(state.prepare(request(rescan: 2)))
        #expect(!retry.refresh)
    }

    @Test("The mini chart is the last 14 midnights, with gaps before the first record")
    func activityWindow() {
        let activity = SpendGlanceActivity.of(
            [
                .codex: Self.ledger([Self.day(2, tokens: 10), Self.day(0, tokens: 4)]),
                .claudeCode: Self.ledger([Self.day(0, tokens: 6)]),
            ],
            now: Self.today,
            calendar: Self.calendar
        )
        #expect(activity.days.count == SpendGlance.activityDays)
        #expect(activity.days.allSatisfy { $0.date == Self.calendar.startOfDay(for: $0.date) })
        #expect(activity.days.first?.date == Self.calendar.date(byAdding: .day, value: -13, to: Self.today))
        #expect(activity.days.last?.date == Self.today)
        #expect(activity.days.last?.tokens == 10)
        let nils = activity.days.filter { $0.tokens == nil }
        #expect(nils.count == 11)
        let quiet = activity.days.filter { $0.tokens == 0 }
        #expect(quiet.count == 1)
        #expect(!activity.hasPartialCounts)
        #expect(activity.days.contains { $0.date == Self.calendar.date(byAdding: .day, value: -20, to: Self.today)! } == false)
    }

    @Test("A day before any record is not drawn as zero, and statistics are left out")
    func activityWithholds() {
        let onlyZero = SpendGlanceActivity.of(
            [.codex: Self.ledger([Self.day(0, tokens: 0)])],
            now: Self.today,
            calendar: Self.calendar
        )
        #expect(onlyZero.isEmpty)

        let statistics = SpendGlanceActivity.of(
            [.codex: Self.ledger([Self.day(0, tokens: 80)], origin: .providerStatistics)],
            now: Self.today,
            calendar: Self.calendar
        )
        #expect(statistics.isEmpty)

        let oldPartial = SpendGlanceActivity.of(
            [.codex: Self.ledger([Self.day(30, tokens: 12)], partial: true)],
            now: Self.today,
            calendar: Self.calendar
        )
        #expect(!oldPartial.isEmpty)
        #expect(oldPartial.days.allSatisfy { $0.tokens == 0 })
        #expect(!oldPartial.hasPartialCounts)

        let recentPartial = SpendGlanceActivity.of(
            [.codex: Self.ledger([Self.day(1, tokens: 12)], partial: true)],
            now: Self.today,
            calendar: Self.calendar
        )
        #expect(recentPartial.hasPartialCounts)
    }

    @Test("Money follows the Settings total: unavailable, partial, or a real zero")
    func estimate() {
        let empty = SpendSummary()
        #expect(SpendGlance.Estimate.of(empty) == .none)

        var unpriced = SpendSummary()
        unpriced.tokens = 20
        unpriced.unpricedTokens = 20
        unpriced.cost = 0
        #expect(SpendGlance.Estimate.of(unpriced) == .unavailable)

        var partial = SpendSummary()
        partial.tokens = 20
        partial.unpricedTokens = 5
        partial.cost = 1.5
        #expect(SpendGlance.Estimate.of(partial) == .amount(1.5, partial: true))

        var incomplete = SpendSummary()
        incomplete.tokens = 20
        incomplete.cost = 2
        incomplete.hasPartialCounts = true
        #expect(SpendGlance.Estimate.of(incomplete) == .amount(2, partial: true))

        var free = SpendSummary()
        free.tokens = 20
        free.cost = 0
        #expect(SpendGlance.Estimate.of(free) == .amount(0, partial: false))
    }

    @Test("Agents are heaviest first, ties by name, and the list stops at eight")
    func topAgents() {
        var summary = SpendSummary()
        summary.agents = [
            .init(agent: .codex, tokens: 5, cost: 1, unpricedTokens: 0),
            .init(agent: .claudeCode, tokens: 5, cost: 1, unpricedTokens: 5),
            .init(agent: .grok, tokens: 9, cost: 3, unpricedTokens: 1),
            .init(agent: .kimiCLI, tokens: 0, cost: 0, unpricedTokens: 0),
        ]
        let rows = SpendGlance.topAgents(summary)
        #expect(rows.map(\.name) == ["Grok Build", "Claude Code", "Codex"])
        #expect(rows[0].share == 1)
        #expect(rows[0].cost == 3)
        #expect(rows[1].cost == nil)
        #expect(rows[2].share == 5.0 / 9.0)

        let agents = Array(SpendAgent.allCases.prefix(9))
        summary.agents = agents.enumerated().map { index, agent in
            .init(agent: agent, tokens: 100 - index, cost: 1, unpricedTokens: 0)
        }
        let capped = SpendGlance.topAgents(summary)
        #expect(capped.count == SpendGlance.agentLimit)
        #expect(capped.first?.tokens == 100)
        #expect(capped.last?.tokens == 93)
    }

    @Test("A right-hand rail keeps the window on the card's side, inside the screen")
    func placement() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let rail = CGRect(x: 1360, y: 200, width: 64, height: 420)
        let frame = SpendGlancePlacement.frame(rail: rail, edge: .right, screen: screen, cardClearance: 270)
        #expect(frame.maxX <= rail.minX - 270)
        #expect(screen.insetBy(dx: 8, dy: 8).contains(frame))

        let cramped = CGRect(x: 20, y: 200, width: 64, height: 420)
        let flipped = SpendGlancePlacement.frame(rail: cramped, edge: .right, screen: screen, cardClearance: 400)
        #expect(flipped.minX >= cramped.maxX)
        #expect(screen.insetBy(dx: 8, dy: 8).contains(flipped))
    }

    @Test("The share image's text is the summary, not a path or an address")
    func shareOmitsPrivateText() throws {
        var ledger = Self.ledger([Self.day(0, tokens: 30, cost: 2)])
        ledger.sessions = [
            UsageLedger.Session(
                id: "/Users/ada/Library/secret.jsonl",
                name: "rollout-secret",
                title: "ada@example.com",
                project: nil,
                start: Self.today,
                end: Self.today,
                tokens: 30,
                cost: 2
            )
        ]
        let summary = SpendSummary.of([.codex: ledger], overLast: nil, now: Self.today, calendar: Self.calendar)
        #expect(summary.sessions.contains { $0.session.id.contains("/Users/ada") })
        let activity = SpendGlanceActivity.of([.codex: ledger], now: Self.today, calendar: Self.calendar)
        let picture = Self.picture(summary: summary, activity: activity)
        let drawn = picture.drawnText.joined(separator: "\n")
        #expect(!drawn.contains("/Users"))
        #expect(!drawn.contains("secret.jsonl"))
        #expect(!drawn.contains("@"))
        #expect(!drawn.contains("rollout-secret"))
        #expect(picture.agents.map(\.name) == ["Codex"])
        #expect(picture.bars.count == SpendGlance.activityDays)
        #expect(picture.brand == "Blinky")
        #expect(picture.span == "Last 7 days")
    }

    @Test("The poster always names Blinky, and leaves out an empty agents list and an empty chart")
    func posterOmitsEmptySections() {
        let empty = Self.picture()
        #expect(empty.brand == "Blinky")
        #expect(empty.drawnText.first == "Blinky")
        #expect(empty.drawnText.last == "Blinky")
        #expect(empty.span == "Last 7 days")
        #expect(empty.tokens == "Nothing in this span")
        #expect(empty.cost == nil)
        #expect(empty.costNote == nil)
        #expect(empty.agents.isEmpty)
        #expect(empty.agentsTitle.isEmpty)
        #expect(empty.bars.isEmpty)
        #expect(empty.activityTitle.isEmpty)
        #expect(empty.footnotes.isEmpty)
        #expect(!empty.drawnText.contains("By agent"))
        #expect(!empty.drawnText.contains("Last 14 days"))

        var priced = SpendSummary()
        priced.tokens = 8
        priced.cost = 1
        let noAgents = Self.picture(summary: priced)
        #expect(noAgents.brand == "Blinky")
        #expect(noAgents.tokens == "8 tokens")
        #expect(noAgents.cost == SpendFormat.money(1, locale: Self.englishLocale) as String?)
        #expect(noAgents.costNote == nil)
        #expect(noAgents.agents.isEmpty)
        #expect(!noAgents.drawnText.contains("By agent"))
    }

    @Test("A priced poster shows the span, the tokens, the cost, the agents, and fourteen bars")
    func posterShowsThePricedSummary() {
        let ledger = Self.ledger([Self.day(2, tokens: 10, cost: 1), Self.day(0, tokens: 30, cost: 2)])
        let summary = SpendSummary.of([.codex: ledger], overLast: nil, now: Self.today, calendar: Self.calendar)
        let activity = SpendGlanceActivity.of([.codex: ledger], now: Self.today, calendar: Self.calendar)
        let picture = Self.picture(summary: summary, activity: activity)
        #expect(summary.tokens == 40)
        #expect(picture.brand == "Blinky")
        #expect(picture.span == "Last 7 days")
        #expect(picture.tokens == "40 tokens")
        #expect(picture.cost == SpendFormat.money(summary.cost, locale: Self.englishLocale) as String?)
        #expect(picture.costNote == nil)
        #expect(picture.agentsTitle == "By agent")
        #expect(picture.agents.map(\.name) == ["Codex"])
        #expect(picture.agents.first?.tokens == "40")
        #expect(picture.agents.first?.cost == SpendFormat.money(summary.cost, locale: Self.englishLocale) as String?)
        #expect(picture.bars.contains { $0.tokens == nil })
        #expect(picture.activityTitle == "Last 14 days")
        #expect(picture.bars.count == SpendGlance.activityDays)
        #expect(picture.bars.map(\.tokens) == activity.days.map(\.tokens))
        #expect(picture.bars.map(\.share).max() == 1 as Double?)
        #expect(picture.bars.filter { $0.tokens == nil }.allSatisfy { $0.share == 0 })
        #expect(picture.drawnText.contains("By agent"))
        #expect(picture.drawnText.contains("Last 14 days"))
        #expect(picture.drawnText.first == "Blinky")
        #expect(picture.drawnText.last == "Blinky")
    }

    @Test("The poster says when a cost is unavailable, and a mix keeps the priced amount")
    func posterNotesTheEstimate() {
        var unavailable = SpendSummary()
        unavailable.tokens = 20
        unavailable.unpricedTokens = 20
        unavailable.cost = 0
        unavailable.agents = [.init(agent: .codex, tokens: 20, cost: 0, unpricedTokens: 20)]
        let missing = Self.picture(summary: unavailable)
        #expect(missing.brand == "Blinky")
        #expect(missing.span == "Last 7 days")
        #expect(missing.tokens == "20 tokens")
        #expect(missing.cost == nil)
        #expect(missing.costNote == "Estimate unavailable")
        #expect(missing.agentsTitle == "By agent")
        #expect(missing.agents.map(\.name) == ["Codex"])
        #expect(missing.agents.first?.cost == nil)

        var partial = SpendSummary()
        partial.tokens = 20
        partial.unpricedTokens = 5
        partial.cost = 1.5
        partial.agents = [.init(agent: .codex, tokens: 20, cost: 1.5, unpricedTokens: 5)]
        let mixed = Self.picture(summary: partial)
        let money = SpendFormat.money(1.5, locale: Self.englishLocale)
        #expect(mixed.cost == money as String?)
        #expect(mixed.costNote == nil)
        #expect(mixed.agents.first?.cost == "\(money)*" as String?)
        #expect(mixed.brand == "Blinky")
    }

    @Test("The poster footnotes a partial count and a record it could not read")
    func posterFootnotesLimits() {
        let activity = SpendGlanceActivity.of(
            [.codex: Self.ledger([Self.day(1, tokens: 12)], partial: true)],
            now: Self.today,
            calendar: Self.calendar
        )
        var summary = SpendSummary()
        summary.tokens = 12
        summary.cost = 1
        let partialChart = Self.picture(summary: summary, activity: activity)
        #expect(partialChart.bars.count == SpendGlance.activityDays)
        #expect(partialChart.activityTitle == "Last 14 days")
        #expect(partialChart.costNote == nil)
        #expect(partialChart.footnotes == ["Counts may be incomplete."])
        #expect(partialChart.brand == "Blinky")

        var incomplete = summary
        incomplete.hasPartialCounts = true
        let both = Self.picture(
            summary: incomplete,
            activity: activity,
            observedAt: Self.today,
            limitations: true
        )
        #expect(both.costNote == nil)
        #expect(both.footnotes == [
            "Updated just now",
            "Counts may be incomplete.",
            "Some compressed records could not be read.",
        ])
        #expect(both.drawnText.first == "Blinky")
        #expect(both.drawnText.last == "Blinky")
    }

    @Test("The chart button exists only while reading is on, and off cannot open the summary")
    @MainActor
    func entryStaysClosedWhileReadingIsOff() async throws {
        #expect(SpendGlance.showsEntry(reading: true, canOpen: true))
        #expect(!SpendGlance.showsEntry(reading: false, canOpen: true))
        #expect(!SpendGlance.showsEntry(reading: true, canOpen: false))
        #expect(!SpendGlance.showsEntry(reading: false, canOpen: false))

        let name = "pulse-spend-glance-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(readsTokenSpend: false, defaults: defaults)
        let model = SpendGlanceModel(settings: settings)
        model.isOpen = true
        #expect(!model.loadKey.isEnabled)
        #expect(model.summaryRequest == nil)
        await model.load()
        #expect(model.read.snapshot == nil)
        #expect(!model.figuresReady)

        settings.readsTokenSpend = true
        model.isOpen = false
        #expect(model.loadKey.isEnabled)
        #expect(model.summaryRequest == nil)
        await model.load()
        #expect(model.read.snapshot == nil)
        #expect(!model.figuresReady)

        settings.readsTokenSpend = false
        let controller = SpendGlanceController(settings: settings)
        controller.toggle()
        controller.show()
        #expect(!controller.isOpen)
    }

    @Test("Tokens stay larger than the estimate, on the window and on the poster")
    func tokensLead() {
        #expect(SpendGlanceHeadline.tokenPointSize == 28)
        #expect(SpendGlanceHeadline.moneyPointSize == 15)
        #expect(SpendGlanceHeadline.tokenPointSize > SpendGlanceHeadline.moneyPointSize)
        #expect(SpendGlanceHeadline.speedPointSize < SpendGlanceHeadline.moneyPointSize)
        #expect(SpendGlanceHeadline.posterTokenPointSize == 40)
        #expect(SpendGlanceHeadline.posterMoneyPointSize == 22)
        #expect(SpendGlanceHeadline.posterTokenPointSize > SpendGlanceHeadline.posterMoneyPointSize)
        #expect(SpendGlanceCopy.hold >= .seconds(4))
        #expect(!SpendGlanceCopy.shiftsLayout)
        #expect(SpendGlancePlacement.size.width >= 640)
        #expect(SpendGlancePlacement.size.height >= 640)
        #expect(!TokenSpendView.showsNumberRow(hidesSpanHeadline: true, hasFocus: false))
        #expect(TokenSpendView.showsNumberRow(hidesSpanHeadline: true, hasFocus: true))
        #expect(TokenSpendView.showsNumberRow(hidesSpanHeadline: false, hasFocus: false))
    }

    @MainActor
    @Test("Share copies a PNG and a TIFF of the visible view, and the recap note does not take a row")
    func shareCopiesTheVisibleView() {
        #expect(!RecapExport.noticeShiftsLayout)
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 40))
        view.wantsLayer = true
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        let pasteboard = NSPasteboard.withUniqueName()
        #expect(SpendGlanceExport.copyVisible(view, pasteboard: pasteboard))
        #expect(pasteboard.data(forType: .png) != nil)
        #expect(pasteboard.data(forType: .tiff) != nil)
    }

    @Test("The palette is saturated and not one grey")
    func paletteIsColoured() {
        #expect(SpendGlancePalette.swatches.count >= 4)
        for swatch in SpendGlancePalette.swatches {
            #expect(!swatch.isGrayscale)
            #expect(swatch.red != swatch.green || swatch.green != swatch.blue)
        }
        #expect(Set(SpendGlancePalette.swatches.map { "\($0.red),\($0.green),\($0.blue)" }).count == SpendGlancePalette.swatches.count)
    }

    @Test("The glance can list models, projects, and sessions, and agent stays the default")
    func dimensions() {
        let held = LocalizationSource.hold(.english)
        defer { held.end() }
        var summary = SpendSummary()
        summary.models = [
            .init(name: "small", tokens: 2, agents: [.codex]),
            .init(name: "large", tokens: 8, agents: [.codex]),
        ]
        summary.projects = [
            .init(
                id: .init(UsageProject("Quiet")!, agent: .codex),
                name: "Quiet",
                tokens: 1,
                cost: 0,
                sessions: 1,
                lastUsed: Self.today
            ),
            .init(
                id: .init(UsageProject("Busy")!, agent: .codex),
                name: "Busy",
                tokens: 4,
                cost: 1,
                sessions: 2,
                lastUsed: Self.today
            ),
        ]
        summary.sessions = [
            .init(agent: .codex, session: UsageLedger.Session(
                id: "newer", name: "file", title: "Newer chat", project: nil,
                start: Self.today, end: Self.today, tokens: 3, cost: 1
            )),
            .init(agent: .codex, session: UsageLedger.Session(
                id: "older", name: "file", title: nil, project: nil,
                start: Self.today, end: Self.today.addingTimeInterval(-100), tokens: 9, cost: 1
            )),
        ]

        let models = SpendGlance.rows(summary, dimension: .model)
        #expect(models.map(\.name) == ["large", "small"])
        #expect(models[0].cost == nil)
        #expect(models[0].share == 1)

        let projects = SpendGlance.rows(summary, dimension: .project)
        #expect(projects.map(\.name) == ["Busy", "Quiet"])
        #expect(projects[0].share == 1)

        let sessions = SpendGlance.rows(summary, dimension: .session)
        #expect(sessions.map(\.name) == ["Newer chat", "Untitled conversation"])
        #expect(sessions.map(\.share).contains(1))
        #expect(SpendGlanceDimension.default == .model)

        let picture = SpendGlancePicture.make(
            span: .week,
            custom: Self.today...Self.today,
            summary: summary,
            activity: SpendGlanceActivity(),
            observedAt: nil,
            hasReadLimitations: false,
            dimension: .model,
            locale: Self.englishLocale,
            bundle: Self.english
        )
        #expect(picture.agentsTitle == "By model")
        #expect(picture.agents.map(\.name) == ["large", "small"])
    }

    @Test("The chart follows the span, by the hour, by the day, or in buckets")
    func chartFollowsTheSpan() {
        var oneDay = SpendSummary()
        oneDay.hours = [9: 4, 15: 0]
        oneDay.days = [SpendSummary.Day(date: Self.today, tokens: 4, cost: 0)]
        let hours = SpendGlanceActivity.covering(
            summary: oneDay, span: .today, custom: Self.today...Self.today,
            calendar: Self.calendar, now: Self.today
        )
        #expect(hours.coverage == .hours)
        #expect(hours.days.count == 24)
        #expect(hours.days.allSatisfy { $0.tokens != nil })
        #expect(hours.days[9].tokens == 4)
        #expect(hours.days[15].tokens == 0)

        var week = SpendSummary()
        week.days = (0..<7).map { offset in
            SpendSummary.Day(
                date: Self.calendar.date(byAdding: .day, value: -offset, to: Self.today)!,
                tokens: offset == 3 ? 0 : 2,
                cost: 0
            )
        }
        let days = SpendGlanceActivity.covering(
            summary: week, span: .week, custom: Self.today...Self.today, calendar: Self.calendar, now: Self.today
        )
        #expect(days.coverage == .span)
        #expect(days.days.count == 7)
        #expect(days.days.contains { $0.tokens == 0 })

        var year = SpendSummary()
        year.days = (0..<100).map { offset in
            SpendSummary.Day(
                date: Self.calendar.date(byAdding: .day, value: -offset, to: Self.today)!,
                tokens: 1,
                cost: 0
            )
        }
        let buckets = SpendGlanceActivity.covering(
            summary: year, span: .thisYear, custom: Self.today...Self.today, calendar: Self.calendar, now: Self.today
        )
        #expect(buckets.coverage == .buckets)
        #expect(buckets.days.count == SpendGlance.maximumBars)
        #expect(buckets.days.compactMap(\.tokens).reduce(0, +) == 100)

        let titled = SpendGlancePicture.make(
            span: .today,
            custom: Self.today...Self.today,
            summary: oneDay,
            activity: hours,
            observedAt: nil,
            hasReadLimitations: false,
            locale: Self.englishLocale,
            bundle: Self.english
        )
        #expect(titled.activityTitle == "By hour")
        #expect(titled.bars.count == 24)
    }

    @MainActor
    @Test("Share stays copied long enough to read, then clears")
    func copiedConfirmation() async {
        let name = "pulse-spend-glance-copy-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.spendGlanceDimension == .model)
        defaults.set("agent", forKey: "settings.spendGlanceDimension")
        let kept = AppSettings.restoredSettings(from: defaults, detected: [], scan: ExtensionCatalog.Scan())
        #expect(kept.spendGlanceDimension == .agent)
        defaults.set("nope", forKey: "settings.spendGlanceDimension")
        let back = AppSettings.restoredSettings(from: defaults, detected: [], scan: ExtensionCatalog.Scan())
        #expect(back.spendGlanceDimension == .model)
        let model = SpendGlanceModel(settings: settings)
        model.noteCopied(hold: .milliseconds(30))
        #expect(model.didCopy)
        // The clear is a main-actor task. A fixed sleep loses to the rest of
        // the suite while that actor is busy, and the flag is still set.
        for _ in 0..<200 where model.didCopy {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(!model.didCopy)
        model.noteCopyFailed(hold: .milliseconds(30))
        #expect(model.copyFailed)
        #expect(!model.didCopy)
        for _ in 0..<200 where model.copyFailed {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(!model.copyFailed)
    }

    @Test("Escape and a click do not dismiss the glance window; the close button does")
    func dismissal() {
        #expect(SpendGlanceDismissal.escapeKeyCode == 53)
        #expect(!SpendGlanceDismissal.shouldCloseOnEscape(keyCode: 53, hasModifiers: false))
        #expect(!SpendGlanceDismissal.shouldCloseOnEscape(keyCode: 53, hasModifiers: true))
        #expect(!SpendGlanceDismissal.shouldCloseOnEscape(keyCode: 36, hasModifiers: false))
        #expect(!SpendGlanceAppFocus.closesOnResign(hasBeenActive: false, windowVisible: true))
        #expect(!SpendGlanceAppFocus.closesOnResign(hasBeenActive: true, windowVisible: false))
        #expect(!SpendGlanceAppFocus.closesOnResign(hasBeenActive: true, windowVisible: true))

        let frame = CGRect(x: 100, y: 100, width: 400, height: 300)
        #expect(!SpendGlanceOutsideClick.shouldClose(point: CGPoint(x: 200, y: 200), windowFrame: frame))
        #expect(!SpendGlanceOutsideClick.shouldClose(point: CGPoint(x: 0, y: 0), windowFrame: frame))

        let button = CGRect(x: 0, y: 0, width: 14, height: 14)
        #expect(SpendGlanceDismissal.claimsCloseClick(buttonBounds: button, pointInButton: CGPoint(x: 7, y: 7)))
        #expect(SpendGlanceDismissal.claimsCloseClick(buttonBounds: button, pointInButton: CGPoint(x: 0, y: 0)))
        #expect(!SpendGlanceDismissal.claimsCloseClick(buttonBounds: button, pointInButton: CGPoint(x: 14, y: 7)))
        #expect(!SpendGlanceDismissal.claimsCloseClick(buttonBounds: button, pointInButton: CGPoint(x: 30, y: 7)))
        #expect(!SpendGlanceDismissal.claimsCloseClick(buttonBounds: .zero, pointInButton: .zero))
        #expect(!SpendGlanceDismissal.claimsCloseClick(buttonBounds: .null, pointInButton: CGPoint(x: 1, y: 1)))
    }

    @Test("The glance lists activity, then Performance, then the rhythm, then one breakdown")
    func glanceOrder() {
        #expect(TokenGlanceSection.order == [.tokenActivity, .performance, .usageRhythm, .dimension])
        #expect(UsageRhythm.metricKeys(hoursComplete: true, hasPeakHour: true, hasModel: true) == [
            "Current streak", "Longest streak", "Peak hour", "Most tokens",
        ])
        #expect(UsageRhythm.metricKeys(hoursComplete: false, hasPeakHour: true, hasModel: false) == [
            "Current streak", "Longest streak",
        ])
        #expect(UsageRhythm.metricKeys(hoursComplete: true, hasPeakHour: false, hasModel: true) == [
            "Current streak", "Longest streak", "Most tokens",
        ])
        #expect(UsageRhythm.spreadsAcrossTheRow)
        #expect(SpendGlanceHeadline.centersFigures)
        #expect(!SpendQuietCopy.isPrimary)
        #expect(SpendQuietCopy.pointSize < SpendGlanceHeadline.tokenPointSize)
        #expect(!TokenSpendView.showsDimensionCaption)
        #expect(SpendGlanceNotes.startsCollapsed)

        let held = LocalizationSource.hold(.english)
        defer { held.end() }
        var summary = SpendSummary()
        summary.tokens = 10
        summary.unpricedModels = ["hidden-model"]
        let notes = SpendGlanceNotes.sections(summary: summary, unreadNames: ["Gemini CLI", "Zed"])
        #expect(notes.estimate.map(\.text) == [
            "Usage records, estimated at models.dev API rates—not an actual bill.",
            "1 models without public pricing: tokens only.",
        ])
        #expect(notes.unread == ["Gemini CLI", "Zed"])
        #expect(!notes.estimate.map(\.text).contains { $0.contains("·") })
        #expect(notes.estimate.contains { $0.help == "hidden-model" })
        #expect(SpendGlanceNotes.sections(summary: SpendSummary(), unreadNames: []).isEmpty)
        let unreadOnly = SpendGlanceNotes.sections(summary: SpendSummary(), unreadNames: ["Zed"])
        #expect(unreadOnly.estimate.isEmpty)
        #expect(unreadOnly.unread == ["Zed"])
        #expect(!notes.estimate.map(\.text).contains("By agent"))
    }

    @Test("The speed section lists the span average and each timed model, in tok/s")
    func outputSpeedSection() {
        let held = LocalizationSource.hold(.english)
        defer { held.end() }

        var summary = SpendSummary()
        summary.tokens = 10
        summary.cost = 1
        summary.unpricedTokens = 2
        summary.outputTokensPerSecond = 86
        summary.models = [
            SpendSummary.Model(name: "Fast", tokens: 8, agents: [], share: 0.8, tokensPerSecond: 100, firstToken: 2.5),
            SpendSummary.Model(name: "Slow", tokens: 2, agents: [], share: 0.2, tokensPerSecond: 0.2, firstToken: nil),
            SpendSummary.Model(name: "Quiet", tokens: 1, agents: [], tokensPerSecond: nil, firstToken: nil),
            SpendSummary.Model(name: "Wait", tokens: 1, agents: [], tokensPerSecond: nil, firstToken: 1.2),
        ]
        let section = SpendSpeedSection.make(summary: summary, locale: Self.englishLocale, bundle: Self.english)
        #expect(section?.title == "Performance")
        #expect(section?.overallTitle == "Overall")
        #expect(section?.overall?.speed == "86 tok/s")
        #expect(section?.columns.shown == [.speed, .firstToken])
        #expect(section?.models.map(\.name) == ["Fast", "Slow", "Wait"])
        #expect(section?.models.map(\.speed) == ["100 tok/s", "0.2 tok/s", nil])
        #expect(section?.models[0].firstToken == "2.5 s")
        #expect(section?.models[1].firstToken == nil)
        #expect(section?.models[2].firstToken == "1.2 s")
        #expect(section?.models.allSatisfy { $0.figures.cache == nil && $0.figures.input == nil } == true)
        #expect(SpendSpeedLayout.isDenserThanSettings)
        #expect(SpendSpeedLayout.verticalPadding <= 4)
        #expect(SpendSpeedLayout.minimumHeight <= 24)
        #expect(SpendSpeedLayout.modelRowHeight <= 32)
        #expect(SettingsRowDensity.compact.verticalPadding == SpendSpeedLayout.verticalPadding)
        #expect(SettingsRowDensity.compact.minimumHeight == SpendSpeedLayout.minimumHeight)
        #expect(SettingsRowDensity.regular.minimumHeight == SettingsRowMetrics.minimumHeight)

        // The headline keeps the money and does not carry the speed, its old
        // explanation, or a partial-estimate label.
        let picture = Self.picture(summary: summary)
        #expect(picture.cost != nil)
        #expect(picture.costNote == nil)
        #expect(!picture.drawnText.contains { $0.contains("tok/s") || $0.contains("tokens/s") })
        #expect(!picture.drawnText.contains("Partial estimate"))
        #expect(!picture.drawnText.contains { $0.contains("Claude Code") })

        #expect(OutputSpeedText.number(0.04, locale: Self.englishLocale) == "0.04")
        #expect(OutputSpeedText.number(0.04, locale: Self.englishLocale) != "0")
        #expect(OutputSpeedText.line(0.04, locale: Self.englishLocale, bundle: Self.english) == "0.04 tok/s")
        #expect(OutputSpeedText.line(86, locale: Self.englishLocale, bundle: Self.english) == "86 tok/s")
        #expect(OutputSpeedText.firstToken(2.5, locale: Self.englishLocale, bundle: Self.english) == "First token 2.5 s")

        summary.outputTokensPerSecond = nil
        summary.models = []
        #expect(SpendSpeedSection.make(summary: summary, locale: Self.englishLocale, bundle: Self.english) == nil)
        let quiet = Self.picture(summary: summary)
        #expect(!quiet.drawnText.contains { $0.contains("tok/s") })
    }

    @Test("Performance shows cache, input and output when the records classified them, and omits a column nobody has")
    func performanceSection() {
        let held = LocalizationSource.hold(.english)
        defer { held.end() }

        let fast = TokenTally(input: 400_000, cacheWrite: 100_000, cacheRead: 1_500_000, output: 80_000)
        let silent = TokenTally(input: 3_000, cacheWrite: 0, cacheRead: 0, output: 2_000, repliesWithoutCacheFields: 2)
        let missed = TokenTally(input: 6_000, cacheWrite: 0, cacheRead: 0, output: 4_000)
        var summary = SpendSummary()
        summary.hasTokenBreakdown = true
        summary.cacheMeasured = true
        summary.cacheHitRate = 0.5
        summary.tally = fast
        summary.unclassifiedTokens = 0
        summary.outputTokensPerSecond = 21
        summary.firstToken = 13.8
        summary.models = [
            SpendSummary.Model(
                name: "Fast", tokens: fast.total, agents: [],
                tally: fast, unclassifiedTokens: 0, cacheMeasured: true,
                cacheHitRate: 1_500_000.0 / 2_000_000.0, tokensPerSecond: 21, firstToken: 13.8
            ),
            SpendSummary.Model(
                name: "Silent", tokens: silent.total, agents: [],
                tally: silent, unclassifiedTokens: 0, cacheMeasured: false,
                cacheHitRate: nil, tokensPerSecond: nil, firstToken: nil
            ),
            SpendSummary.Model(
                name: "Miss", tokens: missed.total, agents: [],
                tally: missed, unclassifiedTokens: 0, cacheMeasured: true,
                cacheHitRate: 0, tokensPerSecond: nil, firstToken: nil
            ),
            SpendSummary.Model(
                name: "Part", tokens: 10, agents: [],
                tally: TokenTally(input: 4, cacheRead: 2, output: 0), unclassifiedTokens: 4,
                cacheMeasured: true, cacheHitRate: nil
            ),
            SpendSummary.Model(name: "Quiet", tokens: 1, agents: []),
        ]
        let section = SpendSpeedSection.make(summary: summary, locale: Self.englishLocale, bundle: Self.english)
        #expect(section?.columns.shown == [.cacheHitRate, .cache, .cacheWrite, .input, .output, .unclassified, .speed, .firstToken])
        #expect(section?.overall?.cacheHitRate == "50%")
        #expect(section?.overall?.cache == "1.5M")
        #expect(section?.overall?.cacheExact == 1_500_000)
        #expect(section?.overall?.cacheWrite == "100K")
        #expect(section?.overall?.input == "500K")
        #expect(section?.overall?.output == "80K")
        #expect(section?.overall?.speed == "21 tok/s")
        #expect(section?.overall?.firstToken == "13.8 s")
        #expect(section?.models.map(\.name) == ["Fast", "Silent", "Miss", "Part"])
        #expect(section?.models[0].figures.cacheHitRate == "75%")
        #expect(section?.models[0].figures.cache == "1.5M")
        #expect(section?.models[0].figures.input == "500K")
        #expect(section?.models[0].figures.output == "80K")
        // A reply that named no cache field is not a measured zero.
        #expect(section?.models[1].figures.cache == nil)
        #expect(section?.models[1].figures.cacheHitRate == nil)
        #expect(section?.models[1].figures.input == "3K")
        #expect(section?.models[1].figures.output == "2K")
        // A recorded miss is 0%, and a write of zero shows once anyone wrote.
        #expect(section?.models[2].figures.cacheHitRate == "0%")
        #expect(section?.models[2].figures.cache == "0")
        #expect(section?.models[2].figures.cacheWrite == "0")
        #expect(section?.models[2].figures.speed == nil)
        // Unclassified tokens keep their count and withhold the rate.
        #expect(section?.models[3].figures.unclassified == "4")
        #expect(section?.models[3].figures.cache == "2")
        #expect(section?.models[3].figures.cacheHitRate == nil)
        #expect(section?.models[3].figures.input == "4")

        // A positive rate that would round to 0% stays visible.
        summary.cacheHitRate = 0.004
        let tiny = SpendSpeedSection.make(summary: summary, locale: Self.englishLocale, bundle: Self.english)
        #expect(tiny?.overall?.cacheHitRate == "<1%")
        #expect(tiny?.overall?.cacheHitRate != "0%")

        let chinese = LocalizationSource.bundle(for: .chineseSimplified)
        let hans = Locale(identifier: "zh_Hans")
        summary.cacheHitRate = 0.5
        summary.tally.cacheRead = 150_000_000
        let zh = SpendSpeedSection.make(summary: summary, locale: hans, bundle: chinese)
        #expect(zh?.title == "性能")
        #expect(zh?.overallTitle == "平均")
        #expect(zh?.overall?.cache == "1.5亿")
        #expect(zh?.overall?.firstToken == "13.8 秒")
        #expect(zh?.overall?.speed == "21 tok/s")

        // Kinds without a timed reply still open the section. Nothing classified
        // and nothing timed leaves it out.
        summary.outputTokensPerSecond = nil
        summary.firstToken = nil
        summary.models = [
            SpendSummary.Model(
                name: "Only", tokens: fast.total, agents: [],
                tally: fast, unclassifiedTokens: 0, cacheMeasured: true, cacheHitRate: 0.75
            ),
        ]
        let kindsOnly = SpendSpeedSection.make(summary: summary, locale: Self.englishLocale, bundle: Self.english)
        #expect(kindsOnly?.columns.speed == false)
        #expect(kindsOnly?.columns.input == true)
        #expect(kindsOnly?.models.map(\.name) == ["Only"])

        summary.hasTokenBreakdown = false
        summary.cacheMeasured = false
        summary.cacheHitRate = nil
        summary.models = [SpendSummary.Model(name: "Quiet", tokens: 5, agents: [])]
        #expect(SpendSpeedSection.make(summary: summary, locale: Self.englishLocale, bundle: Self.english) == nil)
    }

    private static func picture(
        summary: SpendSummary = SpendSummary(),
        activity: SpendGlanceActivity = SpendGlanceActivity(),
        observedAt: Date? = nil,
        limitations: Bool = false
    ) -> SpendGlancePicture {
        SpendGlancePicture.make(
            span: .week,
            custom: today...today,
            summary: summary,
            activity: activity,
            observedAt: observedAt,
            hasReadLimitations: limitations,
            dimension: .agent,
            now: today,
            calendar: calendar,
            locale: englishLocale,
            bundle: english
        )
    }
}
