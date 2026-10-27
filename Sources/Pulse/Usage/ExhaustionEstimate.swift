// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Which limit the remaining-time notices may use, and which limit may say
/// the window is expected to last.
///
/// The weekly limit, when the reading has one. A five-hour window is never
/// one of them: it turns over several times a day, and a pace taken from it
/// is not what those notices are for. A reading with no weekly limit uses
/// its longest other limit that states a length. A reading whose only limit
/// is five hours has nothing for the notices to estimate.
///
/// The card is wider than this set. `BurnRate.forecastLine` still writes a
/// time under a length-stated window this set leaves out — the five-hour
/// limit — when that window's own pace runs out before its reset. That line
/// does not say the short window will last, and these notices do not use it.
enum ExhaustionEstimate {
    /// Five hours, whether or not the provider's row was classified as that kind.
    static let fiveHourSeconds = 5 * 3_600

    static func windows(in windows: [UsageWindow]) -> [UsageWindow] {
        let periods = windows.filter(isTimeLimit)
        let weekly = periods.filter { $0.kind == .weekly }
        if !weekly.isEmpty { return weekly }
        let measurable = periods.filter(\.reportsLength)
        guard let longest = measurable.max(by: prefersShorter) else { return [] }
        return [longest]
    }

    static func includes(_ window: UsageWindow, among windows: [UsageWindow]) -> Bool {
        self.windows(in: windows).contains { $0.id == window.id }
    }

    private static func isTimeLimit(_ window: UsageWindow) -> Bool {
        if isFiveHour(window) { return false }
        switch window.kind {
        case .balance, .topUp, .messages, .spend:
            return false
        default:
            return true
        }
    }

    private static func isFiveHour(_ window: UsageWindow) -> Bool {
        if case .fiveHour = window.kind { return true }
        return window.windowSeconds == fiveHourSeconds
    }

    /// Shorter first, so `max` keeps the longest. Equal lengths keep the
    /// earlier id, which is the order the card already drew.
    private static func prefersShorter(_ lhs: UsageWindow, _ rhs: UsageWindow) -> Bool {
        if lhs.windowSeconds != rhs.windowSeconds { return lhs.windowSeconds < rhs.windowSeconds }
        return lhs.id > rhs.id
    }
}
