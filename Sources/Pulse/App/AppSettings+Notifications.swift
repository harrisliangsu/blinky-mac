// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

// The alert rules. **Off by default**, apart from the time-to-empty forecast:
// that one starts on, with a single stage at 24 hours, because a pace that
// runs out tomorrow is the thing the card is already willing to say and the
// notice exists to say it while you are looking elsewhere. The percentage
// threshold stays off. `UsageAlerts` observes the rules itself, so they do
// not go through `onChange` — which would refetch every provider for a rule
// that reads what is already on screen. (The one that does, the low-balance
// table, says why.) `onRecapAlertChange` exists so that switching the recap
// notice on in the first days of a month announces then.
//
// `UsageAlerts.isSupported` fences every entry point that talks to
// `UNUserNotificationCenter`; nothing in this file does.

extension AppSettings.Key {
    static let lowBalanceAlerts = "settings.lowBalanceAlerts"
    static let alertThreshold = "settings.alertThreshold"
    static let alertsOnReset = "settings.alertsOnReset"
    static let alertsOnFailure = "settings.alertsOnFailure"
    static let alertsOnOutage = "settings.alertsOnOutage"
    static let alertsOnRecap = "settings.alertsOnRecap"
    static let celebratesReset = "settings.celebratesReset"
    static let celebratesHourlyReset = "settings.celebratesHourlyReset"
    static let remindsBeforePredictedReset = "settings.remindsBeforePredictedReset"
    static let predictedResetLead = "settings.predictedResetLead"
    static let remindsBeforeRegularReset = "settings.remindsBeforeRegularReset"
    static let regularResetLead = "settings.regularResetLead"
    static let exhaustionAllAccounts = "settings.exhaustionAllAccounts"
    static let exhaustionAccounts = "settings.exhaustionAccounts"
    static let exhaustionCardHours = "settings.exhaustionCardHours"
    static let exhaustionSoftHint = "settings.exhaustionSoftHint"
    static let exhaustionBeforeReset = "settings.exhaustionBeforeReset"
    static let exhaustionAlerts = "settings.exhaustionAlerts"
    static let exhaustionStages = "settings.exhaustionStages"
    static let exhaustionNotifyBeforeReset = "settings.exhaustionNotifyBeforeReset"
}

extension AppSettings.Default {
    static let alertsOnReset = false
    static let alertsOnFailure = false
}

extension AppSettings {
    /// **Still `onChange`**, as it always was: this is not a layout setting,
    /// and whether a refresh is what a new threshold needs is not decided here.
    func lowBalanceAlertsChanged(from old: [String: Double]) {
        guard lowBalanceAlerts != old else { return }
        defaults.set(lowBalanceAlerts, forKey: Key.lowBalanceAlerts)
        onChange?()
    }

    func alertThresholdChanged(from old: AlertThreshold) {
        guard alertThreshold != old else { return }
        defaults.set(alertThreshold.rawValue, forKey: Key.alertThreshold)
    }

    func alertsOnResetChanged(from old: Bool) {
        guard alertsOnReset != old else { return }
        defaults.set(alertsOnReset, forKey: Key.alertsOnReset)
    }

    func alertsOnFailureChanged(from old: Bool) {
        guard alertsOnFailure != old else { return }
        defaults.set(alertsOnFailure, forKey: Key.alertsOnFailure)
    }

    func alertsOnOutageChanged(from old: Bool) {
        guard alertsOnOutage != old else { return }
        defaults.set(alertsOnOutage, forKey: Key.alertsOnOutage)
    }

    func alertsOnRecapChanged(from old: Bool) {
        guard alertsOnRecap != old else { return }
        defaults.set(alertsOnRecap, forKey: Key.alertsOnRecap)
        onRecapAlertChange?()
    }

    func celebratesResetChanged(from old: Bool) {
        guard celebratesReset != old else { return }
        defaults.set(celebratesReset, forKey: Key.celebratesReset)
    }

    func celebratesHourlyResetChanged(from old: Bool) {
        guard celebratesHourlyReset != old else { return }
        defaults.set(celebratesHourlyReset, forKey: Key.celebratesHourlyReset)
    }

    func remindsBeforePredictedResetChanged(from old: Bool) {
        guard remindsBeforePredictedReset != old else { return }
        defaults.set(remindsBeforePredictedReset, forKey: Key.remindsBeforePredictedReset)
    }

