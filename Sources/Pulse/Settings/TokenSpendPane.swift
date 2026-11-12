// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// Settings for Token spend: the switch that turns reading on, and the way
/// into the recap. The lists and charts live in the window beside the usage
/// card (`SpendGlanceView`), not on this pane.
struct TokenSpendPane: View {
    let settings: AppSettings
    @Bindable var model: SpendPaneModel
    /// Opens the recap window on a period.
    let openRecap: @MainActor (Recap.Period) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(String.localized("Token spend")) {
                SettingsRow(
                    String.localized("Read local usage records"),
                    subtitle: String.localized("When enabled, scans local records and exports."),
                    symbol: "doc.text.magnifyingglass"
                ) {
                    Toggle(String.localized("Read local usage records"), isOn: Binding(
                        get: { settings.readsTokenSpend },
                        set: { settings.readsTokenSpend = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                if SettingsChildRows.showsTokenSpendDetails(reading: settings.readsTokenSpend),
                   model.isScanningSpend, let progress = model.spendProgress {
                    SettingsRowDivider()
                    SettingsRow(String.localized("Reading \(progress.agent.displayName)…"), nested: true, symbol: "hourglass") {
                        Text(verbatim: "\(progress.index + 1)/\(progress.total)")
                            .monospacedDigit()
                    }
                }
                if SettingsChildRows.showsTokenSpendDetails(reading: settings.readsTokenSpend) {
                    SettingsRowDivider()
                    SettingsRow(
                        String.localized("Usage recaps"),
                        subtitle: String.localized("Shareable cards for a day, a week, a month or a year, from this Mac's records."),
                        nested: true,
                        symbol: "rectangle.stack"
                    ) {
                        // One way in. The window switches between day, week,
                        // month and year itself; a button for each period
                        // here was four buttons saying what its own control
                        // already says.
                        Button(String.localized("Open")) { openRecap(recapPeriod) }
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
        }
    }

    /// The period the recap button opens, which is the one the window would
    /// open on by itself (`RecapPeriods.defaultMonth`).
    private var recapPeriod: Recap.Period {
        RecapPeriods.defaultMonth(earliest: RecapPeriods.earliest(in: model.spendLedgers))
    }
}
