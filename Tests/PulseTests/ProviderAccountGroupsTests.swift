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

    @Test("An empty query lists every built-in account and leaves extensions out")
    func emptyQueryKeepsBuiltIns() {
        let cursor = AccountKey(.cursor)
        let codex = AccountKey(.codex)
        let added = AccountKey(.pulseExtension, slot: "demo")
        let panel = [cursor, codex, added]
        let label: (AccountKey) -> String = { $0.provider.displayName }

        let named = ProviderListArrangement.accounts(panelOrder: panel, order: .name, query: "", label: label)
        #expect(named == [codex, cursor])

        let blank = ProviderListArrangement.accounts(panelOrder: panel, order: .panel, query: "   ", label: label)
        #expect(blank == [cursor, codex])
    }

    @Test("Alphabetical order follows the row name, and panel order keeps the rail")
    func sortOrders() {
        let cursor = AccountKey(.cursor)
        let codex = AccountKey(.codex)
        let deepSeek = AccountKey(.deepSeek)
        let panel = [cursor, deepSeek, codex]
        let label: (AccountKey) -> String = { $0.provider.displayName }

        let named = ProviderListArrangement.accounts(panelOrder: panel, order: .name, query: "codex", label: label)
        #expect(named == [codex])

        let allNamed = ProviderListArrangement.accounts(panelOrder: panel, order: .name, query: "", label: label)
        #expect(allNamed.map(\.provider) == [.codex, .cursor, .deepSeek])

        let rail = ProviderListArrangement.accounts(panelOrder: panel, order: .panel, query: "", label: label)
        #expect(rail == panel)

        let enabled: Set<AccountKey> = [codex]
        let groups = ProviderAccountGroups.make(accounts: allNamed) { enabled.contains($0) }
        #expect(groups.map(\.kind) == [.enabled, .billing(.subscription), .billing(.api)])
        #expect(groups[1].accounts == [cursor])

        let panelGroups = ProviderAccountGroups.make(accounts: rail) { _ in false }
        #expect(panelGroups[0].accounts == [cursor, codex])
        #expect(panelGroups[1].accounts == [deepSeek])
    }

    @Test("A query matches the label and the product name, and an empty group is omitted")
    func filterByName() {
        let claude = AccountKey(.claudeCode)
        let work = AccountKey(.claudeCode, slot: "work")
        let zai = AccountKey(.zai)
        let zhipu = AccountKey(.glmCoding)
        let kimi = AccountKey(.kimiCode)
        let panel = [kimi, work, zai, claude, zhipu]
        let label: (AccountKey) -> String = { account in
            account == work ? "工作" : account.provider.displayName
        }

        let byProduct = ProviderListArrangement.accounts(
            panelOrder: panel, order: .panel, query: "claude", label: label
        )
        #expect(byProduct == [work, claude])

        let byLabel = ProviderListArrangement.accounts(
            panelOrder: panel, order: .name, query: "工作", label: label
        )
        #expect(byLabel == [work])

        let zaiMatch = ProviderListArrangement.accounts(
            panelOrder: panel, order: .name, query: "Z.ai", label: label
        )
        #expect(zaiMatch == [zai])

        // GLM is not a stored alias of either shop's row.
        let noAlias = ProviderListArrangement.accounts(
            panelOrder: panel, order: .name, query: "glm", label: label
        )
        #expect(noAlias.isEmpty)

        let none = ProviderListArrangement.accounts(
            panelOrder: panel, order: .name, query: "zzzz", label: label
        )
        #expect(ProviderAccountGroups.make(accounts: none) { _ in true }.isEmpty)

        let onlyKimi = ProviderListArrangement.accounts(
            panelOrder: panel, order: .name, query: "kimi", label: label
        )
        let groups = ProviderAccountGroups.make(accounts: onlyKimi) { _ in false }
        #expect(groups.map(\.kind) == [.billing(.subscription)])
        #expect(groups[0].accounts == [kimi])
    }

    @Test("Two rows with the same name stay in id order")
    func sameNameKeepsIdOrder() {
        let primary = AccountKey(.claudeCode)
        let extra = AccountKey(.claudeCode, slot: "work")
        let label: (AccountKey) -> String = { _ in "Claude Code" }
        let ordered = ProviderListArrangement.accounts(
            panelOrder: [extra, primary], order: .name, query: "", label: label
        )
        #expect(ordered == [primary, extra])
    }

    @Test("The order menu says 字母序 and 面板顺序 in simplified Chinese")
    func chineseOrderTitles() {
        LocalizationSource.use(.chineseSimplified)
        defer { LocalizationSource.use(.system) }

        #expect(ProviderListOrder.name.title == "字母序")
        #expect(ProviderListOrder.panel.title == "面板顺序")
        #expect(String.localized("Search") == "搜索")
        #expect(String.localized("Clear search") == "清除搜索")
        #expect(String.localized("No matches") == "没有匹配的项目")
    }
}
