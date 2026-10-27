// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Every agent's spending added up, which is a different question from any one
/// agent's.
///
/// `AccountUsageCard` answers "how heavily am I using *this*" — one provider,
/// one ring's worth of history, opened from that provider's own pane. Nothing
/// answered "how much have I spent on coding agents", because that figure does
/// not belong to any provider and there was nowhere to put it. This is that
/// figure, and the split underneath it.
///
/// **It reuses the ledgers rather than rescanning.** `UsageLedgerReader` already
/// holds one per provider, priced from the same `ModelPrices` table; adding
/// them up is arithmetic over what is already in memory, not another pass over
/// a few hundred megabytes of transcripts.
///
/// **Only the agents that keep local transcripts can be in it.** A provider's
/// own statistics (Z.ai, Zhipu) report one token total per model and no money,
/// and folding those into a combined cost would put a figure on the total that
/// half of it cannot carry — so `Provider.keepsLocalTranscripts` is the gate,
/// not `providesHistory`.
struct SpendSummary: Equatable, Sendable {
    /// One agent's share of the total.
    struct Agent: Identifiable, Equatable, Sendable {
        let agent: SpendAgent
        let tokens: Int
        let cost: Double
        /// Tokens spent on models with no published price. Counted, not costed.
        let unpricedTokens: Int

        var id: SpendAgent { agent }
    }

    /// One model's share, across every agent that used it.
    ///
    /// **No per-model cost here.** The ledger keeps money per day and per raw
    /// id; a blended rate spread across a display name would be inventing it.
    /// The share is of tokens. Kinds, where every token of this model was
    /// classified, are `tally`. The drill-down is where one model's money is.
    struct Model: Identifiable, Equatable, Sendable {
        /// The name the provider publishes, where models.dev has one.
        let name: String
        let tokens: Int
        /// Which agents sent work to it. One model can belong to two.
        let agents: [SpendAgent]

        var id: String { name }

        var share: Double = 0

        /// Classified kinds over the span. Nil when any of this model's
        /// tokens cannot be sorted into a kind — a missing per-model tally,
        /// or kinds that do not add up to the model's own total. Never a
        /// partial split, and never the day's combined tally borrowed for it.
        var tally: TokenTally? = nil
        /// Explicit unclassified tokens beside `tally`. Nil when the split
        /// itself is unavailable. Zero means the records classified every token.
        var unclassifiedTokens: Int? = nil
        /// Whether `tally`'s cache reads and writes are a measurement.
        /// False when an agent records no cache, or the replies named no
        /// cache field. False is not a hit rate of zero.
        var cacheMeasured: Bool = false
        /// Cache reads over input, cache writes and cache reads. Nil when
        /// the cache was not measured for every one of this model's tokens,
        /// when unclassified tokens remain, when a ledger's counts may be
        /// missing, or when there is no input to measure.
        var cacheHitRate: Double? = nil

        /// Timed replies in the same span, weighted by the output they wrote.
        /// Nil when this model had none — not a speed of zero.
        var tokensPerSecond: Double? = nil
        /// Mean wait for the first token, only where a log recorded it.
        var firstToken: TimeInterval? = nil
    }

    /// One day, with every agent's work in it — the chart's bars, and the
    /// table's rows.
    struct Day: Identifiable, Equatable, Sendable {
        let date: Date
        let tokens: Int
        let cost: Double
        /// The day split by kind of token, summed across agents. Nothing here
        /// is recomputed: the ledger already carries it per day.
        var tally = TokenTally()
        /// Tokens that day with no price behind them, summed across agents.
        /// Carried so a row can show a dash rather than `$0` for work Pulse
        /// could not price, and so the figure is never silently priced at zero.
        var unpricedTokens: Int = 0

        /// Reported tokens whose source supplied no usable category.
        var unclassifiedTokens: Int = 0
        var hasInvalidCategories = false

