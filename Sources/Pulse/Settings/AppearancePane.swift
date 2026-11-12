// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// How the rail and card look: size, spacing, the ends, the surface.
struct AppearancePane: View {
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if settings.needsProviderSelection {
                Text(localized: "Enable a service in its settings to start monitoring.")
                    .foregroundStyle(.secondary)
            }

            SettingsGroup(String.localized("Size and spacing")) {
                SettingsRow(
                    String.localized("Size"),
                    subtitle: String.localized("Size of the rail on screen."),
                    symbol: "textformat.size"
                ) {
                    Picker("", selection: Binding(
                        get: { settings.panelSize },
                        set: { settings.panelSize = $0 }
                    )) {
                        ForEach(PanelSize.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Spacing"),
                    subtitle: String.localized("How much air there is between the rings."),
                    symbol: "arrow.left.and.right"
                ) {
                    Picker("", selection: Binding(
                        get: { settings.railSpacing },
                        set: { settings.railSpacing = $0 }
                    )) {
                        ForEach(RailSpacing.allCases) { spacing in
                            Text(spacing.title).tag(spacing)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Round ends"),
                    subtitle: String.localized("The rail's ends and the card's tail follow the ring's own curve."),
                    symbol: "capsule"
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.usesRoundEnds },
                        set: { settings.usesRoundEnds = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }
            }

            SettingsGroup(String.localized("Look")) {
                // Not greyed out with the panel hidden: the menu's bars
                // follow it too.
                SettingsRow(
                    String.localized("Progress bars"),
                    subtitle: String.localized("How limit bars are drawn on the card and in the menu."),
                    symbol: "chart.bar"
                ) {
                    Picker("", selection: Binding(
                        get: { settings.usageBarStyle },
                        set: { settings.usageBarStyle = $0 }
                    )) {
                        ForEach(UsageBarStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Appearance"),
                    subtitle: String.localized("Dark, light, match the Mac, or glass."),
                    symbol: "paintpalette"
                ) {
                    Picker("", selection: Binding(
                        get: { settings.panelAppearance },
                        set: { settings.panelAppearance = $0 }
                    )) {
                        ForEach(PanelAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
                    .disabled(!settings.isPanelVisible)
                }

                // Only while glass is on: it is how clear the glass is, and on
                // a solid panel there is no glass to be clear. The percent is
                // the stored fraction, shown, not a second setting.
                if SettingsChildRows.showsTransparency(usesGlass: settings.usesGlass) {
                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Transparency"),
                        subtitle: String.localized("Clearer to the right, and the text turns from white to black. Black text is hard to read over dark windows."),
                        nested: true,
                        symbol: "circle.lefthalf.filled"
                    ) {
                        HStack(spacing: 8) {
                            Text(verbatim: GlassTransparencyLabel.percent(settings.glassTransparency))
                                .font(.system(size: 13).monospacedDigit())
                                .frame(minWidth: 44, alignment: .trailing)
                            Slider(
                                value: Binding(
                                    get: { settings.glassTransparency },
                                    set: { settings.glassTransparency = $0 }
                                ),
                                in: 0...1
                            )
                            .labelsHidden()
                            .frame(width: SettingsLayout.controlWidth - 52)
                        }
                        .disabled(!settings.isPanelVisible)
                    }
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Ring activity animation"),
                    subtitle: String.localized("The turning mark for a working CLI or a reading being fetched. Off leaves the ring still."),
                    symbol: "circle.dashed"
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.animatesRingActivity },
                        set: { settings.animatesRingActivity = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }
            }

            SettingsGroup(String.localized("Colour")) {
                SettingsRow(
                    String.localized("Ring colour scheme"),
                    subtitle: String.localized("The colours rings and figures use as a limit fills."),
                    symbol: "paintbrush"
                ) {
                    Picker(String.localized("Ring colour scheme"), selection: Binding(
                        get: { settings.ringColourScheme },
                        set: { settings.ringColourScheme = $0 }
                    )) {
                        ForEach(RingColourScheme.allCases) { scheme in
                            Text(scheme.title).tag(scheme)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
                    .disabled(!settings.isPanelVisible)
                }

                if SettingsChildRows.showsWarningThreshold(settings.ringColourScheme) {
                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Turn red at"),
                        subtitle: settings.ringColourScheme == .quiet
                            ? String.localized("Where a ring turns from green to muted grey.")
                            : String.localized("Where a ring turns from green to red."),
                        nested: true,
                        symbol: "exclamationmark.triangle"
                    ) {
                        Picker(String.localized("Turn red at"), selection: Binding(
                            get: { settings.warningThreshold },
                            set: { settings.warningThreshold = $0 }
                        )) {
                            ForEach(WarningThreshold.allCases) { threshold in
                                Text(threshold.title).tag(threshold)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
                        .disabled(!settings.isPanelVisible)
                    }
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Alert colour when docked"),
                    subtitle: String.localized("Off keeps the collapsed rail neutral even when a limit needs attention."),
                    symbol: "paintpalette"
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.dockShowsAlertColor },
                        set: { settings.dockShowsAlertColor = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }
            }
        }
    }
}
