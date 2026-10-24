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
/// Sentence assertions name the English table. `String.localized` follows
/// the process language, which another suite changes while these run.
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

    @Test("The poster says when a cost is unavailable or only partial")
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
        #expect(mixed.costNote == "Partial estimate")
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
        #expect(both.costNote == "Partial estimate")
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
        LocalizationSource.use(.english)
        defer { LocalizationSource.use(.system) }
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

    @Test("Escape and the close button dismiss the glance window")
    func dismissal() {
        #expect(SpendGlanceDismissal.escapeKeyCode == 53)
        #expect(SpendGlanceDismissal.shouldCloseOnEscape(keyCode: 53, hasModifiers: false))
        #expect(!SpendGlanceDismissal.shouldCloseOnEscape(keyCode: 53, hasModifiers: true))
        #expect(!SpendGlanceDismissal.shouldCloseOnEscape(keyCode: 36, hasModifiers: false))

        // Which window the event names is not part of the decision. Escape
        // still closes when the glance is not key and the event names nothing,
        // or names some other Blinky window. An open menu keeps the key.
        #expect(SpendGlanceDismissal.shouldCloseOnEscape(keyCode: 53, hasModifiers: false, auxiliary: false))
        #expect(!SpendGlanceDismissal.shouldCloseOnEscape(keyCode: 53, hasModifiers: false, auxiliary: true))
        #expect(!SpendGlanceDismissal.shouldCloseOnEscape(keyCode: 53, hasModifiers: true, auxiliary: false))
        #expect(!SpendGlanceDismissal.shouldCloseOnEscape(keyCode: 36, hasModifiers: false, auxiliary: false))
        #expect(!SpendGlanceAppFocus.closesOnResign(hasBeenActive: false, windowVisible: true))
        #expect(!SpendGlanceAppFocus.closesOnResign(hasBeenActive: true, windowVisible: false))
        #expect(SpendGlanceAppFocus.closesOnResign(hasBeenActive: true, windowVisible: true))

        let button = CGRect(x: 0, y: 0, width: 14, height: 14)
        #expect(SpendGlanceDismissal.claimsCloseClick(buttonBounds: button, pointInButton: CGPoint(x: 7, y: 7)))
        #expect(SpendGlanceDismissal.claimsCloseClick(buttonBounds: button, pointInButton: CGPoint(x: 0, y: 0)))
        #expect(!SpendGlanceDismissal.claimsCloseClick(buttonBounds: button, pointInButton: CGPoint(x: 14, y: 7)))
        #expect(!SpendGlanceDismissal.claimsCloseClick(buttonBounds: button, pointInButton: CGPoint(x: 30, y: 7)))
        #expect(!SpendGlanceDismissal.claimsCloseClick(buttonBounds: .zero, pointInButton: .zero))
        #expect(!SpendGlanceDismissal.claimsCloseClick(buttonBounds: .null, pointInButton: CGPoint(x: 1, y: 1)))
    }

    @Test("The glance lists activity, then the rhythm, then one breakdown")
    func glanceOrder() {
        #expect(TokenGlanceSection.order == [.tokenActivity, .usageRhythm, .dimension])
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

        let frame = CGRect(x: 100, y: 100, width: 200, height: 200)
        let entry = CGRect(x: 40, y: 40, width: 20, height: 20)
        #expect(SpendGlanceOutsideClick.shouldClose(
            point: CGPoint(x: 10, y: 10), windowFrame: frame, entryRect: entry, auxiliary: false
        ))
        #expect(!SpendGlanceOutsideClick.shouldClose(
            point: CGPoint(x: 150, y: 150), windowFrame: frame, entryRect: entry, auxiliary: false
        ))
        #expect(!SpendGlanceOutsideClick.shouldClose(
            point: CGPoint(x: 45, y: 45), windowFrame: frame, entryRect: entry, auxiliary: false
        ))
        #expect(!SpendGlanceOutsideClick.shouldClose(
            point: CGPoint(x: 10, y: 10), windowFrame: frame, entryRect: entry, auxiliary: true
        ))
        #expect(SpendGlanceOutsideClick.shouldClose(
            point: CGPoint(x: 10, y: 10), windowFrame: frame, entryRect: .null, auxiliary: false
        ))
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
