// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// What usage shows: the figures, the second ring, the reset clock, the
/// exhaustion estimate, and which accounts that estimate shares with the
/// running-out notices.
struct UsageCardPane: View {
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(String.localized("Figures")) {
                SettingsRow(
                    String.localized("Percentages at the side"),
                    subtitle: String.localized("The figure under each ring, docked left or right.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.sideRailShowsPercentages },
                        set: { settings.sideRailShowsPercentages = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Percentages across"),
                    subtitle: String.localized("When the panel lies across: docked to the top or bottom, or free.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.topRailShowsPercentages },
                        set: { settings.topRailShowsPercentages = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }

                if SettingsChildRows.showsFiguresBeside(percentagesAcross: settings.topRailShowsPercentages) {
                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Figures beside the rings"),
                        subtitle: String.localized("Only when the panel lies free across. A thinner, longer panel."),
                        nested: true
                    ) {
                        Toggle("", isOn: Binding(
                            get: { settings.freeAcrossFiguresBeside },
                            set: { settings.freeAcrossFiguresBeside = $0 }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!settings.isPanelVisible)
                    }
                }

                if SettingsChildRows.showsFigureAboveRing(
                    sidePercentages: settings.sideRailShowsPercentages,
                    acrossPercentages: settings.topRailShowsPercentages
                ) {
                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Figure above the ring"),
                        subtitle: String.localized("Swaps the two, wherever the panel is."),
                        nested: true
                    ) {
                        Toggle("", isOn: Binding(
                            get: { settings.labelAboveRing },
                            set: { settings.labelAboveRing = $0 }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!settings.isPanelVisible)
                    }
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Show what's left"),
                    subtitle: String.localized("Counts down instead of up, figure and ring together.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.showsRemaining },
                        set: { settings.showsRemaining = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Second limit inside the ring"),
                    subtitle: String.localized("A thinner ring for the next-fullest limit, where a provider has one.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.showsSecondRing },
                        set: { settings.showsSecondRing = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Time until reset"),
                    subtitle: String.localized("A second arc outside each ring, showing progress through the current window.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.showsWindowClock },
                        set: { settings.showsWindowClock = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }

                if SettingsChildRows.showsTimeRingDirection(clockOn: settings.showsWindowClock) {
                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Time ring direction"),
                        subtitle: String.localized("Choose whether the outer arc fills with elapsed time or empties with time remaining."),
                        nested: true
                    ) {
                        Picker("", selection: Binding(
                            get: { settings.windowClockDirection },
                            set: { settings.windowClockDirection = $0 }
                        )) {
                            ForEach(WindowClockDirection.allCases) { direction in
                                Text(direction.title).tag(direction)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
                        .disabled(!settings.isPanelVisible)
                    }
                }
            }

            exhaustionCardGroup
            exhaustionAccountGroup
        }
    }

    /// The estimate under the weekly limit. Usable without a notification grant.
    private var exhaustionCardGroup: some View {
        SettingsGroup(ExhaustionSettingsSections.card) {
            SettingsRow(
                String.localized("Show the estimate"),
                subtitle: String.localized("Writes a line under the weekly limit, or under the longest other limit when there is no weekly one, about how long it may last. A shorter limit that states its length, including the five-hour limit, is written under that row when the current pace runs out before its reset.")
            ) {
                Toggle("", isOn: Binding(
                    get: { settings.showsForecast },
                    set: { settings.showsForecast = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!settings.isPanelVisible)
            }

            if SettingsChildRows.showsForecastDetails(onCard: settings.showsForecast) {
                SettingsRowDivider()

                SettingsRow(
                    String.localized("Countdown up to"),
                    subtitle: String.localized("The furthest time, in hours, at which a countdown is written."),
                    nested: true
                ) {
                    ExhaustionHoursStepper(
                        hours: settings.exhaustionCardHours,
                        enabled: settings.isPanelVisible,
                        value: Binding(
                            get: { settings.exhaustionCardHours },
                            set: { settings.exhaustionCardHours = ExhaustionHoursControl.applied($0) }
                        )
                    )
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("May run out before reset"),
                    subtitle: String.localized("Further out, it says the pace may not last until the reset, and does not write a time."),
                    nested: true
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.exhaustionSoftHint },
                        set: { settings.exhaustionSoftHint = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Say roughly when"),
                    subtitle: String.localized("When the pace will not last until the reset, it writes roughly how long is left."),
                    nested: true
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.exhaustionBeforeReset },
                        set: { settings.exhaustionBeforeReset = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }
            }
        }
    }

    /// One list for the card's forecast and the exhaustion notifications.
    private var exhaustionAccountGroup: some View {
        SettingsGroup(ExhaustionSettingsSections.accounts) {
            SettingsRow(
                String.localized("Accounts"),
                subtitle: String.localized("The estimate and the running-out notices both use this list.")
            ) {
                Picker("", selection: Binding(
                    get: { settings.exhaustionAllAccounts },
                    set: { settings.setExhaustionAllAccounts($0) }
                )) {
                    Text(localized: "All shown accounts").tag(true)
                    Text(localized: "Selected accounts").tag(false)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
            }

            if SettingsChildRows.showsExhaustionAccountList(allAccounts: settings.exhaustionAllAccounts) {
                ForEach(settings.shownAccounts, id: \.id) { account in
                    SettingsRowDivider()
                    SettingsRow(settings.label(for: account), nested: true) {
                        Toggle("", isOn: Binding(
                            get: { settings.forecastsExhaustion(for: account) },
                            set: { settings.setForecastsExhaustion($0, for: account) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                }
            }
        }
    }
}
