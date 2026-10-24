// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Codex's account-level history: how many tokens went through, day by day,
/// plus the one-off credits that reset a rate limit early.
///
/// The history stays in settings. The card's reset-credit row is a separate
/// read of `rateLimits` (`CodexResetCredits`), so opening that card does not
/// wait on `account/usage/read`. The forecast and the latest-reset row are
/// not this history either.
///
/// Codex reports tokens here and never money, so the cost shown alongside it
/// in settings comes from `UsageLedger` instead — the local transcripts, which
/// record which model ran, priced at the rates `ModelPrices` publishes. What
/// stays here is what only Codex knows: the account's real lifetime total, and
/// the reset credits.
struct CodexAccountUsage: Equatable, Sendable {
    struct Day: Identifiable, Equatable, Sendable {
        let date: Date
        let tokens: Int

        var id: Date { date }
    }

    /// A credit that clears a rate limit ahead of its reset.
    struct ResetCredit: Equatable, Sendable {
        let title: String
        let expiresAt: Date?
    }

    let days: [Day]
    let lifetimeTokens: Int
    let peakDailyTokens: Int
    let currentStreakDays: Int
    let longestStreakDays: Int
    let availableResetCredits: Int
    /// The credit expiring soonest, which is the one worth spending first.
    let nextExpiringCredit: ResetCredit?
    /// False when the rate-limit payload omitted `rateLimitResetCredits`.
    /// That is "unknown", not a count of zero.
    let creditsKnown: Bool
    /// Whether `availableResetCredits` came from a credit list or from a
    /// count with no list. Unknown when the block itself was missing.
    let resetCreditBasis: CodexCreditSummary.Basis

    var todayTokens: Int { days.last?.tokens ?? 0 }

    func tokens(overLast days: Int) -> Int {
        self.days.suffix(days).reduce(0) { $0 + $1.tokens }
    }

    /// The tail of the history, for the chart.
    func recent(_ count: Int) -> [Day] { Array(days.suffix(count)) }
}

/// Banked reset credits, without the token history they travel with.
///
/// The open card's "how many are left" row is `CodexResetCredits`, behind its
/// own switch. This summary is the line under the Codex Resets forecast: a
/// known zero stays quiet, and an unknown read is not a summary at all.
struct CodexCreditSummary: Equatable, Sendable {
    /// Where the count came from.
    ///
    /// `countOnly` is a reply that named `availableCount` and did not include
    /// a `credits` array — the usage document's shape. `inventory` is a reply
    /// that included the array, including an empty one. A later count-only
    /// reply must not put a positive number back over an inventory that
    /// already proved none are left.
    enum Basis: Equatable, Sendable {
        case countOnly
        case inventory
    }

    var available: Int
    var nextExpiresAt: Date?
    /// Kept for the settings history card, which names the credit.
    var next: CodexAccountUsage.ResetCredit?
    var basis: Basis = .inventory

    /// A known zero is still an answer, and the card stays quiet about it.
    /// An unknown read is not a summary at all. One card whose expiry has
    /// passed is quiet too: the count was true when it was stored, and it
    /// stops being true at that instant, before the next read lands.
    func showsOnCard(at now: Date = Date()) -> Bool {
        guard available > 0 else { return false }
        if available == 1, let nextExpiresAt, nextExpiresAt <= now { return false }
        return true
    }

    /// The usage document's count, applied beside an app-server inventory.
    ///
    /// An inventory replaces whatever was showing, including a known zero.
    /// A count-only reply fills in when nothing is known yet, and it may
    /// replace another count-only reply. It does not replace an inventory:
    /// that list is the later, more specific read, and a usage snapshot of
    /// the old positive count is what kept a spent card on screen.
    static func merging(previous: CodexCreditSummary?, snapshot: CodexCreditSummary) -> CodexCreditSummary {
        if snapshot.basis == .countOnly, previous?.basis == .inventory {
            return previous ?? snapshot
        }
        return snapshot
    }
}

/// What one `account/rateLimits/read` did to the card's reset-card line.
///
/// A summary replaces whatever was showing, including a known zero.
/// `absent` is a document that arrived without a reset-credit block: the
/// previous line comes off, so a card that was spent cannot stay up just
/// because this reply left the field out. `failed` is no document at all
/// (the app server did not answer), and the previous line stays.
enum CodexCreditRead: Equatable, Sendable {
    case summary(CodexCreditSummary)
    case absent
    case failed
}

extension CodexCreditSummary {
    static func reconcile(previous: CodexCreditSummary?, read: CodexCreditRead) -> CodexCreditSummary? {
        switch read {
        case .summary(let summary): summary
        case .absent: nil
        case .failed: previous
        }
    }
}

