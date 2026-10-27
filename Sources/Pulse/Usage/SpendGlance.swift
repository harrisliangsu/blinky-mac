// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import CoreGraphics
import Foundation

/// The floating summary beside the usage panel.
///
/// Arithmetic over a snapshot the pane already holds. Nothing here opens a
/// store: the window asks `AgentLedgers` for the scan it kept, and only
/// Refresh reads again.
/// Which breakdown the glance lists under the rhythm. The window shows one
/// of the four. Model is the shipped list; a stored choice is left as it is.
enum SpendGlanceDimension: String, CaseIterable, Identifiable, Sendable {
    case model
    case agent
    case project
    case session

    static let `default` = SpendGlanceDimension.model

    var id: String { rawValue }

    var title: String { title(in: LocalizationSource.bundle) }

    func title(in bundle: Bundle) -> String {
        switch self {
        case .model: String(localized: "By model", bundle: bundle)
        case .agent: String(localized: "By agent", bundle: bundle)
        case .project: String(localized: "By project", bundle: bundle)
        case .session: String(localized: "By session", bundle: bundle)
        }
    }
}

/// How large the glance writes the headline figures. Tokens stay the large
/// one whether or not a cost was priced, and the estimate under them stays
/// smaller. Both are centered. Output speed is not one of these figures: it
/// has its own section, and `speedPointSize` is that section's overall rate.
enum SpendGlanceHeadline {
    static let tokenPointSize: CGFloat = 28
    static let moneyPointSize: CGFloat = 15
    static let speedPointSize: CGFloat = 13
    static let posterTokenPointSize: CGFloat = 40
    static let posterMoneyPointSize: CGFloat = 22
    static let centersFigures = true
}

/// How the glance writes a speed. A positive rate that would round to zero
/// keeps a decimal, so a slow reply is not shown as a measured zero.
///
/// The unit is `tok/s` in every language. It is an abbreviation, the same
/// way a latency is `ms`, and it is not translated into "token/秒" or a
/// spelled-out "tokens per second".
enum OutputSpeedText {
    static func number(_ tokensPerSecond: Double, locale: Locale = LocalizationSource.locale) -> String {
        let digits: Int
        if tokensPerSecond >= 0.5 {
            digits = 0
        } else if tokensPerSecond >= 0.05 {
            digits = 1
        } else {
            digits = 2
        }
        return tokensPerSecond.formatted(
            .number.precision(.fractionLength(digits)).grouping(.never).locale(locale)
        )
    }

    static func line(
        _ tokensPerSecond: Double,
        locale: Locale = LocalizationSource.locale,
        bundle: Bundle = LocalizationSource.bundle
    ) -> String {
        let figure = number(tokensPerSecond, locale: locale)
        return String(localized: "\(figure) tok/s", bundle: bundle)
    }

    static func firstToken(
        _ seconds: TimeInterval,
        locale: Locale = LocalizationSource.locale,
        bundle: Bundle = LocalizationSource.bundle
    ) -> String {
        let digits = seconds >= 0.05 ? 1 : 2
        let figure = seconds.formatted(
            .number.precision(.fractionLength(digits)).grouping(.never).locale(locale)
        )
        return String(localized: "First token \(figure) s", bundle: bundle)
    }
}

/// The speed section under the span picker: the span's average, then each
/// model that was timed. Nothing here is a zero standing in for a missing
/// measurement, and there is no explanatory paragraph under the figure.
struct SpendSpeedSection: Equatable, Sendable {
    struct Model: Equatable, Sendable, Identifiable {
        var name: String
        /// Nil when this model recorded a first-token wait and no speed.
        var speed: String?
        var firstToken: String?
        var id: String { name }
    }

    var title: String
    /// The row that carries the span's average. "Overall", not a second copy
    /// of the section title.
    var overallTitle: String
    /// Nil when the span timed a wait and no output rate. The section can
    /// still list those models.
    var overall: String?
    /// Heaviest first, the order `SpendSummary.models` already has. A model
    /// with neither a speed nor a first-token wait is left out.
    var models: [Model]

