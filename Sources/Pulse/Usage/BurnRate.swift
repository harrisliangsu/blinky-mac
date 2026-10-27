// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// How a limit is being spent against its own window: whether you are ahead of
/// an even burn, and whether it will last.
///
/// **Everything here comes from one reading.** How much is gone and how far
/// through the window the clock is are both in it already — the second is what
/// draws the window-clock arc — so the pace is the difference between two
/// figures the provider reported, and the rate is the first divided by the
/// second. No history is kept, nothing is sampled, and there is no reset to
/// detect: a window that has turned over simply reports a small elapsed share
/// again.
///
/// That is not the first thing this did. It kept the last two dozen readings
/// of every window in a file and measured a *trailing* rate, which is more
/// responsive — it sees you change pace, where an average since the window
/// opened cannot. Measured over the same bursty five-hour window, that
/// responsiveness is not worth having: the trailing estimate ranged over a
/// factor of **24**, the cumulative one over 13.4, and the cumulative one is
/// free. The idea is CodexBar's; the arithmetic was checked against this
/// machine's own transcripts before it was adopted.
///
/// Two statements, and they are **not** equally trustworthy. Each is offered
/// only when the evidence carries it:
///
/// 1. **The verdict** — "expected to last". An extrapolation, but of the
///    coarsest kind: a yes or a no, which survives bursty usage far better
///    than any number does.
/// 2. **When** — "in about an hour", or, on a weekly window, "in 1d 13h".
///    A prediction, and the fragile one. The card states it only inside the
///    reader's horizon (`AppSettings.exhaustionCardHours`, six hours unless
///    they move it). Further out, the verdict can still be said.
///
/// A third was tried and taken out: the pace itself, as a signed figure
/// against an even burn. It read as a balance — "8% in reserve" under a line
/// saying "20% used" is read as *8% left*, when 80% is left — and the verdict
/// already answers the question it was supporting. A number nobody can read
/// without being taught it first is worse than no number.
enum BurnRate {
    /// Below this, a window that is still lightly used is not divided. Early
    /// on, the elapsed share is so small that dividing by it turns one burst
    /// into a rate that would empty the account before lunch. Three percent
    /// of a week is about five hours. Little spent does not need that
    /// division to be called on course (`earlyQuietUsed`).
    ///
    /// Use already at that share **is** divided, with the same arithmetic as
    /// any later reading. A heavy week right after reset is when the estimate
    /// is wanted; hiding it until the floor left the card blank for the
    /// people who needed it. The card keeps the ordinary wording and adds a
    /// quieter line that the early pace is only a guide (`Reading.earlyPace`).
    /// A reset that has already passed stays quiet. A clock that has not
    /// moved still cannot be divided, so that reading stays absent.
    ///
    /// A window with no stated length is a different sentence. It never
    /// divides, so the five-percent floor is not its hide: crossing that
    /// share is ordinary use, and treating it as "well spent" blanked Kimi's
    /// rolling week for the rest of the window. Light use there stays on
    /// course up to `lightUnstatedUsed`.
    static let minimumElapsed = 0.03

    /// Used share below which a window still inside `minimumElapsed` is said
    /// to be on course, with no time. At or above it, a stated length is
    /// divided even inside the floor.
    static let earlyQuietUsed = 0.05

    /// Used share below which a window with no stated length, and a reset
    /// still ahead, is said to be on course. The sentence does not divide.
    /// A quarter of the allowance is still light for that claim — six percent
    /// of Kimi's rolling week, with days left before the reset, is the case
    /// the five-percent floor was blanking. At or above this share there is
    /// no pace to invent, so the line stays quiet. With no reset at all, only
    /// `earlyQuietUsed` is said to last.
    static let lightUnstatedUsed = 0.25

    struct Reading: Equatable, Sendable {
        /// Whether it is on course to run out before the window resets.
        let exhaustsBeforeReset: Bool
        /// How long until it runs out, when that is before the reset.
        /// Nil when the window lasts, or when nothing may be divided.
        /// The card, not this value, decides how far out a time is worth showing.
        let timeToExhaustion: TimeInterval?
        /// The window is still inside `minimumElapsed`, use is already at
        /// `earlyQuietUsed`, and a length was stated, so the figures above
        /// are the ordinary division. The card adds a line that this early
        /// pace is only a guide. Remaining-time notices leave it alone: they
        /// would state the same figure as a fact.
        let earlyPace: Bool

        init(
            exhaustsBeforeReset: Bool,
            timeToExhaustion: TimeInterval?,
            earlyPace: Bool = false
        ) {
            self.exhaustsBeforeReset = exhaustsBeforeReset
            self.timeToExhaustion = timeToExhaustion
            self.earlyPace = earlyPace
        }
    }

