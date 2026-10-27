import Foundation
import Testing
import UserNotifications
@testable import Pulse

/// The notification rules, which are the reason `AlertMemory.alerts` was
/// written as a pure function in the first place: it reads no clock, no disk
/// and no notification centre, so every rule below is decidable from its
/// arguments. See [Docs/notifications.md](../../Docs/notifications.md) for why
/// each rule is the way it is — these prove that it is.
@Suite("Alert rules")
struct AlertMemoryTests {
    // MARK: - Building readings

    private static let account = AccountKey(.claudeCode)
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func window(
        _ id: String = "weekly",
        used: Double,
        resetsAt: Date? = nil,
        exhausted: Bool = false,
        kind: UsageWindow.Kind = .weekly,
        windowSeconds: Int = 7 * 86_400,
        reportsLength: Bool = true
    ) -> UsageWindow {
        UsageWindow(
            id: id,
            kind: kind,
            scope: nil,
            usedFraction: used,
            windowSeconds: windowSeconds,
            resetsAt: resetsAt,
            reportsLength: reportsLength,
            isExhausted: exhausted
        )
    }

    private static func live(_ windows: UsageWindow..., at observedAt: Date = now) -> ProviderUsage {
        ProviderUsage(
            account: account,
            windows: windows,
            observedAt: observedAt,
            state: .live,
            plan: nil,
            creditBalance: nil
        )
    }

    /// A prepaid balance and no limits — DeepSeek's shape.
    private static func balance(
        _ amount: Double,
        currency: String = "CNY",
        state: ProviderUsage.State = .live,
        at observedAt: Date = now
    ) -> ProviderUsage {
        var usage = ProviderUsage(
            account: account,
            windows: [],
            observedAt: observedAt,
            state: state,
            plan: nil,
            creditBalance: "¥\(amount)"
        )
        usage.creditRemaining = .init(amount: amount, currency: currency)
        return usage
    }

    private static func unavailable(_ reason: ProviderUsage.Unavailability) -> ProviderUsage {
        .unavailable(account, reason: reason)
    }

    private static func stale(observedAt: Date) -> ProviderUsage {
        ProviderUsage(
            account: account,
            windows: [window(used: 0.5)],
            observedAt: observedAt,
            state: .stale,
            plan: nil,
            creditBalance: nil
        )
    }

    /// Everything on, threshold at 90, unless a test says otherwise.
    private func run(
        _ memory: inout AlertMemory,
        _ reading: ProviderUsage,
        raw: ProviderUsage? = nil,
        threshold: AlertThreshold = .ninety,
        announcesReset: Bool = true,
        announcesFailure: Bool = true,
        celebratesReset: Bool = false,
        celebratesHourlyReset: Bool = false,
        staleMeansFailure: Bool = true,
        lowBalance: Double? = nil,
        announcesExhaustion: Bool = false,
        exhaustionStages: [ExhaustionStage] = [],
        announcesBeforeReset: Bool = false,
        now: Date = AlertMemoryTests.now
    ) -> [UsageAlert] {
        memory.alerts(
            for: reading,
            raw: (raw ?? reading).state,
            as: Self.account,
            threshold: threshold,
            announcesReset: announcesReset,
            announcesFailure: announcesFailure,
            celebratesReset: celebratesReset,
            celebratesHourlyReset: celebratesHourlyReset,
            lowBalance: lowBalance,
            staleMeansFailure: staleMeansFailure,
            announcesExhaustion: announcesExhaustion,
            exhaustionStages: exhaustionStages,
            announcesBeforeReset: announcesBeforeReset,
            now: now
        )
    }

    // MARK: - Low balance