    static func make(
        summary: SpendSummary,
        locale: Locale = LocalizationSource.locale,
        bundle: Bundle = LocalizationSource.bundle
    ) -> Self? {
        let models = summary.models.compactMap { model -> Model? in
            let speed = model.tokensPerSecond.map {
                OutputSpeedText.line($0, locale: locale, bundle: bundle)
            }
            let wait = model.firstToken.map {
                OutputSpeedText.firstToken($0, locale: locale, bundle: bundle)
            }
            guard speed != nil || wait != nil else { return nil }
            return Model(name: model.name, speed: speed, firstToken: wait)
        }
        let overall = summary.outputTokensPerSecond.map {
            OutputSpeedText.line($0, locale: locale, bundle: bundle)
        }
        guard overall != nil || !models.isEmpty else { return nil }
        return Self(
            title: String(localized: "Output speed", bundle: bundle),
            overallTitle: String(localized: "Overall", bundle: bundle),
            overall: overall,
            models: models
        )
    }
}

/// The glance body, top to bottom, under the span picker.
/// Output speed draws nothing when the span timed no reply.
enum TokenGlanceSection: String, CaseIterable, Equatable, Hashable, Sendable {
    case outputSpeed
    case tokenActivity
    case usageRhythm
    case dimension

    static let order: [TokenGlanceSection] = [.outputSpeed, .tokenActivity, .usageRhythm, .dimension]
}

/// The Pattern row. The four captions already on that row, spread across it.
enum UsageRhythm {
    static let spreadsAcrossTheRow = true

    static func metricKeys(hoursComplete: Bool, hasPeakHour: Bool, hasModel: Bool) -> [String] {
        var keys = ["Current streak", "Longest streak"]
        if hoursComplete && hasPeakHour { keys.append("Peak hour") }
        if hasModel { keys.append("Most tokens") }
        return keys
    }
}

/// "No usage data read" and the other sentences that say nothing was measured.
/// They stay on the page, and they are not the page's headline.
enum SpendQuietCopy {
    static let isPrimary = false
    static let pointSize: CGFloat = 11
}

/// How long the copied confirmation stays up. A test can pass a shorter one.
enum SpendGlanceCopy {
    static let hold: Duration = .seconds(6)
    /// The confirmation is an overlay. A line in the column moves the lists.
    static let shiftsLayout = false
}

/// Saturated colours for the glance bars. Not the accent colour: the share
/// image is rendered on a dark ground, where an accent may not resolve, and
/// a grey `Color.primary` read as one bar.
struct SpendGlanceSwatch: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    var isGrayscale: Bool { red == green && green == blue }
}

enum SpendGlancePalette {
    static let swatches: [SpendGlanceSwatch] = [
        SpendGlanceSwatch(red: 0.36, green: 0.62, blue: 0.98),
        SpendGlanceSwatch(red: 0.18, green: 0.74, blue: 0.52),
        SpendGlanceSwatch(red: 0.95, green: 0.55, blue: 0.22),
        SpendGlanceSwatch(red: 0.62, green: 0.42, blue: 0.92),
        SpendGlanceSwatch(red: 0.92, green: 0.32, blue: 0.45),
        SpendGlanceSwatch(red: 0.20, green: 0.68, blue: 0.82),
        SpendGlanceSwatch(red: 0.86, green: 0.72, blue: 0.22),
        SpendGlanceSwatch(red: 0.45, green: 0.48, blue: 0.92),
    ]

    static func swatch(at index: Int) -> SpendGlanceSwatch {
        swatches[index % swatches.count]
    }
}

enum SpendGlance {
    /// How many rows the summary lists. The rest stay on the Settings page.
    static let agentLimit = 8
    /// The mini chart's length when it is the fixed recent window (`of`).
    /// The year-long Token activity chart stays in Settings.
    static let activityDays = 14
    /// The most bars the span chart draws. A longer span is folded into this
    /// many equal buckets so a year is still one chart.
    static let maximumBars = 42

    /// The chart button on the usage card. Reading has to be on, and something
    /// has to be able to open the window. Otherwise there is no button, and
    /// the controller refuses to open one.
    static func showsEntry(reading: Bool, canOpen: Bool) -> Bool {
        reading && canOpen
    }

    /// What the headline may say about money. The same three answers as the
    /// Settings total: no figure when every token is unpriced, a marked
    /// partial when some are, and a real zero when a published rate is zero.
    enum Estimate: Equatable, Sendable {
        case none
        case unavailable
        case amount(Double, partial: Bool)

        static func of(_ summary: SpendSummary) -> Self {
            guard summary.tokens > 0 || summary.cost > 0 else { return .none }
            if summary.tokens > 0, summary.unpricedTokens == summary.tokens { return .unavailable }
            let partial = summary.unpricedTokens > 0 || summary.hasPartialCounts
            return .amount(summary.cost, partial: partial)
        }
    }