    /// What may be said about a window, or nil when nothing may be.
    static func reading(for window: UsageWindow, now: Date = Date()) -> Reading? {
        let used = min(max(window.usedFraction, 0), 1)
        // `elapsedFraction` already refuses a window whose length was chosen
        // to sort by rather than reported — which is exactly the length this
        // would otherwise divide by. A sort key is not a pace. Which window
        // may say it lasts is `ExhaustionEstimate`. A shorter window this
        // reading can divide is decided in `forecastLine`.
        //
        // Light use still lasts, and that sentence does not divide. An idle
        // weekly row — Kimi's rolling week, whose seconds only sort it —
        // was returning nil here, so the card stayed blank while a window
        // that stated a length (Codex) drew a line. Holding that sentence
        // to the five-percent floor blanked the same row again once ordinary
        // use crossed it. Light use, under `lightUnstatedUsed`, keeps the
        // line. A window already a quarter spent, with no stated length,
        // stays quiet: there is no pace to invent. A reset that has already
        // passed stays quiet too.
        guard let elapsed = window.elapsedFraction(at: now),
              let resetsAt = window.resetsAt
        else {
            return unpaced(used: used, resetsAt: window.resetsAt, now: now)
        }

        let untilReset = resetsAt.timeIntervalSince(now)
        guard untilReset > 0 else { return nil }

        // Light use inside the floor is on course, and that sentence does
        // not divide. Use already at `earlyQuietUsed` falls through: the
        // same division as any later reading, marked so the card can say
        // the early pace is only a guide.
        if elapsed < minimumElapsed, used < earlyQuietUsed {
            return Reading(exhaustsBeforeReset: false, timeToExhaustion: nil)
        }
        let earlyPace = elapsed < minimumElapsed

        // The window's own length, from the two figures that describe it.
        let elapsedSeconds = untilReset / (1 - elapsed) * elapsed
        guard elapsedSeconds > 0 else { return nil }

        let perHour = used / elapsedSeconds * 3600
        guard used < 1, perHour > 0 else {
            return Reading(
                exhaustsBeforeReset: used >= 1,
                timeToExhaustion: used >= 1 ? 0 : nil,
                earlyPace: earlyPace
            )
        }

        let untilEmpty = (1 - used) / perHour * 3600
        let first = untilEmpty < untilReset

        return Reading(
            exhaustsBeforeReset: first,
            timeToExhaustion: first ? untilEmpty : nil,
            earlyPace: earlyPace
        )
    }

    /// No elapsed share, so nothing may be divided. The length was a sort key,
    /// or the reset was never stated.
    ///
    /// Reset still ahead and use still light: the window is expected to last.
    /// That is the line under a rolling week whose seconds only sort the row.
    /// At or above `lightUnstatedUsed` there is no pace to invent. A reset
    /// that has already passed stays quiet. With no reset at all, only little
    /// or nothing spent is said to last — the same floor as an early window,
    /// because there is no clock to put the use in.
    private static func unpaced(used: Double, resetsAt: Date?, now: Date) -> Reading? {
        guard let resetsAt else {
            guard used < earlyQuietUsed else { return nil }
            return Reading(exhaustsBeforeReset: false, timeToExhaustion: nil)
        }
        guard resetsAt.timeIntervalSince(now) > 0, used < lightUnstatedUsed else { return nil }
        return Reading(exhaustsBeforeReset: false, timeToExhaustion: nil)
    }

    /// "about an hour", "about 40 minutes", "1d 13h" — **rounded, because the
    /// precision is not real.** "53 minutes" claims a minute's accuracy from a
    /// figure that moves by a factor of thirteen over one afternoon. Past a
    /// day the same idea is a count of days and hours, which is what a weekly
    /// window needs: "about 37 hours" is not how anyone says a day and a half.
    static func approximate(_ seconds: TimeInterval) -> String {
        switch rounded(seconds) {
        case .underQuarter:
            return .localized("under 15 minutes")
        case .minutes(let minutes):
            return .localized("about \("\(minutes)") minutes")
        case .hour:
            return .localized("about an hour")
        case .hours(let text):
            return .localized("about \("\(text)") hours")
        case .days(let days, nil):
            return .localized("about \("\(days)")d")
        case .days(let days, let hours?):
            return .localized("about \("\(days)")d \("\(hours)")h")
        }
    }

