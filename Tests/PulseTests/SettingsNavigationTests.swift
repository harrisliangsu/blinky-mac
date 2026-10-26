import Testing
@testable import Pulse

/// The settings window's back and forward (`SettingsNavigation`), as System
/// Settings has them.
@MainActor
@Suite("Settings back and forward")
struct SettingsNavigationTests {
    private let always: (SettingsPane) -> Bool = { _ in true }

    @Test("Back and forward retrace the panes visited, and a new visit drops what was ahead")
    func history() {
        let navigation = SettingsNavigation()
        navigation.pane = .usageCard
        navigation.open(.general)
        navigation.pane = .network

        navigation.goBack(where: always)
        #expect(navigation.pane == .general)
        navigation.goBack(where: always)
        #expect(navigation.pane == .usageCard)
        navigation.goForward(where: always)
        #expect(navigation.pane == .general)

        navigation.pane = .about
        #expect(navigation.forward.isEmpty)
        navigation.goBack(where: always)
        #expect(navigation.pane == .general)
    }

    @Test("Going back skips a pane that cannot be shown any more, and does nothing with nowhere to go")
    func skipsGone() {
        let navigation = SettingsNavigation()
        let removed = AccountKey(.codex)
        navigation.pane = .account(removed)
        navigation.pane = .usageCard

        navigation.goBack(where: { $0 != .account(removed) })
        #expect(navigation.pane == .appearance)
        navigation.goBack(where: always)
        #expect(navigation.pane == .appearance)
        #expect(navigation.back.isEmpty)
    }

    @Test("Choosing the pane already open is not a step")
    func samePane() {
        let navigation = SettingsNavigation()
        navigation.pane = .appearance
        #expect(navigation.back.isEmpty)
    }

    @Test("Usage and Notifications are the pane names, and the old names still find them")
    func usageCardReplacesRings() {
        LocalizationSource.use(.english)
        defer { LocalizationSource.use(.system) }

        #expect(SettingsPane.panel == [.appearance, .usageCard, .placement])
        #expect(SettingsPane.usageCard.title == "Usage")
        #expect(SettingsPane.notifications.title == "Notifications")
        #expect(SettingsPane.usageCard.searchTerms.contains("Percentages at the side"))
        #expect(SettingsPane.usageCard.searchTerms.contains("Exhaustion estimate"))
        #expect(SettingsPane.usageCard.searchTerms.contains("Usage card"))
        #expect(SettingsPane.usageCard.searchTerms.contains("Which accounts"))
        #expect(SettingsPane.appearance.searchTerms.contains("Ring colour scheme"))
        #expect(SettingsPane.appearance.searchTerms.contains("Colour"))
        #expect(!SettingsPane.notifications.searchTerms.contains("What the card shows"))
        #expect(SettingsPane.notifications.searchTerms.contains("Running out"))
        #expect(SettingsPane.notifications.searchTerms.contains("When it is running out"))
        #expect(SettingsPane.notifications.searchTerms.contains("Notify when a limit is running out"))
        #expect(SettingsPane.notifications.searchTerms.contains("Test notification"))
        #expect(SettingsPane.experimental.title == "Experimental")
        #expect(SettingsPane.experimental.searchTerms.contains("Liquid docking"))
        #expect(SettingsPane.providers.searchTerms.contains("Alphabetical"))
        #expect(SettingsPane.providers.searchTerms.contains("Panel order"))

        LocalizationSource.use(.chineseSimplified)
        #expect(SettingsPane.usageCard.title == "用量")
        #expect(SettingsPane.notifications.title == "通知")
        #expect(String.localized("Usage card") == "用量卡片")
        #expect(String.localized("Exhaustion and reminders") == "用尽与提醒")
    }

    @Test("Opening a provider keeps Providers selected, and an extension stays its own row")
    func sidebarSelection() {
        let codex = AccountKey(.codex)
        let ext = AccountKey(.pulseExtension, slot: "demo")
        let listed = SettingsPane.fixedPanes

        #expect(SettingsPane.application == [.general, .notifications, .network, .experimental, .providers])
        #expect(SettingsPane.fixedPanes.filter { $0 == .providers }.count == 1)
        #expect(SettingsPane.sidebarRow(for: .account(codex), listed: listed) == .providers)
        #expect(SettingsPane.sidebarRow(for: .account(ext), listed: listed) == .extensions)
        #expect(SettingsPane.sidebarRow(for: .account(ext), listed: listed + [.account(ext)]) == .account(ext))
        #expect(SettingsPane.sidebarRow(for: .account(codex), listed: listed + [.account(codex)]) == .account(codex))
        #expect(SettingsPane.sidebarRow(for: .notifications, listed: listed) == .notifications)
    }

    @Test("Back from a provider returns to Providers, and the toolbar can go forward again")
    func providerBackIsAStep() {
        let navigation = SettingsNavigation()
        let codex = AccountKey(.codex)
        navigation.open(.providers)
        navigation.open(.account(codex))
        #expect(navigation.back == [.appearance, .providers])

        // The in-pane Back is a new step, so the toolbar can return to the account.
        navigation.open(.providers)
        #expect(navigation.pane == .providers)
        navigation.goBack(where: always)
        #expect(navigation.pane == .account(codex))
        navigation.goForward(where: always)
        #expect(navigation.pane == .providers)
    }

    @Test("The last pane is stored, and a removed account opens Providers")
    func lastPane() {
        let (defaults, cleanup) = AppSettingsPersistenceTests.isolatedDefaults()
        defer { cleanup() }
        let codex = AccountKey(.codex)

        SettingsPaneBookmark.write(.notifications, to: defaults)
        #expect(defaults.string(forKey: SettingsPaneBookmark.key) == "notifications")
        #expect(SettingsPaneBookmark.read(from: defaults, accounts: []) == .notifications)

        SettingsPaneBookmark.write(.experimental, to: defaults)
        #expect(defaults.string(forKey: SettingsPaneBookmark.key) == "experimental")
        #expect(SettingsPaneBookmark.read(from: defaults, accounts: []) == .experimental)

        SettingsPaneBookmark.write(.account(codex), to: defaults)
        #expect(SettingsPaneBookmark.read(from: defaults, accounts: [codex]) == .account(codex))
        #expect(SettingsPaneBookmark.read(from: defaults, accounts: []) == .providers)

        defaults.set("nope", forKey: SettingsPaneBookmark.key)
        #expect(SettingsPaneBookmark.read(from: defaults, accounts: []) == nil)

        let navigation = SettingsNavigation()
        var remembered: [SettingsPane] = []
        navigation.remember = { remembered.append($0) }
        navigation.restore(.usageCard)
        #expect(navigation.pane == .usageCard)
        #expect(navigation.back.isEmpty)
        #expect(remembered.isEmpty)
        navigation.open(.general)
        #expect(remembered == [.general])
        #expect(navigation.back == [.usageCard])
    }
}