    /// Providers that sell prepaid credit report no allowance to take a
    /// percentage of, so the only thing there is to warn about is the money.
    @Test("A balance under the line is announced once, and not again")
    func lowBalanceIsSaidOnce() {
        var memory = AlertMemory()

        #expect(run(&memory, Self.balance(9.40), lowBalance: 20).map(\.kind)
            == [.lowBalance(remaining: "¥9.4")])
        // Still under, still the same line, still nothing more to say.
        #expect(run(&memory, Self.balance(8), lowBalance: 20).isEmpty)
        #expect(run(&memory, Self.balance(0.5), lowBalance: 20).isEmpty)
    }

    @Test("Nothing is said while the balance is over the line")
    func aHealthyBalanceIsSilent() {
        var memory = AlertMemory()
        #expect(run(&memory, Self.balance(50), lowBalance: 20).isEmpty)
    }

    /// Credit is bought, not refilled on a schedule, so the only thing that
    /// re-arms this is the reader topping up.
    @Test("A top-up re-arms the warning")
    func toppingUpRearmsIt() {
        var memory = AlertMemory()
        #expect(run(&memory, Self.balance(9.40), lowBalance: 20).count == 1)

        #expect(run(&memory, Self.balance(100), lowBalance: 20).isEmpty)
        #expect(run(&memory, Self.balance(5), lowBalance: 20).count == 1)
    }

    /// Moving the line is asking a new question, and it deserves an answer
    /// even about a balance that was already under the old one.
    @Test("Raising the line warns again about the same balance")
    func movingTheLineWarnsAgain() {
        var memory = AlertMemory()
        #expect(run(&memory, Self.balance(9.40), lowBalance: 10).count == 1)
        #expect(run(&memory, Self.balance(9.40), lowBalance: 10).isEmpty)

        #expect(run(&memory, Self.balance(9.40), lowBalance: 50).count == 1)
    }

    @Test("No line set is no warning, however low the balance")
    func withoutALineNothingIsSaid() {
        var memory = AlertMemory()
        #expect(run(&memory, Self.balance(0.01), lowBalance: nil).isEmpty)
    }

    /// The same rule the limits follow: a stale reading carries whatever the
    /// cache last banked, and the account may have been topped up since.
    @Test("A stale balance is not warned about")
    func staleBalancesAreNotJudged() {
        var memory = AlertMemory()
        let banked = Self.balance(9.40, state: .stale)
        #expect(run(&memory, banked, raw: banked, lowBalance: 20).isEmpty)
    }

    /// A provider that reports a balance string but no figure — Codex says
    /// "Unlimited" — has said nothing this rule may act on.
    @Test("A balance with no figure behind it is not compared")
    func prosaicBalancesAreNotCompared() {
        var memory = AlertMemory()
        let unlimited = ProviderUsage(
            account: Self.account, windows: [], observedAt: Self.now,
            state: .live, plan: nil, creditBalance: "Unlimited"
        )
        #expect(run(&memory, unlimited, lowBalance: 20).isEmpty)
    }

    // MARK: - Prepaid credit is not a limit

    private static func balanceWindow(_ used: Double) -> UsageWindow {
        // What DeepSeek emits in either mode: the same id, no reset, no length.
        UsageWindow(id: "balance", kind: .balance, scope: nil, usedFraction: used,
                    windowSeconds: 30 * 86_400, resetsAt: nil,
                    reportsLength: false, estimate: .sinceTopUp)
    }

    private static func balanceReading(_ used: Double) -> ProviderUsage {
        ProviderUsage(account: account, windows: [balanceWindow(used)], observedAt: now,
                      state: .live, plan: nil, creditBalance: "¥9.40")
    }

    /// The fraction on a `.balance` row is a **setting**, not a reading: both
    /// DeepSeek modes emit the window id "balance", so switching "My budget"
    /// to "Since top-up" — or lowering the full-tank figure — moved it by
    /// forty points with the money untouched. `resetsAt` is always nil there,
    /// so the reset test collapsed to that drop alone and announced "This
    /// limit has reset" within a second of touching the picker.
    @Test("Changing what the ring measures against is not a reset")
    func aBalanceNeverResets() {
        var memory = AlertMemory()
        #expect(run(&memory, Self.balanceReading(0.90)).map(\.kind) == [.approaching(percent: 90)])

        let after = run(&memory, Self.balanceReading(0.167))
        #expect(!after.contains { $0.kind == .reset })
        #expect(after.isEmpty)
    }

    /// `is_available` is the only thing that may call a prepaid balance spent,
    /// which is what the provider's own doc promises. The fraction here is
    /// arithmetic against a denominator Pulse watched or the reader typed.
    @Test("A balance at 100% of somebody's own figure is not the provider saying it is spent")
    func aClampedBalanceIsNotSpent() {
        var memory = AlertMemory()
        // Every penny of a ¥100 full tank gone, and DeepSeek still paying.
        let alerts = run(&memory, Self.balanceReading(1))

        #expect(!alerts.contains { $0.kind == .spent })
        #expect(alerts.map(\.kind) == [.approaching(percent: 90)])
    }

    /// And the converse: when DeepSeek *does* say so, it is said.
    @Test("A balance the provider calls spent is announced")
    func theProvidersOwnVerdictIsAnnounced() {
        var memory = AlertMemory()
        var window = Self.balanceWindow(1)
        window.isExhausted = true
        let reading = ProviderUsage(account: Self.account, windows: [window], observedAt: Self.now,
                                    state: .live, plan: nil, creditBalance: "¥0.00")

        #expect(run(&memory, reading).contains { $0.kind == .spent })
    }

    // MARK: - Thresholds

    @Test("A limit already past the line is announced once, immediately")
    func firstSightingOverTheLine() {
        var memory = AlertMemory()

        let first = run(&memory, Self.live(Self.window(used: 0.93)))
        #expect(first.count == 1)
        #expect(first.first?.kind == .approaching(percent: 90))

        // Still over it on the next pass, and nothing more to say.
        #expect(run(&memory, Self.live(Self.window(used: 0.94))).isEmpty)
    }

    @Test("A limit under the line says nothing")
    func firstSightingUnderTheLine() {
        var memory = AlertMemory()
        #expect(run(&memory, Self.live(Self.window(used: 0.42))).isEmpty)
    }

    @Test("Crossing the line while Pulse is watching announces")
    func crossingTheLine() {
        var memory = AlertMemory()
        #expect(run(&memory, Self.live(Self.window(used: 0.80))).isEmpty)

        let crossed = run(&memory, Self.live(Self.window(used: 0.91)))
        #expect(crossed.map(\.kind) == [.approaching(percent: 90)])
    }

    @Test("Off means silent, however full the limit is")
    func thresholdOff() {
        var memory = AlertMemory()
        #expect(run(&memory, Self.live(Self.window(used: 1.0, exhausted: true)), threshold: .off).isEmpty)
    }

    @Test("Reconsidering a live snapshot never announces a window that already reset")
    func expiredLiveWindowIsSilent() {
        var memory = AlertMemory()
        let expired = Self.window(used: 1, resetsAt: Self.now.addingTimeInterval(-1), exhausted: true)
        #expect(run(&memory, Self.live(expired)).isEmpty)
        #expect(memory.accounts[Self.account.id]?.windows.isEmpty == true)

        let current = Self.window("weekly-current", used: 0.93, resetsAt: Self.now.addingTimeInterval(3600))
        let produced = run(&memory, Self.live(expired, current))
        #expect(produced.map(\.window?.id) == ["weekly-current"])
    }

    @Test("A live snapshot older than the cache lifetime cannot be reconsidered as current")
    func ancientLiveSnapshotIsSilent() {
        var memory = AlertMemory()
        let old = Self.live(Self.window(used: 1), at: Self.now.addingTimeInterval(-86_401))
        #expect(run(&memory, old).isEmpty)
        #expect(run(&memory, Self.live(Self.window(used: 0.93))).count == 1)
    }

    @Test("Lowering the threshold announces the step that is now crossed")
    func loweringTheThreshold() {
        var memory = AlertMemory()
        // 80% with the line at 90 records nothing announced.
        #expect(run(&memory, Self.live(Self.window(used: 0.80)), threshold: .ninety).isEmpty)

        let lowered = run(&memory, Self.live(Self.window(used: 0.80)), threshold: .seventyFive)
        #expect(lowered.map(\.kind) == [.approaching(percent: 75)])
    }

    // MARK: - Spent is the provider's word

    @Test("`isExhausted` is spent, whatever the fraction says")
    func exhaustedFlagWins() {
        var memory = AlertMemory()
        let alerts = run(&memory, Self.live(Self.window(used: 0.5, exhausted: true)))
        #expect(alerts.map(\.kind) == [.spent])
    }

    @Test("99.6% is not spent — the fraction only reaches 100 rounding down")
    func almostSpentIsNotSpent() {
        var memory = AlertMemory()
        let alerts = run(&memory, Self.live(Self.window(used: 0.996)))
        #expect(alerts.map(\.kind) == [.approaching(percent: 90)])
    }

    @Test("Spent follows the warning rather than replacing it")
    func warningThenSpent() {
        var memory = AlertMemory()
        #expect(run(&memory, Self.live(Self.window(used: 0.91))).map(\.kind) == [.approaching(percent: 90)])
        #expect(run(&memory, Self.live(Self.window(used: 1.0))).map(\.kind) == [.spent])
        // And not a third time.
        #expect(run(&memory, Self.live(Self.window(used: 1.0))).isEmpty)
    }

    // MARK: - Resets

    @Test("A reset time that moved forward is a new window")
    func resetTimeMovedForward() {
        var memory = AlertMemory()
        let first = Date(timeIntervalSince1970: 1_800_003_600)
        _ = run(&memory, Self.live(Self.window(used: 0.95, resetsAt: first)))

        let alerts = run(&memory, Self.live(Self.window(used: 0.0, resetsAt: first.addingTimeInterval(7 * 86_400))))
        #expect(alerts.map(\.kind) == [.reset])
    }

    @Test("A rolling window sliding down a few points is not a reset")
    func rollingWindowIsNotAReset() {
        var memory = AlertMemory()
        _ = run(&memory, Self.live(Self.window(used: 0.95)))

        // Kimi's week can reset anywhere inside it, so the figure drifts down
        // without anything having turned over. Six points is drift.
        #expect(run(&memory, Self.live(Self.window(used: 0.89))).isEmpty)
    }

    @Test("A window oscillating across the line is announced once, not once per wobble")
    func oscillationDoesNotReAnnounce() {
        var memory = AlertMemory()
        // Clearing the announced step on any drop — rather than on the same
        // evidence that would announce a reset — re-armed a window that had
        // not reset. A rolling allowance crossing back and forth then said
        // "93% used" again, and again, for as long as it wobbled.
        #expect(run(&memory, Self.live(Self.window(used: 0.95))).count == 1)
        #expect(run(&memory, Self.live(Self.window(used: 0.89))).isEmpty)
        #expect(run(&memory, Self.live(Self.window(used: 0.93))).isEmpty)
        #expect(run(&memory, Self.live(Self.window(used: 0.88))).isEmpty)
        #expect(run(&memory, Self.live(Self.window(used: 0.97))).isEmpty)
    }

    @Test("A real turnover still re-arms the step after an oscillation")
    func turnoverStillRearms() {
        var memory = AlertMemory()
        _ = run(&memory, Self.live(Self.window(used: 0.95)))
        _ = run(&memory, Self.live(Self.window(used: 0.89)))

        // Unambiguous this time: a forty-point drop.
        #expect(run(&memory, Self.live(Self.window(used: 0.05))).map(\.kind) == [.reset])
        #expect(run(&memory, Self.live(Self.window(used: 0.94))).map(\.kind) == [.approaching(percent: 90)])
    }

    @Test("A drop of forty points with no reset time is a reset")
    func bigDropIsAReset() {
        var memory = AlertMemory()
        _ = run(&memory, Self.live(Self.window(used: 0.95)))

        #expect(run(&memory, Self.live(Self.window(used: 0.10))).map(\.kind) == [.reset])
    }

    @Test("A window that was never warned about resets quietly")
    func unannouncedWindowResetsQuietly() {
        var memory = AlertMemory()
        let first = Date(timeIntervalSince1970: 1_800_003_600)
        _ = run(&memory, Self.live(Self.window(used: 0.12, resetsAt: first)))

        let alerts = run(&memory, Self.live(Self.window(used: 0.0, resetsAt: first.addingTimeInterval(7 * 86_400))))
        #expect(alerts.isEmpty)
    }

    @Test("A reset clears the step, so the next crossing is announced again")
    func resetRearmsTheThreshold() {
        var memory = AlertMemory()
        _ = run(&memory, Self.live(Self.window(used: 0.95)))
        _ = run(&memory, Self.live(Self.window(used: 0.10)))

        #expect(run(&memory, Self.live(Self.window(used: 0.92))).map(\.kind) == [.approaching(percent: 90)])
    }

    @Test("The reset switch off means no reset alert, but the step still clears")
    func resetSwitchOff() {
        var memory = AlertMemory()
        _ = run(&memory, Self.live(Self.window(used: 0.95)), announcesReset: false)
        #expect(run(&memory, Self.live(Self.window(used: 0.10)), announcesReset: false).isEmpty)
        #expect(run(&memory, Self.live(Self.window(used: 0.92)), announcesReset: false)
            .map(\.kind) == [.approaching(percent: 90)])
    }

    @Test("Ribbons fire on a real reset even when nobody was warned")
    func celebrationDoesNotNeedAWarning() {
        var memory = AlertMemory()
        _ = run(&memory, Self.live(Self.window(used: 0.50)), threshold: .off, celebratesReset: true)
        #expect(run(&memory, Self.live(Self.window(used: 0.0)), threshold: .off, celebratesReset: true)
            .map(\.kind) == [.celebration])
    }

    @Test("The first sighting of a low figure is not a celebration")
    func firstSightingIsNotACelebration() {
        var memory = AlertMemory()
        #expect(run(&memory, Self.live(Self.window(used: 0.0)), celebratesReset: true).isEmpty)
    }

    @Test("A warned reset is both a notification and ribbons")
    func warnedResetAlsoCelebrates() {
        var memory = AlertMemory()
        _ = run(&memory, Self.live(Self.window(used: 0.95)), celebratesReset: true)
        #expect(run(&memory, Self.live(Self.window(used: 0.10)), celebratesReset: true)
            .map(\.kind) == [.reset, .celebration])
    }

    @Test("A few points of drift is not a celebration")
    func smallDropIsNotACelebration() {
        var memory = AlertMemory()
        _ = run(&memory, Self.live(Self.window(used: 0.50)), threshold: .off, celebratesReset: true)
        #expect(run(&memory, Self.live(Self.window(used: 0.44)), threshold: .off, celebratesReset: true).isEmpty)
    }

    @Test("A reset clock that slides while usage holds is not a refill")
    func slidingClockIsNotAReset() {
        var memory = AlertMemory()
        let first = Date(timeIntervalSince1970: 1_800_003_600)
        _ = run(
            &memory,
            Self.live(Self.window(used: 0.55, resetsAt: first)),
            threshold: .off,
            celebratesReset: true
        )
        // Codex's 5-hour session pushes resetsAt as you use it. Minutes later
        // is a new clock, not a new tank.
        #expect(
            run(
                &memory,
                Self.live(Self.window(used: 0.57, resetsAt: first.addingTimeInterval(180))),
                threshold: .off,
                celebratesReset: true
            ).isEmpty
        )
    }

    @Test("A forty-point drop that rebounds, with the same reset time, is not a refill")
    func transientDropIsNotAReset() {
        var memory = AlertMemory()
        let boundary = Date(timeIntervalSince1970: 1_800_003_600)
        _ = run(
            &memory,
            Self.live(Self.window(used: 0.80, resetsAt: boundary)),
            threshold: .off,
            celebratesReset: true
        )
        // Codex has read 0% used for one sample without the window turning over.
        #expect(
            run(
                &memory,
                Self.live(Self.window(used: 0.0, resetsAt: boundary)),
                threshold: .off,
                celebratesReset: true
            ).isEmpty
        )
        #expect(
            run(
                &memory,
                Self.live(Self.window(used: 0.80, resetsAt: boundary)),
                threshold: .off,
                celebratesReset: true
            ).isEmpty
        )
    }

    @Test("A forty-point drop with an unchanged reset time is a refill only once it holds")
    func persistentDropWithSameClockConfirms() {
        var memory = AlertMemory()
        let boundary = Date(timeIntervalSince1970: 1_800_003_600)
        _ = run(
            &memory,
            Self.live(Self.window(used: 0.80, resetsAt: boundary)),
            threshold: .off,
            celebratesReset: true
        )
        #expect(
            run(
                &memory,
                Self.live(Self.window(used: 0.0, resetsAt: boundary)),
                threshold: .off,
                celebratesReset: true
            ).isEmpty
        )
        #expect(
            run(
                &memory,
                Self.live(Self.window(used: 0.0, resetsAt: boundary)),
                threshold: .off,
                celebratesReset: true
            ).map(\.kind) == [.celebration]
        )
    }

    @Test("A drop together with a new reset time is a refill on the first sample")
    func dropAndMovedClockFiresImmediately() {
        var memory = AlertMemory()
        let first = Date(timeIntervalSince1970: 1_800_003_600)
        _ = run(
            &memory,
            Self.live(Self.window(used: 0.80, resetsAt: first)),
            threshold: .off,
            celebratesReset: true
        )
        #expect(
            run(
                &memory,
                Self.live(Self.window(used: 0.0, resetsAt: first.addingTimeInterval(7 * 86_400))),
                threshold: .off,
                celebratesReset: true
            ).map(\.kind) == [.celebration]
        )
    }

    @Test("A forty-point drop with a clock that only slid a few minutes is not a refill")
    func smallClockSlideWithADropIsStillPending() {
        var memory = AlertMemory()
        let first = Date(timeIntervalSince1970: 1_800_003_600)
        _ = run(
            &memory,
            Self.live(Self.window(used: 0.80, resetsAt: first)),
            threshold: .off,
            celebratesReset: true
        )
        // Codex pushes resetsAt by the refresh interval on every poll.
        #expect(
            run(
                &memory,
                Self.live(Self.window(used: 0.0, resetsAt: first.addingTimeInterval(11 * 60))),
                threshold: .off,
                celebratesReset: true
            ).isEmpty
        )
        #expect(
            run(
                &memory,
                Self.live(Self.window(used: 0.80, resetsAt: first.addingTimeInterval(22 * 60))),
                threshold: .off,
                celebratesReset: true
            ).isEmpty
        )
    }

    @Test("A five-hour session rolling over does not throw ribbons by default")
    func sessionResetIsNotACelebrationByDefault() {
        var memory = AlertMemory()
        let first = Date(timeIntervalSince1970: 1_800_003_600)
        let session = { (used: Double, resetsAt: Date) in
            Self.window(
                "session",
                used: used,
                resetsAt: resetsAt,
                kind: .fiveHour,
                windowSeconds: 5 * 3_600
            )
        }
        _ = run(
            &memory,
            Self.live(session(0.80, first)),
            threshold: .off,
            celebratesReset: true
        )
        #expect(
            run(
                &memory,
                Self.live(session(0.0, first.addingTimeInterval(5 * 3_600))),
                threshold: .off,
                celebratesReset: true
            ).isEmpty
        )
    }

    @Test("A five-hour window throws ribbons only when hourly celebration is on")
    func fiveHourResetIsACelebrationWhenAsked() {
        var memory = AlertMemory()
        let first = Date(timeIntervalSince1970: 1_800_003_600)
        let session = { (used: Double, resetsAt: Date) in
            Self.window(
                "session",
                used: used,
                resetsAt: resetsAt,
                kind: .fiveHour,
                windowSeconds: 5 * 3_600
            )
        }
        _ = run(
            &memory,
            Self.live(session(0.80, first)),
            threshold: .off,
            celebratesReset: true,
            celebratesHourlyReset: true
        )
        #expect(
            run(
                &memory,
                Self.live(session(0.0, first.addingTimeInterval(5 * 3_600))),
                threshold: .off,
                celebratesReset: true,
                celebratesHourlyReset: true
            ).map(\.kind) == [.celebration]
        )
    }

    @Test("Hourly celebration alone does not throw ribbons")
    func hourlyFlagAloneDoesNotCelebrate() {
        var memory = AlertMemory()
        let first = Date(timeIntervalSince1970: 1_800_003_600)
        let session = { (used: Double, resetsAt: Date) in
            Self.window(
                "session",
                used: used,
                resetsAt: resetsAt,
                kind: .fiveHour,
                windowSeconds: 5 * 3_600
            )
        }
        _ = run(
            &memory,
            Self.live(session(0.80, first)),
            threshold: .off,
            celebratesReset: false,
            celebratesHourlyReset: true
        )
        #expect(
            run(
                &memory,
                Self.live(session(0.0, first.addingTimeInterval(5 * 3_600))),
                threshold: .off,
                celebratesReset: false,
                celebratesHourlyReset: true
            ).isEmpty
        )
    }

    /// Zhipu's five-hour CREDIT_LIMIT states a length and no `nextResetTime`.
    /// The only evidence a turnover can give is the drop.
    @Test("Zhipu's 5-hour limit throws ribbons when hourly celebration is on")
    func zhipuFiveHourResetCelebratesWhenAsked() {
        var memory = AlertMemory()
        let window = { (used: Double) in
            Self.window(
                "glmCoding.CREDIT_LIMIT.3-5.0",
                used: used,
                resetsAt: nil,
                kind: .fiveHour,
                windowSeconds: 5 * 3_600
            )
        }
        _ = run(
            &memory,
            Self.live(window(0.80)),
            threshold: .off,
            celebratesReset: true,
            celebratesHourlyReset: true
        )
        #expect(
            run(
                &memory,
                Self.live(window(0.0)),
                threshold: .off,
                celebratesReset: true,
                celebratesHourlyReset: true
            ).map(\.kind) == [.celebration]
        )
    }

    @Test("Zhipu's 5-hour limit stays silent when hourly celebration is off")
    func zhipuFiveHourResetIsSilentByDefault() {
        var memory = AlertMemory()
        let window = { (used: Double) in
            Self.window(
                "glmCoding.CREDIT_LIMIT.3-5.0",
                used: used,
                resetsAt: nil,
                kind: .fiveHour,
                windowSeconds: 5 * 3_600
            )
        }
        _ = run(
            &memory,
            Self.live(window(0.80)),
            threshold: .off,
            celebratesReset: true
        )
        #expect(
            run(
                &memory,
                Self.live(window(0.0)),
                threshold: .off,
                celebratesReset: true
            ).isEmpty
        )
    }

    /// Kimi's timed `limits[]` row is five hours and carries its own reset
    /// stamp. A drop together with a five-hour jump is a refill on the first
    /// sample, the same as a weekly clock moving on.
    @Test("Kimi's 5-hour limit throws ribbons when hourly celebration is on")
    func kimiFiveHourResetCelebratesWhenAsked() {
        var memory = AlertMemory()
        let first = Date(timeIntervalSince1970: 1_800_003_600)
        let window = { (used: Double, resetsAt: Date) in
            Self.window(
                "limit.0.18000",
                used: used,
                resetsAt: resetsAt,
                kind: .fiveHour,
                windowSeconds: 5 * 3_600
            )
        }
        _ = run(
            &memory,
            Self.live(window(0.80, first)),
            threshold: .off,
            celebratesReset: true,
            celebratesHourlyReset: true
        )
        #expect(
            run(
                &memory,
                Self.live(window(0.0, first.addingTimeInterval(5 * 3_600))),
                threshold: .off,
                celebratesReset: true,
                celebratesHourlyReset: true
            ).map(\.kind) == [.celebration]
        )
    }

    @Test("A five-hour clock that only slid a few minutes still waits for a second sample")
    func fiveHourCodexSlideStillNeedsConfirmation() {
        var memory = AlertMemory()
        let first = Date(timeIntervalSince1970: 1_800_003_600)
        let session = { (used: Double, resetsAt: Date) in
            Self.window(
                "session",
                used: used,
                resetsAt: resetsAt,
                kind: .fiveHour,
                windowSeconds: 5 * 3_600
            )
        }
        _ = run(
            &memory,
            Self.live(session(0.80, first)),
            threshold: .off,
            celebratesReset: true,
            celebratesHourlyReset: true
        )
        #expect(
            run(
                &memory,
                Self.live(session(0.0, first.addingTimeInterval(11 * 60))),
                threshold: .off,
                celebratesReset: true,
                celebratesHourlyReset: true
            ).isEmpty
        )
        #expect(
            run(
                &memory,
                Self.live(session(0.0, first.addingTimeInterval(22 * 60))),
                threshold: .off,
                celebratesReset: true,
                celebratesHourlyReset: true
            ).map(\.kind) == [.celebration]
        )
    }

    // MARK: - Failures

    @Test("Three failed passes in a row, then one alert and silence")
    func failureStreak() {
        var memory = AlertMemory()
        #expect(run(&memory, Self.unavailable(.unreachable)).isEmpty)
        #expect(run(&memory, Self.unavailable(.unreachable)).isEmpty)

        let third = run(&memory, Self.unavailable(.unreachable))
        #expect(third.map(\.kind) == [.unreadable(.unreachable)])

        #expect(run(&memory, Self.unavailable(.unreachable)).isEmpty)
    }

    @Test("A reading that works clears the streak")
    func successClearsTheStreak() {
        var memory = AlertMemory()
        for _ in 1...3 { _ = run(&memory, Self.unavailable(.unreachable)) }

        _ = run(&memory, Self.live(Self.window(used: 0.1)))

        #expect(run(&memory, Self.unavailable(.unreachable)).isEmpty)
        #expect(run(&memory, Self.unavailable(.unreachable)).isEmpty)
        #expect(run(&memory, Self.unavailable(.unreachable)).count == 1)
    }

    @Test("A setup step nobody has taken is not a failure, however often it is seen")
    func steadyStatesAreNotFailures() {
        for reason: ProviderUsage.Unavailability in [
            .apiKeyMissing, .notSignedIn, .antigravityNotRunning, .grokBotNotIncluded,
            .noLimitsReported, .loading, .codexNotInstalled, .volcengineSignInRequired,
            .kimiSignInRequired, .qoderSessionMissing
        ] {
            var memory = AlertMemory()
            for _ in 1...5 {
                #expect(run(&memory, Self.unavailable(reason)).isEmpty, "\(reason) should never alert")
            }
        }
    }

    @Test("A credential that went bad is a failure")
    func badCredentialsAreFailures() {
        for reason: ProviderUsage.Unavailability in [
            .claudeLoginExpired, .cursorLoginExpired, .cursorKeyRefused, .grokLoginExpired,
            .kimiLoginExpired, .qoderSessionExpired, .signedOut, .apiKeyRefused, .serverError
        ] {
            var memory = AlertMemory()
            _ = run(&memory, Self.unavailable(reason))
            _ = run(&memory, Self.unavailable(reason))
            #expect(run(&memory, Self.unavailable(reason)).count == 1, "\(reason) should alert")
        }
    }

    @Test("Failures are still counted while the limit threshold is off")
    func failuresAreIndependentOfTheThreshold() {
        var memory = AlertMemory()
        for _ in 1...2 { _ = run(&memory, Self.unavailable(.unreachable), threshold: .off) }
        #expect(run(&memory, Self.unavailable(.unreachable), threshold: .off).count == 1)
    }

    @Test("The failure switch off means silence, however long the outage")
    func failureSwitchOff() {
        var memory = AlertMemory()
        for _ in 1...5 {
            #expect(run(&memory, Self.unavailable(.unreachable), announcesFailure: false).isEmpty)
        }
    }

    // MARK: - Stale is judged on age

    @Test("Fresh figures from the cache are not a failure")
    func freshStaleIsNotAFailure() {
        var memory = AlertMemory()
        // The trap: `reconciled` returns a stale reading for a *successful*
        // fetch too, when what was banked is newer than what came back.
        let recent = Self.now.addingTimeInterval(-120)
        for _ in 1...5 {
            #expect(run(&memory, Self.stale(observedAt: recent)).isEmpty)
        }
    }

    @Test("A push route going quiet is never a failure, however old the figures")
    func pushRouteStalenessIsNotAFailure() {
        var memory = AlertMemory()
        // Claude Code's status line only writes while a session runs. Hours
        // old means nobody has used it, not that a check failed — and the
        // copy would have said "the last few checks didn't get through" about
        // checks that all got through.
        let ancient = Self.now.addingTimeInterval(-6 * 3_600)
        for _ in 1...6 {
            #expect(run(&memory, Self.stale(observedAt: ancient), staleMeansFailure: false).isEmpty)
        }
    }

    @Test("Only Claude Code's push routes are spared, and only for the primary account")
    func pushRouteIsPerRouteNotPerProvider() {
        let claude = AccountKey(.claudeCode)
        // The status line, and the automatic route that can fall back to it.
        #expect(UsageSource.tooling.reportsOnlyWhenUsed(for: claude))
        #expect(UsageSource.automatic.reportsOnlyWhenUsed(for: claude))
        // These ask a server on every pass, so silence would hide a real
        // outage — which is what asking the *provider* instead of the route
        // did, for the provider Pulse is most about.
        #expect(!UsageSource.endpoint.reportsOnlyWhenUsed(for: claude))
        #expect(!UsageSource.desktopApp.reportsOnlyWhenUsed(for: claude))
        // An added account has no status line at all: it is reached over HTTP
        // and nothing else.
        #expect(!UsageSource.automatic.reportsOnlyWhenUsed(for: AccountKey(.claudeCode, slot: "work")))
        // And no other provider has a push route.
        for provider in Provider.allCases where provider != .claudeCode {
            #expect(!UsageSource.automatic.reportsOnlyWhenUsed(for: AccountKey(provider)),
                    "\(provider) should not be spared")
        }
    }

    @Test("A complete answer ends a run of failures, including \"no plan on this account\"")
    func completeAnswersClearTheRun() {
        var memory = AlertMemory()
        // A key that authenticated and an envelope that parsed. Classed
        // neutral it cleared nothing, so an earlier outage's mark stayed set
        // and the next real one said nothing.
        for reason: ProviderUsage.Unavailability in [.zaiNoCodingPlan, .noLimitsReported, .grokBotNotIncluded] {
            memory = AlertMemory()
            for _ in 1...3 { _ = run(&memory, Self.unavailable(.unreachable)) }
            _ = run(&memory, Self.unavailable(reason))

            var produced: [UsageAlert] = []
            for _ in 1...3 { produced += run(&memory, Self.unavailable(.unreachable)) }
            #expect(produced.count == 1, "\(reason) left the reported mark stuck")
        }
    }

    @Test("Antigravity open but refusing is not a failure; nothing running is not either")
    func antigravityReasonsAreSpared() {
        var memory = AlertMemory()
        for reason: ProviderUsage.Unavailability in [.antigravityNotAnswering, .antigravityNotRunning] {
            memory = AlertMemory()
            for _ in 1...5 {
                #expect(run(&memory, Self.unavailable(reason)).isEmpty, "\(reason) alerted")
            }
        }
    }

    @Test("Figures older than half an hour are a failure")
    func agedStaleIsAFailure() {
        var memory = AlertMemory()
        let old = Self.now.addingTimeInterval(-3_600)
        _ = run(&memory, Self.stale(observedAt: old))
        _ = run(&memory, Self.stale(observedAt: old))
        #expect(run(&memory, Self.stale(observedAt: old)).map(\.kind) == [.unreadable(nil)])
    }

    @Test("A stale reading never drives the limit rules")
    func staleDoesNotDriveWindows() {
        var memory = AlertMemory()
        _ = run(&memory, Self.live(Self.window(used: 0.95)))

        // Cached windows can be lower than what was already recorded. Run
        // through the reset rules they would announce a turnover that never
        // happened.
        let cached = ProviderUsage(
            account: Self.account,
            windows: [Self.window(used: 0.10)],
            observedAt: Self.now.addingTimeInterval(-60),
            state: .stale,
            plan: nil,
            creditBalance: nil
        )
        #expect(run(&memory, cached).isEmpty)
    }

    // MARK: - Several limits at once

    @Test("Each limit is judged on its own")
    func windowsAreIndependent() {
        var memory = AlertMemory()
        let alerts = run(&memory, Self.live(
            Self.window("weekly", used: 0.95),
            Self.window("5h", used: 0.20)
        ))
        #expect(alerts.count == 1)
        #expect(alerts.first?.window?.id == "weekly")
    }

    // MARK: - Time to empty

    /// Used share that empties a half-spent weekly window in `remaining` seconds.
    private static func pace(remaining: TimeInterval, length: Double = 604_800, elapsed: Double = 0.5) -> Double {
        let elapsedSeconds = length * elapsed
        return elapsedSeconds / (remaining + elapsedSeconds)
    }

    private static func weekly(used: Double, resetsAt: Date) -> ProviderUsage {
        live(window(used: used, resetsAt: resetsAt))
    }

    private func exhaustion(
        _ memory: inout AlertMemory,
        _ reading: ProviderUsage,
        stages: [ExhaustionStage] = [],
        beforeReset: Bool = false,
        on: Bool = true
    ) -> [UsageAlert.Kind] {
        run(
            &memory, reading,
            threshold: .off, announcesReset: false, announcesFailure: false,
            announcesExhaustion: on,
            exhaustionStages: stages,
            announcesBeforeReset: beforeReset
        ).map(\.kind)
    }

    @Test("A 24-hour stage is said once, and a bounce back over it is not said again")
    func exhaustionStageDoesNotRepeat() {
        var memory = AlertMemory()
        let stage = [ExhaustionStage(id: "24h", hours: 24)]
        let resets = Self.now.addingTimeInterval(302_400)
        let close = Self.weekly(used: Self.pace(remaining: 20 * 3600), resetsAt: resets)

        let first = exhaustion(&memory, close, stages: stage)
        #expect(first.count == 1)
        guard case .exhaustion(let key, _) = first.first else {
            Issue.record("expected an exhaustion notice")
            return
        }
        #expect(key == "24h|24")
        #expect(exhaustion(
            &memory, Self.weekly(used: Self.pace(remaining: 18 * 3600), resetsAt: resets), stages: stage
        ).isEmpty)

        // Back over the line, then under it again. The stage stays spoken.
        #expect(exhaustion(
            &memory, Self.weekly(used: Self.pace(remaining: 30 * 3600), resetsAt: resets), stages: stage
        ).isEmpty)
        #expect(exhaustion(&memory, close, stages: stage).isEmpty)
    }

    @Test("A drop that is not a reset does not re-arm the stage")
    func exhaustionSurvivesAGlitch() {
        var memory = AlertMemory()
        let stage = [ExhaustionStage.defaultStage]
        let resets = Self.now.addingTimeInterval(302_400)
        let close = Self.weekly(used: Self.pace(remaining: 20 * 3600), resetsAt: resets)

        #expect(exhaustion(&memory, close, stages: stage).count == 1)
        #expect(exhaustion(&memory, Self.weekly(used: 0.2, resetsAt: resets), stages: stage).isEmpty)
        #expect(exhaustion(&memory, close, stages: stage).isEmpty)
    }

    @Test("A confirmed reset lets the same stage speak for the new window")
    func exhaustionRearmsOnReset() {
        var memory = AlertMemory()
        let stage = [ExhaustionStage.defaultStage]
        let resets = Self.now.addingTimeInterval(302_400)

        #expect(exhaustion(
            &memory, Self.weekly(used: Self.pace(remaining: 20 * 3600), resetsAt: resets), stages: stage
        ).count == 1)
        // Forty points down, and the clock jumps by more than a quarter of the week.
        let turned = resets.addingTimeInterval(200_000)
        #expect(exhaustion(&memory, Self.weekly(used: 0.1, resetsAt: turned), stages: stage).isEmpty)
        let elapsed = 1 - turned.timeIntervalSince(Self.now) / 604_800
        let again = Self.pace(remaining: 20 * 3600, elapsed: elapsed)
        #expect(exhaustion(&memory, Self.weekly(used: again, resetsAt: turned), stages: stage).count == 1)
    }

    @Test("A later stage speaks when its own time arrives, and not before")
    func exhaustionStagesAreIndependent() {
        var memory = AlertMemory()
        let stages = [
            ExhaustionStage(id: "24h", hours: 24),
            ExhaustionStage(id: "6h", hours: 6),
        ]
        let resets = Self.now.addingTimeInterval(302_400)

        let early = exhaustion(
            &memory, Self.weekly(used: Self.pace(remaining: 20 * 3600), resetsAt: resets), stages: stages
        )
        #expect(early.count == 1)
        guard case .exhaustion(let earlyKey, _) = early.first else {
            Issue.record("expected the 24-hour stage")
            return
        }
        #expect(earlyKey == "24h|24")

        let later = exhaustion(
            &memory, Self.weekly(used: Self.pace(remaining: 5 * 3600), resetsAt: resets), stages: stages
        )
        #expect(later.count == 1)
        guard case .exhaustion(let laterKey, _) = later.first else {
            Issue.record("expected the 6-hour stage")
            return
        }
        #expect(laterKey == "6h|6")
    }

    @Test("Moving a stage's hours asks again")
    func exhaustionStageHoursArePartOfTheMemory() {
        var memory = AlertMemory()
        let resets = Self.now.addingTimeInterval(302_400)
        let reading = Self.weekly(used: Self.pace(remaining: 10 * 3600), resetsAt: resets)

        #expect(exhaustion(
            &memory, reading, stages: [ExhaustionStage(id: "24h", hours: 24)]
        ).count == 1)
        #expect(exhaustion(
            &memory, reading, stages: [ExhaustionStage(id: "24h", hours: 24)]
        ).isEmpty)
        #expect(exhaustion(
            &memory, reading, stages: [ExhaustionStage(id: "24h", hours: 12)]
        ).count == 1)
    }

    @Test("The before-reset notice is separate, once, and quiet when the window is spent")
    func exhaustionBeforeResetIsOnce() {
        var memory = AlertMemory()
        let resets = Self.now.addingTimeInterval(302_400)

        let first = exhaustion(
            &memory, Self.weekly(used: Self.pace(remaining: 30 * 3600), resetsAt: resets), beforeReset: true
        )
        #expect(first.count == 1)
        guard case .exhaustionBeforeReset = first.first else {
            Issue.record("expected the before-reset notice")
            return
        }
        #expect(exhaustion(
            &memory, Self.weekly(used: Self.pace(remaining: 28 * 3600), resetsAt: resets), beforeReset: true
        ).isEmpty)

        var spent = AlertMemory()
        let gone = Self.live(Self.window(used: 1, resetsAt: resets, exhausted: true))
        #expect(run(
            &spent, gone,
            threshold: .off, announcesReset: false, announcesFailure: false,
            announcesExhaustion: true,
            exhaustionStages: [.defaultStage],
            announcesBeforeReset: true
        ).isEmpty)
    }

    @Test("Time-to-empty stays quiet when it is off, on a stale reading, or without a stated length")
    func exhaustionStaysQuiet() {
        var memory = AlertMemory()
        let resets = Self.now.addingTimeInterval(302_400)
        let reading = Self.weekly(used: Self.pace(remaining: 20 * 3600), resetsAt: resets)
        #expect(run(
            &memory, reading,
            threshold: .off, announcesReset: false, announcesFailure: false,
            announcesExhaustion: false,
            exhaustionStages: [.defaultStage],
            announcesBeforeReset: true
        ).isEmpty)

        let stale = ProviderUsage(
            account: Self.account,
            windows: [Self.window(used: Self.pace(remaining: 20 * 3600), resetsAt: resets)],
            observedAt: Self.now,
            state: .stale,
            plan: nil,
            creditBalance: nil
        )
        #expect(run(
            &memory, stale, raw: stale,
            threshold: .off, announcesReset: false, announcesFailure: false,
            announcesExhaustion: true, exhaustionStages: [.defaultStage]
        ).isEmpty)

        let unstated = Self.live(Self.window(
            used: 0.8, resetsAt: resets, reportsLength: false
        ))
        #expect(run(
            &memory, unstated,
            threshold: .off, announcesReset: false, announcesFailure: false,
            announcesExhaustion: true, exhaustionStages: [.defaultStage]
        ).isEmpty)

        // Light use with no stated length draws the card line. It does not
        // notify: the line says the window lasts, and a notice still needs
        // a pace that runs out first.
        var light = AlertMemory()
        let lasting = Self.live(Self.window(
            used: 0.06, resetsAt: resets, reportsLength: false
        ))
        #expect(run(
            &light, lasting,
            threshold: .off, announcesReset: false, announcesFailure: false,
            announcesExhaustion: true, exhaustionStages: [.defaultStage],
            announcesBeforeReset: true
        ).isEmpty)
    }

    @Test("A fast start inside the early floor does not notify; the same pace later does")
    func exhaustionStaysQuietDuringAnEarlyBurst() {
        var early = AlertMemory()
        let length = 604_800.0
        let burst = Self.weekly(used: 0.4, resetsAt: Self.now.addingTimeInterval(length * 0.99))
        #expect(exhaustion(
            &early, burst, stages: [.defaultStage], beforeReset: true
        ).isEmpty)

        var later = AlertMemory()
        let open = Self.now.addingTimeInterval(length * 0.5)
        #expect(exhaustion(
            &later,
            Self.weekly(used: Self.pace(remaining: 4 * 3600), resetsAt: open),
            stages: [.defaultStage]
        ).count == 1)
    }

    @Test("Remaining-time notices use the weekly limit, or the longest other limit")
    func exhaustionFollowsTheWeeklyLimit() {
        let stage = [ExhaustionStage.defaultStage]
        let weekResets = Self.now.addingTimeInterval(302_400)
        let week = Self.window(
            "week",
            used: Self.pace(remaining: 20 * 3600),
            resetsAt: weekResets
        )
        let fiveResets = Self.now.addingTimeInterval(9_000)
        let five = Self.window(
            "5h",
            used: Self.pace(remaining: 1_800, length: 18_000),
            resetsAt: fiveResets,
            kind: .fiveHour,
            windowSeconds: 18_000
        )

        var fiveOnly = AlertMemory()
        #expect(exhaustion(&fiveOnly, Self.live(five), stages: stage).isEmpty)
        var beforeFive = AlertMemory()
        #expect(exhaustion(&beforeFive, Self.live(five), beforeReset: true).isEmpty)

        var both = AlertMemory()
        let weeklyNotice = run(
            &both, Self.live(week, five),
            threshold: .off, announcesReset: false, announcesFailure: false,
            announcesExhaustion: true, exhaustionStages: stage
        )
        #expect(weeklyNotice.map(\.window?.id) == ["week"])

        var fiveBesideQuietWeek = AlertMemory()
        let quietWeek = Self.window("week", used: 0.2, resetsAt: weekResets)
        #expect(exhaustion(&fiveBesideQuietWeek, Self.live(quietWeek, five), stages: stage).isEmpty)

        let month = Self.window(
            "month",
            used: Self.pace(remaining: 20 * 3600, length: Double(30 * 86_400)),
            resetsAt: Self.now.addingTimeInterval(15 * 86_400),
            kind: .monthly,
            windowSeconds: 30 * 86_400
        )
        let day = Self.window(
            "day",
            used: Self.pace(remaining: 2 * 3600, length: 86_400),
            resetsAt: Self.now.addingTimeInterval(43_200),
            kind: .daily,
            windowSeconds: 86_400
        )
        var longest = AlertMemory()
        let monthNotice = run(
            &longest, Self.live(day, month),
            threshold: .off, announcesReset: false, announcesFailure: false,
            announcesExhaustion: true, exhaustionStages: stage
        )
        #expect(monthNotice.map(\.window?.id) == ["month"])

        var dailyOnly = AlertMemory()
        #expect(exhaustion(&dailyOnly, Self.live(day), stages: stage).count == 1)

        var beforeWeek = AlertMemory()
        #expect(exhaustion(
            &beforeWeek,
            Self.weekly(used: Self.pace(remaining: 30 * 3600), resetsAt: weekResets),
            beforeReset: true
        ).count == 1)

        // The percentage track still sees a five-hour window. The remaining-time
        // notices do not, even when that window is also inside a stage.
        var percent = AlertMemory()
        let hot = Self.window(
            "5h", used: 0.95, resetsAt: fiveResets, kind: .fiveHour, windowSeconds: 18_000
        )
        let warned = run(
            &percent, Self.live(hot),
            announcesExhaustion: true, exhaustionStages: stage, announcesBeforeReset: true
        )
        #expect(warned.contains { if case .approaching = $0.kind { return true } else { return false } })
        #expect(!warned.contains { if case .exhaustion = $0.kind { return true } else { return false } })
        #expect(!warned.contains { if case .exhaustionBeforeReset = $0.kind { return true } else { return false } })
    }

    @Test("An alerts file from before stages still decodes")
    func legacyAlertMemoryDecodes() throws {
        let json = """
        {"accounts":{"claudeCode":{"windows":{"weekly":{"announced":90,"fraction":0.91,"pendingReset":false}},"failures":1,"reportedFailure":false}}}
        """
        let decoded = try JSONDecoder().decode(AlertMemory.self, from: Data(json.utf8))
        let window = try #require(decoded.accounts["claudeCode"]?.windows["weekly"])
        #expect(window.announced == 90)
        #expect(window.exhaustionStages.isEmpty)
        #expect(window.exhaustionBeforeReset == false)
    }

}