    func predictedResetLeadChanged(from old: ResetLead) {
        guard predictedResetLead != old else { return }
        defaults.set(predictedResetLead.rawValue, forKey: Key.predictedResetLead)
    }

    func remindsBeforeRegularResetChanged(from old: Bool) {
        guard remindsBeforeRegularReset != old else { return }
        defaults.set(remindsBeforeRegularReset, forKey: Key.remindsBeforeRegularReset)
    }

    func regularResetLeadChanged(from old: ResetLead) {
        guard regularResetLead != old else { return }
        defaults.set(regularResetLead.rawValue, forKey: Key.regularResetLead)
    }

    func exhaustionAllAccountsChanged(from old: Bool) {
        guard exhaustionAllAccounts != old else { return }
        defaults.set(exhaustionAllAccounts, forKey: Key.exhaustionAllAccounts)
    }

    func exhaustionAccountsChanged(from old: Set<String>) {
        guard exhaustionAccounts != old else { return }
        defaults.set(exhaustionAccounts.sorted(), forKey: Key.exhaustionAccounts)
    }

    func exhaustionCardHoursChanged(from old: Int) {
        let clamped = ExhaustionStage.clamped(exhaustionCardHours)
        if clamped != exhaustionCardHours {
            exhaustionCardHours = clamped
            return
        }
        guard exhaustionCardHours != old else { return }
        defaults.set(exhaustionCardHours, forKey: Key.exhaustionCardHours)
    }

    func exhaustionSoftHintChanged(from old: Bool) {
        guard exhaustionSoftHint != old else { return }
        defaults.set(exhaustionSoftHint, forKey: Key.exhaustionSoftHint)
    }

    func exhaustionBeforeResetChanged(from old: Bool) {
        guard exhaustionBeforeReset != old else { return }
        defaults.set(exhaustionBeforeReset, forKey: Key.exhaustionBeforeReset)
    }

    func exhaustionAlertsChanged(from old: Bool) {
        guard exhaustionAlerts != old else { return }
        defaults.set(exhaustionAlerts, forKey: Key.exhaustionAlerts)
    }

    func exhaustionStagesChanged(from old: [ExhaustionStage]) {
        let clamped = exhaustionStages.map { stage in
            var copy = stage
            copy.hours = ExhaustionStage.clamped(stage.hours)
            return copy
        }
        if clamped != exhaustionStages {
            exhaustionStages = clamped
            return
        }
        guard exhaustionStages != old else { return }
        if let data = try? JSONEncoder().encode(exhaustionStages) {
            defaults.set(data, forKey: Key.exhaustionStages)
        }
    }

    func exhaustionNotifyBeforeResetChanged(from old: Bool) {
        guard exhaustionNotifyBeforeReset != old else { return }
        defaults.set(exhaustionNotifyBeforeReset, forKey: Key.exhaustionNotifyBeforeReset)
    }

    /// Whether this account's windows are forecast at all.
    func forecastsExhaustion(for account: AccountKey) -> Bool {
        if exhaustionAllAccounts { return true }
        return exhaustionAccounts.contains(account.id)
    }

    /// Switching to a list starts from whoever is on the rail, so the first
    /// thing that happens is not every forecast going quiet.
    func setExhaustionAllAccounts(_ all: Bool) {
        if !all, exhaustionAccounts.isEmpty {
            exhaustionAccounts = Set(shownAccounts.map(\.id))
        }
        exhaustionAllAccounts = all
    }

    func setForecastsExhaustion(_ included: Bool, for account: AccountKey) {
        var next = exhaustionAccounts
        if included {
            next.insert(account.id)
        } else {
            next.remove(account.id)
        }
        exhaustionAccounts = next
    }

    func setExhaustionStageHours(id: String, hours: Int) {
        guard let index = exhaustionStages.firstIndex(where: { $0.id == id }) else { return }
        let clamped = ExhaustionStage.clamped(hours)
        // Two stages on one hour are the same notice twice. Leaving the
        // stepper where it was is quieter than posting both.
        guard !exhaustionStages.contains(where: { $0.id != id && $0.hours == clamped }) else { return }
        exhaustionStages[index].hours = clamped
    }

    /// The next free hour, starting at six. Two stages on the same hour would
    /// be the same notice twice.
    func addExhaustionStage() {
        var hours = 6
        let taken = Set(exhaustionStages.map(\.hours))
        while taken.contains(hours), hours < ExhaustionStage.maximumHours {
            hours += 1
        }
        guard !taken.contains(hours) else { return }
        exhaustionStages.append(ExhaustionStage(id: UUID().uuidString, hours: hours))
    }