    struct AgentRow: Equatable, Sendable {
        let name: String
        let tokens: Int
        /// Nil when none of this agent's tokens had a price. A published zero stays zero.
        let cost: Double?
        let unpricedTokens: Int
        /// Share of the heaviest row, so the longest bar is the first.
        let share: Double
    }

    /// Heaviest first, ties by name, capped at `limit`. An agent with no tokens
    /// in the span is not a row.
    static func topAgents(_ summary: SpendSummary, limit: Int = agentLimit) -> [AgentRow] {
        let ranked = summary.agents
            .filter { $0.tokens > 0 }
            .sorted { lhs, rhs in
                if lhs.tokens != rhs.tokens { return lhs.tokens > rhs.tokens }
                return lhs.agent.displayName < rhs.agent.displayName
            }
        let heaviest = ranked.first?.tokens ?? 0
        return ranked.prefix(limit).map { agent in
            AgentRow(
                name: agent.agent.displayName,
                tokens: agent.tokens,
                cost: UsageLedger.shownCost(agent.cost, tokens: agent.tokens, unpriced: agent.unpricedTokens),
                unpricedTokens: agent.unpricedTokens,
                share: heaviest > 0 ? Double(agent.tokens) / Double(heaviest) : 0
            )
        }
    }

    /// The rows under the total, for the dimension the glance is showing.
    ///
    /// Agents, models, and projects are sorted heaviest first here, ties by
    /// name, and then capped, so the cap is the heaviest rows rather than
    /// whichever eight the summary happened to list first. Sessions stay in
    /// the summary's newest-first order, and then the cap. The share is of
    /// the heaviest row in that list, so the longest bar fills. A model has
    /// no cost: the summary does not price one.
    static func rows(
        _ summary: SpendSummary,
        dimension: SpendGlanceDimension,
        limit: Int = agentLimit
    ) -> [AgentRow] {
        switch dimension {
        case .agent:
            return topAgents(summary, limit: limit)
        case .model:
            let ranked = summary.models
                .filter { $0.tokens > 0 }
                .sorted { lhs, rhs in
                    if lhs.tokens != rhs.tokens { return lhs.tokens > rhs.tokens }
                    return lhs.name < rhs.name
                }
            return shared(ranked.prefix(limit).map { model in
                (model.name, model.tokens, nil, 0)
            })
        case .project:
            let ranked = summary.projects
                .filter { $0.tokens > 0 }
                .sorted { lhs, rhs in
                    if lhs.tokens != rhs.tokens { return lhs.tokens > rhs.tokens }
                    return lhs.name < rhs.name
                }
            return shared(ranked.prefix(limit).map { project in
                (project.name, project.tokens, project.estimatedCost, project.unpricedTokens)
            })
        case .session:
            return shared(
                summary.sessions.filter { $0.session.tokens > 0 }.prefix(limit).map { row in
                    (
                        row.session.label(projectName: summary.projectName(for: row)),
                        row.session.tokens,
                        row.session.estimatedCost,
                        row.session.unpricedTokens
                    )
                }
            )
        }
    }

    private static func shared(
        _ raw: [(name: String, tokens: Int, cost: Double?, unpriced: Int)]
    ) -> [AgentRow] {
        let listed = Array(raw)
        let heaviest = listed.map(\.tokens).max() ?? 0
        return listed.map { item in
            AgentRow(
                name: item.name,
                tokens: item.tokens,
                cost: item.cost,
                unpricedTokens: item.unpriced,
                share: heaviest > 0 ? Double(item.tokens) / Double(heaviest) : 0
            )
        }
    }

    /// The label in the header. A custom range names its days, because this
    /// window has no date fields under the menu the way Settings does.
    static func spanTitle(
        _ span: SpendSpan,
        custom: ClosedRange<Date>,
        calendar: Calendar = .current,
        locale: Locale = LocalizationSource.locale,
        bundle: Bundle = LocalizationSource.bundle
    ) -> String {
        guard span == .custom else { return span.title(in: bundle) }
        let style = Date.FormatStyle().month(.abbreviated).day().year().locale(locale)
        let first = calendar.startOfDay(for: custom.lowerBound)
        let last = calendar.startOfDay(for: custom.upperBound)
        let start = first.formatted(style)
        if calendar.isDate(first, inSameDayAs: last) { return start }
        return String(localized: "\(start) - \(last.formatted(style))", bundle: bundle)
    }
}