/// The rules as they are actually reached: service → `UsageCache.reconciled` →
/// state machine. `AlertMemoryTests` feeds the machine directly, which is how
/// two rounds of review missed that the cache **replaces a failure with the
/// last good figures** and destroys the reason on the way past.
@Suite("Alerts through the cache")
struct AlertsThroughTheCacheTests {
    private static let account = AccountKey(.antigravity)

    private static func cache() -> UsageCache {
        UsageCache(
            file: FileManager.default.temporaryDirectory
                .appending(path: "pulse-alerts-chain-\(UUID().uuidString).json")
        )
    }

    private static func live(used: Double) -> ProviderUsage {
        ProviderUsage(
            account: account,
            windows: [UsageWindow(
                id: "5h",
                kind: .fiveHour,
                scope: nil,
                usedFraction: used,
                windowSeconds: 5 * 3_600,
                // Far enough out that the cache does not drop it as reset.
                resetsAt: Date().addingTimeInterval(4 * 3_600)
            )],
            observedAt: Date().addingTimeInterval(-2 * 3_600),
            state: .live,
            plan: nil,
            creditBalance: nil
        )
    }

    private func alerts(
        _ memory: inout AlertMemory,
        shown: ProviderUsage,
        raw: ProviderUsage
    ) -> [UsageAlert] {
        memory.alerts(
            for: shown,
            raw: raw.state,
            as: Self.account,
            threshold: .ninety,
            announcesReset: true,
            announcesFailure: true,
            celebratesReset: false,
            lowBalance: nil,
            staleMeansFailure: true,
            now: Date()
        )
    }