    func removeExhaustionStage(id: String) {
        exhaustionStages.removeAll { $0.id == id }
    }

    /// How far out the card will state a time.
    var exhaustionCardHorizon: TimeInterval {
        TimeInterval(exhaustionCardHours) * 3600
    }

    /// The balance this account should be warned below, or nil for no warning.
    func lowBalanceAlert(for account: AccountKey) -> Double? {
        lowBalanceAlerts[account.id]
    }

    /// Anything that is not a positive figure clears it: a warning below zero
    /// can never fire, and one at zero fires only once the account is already
    /// empty, which is the moment it is too late to be told.
    func setLowBalanceAlert(_ amount: Double?, for account: AccountKey) {
        var updated = lowBalanceAlerts
        updated[account.id] = amount.flatMap { $0 > 0 ? $0 : nil }
        lowBalanceAlerts = updated
    }

    /// Whether any rule about readings is on. What `UsageAlerts.observe`
    /// works for; the outage check reads status pages, not readings.
    /// The time-to-empty notices, as distinct from the percentage threshold.
    var wantsExhaustionAlerts: Bool {
        (exhaustionAlerts && !exhaustionStages.isEmpty) || exhaustionNotifyBeforeReset
    }

    var wantsUsageAlerts: Bool {
        alertThreshold != .off || alertsOnReset || alertsOnFailure || !lowBalanceAlerts.isEmpty
            || wantsExhaustionAlerts
    }

    /// Whether anything at all would be posted. What decides if permission is
    /// worth asking for.
    var wantsAlerts: Bool {
        wantsUsageAlerts || alertsOnOutage || alertsOnRecap || !primedProviders.isEmpty
    }

    /// Predicted or regular reset reminders, which are notifications of their
    /// own and not the after-the-fact "limit came back" rule.
    var wantsAdvanceReminders: Bool {
        remindsBeforePredictedReset || remindsBeforeRegularReset
    }

    /// Anything that needs the system notification grant, including the
    /// advance reminders. Celebrations do not: they are drawn in-process.
    var wantsNotificationPermission: Bool {
        wantsAlerts || wantsAdvanceReminders
    }

    /// The settings `init` has no parameter for.
    func restoreNotifications(from defaults: UserDefaults) {
        alertsOnOutage = defaults.bool(forKey: Key.alertsOnOutage)
        alertsOnRecap = defaults.bool(forKey: Key.alertsOnRecap)
        celebratesReset = defaults.bool(forKey: Key.celebratesReset)
        celebratesHourlyReset = defaults.bool(forKey: Key.celebratesHourlyReset)
        remindsBeforePredictedReset = defaults.bool(forKey: Key.remindsBeforePredictedReset)
        predictedResetLead = (defaults.object(forKey: Key.predictedResetLead) as? Int)
            .flatMap(ResetLead.init(rawValue:)) ?? .default
        remindsBeforeRegularReset = defaults.bool(forKey: Key.remindsBeforeRegularReset)
        regularResetLead = (defaults.object(forKey: Key.regularResetLead) as? Int)
            .flatMap(ResetLead.init(rawValue:)) ?? .default
        exhaustionAllAccounts = defaults.settingsFlag(
            Key.exhaustionAllAccounts, default: true
        )
        exhaustionAccounts = Set(defaults.stringArray(forKey: Key.exhaustionAccounts) ?? [])
        if let hours = defaults.object(forKey: Key.exhaustionCardHours) as? Int {
            exhaustionCardHours = ExhaustionStage.clamped(hours)
        }
        exhaustionSoftHint = defaults.settingsFlag(Key.exhaustionSoftHint, default: true)
        exhaustionBeforeReset = defaults.settingsFlag(Key.exhaustionBeforeReset, default: true)
        exhaustionAlerts = defaults.settingsFlag(Key.exhaustionAlerts, default: true)
        // The switch in Settings reads this bit directly. Off is the shipped
        // default; a stored `true` stays on, and a stored `false` stays off.
        exhaustionNotifyBeforeReset = defaults.settingsFlag(
            Key.exhaustionNotifyBeforeReset, default: false
        )
        if let data = defaults.data(forKey: Key.exhaustionStages),
           let stored = try? JSONDecoder().decode([ExhaustionStage].self, from: data) {
            exhaustionStages = stored
        }
    }
}
