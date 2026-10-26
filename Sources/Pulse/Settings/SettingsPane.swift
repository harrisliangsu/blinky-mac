// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

extension Provider.Billing {
    /// What the sidebar and the chooser head each group with.
    var sectionTitle: String {
        switch self {
        case .subscription: .localized("Subscriptions")
        case .api: .localized("API and pay-as-you-go")
        }
    }
}

enum SettingsPane: Hashable {
    /// The panel's own settings, split by what they are about. They were one
    /// "General" pane of thirty-odd rows until that was too long to find
    /// anything in.
    case appearance
    /// What usage shows: figures, the second ring, the reset clock, the
    /// exhaustion estimate, and which accounts that estimate shares with
    /// the running-out notices.
    case usageCard
    case placement
    /// Pulse as an app: launch, menu bar, shortcuts, language.
    case general
    case notifications
    case network
    /// Features still being tuned, off until switched on.
    case experimental
    case account(AccountKey)
    /// Every agent's spending added up — a pane whose subject is not a
    /// provider, which is why it sits outside the accounts rather than inside
    /// one of them.
    case spend
    case about
    case integrations
    /// Where extensions live and which were found. Each one found is an
    /// `.account` of its own; this is the list.
    case extensions
    /// Every built-in account, on one page. The sidebar has this one row,
    /// inside Application. Opening an account does not add another row;
    /// search still lists the matches.
    case providers

    /// The sidebar's fixed rows, section by section. `bottom` is the Other
    /// section: extensions, then integrations, then About.
    static let panel: [SettingsPane] = [.appearance, .usageCard, .placement]
    static let application: [SettingsPane] = [.general, .notifications, .network, .experimental, .providers]
    static let bottom: [SettingsPane] = [.extensions, .integrations, .about]

    /// Every fixed row, for the sidebar's "No matches" line.
    static var fixedPanes: [SettingsPane] {
        panel + [.spend] + application + bottom
    }

    /// The sidebar row that stays selected for this pane.
    ///
    /// A built-in account is not its own row, so Providers stays selected
    /// while that account's page is showing. An extension is already a row
    /// under Other. A search match is selected as itself while that row is
    /// in the list.
    static func sidebarRow(for pane: SettingsPane, listed: [SettingsPane]) -> SettingsPane {
        if listed.contains(pane) { return pane }
        switch pane {
        case .account(let account) where account.provider == .pulseExtension:
            return listed.contains(.extensions) ? .extensions : pane
        case .account:
            return listed.contains(.providers) ? .providers : pane
        default:
            return pane
        }
    }

    var title: String {
        switch self {
        case .appearance: .localized("Appearance")
        case .usageCard: .localized("Usage")
        case .placement: .localized("Position and behavior")
        case .general: .localized("General")
        case .notifications: .localized("Notifications")
        case .network: .localized("Network and refresh")
        case .experimental: .localized("Experimental")
        // Not "Usage history", which is what a provider's own card is called.
        // Two panes with one name is two places to look for one thing.
        case .spend: .localized("Token spend")
        // Brand names, left as they are in every language.
        // A fallback: the view titles these from the account's own label.
        case .account(let account): account.provider.displayName
        case .about: .localized("About")
        case .integrations: .localized("Developer integrations")
        case .extensions: .localized("Manage extensions")
        case .providers: .localized("Providers")
        }
    }

    /// Only meaningful for the panes drawn with an SF Symbol; provider panes
    /// use the provider's own mark instead.
    var symbol: String {
        switch self {
        case .appearance: "paintpalette"
        case .usageCard: "square.text.square"
        case .placement: "rectangle.righthalf.inset.filled"
        case .general: "slider.horizontal.3"
        case .notifications: "bell"
        case .network: "network"
        case .experimental: "flask"
        case .spend: "chart.bar"
        case .account: "square.stack.3d.up"
        case .about: "info.circle"
        case .integrations: "terminal"
        case .extensions: "puzzlepiece.extension"
        case .providers: "square.grid.2x2"
        }
    }

    /// The names of the settings on the pane, so the sidebar's search finds
    /// the pane a setting is on. Only the panes whose rows are fixed; an
    /// account is found by its name.
    var searchTerms: [String] {
        switch self {
        case .appearance:
            [.localized("Size and spacing"), .localized("Size"), .localized("Spacing"), .localized("Round ends"),
             .localized("Look"), .localized("Progress bars"),
             .localized("Appearance"), .localized("Transparency"), .localized("Ring activity animation"),
             .localized("Colour"), .localized("Ring colour scheme"), .localized("Turn red at"),
             .localized("Alert colour when docked")]
        case .usageCard:
            [.localized("Figures"), .localized("Percentages at the side"), .localized("Percentages across"),
             .localized("Figures beside the rings"), .localized("Figure above the ring"), .localized("Show what's left"),
             .localized("Second limit inside the ring"), .localized("Time until reset"), .localized("Time ring direction"),
             .localized("Exhaustion estimate"), .localized("Show the estimate"), .localized("Exhaustion forecast"),
             .localized("Countdown up to"), .localized("May run out before reset"),
             .localized("Say roughly when"), .localized("Which accounts"), .localized("Accounts"),
             .localized("Usage card"), .localized("Exhaustion on the card"), .localized("On the card")]
        case .placement:
            [.localized("Panel"), .localized("Show floating panel"), .localized("Hide in full screen"),
             .localized("Hide from screenshots"), .localized("Hide until pointed at"), .localized("Position"),
             .localized("Snap to screen edges"), .localized("Follow the active display"), .localized("Order")]
        case .general:
            [.localized("Startup and windows"), .localized("Open at login"),
             .localized("Show main window when opened at login"),
             .localized("Always show Dock icon"), .localized("Show Dock icon while a window is open"),
             .localized("Hide menu bar icon"), .localized("Show floating panel"),
             .localized("Shortcuts"), .localized("Interface language")]
        case .notifications:
            [.localized("Limit reminders"), .localized("Warn at"), .localized("When a limit comes back"),
             .localized("Running out"), .localized("When it is running out"), .localized("Remaining hours"),
             .localized("Will not last until the reset"), .localized("Add a stage"),
             .localized("Service status"), .localized("When a reading stops arriving"),
             .localized("When it is down"), .localized("Monthly recap"), .localized("When it is ready"),
             .localized("How early"), .localized("Reset reminders"), .localized("Predicted reset"),
             .localized("Regular resets"), .localized("Celebrate a reset"),
             .localized("Also celebrate hourly quota resets"),
             .localized("Exhaustion and reminders"), .localized("Exhaustion notifications"),
             .localized("Notify when a limit is running out"),
             .localized("Test notification"), .localized("Send")]
        case .network:
            [.localized("Check every"), .localized("Proxy")]
        case .extensions:
            [.localized("Extensions"), .localized("Look again")]
        case .experimental:
            [.localized("Liquid docking")]
        case .providers:
            [.localized("Enabled"), .localized("Subscriptions"), .localized("API and pay-as-you-go"),
             .localized("Alphabetical"), .localized("Panel order")]
        case .account, .spend, .about, .integrations:
            []
        }
    }
}

extension SettingsPane {
    /// The pane's name. An account's is the user's own label, which the pane
    /// itself cannot reach — two subscriptions to the same plan are told apart
    /// by nothing else.
    func title(in settings: AppSettings) -> String {
        if case .account(let account) = self { return settings.label(for: account) }
        return title
    }
}
