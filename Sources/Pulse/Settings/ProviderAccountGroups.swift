// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Built-in accounts, grouped the way the sidebar used to list them: what is
/// switched on, then each way of paying, and an enabled account only once.
///
/// The Providers page draws this after its own filter and sort. A sidebar
/// search draws the same groups for the accounts that search matched, so the
/// two lists agree on what a group is. The order inside a group is the order
/// of `accounts`.
struct ProviderAccountGroups {
    enum Kind: Hashable {
        case enabled
        case billing(Provider.Billing)
    }

    struct Group: Identifiable {
        let kind: Kind
        let title: String
        let accounts: [AccountKey]
        var id: Kind { kind }
    }

    /// `accounts` is already in the order the caller wants. That order is kept
    /// inside each group.
    static func make(accounts: [AccountKey], isEnabled: (AccountKey) -> Bool) -> [Group] {
        var groups: [Group] = []
        let enabled = accounts.filter(isEnabled)
        if !enabled.isEmpty {
            groups.append(Group(kind: .enabled, title: String.localized("Enabled"), accounts: enabled))
        }
        for billing in Provider.Billing.allCases {
            let rows = accounts.filter { $0.provider.billing == billing && !isEnabled($0) }
            if !rows.isEmpty {
                groups.append(Group(kind: .billing(billing), title: billing.sectionTitle, accounts: rows))
            }
        }
        return groups
    }
}

/// Which provider accounts the sidebar draws.
///
/// A search draws the matches. With the field empty it draws none: the full
/// list is the Providers page, and opening an account does not add a row.
/// An extension is drawn with the other bottom rows, not here.
enum SettingsProviderListing {
    static func accounts(searching: Bool, matches: [AccountKey]) -> [AccountKey] {
        searching ? matches : []
    }
}

/// How the Providers page orders the rows inside each group.
///
/// Alphabetical is the shipped default. Panel order is the rail's order,
/// which is that same name order until somebody arranges the rail. There is
/// no popularity order: the app does not rank providers by how often they
/// are opened, and Token spend covers only the agents that keep local
/// transcripts.
enum ProviderListOrder: String, CaseIterable, Identifiable, Sendable {
    case name
    case panel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: String.localized("Alphabetical")
        case .panel: String.localized("Panel order")
        }
    }
}

/// Whether a provider row matches a typed query.
///
/// A blank query matches every row. Otherwise the name on the row **and**
/// the product name, which is what the sidebar search already does: a second
/// Claude subscription called "工作" is still found by typing "claude".
/// `localizedStandardContains` is Finder's match, so "z.ai" finds Z.ai.
enum ProviderAccountMatch {
    static func matches(label: String, displayName: String, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return label.localizedStandardContains(query) || displayName.localizedStandardContains(query)
    }
}

/// The built-in accounts the Providers page draws, already filtered and ordered.
enum ProviderListArrangement {
    /// `panelOrder` is the rail's order. Extensions are left out: they stay
    /// in the sidebar's Other section. An empty query keeps every built-in
    /// account. Alphabetical re-sorts by the name on the row; panel order
    /// keeps `panelOrder`.
    static func accounts(
        panelOrder: [AccountKey],
        order: ProviderListOrder,
        query: String,
        label: (AccountKey) -> String
    ) -> [AccountKey] {
        let matched = panelOrder.filter { account in
            account.provider != .pulseExtension
                && ProviderAccountMatch.matches(
                    label: label(account),
                    displayName: account.provider.displayName,
                    query: query
                )
        }
        switch order {
        case .panel:
            return matched
        case .name:
            return matched.sorted { AppSettings.namePrecedes($0, $1, label: label) }
        }
    }
}
