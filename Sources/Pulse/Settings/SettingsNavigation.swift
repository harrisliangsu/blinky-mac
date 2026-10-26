// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import Observation

@MainActor
@Observable
final class SettingsNavigation {
    /// The first pane in the sidebar, which is where the panel is dressed.
    var pane: SettingsPane = .appearance {
        didSet {
            // Every way to a pane — the sidebar, a link, a button in a
            // pane — is a step the back button can undo; going back and
            // forward is not. Restoring the last pane is not a step either.
            guard pane != oldValue, !isStepping else { return }
            back.append(oldValue)
            if back.count > Self.depth { back.removeFirst() }
            forward.removeAll()
            remember?(pane)
        }
    }
    /// Writes the pane so the next launch can open it again. Not called
    /// while a stored pane is being put back.
    var remember: ((SettingsPane) -> Void)?
    var isWindowVisible = false
    private(set) var requestID = UUID()

    /// The panes visited before this one, and those gone back from — the
    /// toolbar's back and forward buttons, as in System Settings.
    private(set) var back: [SettingsPane] = []
    private(set) var forward: [SettingsPane] = []
    @ObservationIgnored private var isStepping = false
    private static let depth = 50

    /// A step back, past any pane that cannot be shown any more — an
    /// account removed since it was visited. `exists` says which can.
    func goBack(where exists: (SettingsPane) -> Bool) {
        step(from: &back, to: &forward, where: exists)
    }

    func goForward(where exists: (SettingsPane) -> Bool) {
        step(from: &forward, to: &back, where: exists)
    }

    private func step(from source: inout [SettingsPane], to other: inout [SettingsPane], where exists: (SettingsPane) -> Bool) {
        while let target = source.popLast() {
            guard exists(target) else { continue }
            other.append(pane)
            isStepping = true
            pane = target
            isStepping = false
            requestID = UUID()
            return
        }
    }

    /// Puts a stored pane back without recording a step and without writing
    /// it again.
    func restore(_ pane: SettingsPane) {
        guard pane != self.pane else { return }
        isStepping = true
        self.pane = pane
        isStepping = false
    }

    /// Goes to a pane, as a link does.
    func open(_ pane: SettingsPane) {
        self.pane = pane
        requestID = UUID()
    }

    func open(_ link: PulseLink, accounts: [AccountKey]) {
        switch link {
        case .settings: pane = .appearance
        case .integrations: pane = .integrations
        case .account(let account):
            // A removed account's old link must not recreate an account pane.
            guard accounts.contains(account) else { return }
            pane = .account(account)
        }
        requestID = UUID()
    }
}

/// The last settings pane, so the control on the usage card can open it
/// again. The key is new. Older installs have no value and open Appearance,
/// which is where the window already opened.
enum SettingsPaneBookmark {
    static let key = "settings.lastPane"

    static func write(_ pane: SettingsPane, to defaults: UserDefaults) {
        defaults.set(token(for: pane), forKey: key)
    }

    static func read(from defaults: UserDefaults, accounts: [AccountKey]) -> SettingsPane? {
        guard let raw = defaults.string(forKey: key) else { return nil }
        return pane(from: raw, accounts: accounts)
    }

    static func token(for pane: SettingsPane) -> String {
        switch pane {
        case .appearance: "appearance"
        case .usageCard: "usageCard"
        case .placement: "placement"
        case .general: "general"
        case .notifications: "notifications"
        case .network: "network"
        case .experimental: "experimental"
        case .spend: "spend"
        case .about: "about"
        case .integrations: "integrations"
        case .extensions: "extensions"
        case .providers: "providers"
        case .account(let account): "account:\(account.id)"
        }
    }

    static func pane(from token: String, accounts: [AccountKey]) -> SettingsPane? {
        switch token {
        case "appearance": return .appearance
        case "usageCard": return .usageCard
        case "placement": return .placement
        case "general": return .general
        case "notifications": return .notifications
        case "network": return .network
        case "experimental": return .experimental
        case "spend": return .spend
        case "about": return .about
        case "integrations": return .integrations
        case "extensions": return .extensions
        case "providers": return .providers
        default:
            guard token.hasPrefix("account:") else { return nil }
            let id = String(token.dropFirst("account:".count))
            guard let account = AccountKey(id: id) else { return nil }
            return accounts.contains(account) ? .account(account) : .providers
        }
    }
}