        var hasTokenBreakdown: Bool {
            !hasInvalidCategories && tally.accountsFor(tokens: tokens, unclassified: unclassifiedTokens)
        }

        var classifiedTally: TokenTally? {
            hasTokenBreakdown && !(tokens > 0 && unclassifiedTokens == tokens) ? tally : nil
        }

        var id: Date { date }
    }

    /// One transcript, with the agent that wrote it.
    struct Session: Identifiable, Equatable, Sendable {
        let agent: SpendAgent
        let session: UsageLedger.Session

        var id: String { session.id }
    }

    /// One identified project, across every session in the selected span.
    struct Project: Identifiable, Equatable, Sendable {
        struct ID: Hashable, Sendable {
            let identity: UsageProject.Identity
            // A label alone cannot prove that two agents mean the same project.
            let agent: SpendAgent?

            init(_ project: UsageProject, agent: SpendAgent) {
                identity = project.identity
                if case .label = project.identity { self.agent = agent }
                else { self.agent = nil }
            }
        }

        let id: ID
        let name: String
        let tokens: Int
        let cost: Double
        var unpricedTokens: Int = 0
        var estimatedCost: Double? { tokens > 0 && unpricedTokens == tokens ? nil : cost }
        let sessions: Int
        let lastUsed: Date
    }

    func projectName(for row: Session) -> String? {
        guard let project = row.session.project else { return nil }
        let id = Project.ID(project, agent: row.agent)
        return projects.first { $0.id == id }?.name ?? project.name
    }

    var tokens = 0
    var cost = 0.0
    /// The whole span split by kind of token. Fresh input, cache written,
    /// cache read and output are priced an order of magnitude apart, so "four
    /// billion tokens" says much less than this does.
    var tally = TokenTally()
    var unclassifiedTokens = 0
    /// Every contributing day's categories and explicit remainder reconcile.
    var hasTokenBreakdown = false
    var unpricedTokens = 0
    var agents: [Agent] = []
    var models: [Model] = []
    var days: [Day] = []
    /// Newest first.
    var sessions: [Session] = []
    /// Heaviest first.
    var projects: [Project] = []
    /// Models seen in the logs that models.dev has no price for, named so the
    /// footnote can say which.
    var unpricedModels: [String] = []

    /// Whether any contributing ledger had only session- or report-level
    /// timing for some of its work, so the hour figure must not be drawn.
    var hasAggregateTiming = false

    /// Whether any contributing ledger's counts may be missing. When set, the
    /// total is a floor rather than a whole: the UI says "partial" instead of
    /// quietly under-reporting. It adds no tokens and changes no price.
    var hasPartialCounts = false

    /// Output tokens per second across every timed reply in the span.
    ///
    /// Nil when nothing in the span was timed. That is not a speed of zero.
    /// All timed output over all timed seconds, so a long reply weighs more
    /// than a short one. The account card's rolling day and five-reply floor
    /// are a different reading (`UsageLedger.outputSpeedsByModel(since:)`).
    var outputTokensPerSecond: Double? = nil

    /// Mean wait for the first token across timed replies in the span.
    /// Nil when no log recorded one — not a wait of zero.
    var firstToken: TimeInterval? = nil

    /// Whether `tally`'s cache counts are a measurement of the span.
    /// False when no contributing agent records a cache, or every reply
    /// named no cache field. False is not a hit rate of zero. A mix of
    /// agents, some of which record a cache, still shows the recorded hits;
    /// the rate beside them does not, because it would count the rest as misses.
    var cacheMeasured: Bool = false

    /// Cache reads over the span's measured input. Nil when the cache was
    /// not measured for every contributing token, when unclassified tokens
    /// remain, when a ledger's counts may be missing, or when there is no input.
    var cacheHitRate: Double? = nil

    var isEmpty: Bool { tokens == 0 && cost == 0 }

    /// The heaviest day in the span, across every agent — which is not the
    /// same day as any one agent's heaviest.
    var busiestDay: Day? { days.max { $0.tokens < $1.tokens } }

