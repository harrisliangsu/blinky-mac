// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import SwiftUI

struct AboutPane: View {
    let update: AppUpdate
    let settings: AppSettings
    let alerts: UsageAlerts

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup {
                SettingsRow(String.localized("Version"), subtitle: updateSubtitle) {
                    if update.canCheck {
                        // Sparkle puts up its own window with whatever it
                        // finds, so this is the same button either way — there
                        // is nothing for Pulse to draw on top of it.
                        Button(
                            update.newer.map { String.localized("Update to \($0.version)") }
                                ?? String.localized("Check now")
                        ) {
                            update.check()
                        }
                        .disabled(update.isChecking)
                    } else {
                        Text(Self.version)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }

                if update.canCheck {
                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Check automatically"),
                        subtitle: String.localized("Scheduled checks use the interval below. The choice under it decides whether Blinky notifies you, opens the update window, or installs without asking.")
                    ) {
                        Toggle("", isOn: Binding(
                            get: { update.checksAutomatically },
                            set: { update.checksAutomatically = $0 }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }

                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Check for updates every"),
                        subtitle: String.localized("How often a scheduled check runs. Check now still opens the update window.")
                    ) {
                        HStack(spacing: 8) {
                            Stepper(
                                value: Binding(
                                    get: { settings.updateCheckCadence.amount },
                                    set: { settings.updateCheckCadence.amount = $0 }
                                ),
                                in: UpdateCheckCadence.minimumAmount...UpdateCheckCadence.maximumAmount
                            ) {
                                Text(verbatim: "\(settings.updateCheckCadence.amount)")
                                    .font(.system(size: 13).monospacedDigit())
                                    .frame(minWidth: 36, alignment: .trailing)
                            }
                            .fixedSize()
                            .accessibilityValue("\(settings.updateCheckCadence.amount)")

                            Picker("", selection: Binding(
                                get: { settings.updateCheckCadence.unit },
                                set: { settings.updateCheckCadence.unit = $0 }
                            )) {
                                ForEach(UpdateCheckUnit.allCases) { unit in
                                    Text(unit.title).tag(unit)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .fixedSize()
                        }
                        .accessibilityLabel(String.localized("Check for updates every"))
                    }

                    SettingsRowDivider()

                    SettingsRow(String.localized("When an update is found"), subtitle: discoverySubtitle) {
                        Picker("", selection: Binding(
                            get: { settings.updateDiscovery },
                            set: { settings.updateDiscovery = $0 }
                        )) {
                            ForEach(UpdateDiscovery.allCases) { choice in
                                Text(choice.title).tag(choice)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
                    }
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Usage data"),
                    subtitle: String.localized("Read from each provider's own account. Blinky shows the figures they report; where it has to infer one, the figure itself says so.")
                ) {
                    EmptyView()
                }

                SettingsRowDivider()

                // The address itself as the subtitle, not a sentence about it:
                // somebody reading this pane wants to know where the source is,
                // and half of them will want to type it rather than click.
                SettingsRow(
                    String.localized("Source code"),
                    subtitle: "github.com/harrisliangsu/blinky-mac"
                ) {
                    Button(String.localized("Open")) {
                        NSWorkspace.shared.open(URL(string: "https://github.com/harrisliangsu/blinky-mac")!)
                    }
                }
            }

            SettingsGroup(String.localized("Credits")) {
                SettingsRow(
                    "Vinz (@hivinz_)",
                    subtitle: String.localized("Panel design inspired by Vinz's work shared on X.")
                ) {
                    Button(String.localized("Open")) {
                        NSWorkspace.shared.open(
                            URL(string: "https://x.com/hivinz_/status/2092996055248126353")!
                        )
                    }
                }

                SettingsRowDivider()

                SettingsRow(
                    "Lobe Icons",
                    subtitle: String.localized("Provider marks from github.com/lobehub/lobe-icons.")
                ) {
                    EmptyView()
                }

                SettingsRowDivider()

                // Credited for the same reason the icons above are: it is
                // somebody else's work, shipped here. What that data is and
                // where it came from: Docs/decisions/bot-mark-geometry.md.
                SettingsRow(
                    "Morph Bot",
                    subtitle: String.localized("The animated marks are a port of github.com/iduu/grokbot-animation, itself a study of the bot on x.ai.")
                ) {
                    Button(String.localized("Open")) {
                        NSWorkspace.shared.open(
                            URL(string: "https://github.com/iduu/grokbot-animation")!
                        )
                    }
                }
            }
        }
        // Without this the row says "up to date" on nothing but the last
        // answer, however old. Quiet: the subtitle is where the result goes.
        .onAppear {
            update.probe()
            if settings.updateDiscovery == .notifyFirst {
                Task { _ = await alerts.requestUpdateNoticeAuthorization() }
            }
        }
    }

    /// The version, and what is known about a newer one. All four states are
    /// distinguishable on purpose: "no update" and "couldn't ask" look
    /// identical otherwise, and a check that silently failed is worse than one
    /// that says so.
    private var discoverySubtitle: String {
        switch settings.updateDiscovery {
        case .notifyFirst:
            String.localized("A scheduled check posts a notification, and the update window opens when that notification is clicked. Check now still opens the window.")
        case .showWindow:
            String.localized("A scheduled check opens the update window.")
        case .installSilently:
            String.localized("A scheduled check downloads the update, installs it, and relaunches Blinky, without an update window. After Blinky opens again, a notification names the installed version and what changed. Check now still opens the window.")
        }
    }

    private var updateSubtitle: String {
        if let newer = update.newer {
            return .localized("\(Self.version) installed · \(newer.version) available")
        }
        if update.isChecking { return .localized("Checking…") }
        if update.didFail { return .localized("Couldn't reach the update feed.") }
        if !update.canCheck { return .localized("Built from source — no update check.") }
        return .localized("\(Self.version) · up to date")
    }

    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1 (prototype)"
    }
}