    @Test("Quitting Antigravity is not an outage, however old the cached figures get")
    func quittingIsNotAnOutage() async {
        let cache = Self.cache()
        var memory = AlertMemory()

        // One good reading, banked. Its figures are two hours old.
        let good = Self.live(used: 0.4)
        _ = alerts(&memory, shown: await cache.reconciled(good), raw: good)

        // Now the app is closed. The service says so — a reason the rules
        // deliberately spare — and the cache hands on those two-hour-old
        // figures marked `.stale`, which is right for the panel and used to be
        // read here as "the last few checks didn't get through".
        let closed = ProviderUsage.unavailable(Self.account, reason: .antigravityNotRunning)
        for _ in 1...6 {
            let shown = await cache.reconciled(closed)
            #expect(shown.state == .stale, "the cache should still be standing in")
            #expect(alerts(&memory, shown: shown, raw: closed).isEmpty)
        }
    }

    @Test("A real outage behind the same cache still alerts")
    func realOutageStillAlerts() async {
        let cache = Self.cache()
        var memory = AlertMemory()

        let good = Self.live(used: 0.4)
        _ = alerts(&memory, shown: await cache.reconciled(good), raw: good)

        // Identical shape on the panel — cached figures, marked stale — and a
        // completely different cause.
        let down = ProviderUsage.unavailable(Self.account, reason: .unreachable)
        var produced: [UsageAlert] = []
        for _ in 1...3 {
            produced += alerts(&memory, shown: await cache.reconciled(down), raw: down)
        }

        #expect(produced.map(\.kind) == [.unreadable(.unreachable)])
    }