    /// The same rounding, without the word "about". The reset sentence already
    /// says "about", and saying it twice is how "约 约 1天" gets onto the card.
    static func span(_ seconds: TimeInterval) -> String {
        switch rounded(seconds) {
        case .underQuarter:
            return .localized("\("15") minutes")
        case .minutes(let minutes):
            return .localized("\("\(minutes)") minutes")
        case .hour:
            return .localized("1 hour")
        case .hours(let text):
            return .localized("\("\(text)") hours")
        case .days(let days, nil):
            return .localized("\("\(days)")d")
        case .days(let days, let hours?):
            return .localized("\("\(days)")d \("\(hours)")h")
        }
    }

    /// What the card draws under one limit, or nil when this setting leaves
    /// the row quiet.
    struct CardLine: Equatable, Sendable {
        enum Tone: Equatable, Sendable {
            /// Inside the reader's horizon: the window's name and a time.
            case countdown
            /// Further out, but before the reset, with the time said once.
            case beforeReset
            /// The same fact, without a time.
            case hint
            /// On course to last.
            case lasts
        }

        var text: String
        var tone: Tone
        /// A quieter line under `text`. Set only while `Reading.earlyPace`
        /// is true and the line is an exhaustion estimate, not the
        /// "expected to last" sentence.
        let note: String?

        /// The forecast, and the early-pace note when there is one.
        var spoken: String {
            guard let note, !note.isEmpty else { return text }
            return "\(text) \(note)"
        }

        init(text: String, tone: Tone, note: String? = nil) {
            self.text = text
            self.tone = tone
            self.note = note
        }
    }

    /// The line under a limit.
    ///
    /// A time only inside `horizon` (six hours unless the reader moves it).
    /// Past that, the reset sentence when they asked for it, otherwise the
    /// quieter hint, otherwise nothing about an exhaustion that is still only
    /// a verdict. A window that lasts still says so: the line is either there
    /// or it is not, and appearing only for bad news makes the card jump.
    /// A reading divided inside the early floor keeps that wording and adds
    /// the early-pace note.
    static func cardLine(
        for window: UsageWindow,
        reading: Reading,
        horizon: TimeInterval,
        softHint: Bool,
        beforeReset: Bool
    ) -> CardLine? {
        if let seconds = reading.timeToExhaustion, seconds <= horizon {
            let name = window.forecastName
            let when = approximate(seconds)
            return stated(
                .localized("\(name) · may run out in \(when)"),
                tone: .countdown,
                reading: reading
            )
        }
        if reading.exhaustsBeforeReset, beforeReset, let seconds = reading.timeToExhaustion {
            let when = span(seconds)
            return stated(
                .localized("At the current pace, about \(when) before the next reset."),
                tone: .beforeReset,
                reading: reading
            )
        }
        if reading.exhaustsBeforeReset, softHint {
            let name = window.forecastName
            return stated(
                .localized("\(name) · may run out before the reset"),
                tone: .hint,
                reading: reading
            )
        }
        if !reading.exhaustsBeforeReset {
            return stated(.localized("Expected to last the window"), tone: .lasts, reading: reading)
        }
        return nil
    }

    /// The ordinary line, plus the early-pace note when this reading was
    /// divided inside `minimumElapsed`. The "expected to last" sentence is
    /// the light-use path and does not carry that note.
    private static func stated(_ text: String, tone: CardLine.Tone, reading: Reading) -> CardLine {
        CardLine(
            text: text,
            tone: tone,
            note: reading.earlyPace && tone != .lasts
                ? String.localized("A fast start. The estimate is only a guide.")
                : nil
        )
    }

    /// The line the card draws under one window.
    ///
    /// `showsForecast` is the card switch already combined with the account
    /// list. The weekly limit may say it is expected to last, or when it
    /// runs out; with no weekly limit, the longest other stated limit may.
    /// A shorter window that states a length — the five-hour limit — may
    /// say when its own pace runs out before its reset, under that row.
    /// It does not say it will last. Remaining-time notices still ignore
    /// it (`ExhaustionEstimate.windows`).
    static func forecastLine(
        for window: UsageWindow,
        among windows: [UsageWindow],
        showsForecast: Bool,
        horizon: TimeInterval,
        softHint: Bool,
        beforeReset: Bool,
        now: Date = Date()
    ) -> CardLine? {
        guard showsForecast else { return nil }
        guard let reading = reading(for: window, now: now) else { return nil }
        if !ExhaustionEstimate.includes(window, among: windows),
           !statesOwnExhaustion(window, reading: reading) {
            return nil
        }
        return cardLine(
            for: window,
            reading: reading,
            horizon: horizon,
            softHint: softHint,
            beforeReset: beforeReset
        )
    }