/// Bars under the glance total.
///
/// `of` is the fixed last two weeks, kept for the chart that does not follow
/// a span: a day before the first record is `nil`, and a later quiet day is
/// zero. `covering` is what the window draws. It follows the span already
/// summed — one bar an hour, one bar a day, or at most `maximumBars` buckets
/// when the span is longer — and a quiet day inside that span is zero.
/// A provider's own statistics are left out, the same gate as every Token
/// spend total.
struct SpendGlanceActivity: Equatable, Sendable {
    /// What the bars are. `recent` is `of`, the fixed last two weeks. The
    /// others follow the span the glance is showing.
    enum Coverage: Equatable, Sendable {
        case recent
        case hours
        case span
        case buckets
    }

    struct Day: Equatable, Sendable {
        let date: Date
        /// Nil before the first record, and only on `of`. A measured quiet
        /// day, including one inside a chosen span, is zero.
        let tokens: Int?
    }

    var days: [Day] = []
    var hasPartialCounts = false
    var coverage: Coverage = .recent

    var isEmpty: Bool { days.isEmpty }

    static func of(
        _ ledgers: [SpendAgent: UsageLedger],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Self {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(SpendGlance.activityDays - 1), to: today) else {
            return Self()
        }
        let windowStart = calendar.startOfDay(for: start)

        var tokensByDay: [Date: Int] = [:]
        var partial = false
        var first: Date?
        for ledger in ledgers.values {
            guard ledger.origin.supportsTokenSpend else { continue }
            var contributes = false
            for day in ledger.days where day.tokens > 0 {
                let date = calendar.startOfDay(for: day.date)
                first = min(first ?? date, date)
                guard date >= windowStart, date <= today else { continue }
                tokensByDay[date, default: 0] += day.tokens
                contributes = true
            }
            if contributes, ledger.hasPartialCounts { partial = true }
        }
        guard let first, first <= today else { return Self() }

        var days: [Day] = []
        var cursor = windowStart
        for _ in 0..<SpendGlance.activityDays {
            let date = calendar.startOfDay(for: cursor)
            guard date <= today else { break }
            if date >= calendar.startOfDay(for: first) {
                days.append(Day(date: date, tokens: tokensByDay[date] ?? 0))
            } else {
                days.append(Day(date: date, tokens: nil))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            cursor = next
        }
        return Self(days: days, hasPartialCounts: partial, coverage: .recent)
    }

    /// The chart for the span on screen.
    ///
    /// One calendar day with hourly figures is twenty-four bars. A span of at
    /// most `maximumBars` days is one bar a day, quiet days included as zero.
    /// A longer span — a year is the one that needs it — is folded into at
    /// most that many equal buckets covering the whole span. Nothing before
    /// the first record is invented as a gap here: the summary's days are
    /// already the span.
    static func covering(
        summary: SpendSummary,
        span: SpendSpan,
        custom: ClosedRange<Date>,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Self {
        if span.isOneDay(custom: custom, calendar: calendar), !summary.hours.isEmpty {
            let today = calendar.startOfDay(for: now)
            let days = (0..<24).map { hour in
                Day(
                    date: calendar.date(byAdding: .hour, value: hour, to: today) ?? today,
                    tokens: summary.hours[hour] ?? 0
                )
            }
            return Self(days: days, hasPartialCounts: summary.hasPartialCounts, coverage: .hours)
        }
        let source = summary.days
        guard !source.isEmpty else {
            return Self(hasPartialCounts: summary.hasPartialCounts, coverage: .span)
        }
        if source.count <= SpendGlance.maximumBars {
            return Self(
                days: source.map { Day(date: $0.date, tokens: $0.tokens) },
                hasPartialCounts: summary.hasPartialCounts,
                coverage: .span
            )
        }
        let groups = SpendGlance.maximumBars
        var buckets: [Day] = []
        buckets.reserveCapacity(groups)
        for index in 0..<groups {
            let start = index * source.count / groups
            let end = (index + 1) * source.count / groups
            let slice = source[start..<end]
            let tokens = slice.reduce(0) { $0 + $1.tokens }
            buckets.append(Day(date: slice.first?.date ?? source[start].date, tokens: tokens))
        }
        return Self(days: buckets, hasPartialCounts: summary.hasPartialCounts, coverage: .buckets)
    }
}

/// Where the summary window sits: on the side the provider card opens, clear
/// of that card, and inside the screen.
enum SpendGlancePlacement {
    static let gap: CGFloat = 12
    /// Close to the settings pane the lists used to fill: wide enough for the
    /// year chart, tall enough that the first screen holds the headline and
    /// the lists under it. A shorter display clamps this inside the screen.
    static let size = CGSize(width: 720, height: 780)

    static func frame(
        rail: CGRect,
        edge: PanelEdge,
        screen: CGRect,
        size: CGSize = size,
        cardClearance: CGFloat
    ) -> CGRect {
        let room = screen.insetBy(dx: 8, dy: 8)
        let preferred = beside(rail: rail, edge: edge, size: size, clearance: cardClearance)
        if room.contains(preferred) { return preferred }
        let flipped = beside(rail: rail, edge: edge.opposite, size: size, clearance: gap)
        if room.contains(flipped) { return flipped }
        return clamp(preferred, to: room)
    }

    /// The card opens away from the edge the rail's back faces.
    private static func beside(rail: CGRect, edge: PanelEdge, size: CGSize, clearance: CGFloat) -> CGRect {
        switch edge {
        case .left:
            return CGRect(
                x: rail.maxX + clearance,
                y: rail.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        case .right:
            return CGRect(
                x: rail.minX - clearance - size.width,
                y: rail.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        case .top:
            return CGRect(
                x: rail.midX - size.width / 2,
                y: rail.minY - clearance - size.height,
                width: size.width,
                height: size.height
            )
        case .bottom:
            return CGRect(
                x: rail.midX - size.width / 2,
                y: rail.maxY + clearance,
                width: size.width,
                height: size.height
            )
        }
    }

    private static func clamp(_ frame: CGRect, to room: CGRect) -> CGRect {
        var frame = frame
        frame.size.width = min(frame.width, room.width)
        frame.size.height = min(frame.height, room.height)
        if frame.maxX > room.maxX { frame.origin.x = room.maxX - frame.width }
        if frame.minX < room.minX { frame.origin.x = room.minX }
        if frame.maxY > room.maxY { frame.origin.y = room.maxY - frame.height }
        if frame.minY < room.minY { frame.origin.y = room.minY }
        return frame
    }
}

private extension PanelEdge {
    /// The side with the screen behind the rail.
    var opposite: PanelEdge {
        switch self {
        case .left: .right
        case .right: .left
        case .top: .bottom
        case .bottom: .top
        }
    }
}

/// Whether this window reads, reuses, or lets a snapshot go.
///
/// The same fences as `SpendReadState`: one read id, a cancelled predecessor
/// cannot publish, and Refresh is the only pass that bypasses the agent caches.
struct SpendGlanceRead {
    struct Request: Hashable {
        let isEnabled: Bool
        let isOpen: Bool
        let rescan: Int
    }

    enum Action: Equatable {
        case retain
        case release
        case scan(id: UUID, refresh: Bool)
    }

    private(set) var snapshot: AgentLedgers.Snapshot?
    private(set) var snapshotID: UUID?
    private var readID: UUID?
    private var consumedRescan = 0

    mutating func prepare(_ request: Request) -> Action {
        readID = nil
        guard request.isEnabled, request.isOpen else {
            snapshot = nil
            snapshotID = nil
            return .release
        }
        let refresh = request.rescan != consumedRescan
        guard snapshot == nil || refresh else { return .retain }
        snapshot = nil
        snapshotID = nil
        consumedRescan = request.rescan
        let id = UUID()
        readID = id
        return .scan(id: id, refresh: refresh)
    }

    func isCurrent(_ id: UUID) -> Bool { readID == id }

    @discardableResult
    mutating func complete(_ snapshot: AgentLedgers.Snapshot, for id: UUID) -> Bool {
        guard isCurrent(id) else { return false }
        self.snapshot = snapshot
        snapshotID = UUID()
        return true
    }

    @discardableResult
    mutating func finish(_ id: UUID) -> Bool {
        guard isCurrent(id) else { return false }
        readID = nil
        return true
    }

    /// Shows a snapshot the caller already holds, without a scan. The glance
    /// window tests use an empty one so Share can be clicked.
    mutating func install(_ snapshot: AgentLedgers.Snapshot) {
        self.snapshot = snapshot
        snapshotID = UUID()
        readID = nil
    }
}

/// The strings the share image draws. Built from the summary on screen, so a
/// path or an address would have to be put here on purpose — the session list
/// is not one of these fields.
struct SpendGlancePicture: Equatable, Sendable {
    struct Agent: Equatable, Sendable {
        var name: String
        var tokens: String
        var cost: String?
        var share: Double
    }

    struct Bar: Equatable, Sendable {
        /// Nil draws a gap. Zero draws the quiet mark.
        var tokens: Int?
        var share: Double
    }

    var brand = "Blinky"
    var span = ""
    var tokens = ""
    var cost: String?
    /// "Estimate unavailable" when nothing could be priced. A mix is not
    /// labelled here: the combined headline does not say "Partial estimate".
    var costNote: String?
    var agentsTitle = ""
    var agents: [Agent] = []
    var activityTitle = ""
    var bars: [Bar] = []
    var footnotes: [String] = []

    /// Every piece of text the image paints, in the order the poster reads them.
    var drawnText: [String] {
        var lines = [brand, span, tokens]
        if let cost { lines.append(cost) }
        if let costNote { lines.append(costNote) }
        if !agents.isEmpty { lines.append(agentsTitle) }
        for agent in agents {
            lines.append(agent.name)
            lines.append(agent.tokens)
            if let cost = agent.cost { lines.append(cost) }
        }
        if !bars.isEmpty { lines.append(activityTitle) }
        lines.append(contentsOf: footnotes)
        lines.append(brand)
        return lines
    }

    static func make(
        span: SpendSpan,
        custom: ClosedRange<Date>,
        summary: SpendSummary,
        activity: SpendGlanceActivity,
        observedAt: Date?,
        hasReadLimitations: Bool,
        dimension: SpendGlanceDimension = .default,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = LocalizationSource.locale,
        bundle: Bundle = LocalizationSource.bundle
    ) -> Self {
        let units = LocalizationSource.myriadUnits(for: locale)
        var picture = Self()
        picture.span = SpendGlance.spanTitle(
            span, custom: custom, calendar: calendar, locale: locale, bundle: bundle
        )
        picture.tokens = String(
            localized: "\(TokenCount.short(summary.tokens, units: units)) tokens",
            bundle: bundle
        )
        switch SpendGlance.Estimate.of(summary) {
        case .none:
            if summary.tokens == 0 {
                picture.tokens = String(localized: "Nothing in this span", bundle: bundle)
            }
        case .unavailable:
            picture.costNote = String(localized: "Estimate unavailable", bundle: bundle)
        case .amount(let amount, _):
            // The amount is the priced part. The headline does not add
            // "Partial estimate" under it.
            picture.cost = SpendFormat.money(amount, locale: locale)
        }
        let rows = SpendGlance.rows(summary, dimension: dimension)
        if !rows.isEmpty {
            picture.agentsTitle = dimension.title(in: bundle)
            picture.agents = rows.map { row in
                Agent(
                    name: row.name,
                    tokens: TokenCount.short(row.tokens, units: units),
                    cost: row.cost.map { cost in
                        let money = SpendFormat.money(cost, locale: locale)
                        return row.unpricedTokens > 0 ? "\(money)*" : money
                    },
                    share: row.share
                )
            }
        }
        if !activity.isEmpty {
            switch activity.coverage {
            case .recent:
                picture.activityTitle = String(
                    localized: "Last \("\(SpendGlance.activityDays)") days",
                    bundle: bundle
                )
            case .hours:
                picture.activityTitle = String(localized: "By hour", bundle: bundle)
            case .span, .buckets:
                picture.activityTitle = picture.span
            }
            let busiest = activity.days.compactMap(\.tokens).max() ?? 0
            picture.bars = activity.days.map { day in
                Bar(
                    tokens: day.tokens,
                    share: day.tokens.map { busiest > 0 ? Double($0) / Double(busiest) : 0 } ?? 0
                )
            }
        }
        if let observedAt {
            picture.footnotes.append(UsageDetailCard.updatedText(
                observedAt, now: now, locale: locale, bundle: bundle
            ))
        }
        if summary.hasPartialCounts || activity.hasPartialCounts {
            picture.footnotes.append(String(localized: "Counts may be incomplete.", bundle: bundle))
        }
        if hasReadLimitations {
            picture.footnotes.append(String(localized: "Some compressed records could not be read.", bundle: bundle))
        }
        return picture
    }
}