    @Test("Real failures behind fresh cached figures keep the thirty-minute grace")
    func freshCacheKeepsTheGrace() async {
        let cache = Self.cache()
        var memory = AlertMemory()
        let sample = Self.live(used: 0.4)
        let now = Date()
        let good = ProviderUsage(account: Self.account, windows: sample.windows,
                                 observedAt: now, state: .live, plan: nil, creditBalance: nil)
        _ = await cache.reconciled(good)
        let down = ProviderUsage.unavailable(Self.account, reason: .unreachable)
        let shown = await cache.reconciled(down)
        #expect(shown.state == .stale)
        for seconds in [120.0, 240, 360, 1800] {
            let produced = memory.alerts(for: shown, raw: down.state, as: Self.account,
                                        threshold: .off, announcesReset: false, announcesFailure: true,
                                        celebratesReset: false, lowBalance: nil, staleMeansFailure: true, now: now.addingTimeInterval(seconds))
            #expect(produced.isEmpty)
        }
        #expect(memory.accounts[Self.account.id]?.failures == 0)
        var produced: [UsageAlert] = []
        for seconds in [1801.0, 1921, 2041] {
            produced += memory.alerts(for: shown, raw: down.state, as: Self.account,
                                      threshold: .off, announcesReset: false, announcesFailure: true,
                                      celebratesReset: false, lowBalance: nil, staleMeansFailure: true, now: now.addingTimeInterval(seconds))
        }
        #expect(produced.map(\.kind) == [.unreadable(.unreachable)])
    }

