// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Testing
@testable import Pulse

@Suite("Settings providers list")
struct ProviderAccountGroupsTests {
    @Test("An enabled account is listed once, ahead of the billing groups, in the order given")
    func groups() {
        let codex = AccountKey(.codex)
        let cursor = AccountKey(.cursor)
        let deepSeek = AccountKey(.deepSeek)
        let accounts = [cursor, deepSeek, codex]
        let enabled: Set<AccountKey> = [codex]

        let groups = ProviderAccountGroups.make(accounts: accounts) { enabled.contains($0) }

        #expect(groups.map(\.kind) == [.enabled, .billing(.subscription), .billing(.api)])
        #expect(groups[0].accounts == [codex])
        #expect(groups[1].accounts == [cursor])
        #expect(groups[2].accounts == [deepSeek])
    }

    @Test("An enabled API account is not listed again under API, and an empty group is left out")
    func enabledOnce() {
        let deepSeek = AccountKey(.deepSeek)
        let onlyEnabled = ProviderAccountGroups.make(accounts: [deepSeek]) { _ in true }
        #expect(onlyEnabled.map(\.kind) == [.enabled])

        let codex = AccountKey(.codex)
        let onlySubscription = ProviderAccountGroups.make(accounts: [codex]) { _ in false }
        #expect(onlySubscription.map(\.kind) == [.billing(.subscription)])
        #expect(onlySubscription[0].accounts == [codex])
    }

    @Test("The sidebar lists provider matches only while searching")
    func listing() {
        let cursor = AccountKey(.cursor)
        let codex = AccountKey(.codex)

        #expect(SettingsProviderListing.accounts(searching: true, matches: [cursor]) == [cursor])
        #expect(SettingsProviderListing.accounts(searching: true, matches: [cursor, codex]) == [cursor, codex])
        #expect(SettingsProviderListing.accounts(searching: false, matches: [cursor, codex]).isEmpty)
    }

    @Test("Providers sits in Application, and the bottom three stay in one order")
    func panes() {
        #expect(SettingsPane.bottom == [.extensions, .integrations, .about])
        #expect(SettingsPane.application == [.general, .notifications, .network, .experimental, .providers])
        #expect(SettingsPane.fixedPanes.contains(.providers))
        #expect(!SettingsPane.panel.contains(.providers))
        #expect(SettingsPane.fixedPanes.filter { $0 == .providers }.count == 1)
    }
}