    /// A window the weekly line leaves out, stating the time it runs out.
    ///
    /// The length has to be one the provider reported, and the pace has to
    /// run out before this window's own reset. Balance, a top-up, messages,
    /// and spend are not that line. A window that will last stays quiet:
    /// "expected to last" belongs to the weekly line, including a week whose
    /// length is only a sort key.
    private static func statesOwnExhaustion(_ window: UsageWindow, reading: Reading) -> Bool {
        guard window.reportsLength,
              reading.exhaustsBeforeReset,
              reading.timeToExhaustion != nil
        else { return false }
        switch window.kind {
        case .balance, .topUp, .messages, .spend:
            return false
        default:
            return true
        }
    }

    private enum Rounded: Equatable {
        case underQuarter
        case minutes(Int)
        case hour
        case hours(String)
        case days(Int, Int?)
    }

    /// Under an hour in quarters; past that in halves of an hour, until a
    /// day, and then in whole hours beside whole days. The cut under an hour
    /// is at 68 rather than 75 because five quarters *is* an hour and a
    /// quarter — printing "about 75 minutes" between "about an hour" and
    /// "about 1.5 hours" reads as a different scale for one step.
    private static func rounded(_ seconds: TimeInterval) -> Rounded {
        let minutes = Int((max(seconds, 0) / 60).rounded())
        if minutes < 15 { return .underQuarter }
        if minutes < 68 {
            let quarters = max(Int((Double(minutes) / 15).rounded()), 1)
            return quarters >= 4 ? .hour : .minutes(quarters * 15)
        }
        let hours = (Double(minutes) / 60 * 2).rounded() / 2
        if hours < 24 {
            let text = hours.formatted(
                .number.precision(.fractionLength(0...1)).locale(LocalizationSource.locale)
            )
            return .hours(text)
        }
        let whole = Int(hours.rounded())
        let days = whole / 24
        let rest = whole % 24
        return .days(max(days, 1), rest == 0 ? nil : rest)
    }
}

/// How the forecast line is inked.
///
/// Lasting is green. A pace that may not last the window — the countdown,
/// the reset sentence, and the hint — is amber. Both sit under full strength
/// (`opacity`) so the line stays quieter than the percentage beside it.
/// Lasting stays regular; the amber line is a step heavier, still not bold.
struct ForecastLineInk: Equatable, Sendable {
    enum Hue: Equatable, Sendable {
        case green
        case amber
    }

    enum Weight: Equatable, Sendable {
        case regular
        case medium
    }

    var hue: Hue
    var weight: Weight

    /// Held back from 1 so neither green nor amber reads as a second alarm.
    static let opacity = 0.66

    static func style(for tone: BurnRate.CardLine.Tone) -> ForecastLineInk {
        switch tone {
        case .lasts:
            ForecastLineInk(hue: .green, weight: .regular)
        case .countdown, .beforeReset, .hint:
            ForecastLineInk(hue: .amber, weight: .medium)
        }
    }
}

/// One remaining-time notice. Several may be on at once; each fires on its own.
///
/// Stored with the notification settings. The id stays put when the hours
/// change, and the memory key includes the hours, so moving the line asks
/// again — the same rule as the low-balance figure — while a pace that
/// wobbles across the old line does not.
struct ExhaustionStage: Codable, Equatable, Sendable, Identifiable {
    var id: String
    /// Whole hours still left when this stage should speak. One hour through
    /// fourteen days: long enough for a weekly window, short of a made-up month.
    var hours: Int

    var remaining: TimeInterval { TimeInterval(hours) * 3600 }

    /// What `AlertMemory` records. The hours are part of it, so editing them
    /// is a new question and a wobble of the estimate is not.
    var memoryKey: String { "\(id)|\(hours)" }

    static let minimumHours = 1
    static let maximumHours = 24 * 14

    static func clamped(_ hours: Int) -> Int {
        min(max(hours, minimumHours), maximumHours)
    }

    /// The stage a fresh install starts with: one notice at 24 hours left.
    static let defaultStage = ExhaustionStage(id: "24h", hours: 24)
    static let defaultStages = [defaultStage]
}

/// The hours the settings stepper shows, and the value it writes.
///
/// The countdown row used to give the stepper an empty label and then hide
/// it. The chevrons drew, the number did not, and the pane never read
/// `exhaustionCardHours` while building that row, so a click did not stay.
/// The label is `digits`, which is never empty, and the binding reads the
/// setting itself rather than a copy taken before the click.
enum ExhaustionHoursControl {
    static func applied(_ hours: Int) -> Int {
        ExhaustionStage.clamped(hours)
    }

    static func digits(_ hours: Int) -> String {
        String(applied(hours))
    }
}