    /// Days with anything on them. A span is drawn with its gaps so the chart
    /// reads as a calendar, but "you used it on 14 days" is about the work.
    var activeDays: Int { days.count { $0.tokens > 0 } }

    /// Tokens by calendar month, newest last.
    var months: [Day] = []

    /// Tokens by hour of the local day, 0–23. Built from the ledger's
    /// quarter-hour buckets, which is the only place the time of day survives:
    /// a `LedgerDay` has already thrown it away.
    var hours: [Int: Int] = [:]

    /// Hours with anything in them, for the day-long span where "how many of
    /// the seven days" is a question about one day.
    var activeHours: Int { hours.count { $0.value > 0 } }

    /// The hour with the most tokens in it. Nil where nothing was recorded, so
    /// an empty span does not report a busy midnight.
    var peakHour: Int? {
        hours.max { $0.value < $1.value }.map(\.key)
    }

    /// The run of days with work on them that is still going, and the longest
    /// run there has ever been.
    ///
    /// **Over the whole history, not the span.** Picking "last 7 days" capped
    /// both at seven, and "today" at one, so a month-long habit read as a
    /// week's. The span decides what is added up; a streak is a fact about
    /// every day there are records for.
    ///
    /// **Today is not over.** A run that reached yesterday is still current
    /// before anything has been done today — read first thing in the morning,
    /// a thirty-day streak used to show zero. It ends only once a whole day
    /// passes without work.
    var currentStreak = 0
    var longestStreak = 0

    static func streaks(of worked: Set<Date>, today: Date, calendar: Calendar) -> (current: Int, longest: Int) {
        var current = 0
        var cursor = worked.contains(today) ? today : calendar.date(byAdding: .day, value: -1, to: today) ?? today
        while worked.contains(cursor) {
            current += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        var longest = 0
        var run = 0
        var last: Date?
        for day in worked.sorted() {
            let follows = last.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } == day
            run = follows ? run + 1 : 1
            longest = max(longest, run)
            last = day
        }
        return (current, longest)
    }

    /// The day rows, in the order a column asks for.
    ///
    /// **Sorting is data, not layout**, so it lives here rather than on the
    /// view: it is the same question asked of the same rows whoever is asking,
    /// and a `View` is isolated to the main actor for reasons that have nothing
    /// to do with ordering a list.
    static func sorted(
        _ days: [Day],
        by column: DayColumn,
        ascending: Bool,
        cacheUnreported: Bool = false
    ) -> [Day] {
        // **What the table shows blank sorts last, either way.** A day whose
        // kinds do not add up to its total shows no kinds, and a day nothing
        // in which had a price shows no money; ranked by the numbers behind
        // the blanks, a "—" landed among real figures as if it were one.
        func kind(_ day: Day, _ value: (TokenTally) -> Int) -> Int? {
            day.classifiedTally.map(value)
        }
        // Counts remain Int: adjacent large totals must not compare equal
        // after conversion to Double. Money keeps its fractional amount.
        func ranked<T: Comparable>(_ value: (Day) -> T?) -> [Day] {
            days.sorted { lhs, rhs in
                switch (value(lhs), value(rhs)) {
                case (nil, nil): return ascending ? lhs.date < rhs.date : lhs.date > rhs.date
                case (nil, _): return false
                case (_, nil): return true
                case let (left?, right?):
                    guard left == right else { return ascending ? left < right : left > right }
                    return ascending ? lhs.date < rhs.date : lhs.date > rhs.date
                }
            }
        }
        switch column {
        case .date: return ranked { $0.date }
        case .fresh: return ranked { kind($0, \.fresh) }
        case .cacheRead:
            return ranked { kind($0, \.cacheRead).flatMap { cacheUnreported && $0 == 0 ? nil : $0 } }
        case .output: return ranked { kind($0, \.output) }
        case .unclassified: return ranked { $0.hasTokenBreakdown ? $0.unclassifiedTokens : nil }
        case .total: return ranked { $0.tokens }
        case .cost: return ranked { $0.tokens > 0 && $0.unpricedTokens == $0.tokens ? nil : $0.cost }
        }
    }

