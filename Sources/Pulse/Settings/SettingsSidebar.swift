// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// The source list: the panes in sections, then Providers as one row.
///
/// Built-in accounts are not rows here. They are on the Providers page, and
/// a search lists the ones it matches. The shell sets the column's width and
/// the search field on this view rather than here: both are properties of the
/// split view's sidebar column.
struct SettingsSidebar: View {
    let settings: AppSettings
    @Bindable var navigation: SettingsNavigation
    /// Narrows the sidebar. Held by the shell so a language change, which
    /// rebuilds the split view, does not clear it.
    let search: String

    var body: some View {
        List(selection: selection) {
            if SettingsPane.panel.contains(where: matches) || matches(.spend) {
                Section(String.localized("Panel")) {
                    ForEach(SettingsPane.panel.filter(matches), id: \.self) { row($0) }
                    if matches(.spend) { row(.spend) }
                }
            }

            if SettingsPane.application.contains(where: matches) {
                Section(String.localized("Application")) {
                    ForEach(SettingsPane.application.filter(matches), id: \.self) { row($0) }
                }
            }

            ForEach(searchedProviderGroups) { group in
                Section(group.title) {
                    ForEach(group.accounts) { account in
                        row(.account(account))
                    }
                }
            }

            // Manage extensions, Developer integrations and About, with any
            // extension somebody added. A header, and no extra click: these
            // are the rows the long provider list used to push off screen.
            if showsBottom {
                Section(String.localized("Other")) {
                    if matches(.extensions) { row(.extensions) }
                    ForEach(matchingExtensionAccounts) { account in
                        row(.account(account))
                    }
                    if matches(.integrations) { row(.integrations) }
                    if matches(.about) { row(.about) }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if isSearching, matchingAccounts.isEmpty, !SettingsPane.fixedPanes.contains(where: matches) {
                Text(localized: "No matches")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// What the sidebar is being narrowed to, or nothing.
    private var query: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool { !query.isEmpty }

    /// Accounts whose name the search matches, in rail order.
    ///
    /// Matched against the provider's name **as well as** the user's label, not
    /// instead of it. A second Claude subscription called "工作" is still a
    /// Claude Code account, and typing the product name is the obvious way to
    /// look for it — `title(_:)` alone would only know the label.
    private var matchingAccounts: [AccountKey] {
        settings.orderedAccounts.filter {
            ProviderAccountMatch.matches(
                label: title(.account($0)),
                displayName: $0.provider.displayName,
                query: query
            )
        }
    }

    private var matchingProviderAccounts: [AccountKey] {
        matchingAccounts.filter { $0.provider != .pulseExtension }
    }

    private var matchingExtensionAccounts: [AccountKey] {
        matchingAccounts.filter { $0.provider == .pulseExtension }
    }

    private var listedProviderAccounts: [AccountKey] {
        SettingsProviderListing.accounts(searching: isSearching, matches: matchingProviderAccounts)
    }

    /// Every row tag currently in the list. The selection highlight has to
    /// be one of these: a provider account maps back to Providers.
    private var listedRows: [SettingsPane] {
        var rows: [SettingsPane] = []
        if SettingsPane.panel.contains(where: matches) || matches(.spend) {
            rows += SettingsPane.panel.filter(matches)
            if matches(.spend) { rows.append(.spend) }
        }
        if SettingsPane.application.contains(where: matches) {
            rows += SettingsPane.application.filter(matches)
        }
        if isSearching {
            rows += listedProviderAccounts.map(SettingsPane.account)
        }
        if showsBottom {
            if matches(.extensions) { rows.append(.extensions) }
            rows += matchingExtensionAccounts.map(SettingsPane.account)
            if matches(.integrations) { rows.append(.integrations) }
            if matches(.about) { rows.append(.about) }
        }
        return rows
    }

    private var selection: Binding<SettingsPane> {
        Binding(
            get: { SettingsPane.sidebarRow(for: navigation.pane, listed: listedRows) },
            set: { pane in
                guard navigation.pane != pane else { return }
                navigation.open(pane)
            }
        )
    }

    /// Provider groups for a search. Empty when the field is empty: the
    /// accounts are on the Providers page, not in the sidebar.
    private var searchedProviderGroups: [ProviderAccountGroups.Group] {
        guard isSearching else { return [] }
        return ProviderAccountGroups.make(accounts: listedProviderAccounts, isEnabled: settings.isEnabled)
    }

    private var showsBottom: Bool {
        matches(.extensions) || matches(.integrations) || matches(.about) || !matchingExtensionAccounts.isEmpty
    }

    /// By the pane's name, or by the name of any setting on it: with the
    /// panel's settings spread over several panes, "proxy" has to find the
    /// one proxy is on rather than nothing.
    private func matches(_ pane: SettingsPane) -> Bool {
        guard isSearching else { return true }
        return matches(title(pane)) || pane.searchTerms.contains(where: matches)
    }

    /// Case- and accent-insensitive, and localized: `localizedStandardContains`
    /// is what Finder searches with, so "z.ai" finds Z.ai and a stray accent
    /// doesn't lose a row.
    private func matches(_ text: String) -> Bool {
        text.localizedStandardContains(query)
    }

    private func row(_ pane: SettingsPane) -> some View {
        Label {
            Text(title(pane))
        } icon: {
            switch pane {
            case .account(let account):
                LobeIconView(provider: account.provider, size: 14)
            default:
                Image(systemName: pane.symbol)
            }
        }
        .labelStyle(SidebarRowLabelStyle())
        .tag(pane)
    }

    private func title(_ pane: SettingsPane) -> String {
        pane.title(in: settings)
    }
}

/// A sidebar row whose icon is the text's colour (black, white in dark
/// mode), not the accent colour a source list tints its icons with: two
/// dozen blue marks down the list read as links rather than as places.
///
/// Laid out here rather than recoloured. A `foregroundStyle` on the icon does
/// not reach past the sidebar's own label style, and `listItemTint` held only
/// for the rows on screen when the window opened — rows scrolled into view
/// later were blue again.
private struct SidebarRowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        // Measured against the system's row: icon centred 12pt in, title
        // 30pt in, so the text starts where it did before.
        HStack(spacing: 6) {
            configuration.icon
                .foregroundStyle(.primary)
                .frame(width: 24)
            configuration.title
        }
    }
}
