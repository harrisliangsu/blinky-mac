// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// Pulse as an app rather than as a panel: launch, menu bar, shortcuts,
/// language, and the currency estimates are shown in.
struct GeneralPane: View {
    let settings: AppSettings
    /// Not for reading settings — those are in `settings` — but for the one
    /// thing only the monitor knows: whether the window server would take the
    /// combination.
    let shortcuts: GlobalShortcutMonitor

    /// Login-item state lives with the system, not in `AppSettings`, so it is
    /// read back rather than stored — and nudged when it changes.
    @State private var loginGeneration = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(String.localized("Startup and windows")) {
                SettingsRow(
                    String.localized("Open at login"),
                    subtitle: loginSubtitle,
                    symbol: "power"
                ) {
                    Toggle("", isOn: Binding(
                        get: {
                            _ = loginGeneration
                            return LoginItem.isEnabled
                        },
                        set: {
                            LoginItem.setEnabled($0)
                            loginGeneration += 1
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                if SettingsChildRows.showsMainWindowAtLogin(openAtLogin: loginItemIsOn) {
                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Show main window when opened at login"),
                        subtitle: String.localized("The main window opens when Blinky starts at login."),
                        nested: true,
                        symbol: "macwindow"
                    ) {
                        Toggle("", isOn: Binding(
                            get: { settings.showMainWindowAtLogin },
                            set: { settings.showMainWindowAtLogin = $0 }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Always show Dock icon"),
                    subtitle: String.localized("Blinky stays in the Dock and in ⌘-Tab, including while every window is closed."),
                    symbol: "dock.rectangle"
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.alwaysShowsDockIcon },
                        set: { settings.alwaysShowsDockIcon = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                if SettingsChildRows.showsDockIconWhileWindowOpen(alwaysShowsDockIcon: settings.alwaysShowsDockIcon) {
                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Show Dock icon while a window is open"),
                        subtitle: String.localized("The icon is there while the main window, a recap, or the service chooser is open, and it goes when they close."),
                        nested: true,
                        symbol: "macwindow"
                    ) {
                        Toggle("", isOn: Binding(
                            get: { settings.showsDockIconInSettings },
                            set: { settings.showsDockIconInSettings = $0 }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Hide menu bar icon"),
                    subtitle: menuBarIconSubtitle,
                    symbol: "menubar.rectangle"
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.hidesMenuBarIcon },
                        set: { hidden in
                            // Honour the request without taking away the last
                            // visible route back to Settings. Registration,
                            // not merely a stored combination, is what counts.
                            if hidden,
                               AppDelegate.menuBarIconMustRemainVisible(
                                   panelVisible: !settings.needsProviderSelection && settings.isPanelVisible,
                                   hasRegisteredShortcut: shortcuts.hasRegisteredEntryPoint
                               ) {
                                // No chosen provider means no panel exists to
                                // show, even when its preference reads true.
                                guard !settings.needsProviderSelection else { return }
                                settings.isPanelVisible = true
                            }
                            settings.hidesMenuBarIcon = hidden
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Show floating panel"),
                    subtitle: String.localized("The usage rail at the edge of the screen."),
                    symbol: "eye"
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.isPanelVisible },
                        set: { settings.isPanelVisible = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }

            SettingsGroup(String.localized("Application")) {
                // Greyed out rather than hidden while the icon is: it is what
                // the icon would show, and says so.
                SettingsRow(
                    String.localized("Show usage in the menu bar"),
                    subtitle: String.localized("A ring's mark and figure beside the icon, red past the warning line."),
                    symbol: "percent"
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.showsUsageInMenuBar },
                        set: { settings.showsUsageInMenuBar = $0 }
                    ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .disabled(settings.hidesMenuBarIcon)

                // Only once there is a figure to shape. Offered even with the
                // icon hidden would be two controls for nothing on screen.
                if SettingsChildRows.showsMenuBarFigureOptions(
                    showsUsage: settings.showsUsageInMenuBar,
                    iconHidden: settings.hidesMenuBarIcon
                ) {
                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Menu bar shows"),
                        subtitle: String.localized("An account switched off falls back to the fullest ring."),
                        nested: true,
                        symbol: "scope"
                    ) {
                        Picker("", selection: Binding(
                            // An account taken off the rail reads as the
                            // fallback it has become, not as no selection.
                            get: {
                                settings.menuBarAccount.flatMap { id in
                                    settings.shownAccounts.contains { $0.id == id } ? id : nil
                                }
                            },
                            set: { settings.menuBarAccount = $0 }
                        )) {
                            Text(localized: "Fullest ring").tag(String?.none)
                            ForEach(settings.shownAccounts, id: \.id) { account in
                                Text(verbatim: settings.label(for: account)).tag(String?.some(account.id))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
                    }

                    SettingsRowDivider()

                    SettingsRow(String.localized("Menu bar style"), nested: true, symbol: "paintbrush") {
                        Picker("", selection: Binding(
                            get: { settings.menuBarStyle },
                            set: { settings.menuBarStyle = $0 }
                        )) {
                            Text(localized: "Figure").tag(MenuBarStyle.figure)
                            Text(localized: "Ring").tag(MenuBarStyle.ring)
                            Text(localized: "Split").tag(MenuBarStyle.split)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                }

                SettingsRowDivider()

                // Its own switch, apart from the figure beside the icon: one
                // is a glance, the other a sit-down, and either can be wanted
                // alone. Greyed out with the icon hidden, like the figure.
                SettingsRow(
                    String.localized("Usage panel in the menu"),
                    subtitle: String.localized("Opens the menu bar menu on an overview of every account, with a tab for each one's limits, plan and spend."),
                    symbol: "list.bullet.rectangle"
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.showsMenuDashboard },
                        set: { settings.showsMenuDashboard = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                .disabled(settings.hidesMenuBarIcon)
            }

            SettingsGroup(String.localized("Shortcuts")) {
                SettingsRow(
                    String.localized("Open settings"),
                    subtitle: shortcutSubtitle(
                        for: .openSettings,
                        when: String.localized("Reaches this window with the menu bar icon out of sight.")
                    ),
                    symbol: "keyboard"
                ) {
                    ShortcutField(shortcut: settings.openSettingsShortcut) { shortcut in
                        settings.openSettingsShortcut = shortcut
                        shortcuts.apply(settings)
                    }
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Show or hide the panel"),
                    subtitle: shortcutSubtitle(
                        for: .togglePanel,
                        when: String.localized("Draws the usage rail, or takes it away.")
                    ),
                    symbol: "keyboard"
                ) {
                    ShortcutField(shortcut: settings.togglePanelShortcut) { shortcut in
                        settings.togglePanelShortcut = shortcut
                        shortcuts.apply(settings)
                    }
                }
            }

            SettingsGroup(String.localized("Language")) {
                SettingsRow(
                    String.localized("Interface language"),
                    subtitle: String.localized("Takes effect right away."),
                    symbol: "globe"
                ) {
                    Picker("", selection: Binding(
                        get: { settings.language },
                        set: { settings.language = $0 }
                    )) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
                }
            }

            CurrencySettingsGroup(settings: settings)
        }
    }

    /// What a shortcut row says under its title.
    ///
    /// A combination the window server refused is one that will never fire, and
    /// saying nothing would leave the reader to work that out by pressing it —
    /// so the clash takes the line over while it lasts.
    private func shortcutSubtitle(
        for action: GlobalShortcutMonitor.Action,
        when available: String
    ) -> String {
        shortcuts.unavailable.contains(action)
            ? .localized("Another app is already using this combination.")
            : available
    }

    /// Open at login, read so the nested row hides with the switch. The
    /// generation is what redraws this after the system reports a new state.
    private var loginItemIsOn: Bool {
        _ = loginGeneration
        return LoginItem.isEnabled
    }

    /// The ordinary explanation, or the note left when the icon was turned
    /// back on because hiding it would have left no way into Blinky.
    private var menuBarIconSubtitle: String {
        if settings.menuBarIconRestoreNote {
            return .localized("Blinky turned the menu bar icon back on, because the panel is hidden and no shortcut is registered.")
        }
        return .localized("Remove Blinky from the menu bar; use the panel menu or shortcut to open settings.")
    }

    /// The login item's state is the system's to hold, so this says what the
    /// system actually reports rather than what was asked for.
    private var loginSubtitle: String {
        _ = loginGeneration

        return switch LoginItem.state {
        case .needsApproval:
            .localized("Waiting for approval in System Settings › General › Login Items.")
        case .on, .off:
            .localized("Start Blinky automatically when you log in.")
        }
    }
}