    /// The part of a session that falls inside the span, or nil where none
    /// does.
    ///
    /// This is the whole reason a session carries its own buckets. A session
    /// whose work straddles the cutoff contributes only its in-span
    /// quarter-hours, so a project's money and the span's own total are the
    /// same sum — never the whole conversation, and never a share of it
    /// worked out from a ratio.
    ///
    /// Calendar-day buckets also preserve the span when a report has no exact
    /// hour. They are used only when quarter-hour buckets are unavailable.
    /// A session with neither kind of bucket is one read before the ledger kept them:
    /// it falls back to being counted whole when it ended inside the span,
    /// which is the old rule and never a silent zero.
    private static func window(
        _ session: UsageLedger.Session,
        from lower: Date?,
        until upper: Date?
    ) -> (tokens: Int, cost: Double, unpriced: Int, last: Date)? {
        guard lower != nil || upper != nil else { return (session.tokens, session.cost, session.unpricedTokens, session.end) }

        func inside(_ date: Date) -> Bool {
            (lower.map { date >= $0 } ?? true) && (upper.map { date < $0 } ?? true)
        }

        guard !session.slots.isEmpty else {
            if !session.days.isEmpty {
                let days = session.days.filter { inside($0.date) }
                guard let last = days.map(\.date).max() else { return nil }
                return (days.reduce(0) { $0 + $1.tokens }, days.reduce(0.0) { $0 + $1.cost }, days.reduce(0) { $0 + $1.unpricedTokens }, last)
            }
            return inside(session.end) ? (session.tokens, session.cost, session.unpricedTokens, session.end) : nil
        }

        var tokens = 0
        var cost = 0.0
        var unpriced = 0
        var last = lower ?? .distantPast
        var found = false
        for slot in session.slots where inside(slot.start) {
            found = true
            tokens += slot.tokens
            cost += slot.cost
            unpriced += slot.unpricedTokens
            last = max(last, slot.start)
        }
        return found ? (tokens, cost, unpriced, last) : nil
    }