    @Test("An answer with no limits in it ends a run of failures")
    func answeredBreaksTheRun() async {
        var memory = AlertMemory()
        let down = ProviderUsage.unavailable(Self.account, reason: .unreachable)
        let answered = ProviderUsage.unavailable(Self.account, reason: .noLimitsReported)

        _ = alerts(&memory, shown: down, raw: down)
        _ = alerts(&memory, shown: down, raw: down)
        // The provider replied. It can be reached, so the run is over — this
        // used to be skipped, neither counting nor clearing, and the next
        // failure completed a "three in a row" that had been interrupted.
        #expect(alerts(&memory, shown: answered, raw: answered).isEmpty)
        #expect(alerts(&memory, shown: down, raw: down).isEmpty)
        #expect(alerts(&memory, shown: down, raw: down).isEmpty)
        #expect(alerts(&memory, shown: down, raw: down).count == 1)
    }

    @Test("And it clears the mark, so the next outage is reported")
    func answeredClearsTheReportedMark() async {
        var memory = AlertMemory()
        let down = ProviderUsage.unavailable(Self.account, reason: .unreachable)
        let answered = ProviderUsage.unavailable(Self.account, reason: .noLimitsReported)

        for _ in 1...3 { _ = alerts(&memory, shown: down, raw: down) }
        _ = alerts(&memory, shown: answered, raw: answered)

        var produced: [UsageAlert] = []
        for _ in 1...3 { produced += alerts(&memory, shown: down, raw: down) }
        #expect(produced.count == 1, "reportedFailure stayed true and silenced the next outage")
    }

