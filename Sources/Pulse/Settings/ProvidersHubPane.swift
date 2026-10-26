// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// Every built-in account, which the sidebar no longer lists one by one.
///
/// Extensions stay in the sidebar's Other section: they are programs somebody
/// added, not services Blinky ships. An account here opens the same pane the
/// sidebar row used to open. The field at the top filters this page only;
/// the sidebar keeps its own search.
struct ProvidersHubPane: View {
    let settings: AppSettings
    let navigation: SettingsNavigation
    /// Held by the shell, so opening an account and coming back keeps what
    /// was typed, and a language change does not clear it.
    @Binding var query: String

    var body: some View {
        let accounts = ProviderListArrangement.accounts(
            panelOrder: settings.orderedAccounts,
            order: settings.providersListOrder,
            query: query,
            label: settings.label(for:)
        )
        let groups = ProviderAccountGroups.make(accounts: accounts, isEnabled: settings.isEnabled)
        VStack(alignment: .leading, spacing: 22) {
            controls
            if groups.isEmpty {
                Text(localized: "No matches")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            } else {
                ForEach(groups) { group in
                    SettingsGroup(group.title) {
                        ForEach(Array(group.accounts.enumerated()), id: \.element.id) { index, account in
                            if index > 0 { SettingsRowDivider() }
                            accountRow(account)
                        }
                    }
                }
            }
        }
    }

    /// The field and the order menu, on one line above the groups.
    private var controls: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField(
                    "",
                    text: $query,
                    prompt: Text(localized: "Search")
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .autocorrectionDisabled()
                .accessibilityLabel(String.localized("Search"))
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String.localized("Clear search"))
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background)
            .clipShape(.rect(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.separator.opacity(0.5), lineWidth: 1)
                    .allowsHitTesting(false)
            }

            Picker(String.localized("Order"), selection: order) {
                ForEach(ProviderListOrder.allCases) { mode in
                    Text(verbatim: mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    private var order: Binding<ProviderListOrder> {
        Binding(
            get: { settings.providersListOrder },
            set: { settings.providersListOrder = $0 }
        )
    }

    private func accountRow(_ account: AccountKey) -> some View {
        Button {
            navigation.open(.account(account))
        } label: {
            HStack(spacing: 10) {
                LobeIconView(provider: account.provider, size: 16)
                Text(settings.label(for: account))
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview("Providers") {
    ProvidersHubPreview()
}

private struct ProvidersHubPreview: View {
    @State private var query = ""

    var body: some View {
        ProvidersHubPane(settings: AppSettings(), navigation: SettingsNavigation(), query: $query)
            .padding()
            .frame(width: 560)
    }
}