/// The reset credits alone, as the card shows them when the switch is on.
///
/// **What Codex said, or that it said nothing.** `unreported` is a reply with
/// no reset-credit block in it, or no app server to ask; it is shown as "Not
/// available" rather than a count Pulse worked out.
enum CodexResetCredits: Equatable, Sendable {
    case available(count: Int, nextExpiry: Date?)
    case unreported
    /// No `codex` anywhere Pulse looks, so nothing was asked. Said apart from
    /// `unreported` because the remedy is different, and "Not available" for
    /// both left two Macs with several credits guessing which (issue #67).
    case codexMissing
}

/// Reads `account/usage/read` and the reset credits from `codex app-server`.
///
/// Only the app server offers these — the usage endpoint the panel normally
/// uses carries limits, not history — so this is unavailable when the `codex`
/// command can't be found.
struct CodexAccountUsageService: Sendable {
    let server: CodexAppServer

    func fetch() async -> CodexAccountUsage? {
        async let usage = server.accountUsage()
        async let limits = server.rateLimits()

        guard
            let usageData = try? await usage,
            let usageRoot = try? JSONSerialization.jsonObject(with: usageData) as? [String: Any]
        else { return nil }

        let limitsRoot = (try? await limits)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]

        return parse(usage: usageRoot, limits: limitsRoot)
    }

    /// Credits alone, for the forecast card.
    ///
    /// A thrown read is `.failed` (keep the previous line). A document with
    /// no reset-credit block is `.absent` (take the line off). A block that
    /// names a count, including zero, is a summary.
    func readCredits() async -> CodexCreditRead {
        let data: Data
        do {
            data = try await server.rateLimits()
        } catch {
            return .failed
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .failed }
        guard Self.creditBlock(in: root) != nil else { return .absent }
        guard let summary = Self.credits(from: root) else { return .absent }
        return .summary(summary)
    }

    /// Only the reset credits, from `account/rateLimits/read` — what the card
    /// asks for on every Codex refresh while its switch is on. One call, not
    /// the history's two.
    func resetCredits() async -> CodexResetCredits {
        let data: Data
        do {
            data = try await server.rateLimits()
        } catch CodexAppServer.Failure.executableNotFound {
            return .codexMissing
        } catch {
            return .unreported
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .unreported }
        return Self.resetCredits(in: root)
    }

    /// What `account/rateLimitResetCredit/consume` said.
    ///
    /// `unreported` is a reply that named none of the four outcomes, or an
    /// app server that did not answer. It is not a guess that the card was spent.
    enum ConsumeOutcome: Equatable, Sendable {
        case reset
        case nothingToReset
        case noCredit
        case alreadyRedeemed
        case unreported
    }

    /// The consume call, without a server. `creditID` is omitted when it is
    /// empty, and the app server then picks a card.
    struct ConsumeRequest: Equatable, Sendable {
        static let method = "account/rateLimitResetCredit/consume"
        var idempotencyKey: String
        var creditID: String?

        var includesCreditID: Bool {
            guard let creditID else { return false }
            return !creditID.isEmpty
        }
    }

    static func consumeRequest(idempotencyKey: String, creditID: String?) -> ConsumeRequest {
        ConsumeRequest(idempotencyKey: idempotencyKey, creditID: creditID)
    }

    /// The soonest usable row's id, when the list names one.
    static func preferredCreditID(in limits: [String: Any], now: Date = Date()) -> String? {
        guard let block = creditBlock(in: limits),
              let rows = creditRows(field(block["credits"]))
        else { return nil }
        return soonestID(in: rows.filter { isUsable($0, now: now) })
    }

    /// The consume reply. The app server returns the result object, not the
    /// JSON-RPC envelope. A name this build does not know is unreported.
    static func consumeOutcome(in object: [String: Any]) -> ConsumeOutcome {
        let named = (object["type"] as? String)
            ?? (object["outcome"] as? String)
            ?? (object["status"] as? String)
        if let named, let outcome = namedOutcome(named) { return outcome }
        for key in ["reset", "nothingToReset", "noCredit", "alreadyRedeemed"] {
            guard object[key] != nil, let outcome = namedOutcome(key) else { continue }
            return outcome
        }
        return .unreported
    }

    /// Reads the list, spends the soonest card that names an id, and reports
    /// what the app server said. Nothing here asks the reader; the card does.
    func consumeNextResetCredit() async -> ConsumeOutcome {
        let limits: Data
        do {
            limits = try await server.rateLimits()
        } catch {
            return .unreported
        }
        let root = (try? JSONSerialization.jsonObject(with: limits) as? [String: Any]) ?? [:]
        let request = Self.consumeRequest(
            idempotencyKey: UUID().uuidString,
            creditID: Self.preferredCreditID(in: root)
        )
        let data: Data
        do {
            data = try await server.consumeResetCredit(
                idempotencyKey: request.idempotencyKey,
                creditID: request.includesCreditID ? request.creditID : nil
            )
        } catch {
            return .unreported
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unreported
        }
        return Self.consumeOutcome(in: object)
    }

    private static func namedOutcome(_ raw: String) -> ConsumeOutcome? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "reset": .reset
        case "nothingToReset", "nothing_to_reset": .nothingToReset
        case "noCredit", "no_credit": .noCredit
        case "alreadyRedeemed", "already_redeemed": .alreadyRedeemed
        default: nil
        }
    }

    /// Internal and static so the parsing is testable without a server.
    ///
    /// `now` decides which `expiresAt` is still ahead. Callers that care
    /// about a fixed instant pass it; the app passes the clock.
    static func resetCredits(in limits: [String: Any], now: Date = Date()) -> CodexResetCredits {
        guard let block = creditBlock(in: limits) else { return .unreported }
        guard let inventory = inventory(in: block, now: now) else { return .unreported }
        return .available(count: inventory.count, nextExpiry: inventory.next?.expiresAt)
    }

    /// The cards still left in one reset-credit object.
    ///
    /// Nil when the object names neither a count nor a `credits` array —
    /// that is "not reported", the same as a missing block. `credits: null`
    /// is count-only. An array is the inventory.
    ///
    /// A row counts unless its status says it has been spent, or its expiry
    /// is already past. `available`, `unknown`, a missing status, and any
    /// other word count: the app server maps a status it does not recognise
    /// to `unknown`, and that credit is still inside the reported count.
    /// An empty array, or a list with nothing still usable, is zero even
    /// when the stated count is still positive — that count can lag a list
    /// that has already been spent. A shorter list keeps the higher count
    /// while at least one row is still usable.
    ///
    /// Camel case (`rateLimitResetCredits`, `availableCount`, `expiresAt`)
    /// and the usage document's snake case (`rate_limit_reset_credits`,
    /// `available_count`, `expires_at`) are the same object.
    private struct CreditInventory {
        var count: Int
        var next: CodexAccountUsage.ResetCredit?
        var basis: CodexCreditSummary.Basis
    }

    /// Statuses that are no longer a card to spend. Compared without case.
    /// Anything else, including `unknown` and a missing status, still counts.
    private static let spentStatuses: Set<String> = [
        "redeemed", "redeeming", "used", "consumed", "expired",
    ]

    /// Unix milliseconds begin at 10^10, which is year 2286 in seconds.
    /// A real `expiresAt` in seconds stays as it is.
    private static let millisecondThreshold: Double = 10_000_000_000

    private static func inventory(in block: [String: Any], now: Date) -> CreditInventory? {
        // `Int(_:)` traps past its range, and a number in somebody's JSON
        // is not bounded by anything.
        let stated: Int?
        if let value = number(field(block["availableCount"], or: block["available_count"])),
           value.isFinite, value >= 0, value < 1_000_000 {
            stated = Int(value)
        } else {
            stated = nil
        }
        guard let rows = creditRows(field(block["credits"])) else {
            guard let stated else { return nil }
            return CreditInventory(count: stated, next: nil, basis: .countOnly)
        }

        let usable = rows.filter { isUsable($0, now: now) }
        guard !usable.isEmpty else {
            return CreditInventory(count: 0, next: nil, basis: .inventory)
        }
        // A shorter list keeps the stated count, including when some of the
        // listed rows are already spent: the protocol allows the array to be
        // capped below `availableCount`. A list that is not shorter is the
        // inventory, and the usable rows are the count.
        let count: Int
        if let stated, stated > usable.count, rows.count < stated {
            count = stated
        } else {
            count = usable.count
        }
        return CreditInventory(count: count, next: soonestCredit(in: usable), basis: .inventory)
    }

    /// The first value that is present. `NSNull` is not absent to `??`, so a
    /// null camel-case field must still reach the snake-case one beside it.
    private static func field(_ value: Any?, or other: Any? = nil) -> Any? {
        if let value, !(value is NSNull) { return value }
        if let other, !(other is NSNull) { return other }
        return nil
    }

    /// The reset-credit object, under either name the two routes use.
    private static func creditBlock(in object: [String: Any]) -> [String: Any]? {
        let value = field(object["rateLimitResetCredits"], or: object["rate_limit_reset_credits"])
        return value as? [String: Any]
    }

    /// `nil` when `credits` is null or absent: only the count is known.
    /// An array, including an empty one, is the inventory.
    private static func creditRows(_ value: Any?) -> [[String: Any]]? {
        if value == nil || value is NSNull { return nil }
        if let rows = value as? [[String: Any]] { return rows }
        // JSON null is already handled. An empty array from the parser is an
        // inventory of none; a list that is not all objects is not one.
        guard let rows = value as? [Any] else { return nil }
        if rows.isEmpty { return [] }
        let objects = rows.compactMap { $0 as? [String: Any] }
        guard objects.count == rows.count else { return nil }
        return objects
    }

    /// Still redeemable. A spent status is not, and neither is an expiry that
    /// has passed, whichever status the snapshot still carries. No status, or
    /// one this build does not know, is still a card.
    private static func isUsable(_ credit: [String: Any], now: Date) -> Bool {
        if let status = (credit["status"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           spentStatuses.contains(status) {
            return false
        }
        if let expires = expiry(of: credit), expires <= now { return false }
        return true
    }

    private static func expiry(of credit: [String: Any]) -> Date? {
        expiryDate(field(credit["expiresAt"], or: credit["expires_at"]))
    }

    private static func soonestCredit(in rows: [[String: Any]]) -> CodexAccountUsage.ResetCredit? {
        rows.compactMap { row -> (CodexAccountUsage.ResetCredit, Date)? in
            guard let expires = expiry(of: row) else { return nil }
            let title = (row["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (CodexAccountUsage.ResetCredit(title: title, expiresAt: expires), expires)
        }
        .min { $0.1 < $1.1 }?
        .0
    }

    /// The id of the credit that expires first. A usable row with no date
    /// still counts, and is used when none of the usable rows named a date.
    private static func soonestID(in rows: [[String: Any]]) -> String? {
        let dated = rows.compactMap { row -> (String, Date)? in
            guard let id = creditIdentifier(row), let expires = expiry(of: row) else { return nil }
            return (id, expires)
        }
        if let soonest = dated.min(by: { $0.1 < $1.1 }) {
            return soonest.0
        }
        return rows.compactMap(creditIdentifier).first
    }

    private static func creditIdentifier(_ row: [String: Any]) -> String? {
        let value = field(row["id"], or: row["creditId"]) ?? field(row["credit_id"])
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let number = value as? NSNumber else { return nil }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        return number.stringValue
    }

    /// Unix seconds, as app-server sends them, milliseconds when the number
    /// is past any second-stamp this clock will see, or an ISO-8601 string.
    /// Anything else is no date — the card is kept, and no expiry is invented.
    private static func expiryDate(_ value: Any?) -> Date? {
        if let seconds = number(value) {
            guard seconds.isFinite, seconds > 0 else { return nil }
            let unix = seconds >= millisecondThreshold ? seconds / 1000 : seconds
            return Date(timeIntervalSince1970: unix)
        }
        if let text = value as? String {
            return CodexResetDates.parse(text)
        }
        return nil
    }

    private func parse(usage: [String: Any], limits: [String: Any]) -> CodexAccountUsage {
        let summary = usage["summary"] as? [String: Any] ?? [:]

        let days = (usage["dailyUsageBuckets"] as? [[String: Any]] ?? []).compactMap { bucket -> CodexAccountUsage.Day? in
            guard
                let text = bucket["startDate"] as? String,
                let date = Self.dayFormatter.date(from: text),
                let tokens = Self.number(bucket["tokens"])
            else { return nil }
            return CodexAccountUsage.Day(date: date, tokens: Int(tokens))
        }

        let block = Self.creditBlock(in: limits)
        let inventory = block.flatMap { Self.inventory(in: $0, now: Date()) }

        return CodexAccountUsage(
            days: days,
            lifetimeTokens: Int(Self.number(summary["lifetimeTokens"]) ?? 0),
            peakDailyTokens: Int(Self.number(summary["peakDailyTokens"]) ?? 0),
            currentStreakDays: Int(Self.number(summary["currentStreakDays"]) ?? 0),
            longestStreakDays: Int(Self.number(summary["longestStreakDays"]) ?? 0),
            availableResetCredits: inventory?.count ?? 0,
            nextExpiringCredit: inventory?.next,
            creditsKnown: inventory != nil,
            resetCreditBasis: inventory?.basis ?? .countOnly
        )
    }

    /// Nil when the field is absent, or present but names neither a count nor
    /// a list. A present count of zero is a summary. The basis says whether
    /// that count came from a list.
    static func credits(from limits: [String: Any], now: Date = Date()) -> CodexCreditSummary? {
        guard
            let block = creditBlock(in: limits),
            let inventory = inventory(in: block, now: now)
        else { return nil }
        return CodexCreditSummary(
            available: inventory.count,
            nextExpiresAt: inventory.next?.expiresAt,
            next: inventory.next,
            basis: inventory.basis
        )
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func number(_ value: Any?) -> Double? {
        (value as? Double) ?? (value as? Int).map(Double.init) ?? (value as? NSNumber)?.doubleValue
    }
}