    @Test("Cached figures never drive the limit rules, whatever the panel shows")
    func cachedFiguresDoNotAnnounce() async {
        let cache = Self.cache()
        var memory = AlertMemory()

        let high = Self.live(used: 0.95)
        #expect(alerts(&memory, shown: await cache.reconciled(high), raw: high).count == 1)

        // The fetch failed; the panel shows the banked 95% again. Nothing new
        // has been witnessed, so nothing may be said.
        let down = ProviderUsage.unavailable(Self.account, reason: .unreachable)
        #expect(alerts(&memory, shown: await cache.reconciled(down), raw: down).isEmpty)
    }


}

@Suite("Notification authorization")
@MainActor
struct NotificationAuthorizationTests {
    @Test("An in-flight grant does not consume readings, and concurrent requests share it", arguments: [true, false])
    func pendingAuthorizationDoesNotConsumeWarning(granted: Bool) async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "pulse-permission-\(UUID()).json")
        // Never the real `status-alerts.json`.
        let outages = FileManager.default.temporaryDirectory.appending(path: "pulse-outages-\(UUID()).json")
        let settings = AppSettings(alertThreshold: .ninety)
        let alerts = UsageAlerts(settings: settings, file: file, outageFile: outages)
        var finish: CheckedContinuation<Bool, Never>?
        let first = Task {
            await alerts.requestAuthorizationIfNeeded {
                await withCheckedContinuation { finish = $0 }
            }
        }
        while finish == nil { await Task.yield() }
        var joined = false
        var repeated = false
        let second = Task {
            joined = true
            return await alerts.requestAuthorizationIfNeeded {
                repeated = true
                return false
            }
        }
        while !joined { await Task.yield() }

        let account = AccountKey(.claudeCode)
        let reading = ProviderUsage(
            account: account,
            windows: [UsageWindow(id: "weekly", kind: .weekly, scope: nil,
                                  usedFraction: 0.93, windowSeconds: 604_800, resetsAt: nil)],
            observedAt: Date(), state: .live, plan: nil, creditBalance: nil
        )
        alerts.observe(reading, raw: reading, as: account)
        #expect(alerts.memory.accounts.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        finish?.resume(returning: granted)
        #expect(await first.value == granted)
        #expect(await second.value == granted)
        #expect(!repeated)
        var memory = alerts.memory
        #expect(memory.alerts(for: reading, raw: reading.state, as: account,
                              threshold: .ninety, announcesReset: false, announcesFailure: false,
                              celebratesReset: false, lowBalance: nil, staleMeansFailure: false, now: Date()).count == 1)
    }

    @Test("The foreground presentation callback is a real optional protocol method")
    func foregroundSelectorIsImplemented() {
        let handler = NotificationTapHandler(open: {})
        #expect(handler.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(
            _:willPresent:withCompletionHandler:
        ))))
    }
}