    /// Adds the ledgers up over the last `span` days, or over everything when
    /// `span` is nil.
    ///
    /// Dates are the ledgers' own day keys, which are already local midnights,
    /// so two agents' work on one day lands on one bar without any rounding
    /// here.
    ///
    /// **The span is a window on the calendar, not each ledger's last N
    /// entries.** Taking the suffix of every ledger looks equivalent and is
    /// not: an agent last used a fortnight ago contributes its *own* last
    /// seven recorded days, and "the last 7 days" then drew nine bars. The
    /// cutoff is a date, and the series is padded out to the whole window so a
    /// day nobody worked is a gap in a calendar rather than a missing column.
    static func of(
        _ ledgers: [SpendAgent: UsageLedger],
        overLast span: Int?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SpendSummary {
        let today = calendar.startOfDay(for: now)
        let cutoff = span.flatMap { calendar.date(byAdding: .day, value: -($0 - 1), to: today) }
        return summarize(ledgers, from: cutoff, until: nil, today: today, calendar: calendar)
    }

    /// Adds the ledgers up over the calendar days from `start` up to, **not
    /// including**, `end` — both local midnights — instead of "the last N days
    /// ending today". A month's or a year's recap is such a span.
    ///
    /// Everything `of(_:overLast:)` says holds, with the far edge added: days,
    /// quarter-hours and a session's own buckets outside `[start, end)` are not
    /// in it, and the padded series runs from `start` to the day before `end`
    /// (so an `end` that is not after `start` is an empty series). **Streaks are
    /// still the whole history, as of `now`'s day**: a span decides what is added
    /// up, not what a habit is.
    static func of(
        _ ledgers: [SpendAgent: UsageLedger],
        from start: Date,
        until end: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SpendSummary {
        summarize(ledgers, from: start, until: end, today: calendar.startOfDay(for: now), calendar: calendar)
    }

    /// Either edge open: from the first record when `start` is nil, through
    /// today when `end` is. What the Token spend pane's span picker asks for,
    /// a preset or the reader's own dates.
    static func of(
        _ ledgers: [SpendAgent: UsageLedger],
        starting start: Date?,
        before end: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SpendSummary {
        summarize(ledgers, from: start, until: end, today: calendar.startOfDay(for: now), calendar: calendar)
    }

    private static func summarize(
        _ ledgers: [SpendAgent: UsageLedger],
        from cutoff: Date?,
        until upper: Date?,
        today: Date,
        calendar: Calendar
    ) -> SpendSummary {
        var summary = SpendSummary()

        func inside(_ date: Date) -> Bool {
            (cutoff.map { date >= $0 } ?? true) && (upper.map { date < $0 } ?? true)
        }

        var dayTokens: [Date: Int] = [:]
        var dayCost: [Date: Double] = [:]
        var dayTally: [Date: TokenTally] = [:]
        var dayUnpriced: [Date: Int] = [:]
        var dayUnclassified: [Date: Int] = [:]
        var invalidCategoryDays: Set<Date> = []
        var categoriesComplete = true
        var hourTokens: [Int: Int] = [:]
        var tally = TokenTally()
        var modelTokens: [String: Int] = [:]
        var modelAgents: [String: Set<SpendAgent>] = [:]
        var unpriced: Set<String> = []
        var projectTokens: [Project.ID: Int] = [:]
        var projectCost: [Project.ID: Double] = [:]
        var projectUnpriced: [Project.ID: Int] = [:]
        var projectSessions: [Project.ID: Int] = [:]
        var projectLastUsed: [Project.ID: Date] = [:]
        var projectMetadata: [Project.ID: UsageProject] = [:]
        var hasAggregate = false
        var hasPartial = false
        var worked: Set<Date> = []
        var modelTimings: [String: ReplyTiming] = [:]
        var spanTiming = ReplyTiming()
        // Per display name. A day that cannot vouch for its kinds marks the
        // whole name, so a later day cannot publish a partial split.
        var modelKinds: [String: TokenTally] = [:]
        var modelExtra: [String: Int] = [:]
        var modelUnvouched: Set<String> = []
        /// Tokens whose agent records no cache. They are not misses.
        var modelCacheExcluded: [String: Int] = [:]
        /// A partial ledger, or any other reason a rate would cover only
        /// part of the model's work.
        var modelRateBlocked: Set<String> = []
        var measuredCache = TokenTally()
        var rateBlocked = false
        var sawCachingAgent = false

        for (agent, ledger) in ledgers {
            guard !Task.isCancelled else { return SpendSummary() }
            // A ledger that cannot be priced has no place in a combined cost.
            // Local records and imported ones can be; a provider's own
            // statistics carry one total per model and no money.
            guard ledger.origin.supportsTokenSpend else { continue }

            for day in ledger.days where day.tokens > 0 { worked.insert(calendar.startOfDay(for: day.date)) }

            let window = cutoff == nil && upper == nil ? ledger.days : ledger.days.filter { inside($0.date) }

            // Hours stay behind an empty day window, as they always have: a
            // ledger with no day in the span does not shape the hour profile.
            // Timings do not. A quarter-hour inside the span is a timed reply
            // whether or not that day also carried a token total.
            for slot in ledger.slots where inside(slot.start) {
                guard !Task.isCancelled else { return SpendSummary() }
                if !window.isEmpty, slot.tokens > 0 {
                    hourTokens[calendar.component(.hour, from: slot.start), default: 0] += slot.tokens
                }
                for (raw, timing) in slot.timings {
                    let name = ledger.modelNames[raw] ?? raw
                    modelTimings[name] = (modelTimings[name] ?? ReplyTiming()) + timing
                    spanTiming = spanTiming + timing
                }
            }
            guard !window.isEmpty else { continue }

            var agentTokens = 0
            var agentCost = 0.0
            var agentUnpriced = 0

            for day in window {
                guard !Task.isCancelled else { return SpendSummary() }
                agentTokens += day.tokens
                agentCost += day.cost
                agentUnpriced += day.unpricedTokens
                tally = tally + day.tally

                // Only the source's explicit remainder, never total minus
                // known kinds. Check each day before combining different agents.
                let unknown = day.modelUnclassifiedTokens.values.reduce(Int?.some(0)) { total, value in
                    guard let total, value >= 0 else { return nil }
                    let (sum, overflow) = total.addingReportingOverflow(value)
                    return overflow ? nil : sum
                }
                if let unknown {
                    if !day.tally.accountsFor(tokens: day.tokens, unclassified: unknown) {
                        categoriesComplete = false
                        invalidCategoryDays.insert(day.date)
                    }
                    dayUnclassified[day.date, default: 0] += unknown
                    summary.unclassifiedTokens += unknown
                } else {
                    categoriesComplete = false
                    invalidCategoryDays.insert(day.date)
                }

                dayTokens[day.date, default: 0] += day.tokens
                dayCost[day.date, default: 0] += day.cost
                dayUnpriced[day.date, default: 0] += day.unpricedTokens
                dayTally[day.date] = (dayTally[day.date] ?? TokenTally()) + day.tally

                let recordsCache = agent.reportsCacheReads && ledger.reportsCacheReads
                for (model, tokens) in day.models {
                    let name = ledger.modelNames[model] ?? model
                    modelTokens[name, default: 0] += tokens
                    modelAgents[name, default: []].insert(agent)
                    guard tokens > 0 else { continue }
                    // The day's combined tally is not this model's. A raw id
                    // with no tally of its own, or one that does not add up
                    // to the id's tokens, leaves the name without a split.
                    let extra = day.modelUnclassifiedTokens[model] ?? 0
                    if let piece = day.modelTallies[model],
                       piece.accountsFor(tokens: tokens, unclassified: extra) {
                        modelKinds[name] = (modelKinds[name] ?? TokenTally()) + piece
                        modelExtra[name, default: 0] += extra
                        if !recordsCache {
                            modelCacheExcluded[name, default: 0] += tokens
                        }
                    } else {
                        modelUnvouched.insert(name)
                    }
                    if ledger.hasPartialCounts { modelRateBlocked.insert(name) }
                }
            }

            // **A session is counted by the part of it that falls in the
            // span, not by when it ended.** A conversation that ran past
            // midnight, or was resumed over days, used to be added whole to
            // whichever day it finished on — so a project could report
            // yesterday's $9 under today's $1. Its own quarter-hour buckets
            // are what make the window exact, and they are priced, so the
            // money is a sum rather than a proportion guessed from the total.
            for session in ledger.sessions {
                guard !Task.isCancelled else { return SpendSummary() }
                guard let windowed = Self.window(session, from: cutoff, until: upper) else { continue }

                // The row carries the span's portion, so the list and the
                // totals above it are the same arithmetic. Its `start` and
                // `end` stay the conversation's own, which is when it ran.
                summary.sessions.append(
                    Session(
                        agent: agent,
                        session: UsageLedger.Session(
                            id: session.id, name: session.name, title: session.title, isReview: session.isReview,
                            project: session.project, start: session.start, end: session.end,
                            tokens: windowed.tokens, cost: windowed.cost, unpricedTokens: windowed.unpriced, slots: session.slots, days: session.days
                        )
                    )
                )

                guard let metadata = session.project else { continue }
                let project = Project.ID(metadata, agent: agent)
                projectMetadata[project] = metadata
                projectTokens[project, default: 0] += windowed.tokens
                projectCost[project, default: 0] += windowed.cost
                projectUnpriced[project, default: 0] += windowed.unpriced
                projectSessions[project, default: 0] += 1
                projectLastUsed[project] = max(projectLastUsed[project] ?? windowed.last, windowed.last)
            }

            if agentTokens > 0 {
                let recordsCache = agent.reportsCacheReads && ledger.reportsCacheReads
                if !recordsCache {
                    // Its zeros are not hits that missed, and they are not
                    // the denominator of anyone else's rate.
                    rateBlocked = true
                } else {
                    sawCachingAgent = true
                    if ledger.hasPartialCounts {
                        rateBlocked = true
                    } else {
                        switch ledger.cacheReading(in: window) {
                        case .measured(let measured):
                            measuredCache = measuredCache + measured
                        case .unrecorded, .unvouched:
                            rateBlocked = true
                        }
                    }
                }
            }

            guard agentTokens > 0 || agentCost > 0 else { continue }

            // A ledger that contributed and had aggregate timing taints the
            // hour figure for the whole scope; a ledger that contributed
            // nothing does not. The same rule marks the total partial.
            if ledger.hasAggregateTiming { hasAggregate = true }
            if ledger.hasPartialCounts { hasPartial = true }

            summary.agents.append(
                Agent(agent: agent, tokens: agentTokens, cost: agentCost, unpricedTokens: agentUnpriced)
            )
            summary.tokens += agentTokens
            summary.cost += agentCost
            summary.unpricedTokens += agentUnpriced
            unpriced.formUnion(ledger.unpricedModels)
        }

        // Heaviest first: the list is read to find where the work went, and an
        // alphabetical one makes that a search.
        summary.agents.sort { $0.tokens > $1.tokens }

        summary.outputTokensPerSecond = spanTiming.outputTokensPerSecond
        summary.firstToken = spanTiming.meanFirstToken
        let overall = modelTokens.values.reduce(0, +)
        summary.models = modelTokens
            .map { name, tokens in
                let timing = modelTimings[name] ?? ReplyTiming()
                let unvouched = modelUnvouched.contains(name)
                let extra: Int? = unvouched ? nil : (modelExtra[name] ?? 0)
                let split: TokenTally? = {
                    guard !unvouched, let kinds = modelKinds[name], let extra else { return nil }
                    guard kinds.accountsFor(tokens: tokens, unclassified: extra) else { return nil }
                    return kinds
                }()
                let cacheMeasured = split != nil
                    && (modelCacheExcluded[name] ?? 0) == 0
                    && split?.reportsNoCache == false
                var rate: Double? = nil
                if cacheMeasured, !modelRateBlocked.contains(name), let split, extra == 0 {
                    let input = split.input + split.cacheWrite + split.cacheRead
                    if input > 0 { rate = Double(split.cacheRead) / Double(input) }
                }
                return Model(
                    name: name,
                    tokens: tokens,
                    // Sorted so a row's agents do not shuffle between reads.
                    agents: (modelAgents[name] ?? []).sorted { $0.displayName < $1.displayName },
                    share: overall > 0 ? Double(tokens) / Double(overall) : 0,
                    tally: split,
                    unclassifiedTokens: extra,
                    cacheMeasured: cacheMeasured,
                    cacheHitRate: rate,
                    tokensPerSecond: timing.outputTokensPerSecond,
                    firstToken: timing.meanFirstToken
                )
            }
            .sorted { $0.tokens > $1.tokens }

        (summary.currentStreak, summary.longestStreak) = Self.streaks(of: worked, today: today, calendar: calendar)

        // Every day in the window, including the empty ones: a chart whose
        // bars are only the days with work on them compresses a quiet
        // fortnight into nothing and reads as a busy one.
        let first = cutoff ?? dayTokens.keys.min() ?? today
        let last = upper.flatMap { calendar.date(byAdding: .day, value: -1, to: $0) }
            ?? max(today, dayTokens.keys.max() ?? today)
        // A bounded span starts where it was asked to; an `end` not after
        // `start` leaves no days rather than one before it.
        var cursor = upper == nil ? min(first, last) : first
        while cursor <= last {
            summary.days.append(
                Day(
                    date: cursor,
                    tokens: dayTokens[cursor] ?? 0,
                    cost: dayCost[cursor] ?? 0,
                    tally: dayTally[cursor] ?? TokenTally(),
                    unpricedTokens: dayUnpriced[cursor] ?? 0,
                    unclassifiedTokens: dayUnclassified[cursor] ?? 0,
                    hasInvalidCategories: invalidCategoryDays.contains(cursor)
                )
            )
            // `startOfDay` again: where DST begins at midnight (Santiago,
            // Asunción) adding a day lands on 01:00 and every later day would
            // miss its key.
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = calendar.startOfDay(for: next)
        }

        // Months are rolled up from the padded day series, so a month with no
        // work in it is still a row rather than a hole in the sequence.
        var monthTokens: [Date: Int] = [:]
        var monthCost: [Date: Double] = [:]
        var monthUnpriced: [Date: Int] = [:]
        for day in summary.days {
            guard let month = calendar.date(from: calendar.dateComponents([.year, .month], from: day.date))
            else { continue }
            monthTokens[month, default: 0] += day.tokens
            monthCost[month, default: 0] += day.cost
            monthUnpriced[month, default: 0] += day.unpricedTokens
        }
        summary.months = monthTokens
            .map {
                Day(
                    date: $0.key, tokens: $0.value, cost: monthCost[$0.key] ?? 0,
                    unpricedTokens: monthUnpriced[$0.key] ?? 0
                )
            }
            .sorted { $0.date < $1.date }

        summary.sessions.sort { $0.session.end > $1.session.end }
        let knownProjects = Set(projectMetadata.values)
        let projectNames = UsageProject.displayNames(for: knownProjects)
        let nameCounts = projectMetadata.values.reduce(into: [String: Int]()) { $0[$1.name, default: 0] += 1 }
        summary.projects = projectTokens
            .map { id, tokens in
                let metadata = projectMetadata[id]!
                var name = projectNames[metadata] ?? metadata.name
                if let agent = id.agent, (nameCounts[name] ?? 0) > (metadata.name == name ? 1 : 0) {
                    name += " · " + agent.displayName
                }
                return Project(
                    id: id, name: name,
                    tokens: tokens,
                    cost: projectCost[id] ?? 0,
                    unpricedTokens: projectUnpriced[id] ?? 0,
                    sessions: projectSessions[id] ?? 0,
                    lastUsed: projectLastUsed[id] ?? .distantPast
                )
            }
            .sorted { $0.tokens > $1.tokens }

        summary.tally = tally
        summary.hasTokenBreakdown = categoriesComplete
            && tally.accountsFor(tokens: summary.tokens, unclassified: summary.unclassifiedTokens)
        // Counts follow the kind breakdown: recorded hits, including a real
        // zero, and nothing where the cache was not recorded at all. The rate
        // is stricter. It has to describe every contributing token, so a
        // partial ledger, an unclassified remainder, an agent with no cache
        // column, or a measured subset that is not the whole tally leaves it nil.
        summary.cacheMeasured = summary.hasTokenBreakdown
            && !tally.reportsNoCache
            && sawCachingAgent
        if summary.cacheMeasured, !rateBlocked, summary.unclassifiedTokens == 0 {
            let displayed = tally.input + tally.cacheWrite + tally.cacheRead
            let measuredInput = measuredCache.input + measuredCache.cacheWrite + measuredCache.cacheRead
            if displayed > 0, measuredInput == displayed, measuredCache.cacheRead == tally.cacheRead {
                summary.cacheHitRate = Double(tally.cacheRead) / Double(displayed)
            }
        }
        summary.hours = hourTokens
        summary.unpricedModels = unpriced.sorted()
        summary.hasAggregateTiming = hasAggregate
        summary.hasPartialCounts = hasPartial

        return summary
    }
}
