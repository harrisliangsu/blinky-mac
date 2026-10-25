import Foundation
import Testing
@testable import Pulse

/// Which providers are subscriptions and which are API accounts, which decides
/// where each is listed. See `Provider.Billing`.
@Suite("Billing kind")
struct BillingTests {
    @Test("Money drawn down by the call is an API account; a plan is a subscription")
    func kinds() {
        for provider: Provider in [.deepSeek, .sub2api, .newAPI, .openAIPlatform, .xaiAPI, .moonshot, .liteLLM] {
            #expect(provider.billing == .api, "\(provider.rawValue)")
        }
        // A plan with a balance beside it is still a plan.
        for provider: Provider in [.claudeCode, .codex, .commandCode, .kimiCode, .clinePass, .amp, .kiloCode] {
            #expect(provider.billing == .subscription, "\(provider.rawValue)")
        }
    }

    @Test("Every API account that reports money says so, so its low-balance line is offered")
    func apiBalances() {
        for provider in Provider.builtIn where provider.billing == .api && provider.profile?.reportsSpendableBalance == true {
            #expect(provider.reportsSpendableBalance)
        }
    }
}

/// The Order group lists and moves only what the rail draws.
@Suite("Rail order among shown accounts")
@MainActor
struct ShownOrderTests {
    private func settings() -> AppSettings {
        AppSettings(enabledAccounts: ["codex", "claudeCode", "deepSeek"], providerOrder: ["codex", "kiro", "claudeCode", "deepSeek"])
    }

    @Test("An arrow moves past the next shown account, not past a hidden one")
    func arrowsSkipHidden() {
        let settings = settings()
        #expect(settings.shownAccounts.map(\.id) == ["codex", "claudeCode", "deepSeek"])
        settings.move(AccountKey(.claudeCode), by: -1)
        #expect(settings.shownAccounts.map(\.id) == ["claudeCode", "codex", "deepSeek"])
        // Kiro is off: it keeps a place, after the shown ones.
        #expect(settings.orderedAccounts.map(\.id).prefix(4) == ["claudeCode", "codex", "deepSeek", "kiro"])
    }

    @Test("A drop lands among the shown accounts, and the ends do nothing")
    func dropAndEnds() {
        let settings = settings()
        settings.move(AccountKey(.deepSeek), onto: AccountKey(.codex))
        #expect(settings.shownAccounts.map(\.id) == ["deepSeek", "codex", "claudeCode"])
        settings.move(AccountKey(.deepSeek), by: -1)
        #expect(settings.shownAccounts.map(\.id) == ["deepSeek", "codex", "claudeCode"])
        // A hidden account is not moved by either.
        settings.move(AccountKey(.kiro), by: 1)
        settings.move(AccountKey(.kiro), onto: AccountKey(.codex))
        #expect(settings.shownAccounts.map(\.id) == ["deepSeek", "codex", "claudeCode"])
    }
}

/// Codex's limit reset credits, as the card shows them: the count Codex
/// reported, or that it reported none.
@Suite("Codex reset credits")
@MainActor
struct CodexResetCreditsTests {
    @Test("The stated count is read, with the soonest expiry among the available ones")
    func count() {
        let now = Date(timeIntervalSince1970: 1_600_000_000)
        let limits: [String: Any] = ["rateLimitResetCredits": [
            "availableCount": 2,
            "credits": [
                ["title": "a", "status": "available", "expiresAt": 1_900_000_000],
                ["title": "b", "status": "available", "expiresAt": 1_800_000_000],
                ["title": "c", "status": "used", "expiresAt": 1_700_000_000],
            ],
        ]]
        #expect(CodexAccountUsageService.resetCredits(in: limits, now: now)
                == .available(count: 2, nextExpiry: Date(timeIntervalSince1970: 1_800_000_000)))
    }

    @Test("A null credit list is the stated count, and no expiry is invented")
    func countOnly() {
        let limits: [String: Any] = ["rateLimitResetCredits": [
            "availableCount": 1,
            "credits": NSNull(),
        ]]
        #expect(CodexAccountUsageService.resetCredits(in: limits)
                == .available(count: 1, nextExpiry: nil))
    }

    @Test("A list with nothing still usable is zero, even when the stated count is not")
    func spentListIsZero() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let empty: [String: Any] = ["rateLimitResetCredits": [
            "availableCount": 1,
            "credits": [[String: Any]](),
        ]]
        #expect(CodexAccountUsageService.resetCredits(in: empty, now: now) == .available(count: 0, nextExpiry: nil))

        let redeemed: [String: Any] = ["rateLimitResetCredits": [
            "availableCount": 1,
            "credits": [["title": "Full reset", "status": "redeemed", "expiresAt": 1_900_000_000]],
        ]]
        #expect(CodexAccountUsageService.resetCredits(in: redeemed, now: now) == .available(count: 0, nextExpiry: nil))

        let expired: [String: Any] = ["rateLimitResetCredits": [
            "availableCount": 1,
            "credits": [["title": "Full reset", "status": "available", "expiresAt": 1_700_000_000]],
        ]]
        #expect(CodexAccountUsageService.resetCredits(in: expired, now: now) == .available(count: 0, nextExpiry: nil))
        #expect(CodexAccountUsageService.credits(from: expired, now: now)?.showsOnCard(at: now) == false)
    }

    @Test("A shorter list of only still-usable cards keeps the higher stated count")
    func cappedListKeepsStatedCount() {
        let now = Date(timeIntervalSince1970: 1_600_000_000)
        let limits: [String: Any] = ["rateLimitResetCredits": [
            "availableCount": 3,
            "credits": [
                ["title": "Later", "status": "available", "expiresAt": 1_900_000_000],
                ["title": "Soon", "status": "available", "expiresAt": 1_800_000_000],
            ],
        ]]
        #expect(CodexAccountUsageService.resetCredits(in: limits, now: now)
                == .available(count: 3, nextExpiry: Date(timeIntervalSince1970: 1_800_000_000)))
    }

    @Test("An ISO-8601 expiry is a date, and one already past is not a card")
    func isoExpiry() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let limits: [String: Any] = ["rateLimitResetCredits": [
            "credits": [
                ["title": "Later", "status": "available", "expiresAt": "2027-01-15T08:00:00Z"],
                ["title": "Gone", "status": "available", "expiresAt": "2023-11-14T22:13:20Z"],
            ],
        ]]
        let credits = CodexAccountUsageService.resetCredits(in: limits, now: now)
        #expect(credits == .available(count: 1, nextExpiry: Date(timeIntervalSince1970: 1_800_000_000)))
    }

    @Test("A failed read keeps the previous line; a reply with no block removes it; a zero replaces it")
    func reconcile() {
        let previous = CodexCreditSummary(
            available: 1,
            nextExpiresAt: Date(timeIntervalSince1970: 1_900_000_000),
            next: nil
        )
        #expect(CodexCreditSummary.reconcile(previous: previous, read: .failed) == previous)
        #expect(CodexCreditSummary.reconcile(previous: previous, read: .absent) == nil)
        let zero = CodexCreditSummary(available: 0, nextExpiresAt: nil, next: nil)
        #expect(CodexCreditSummary.reconcile(previous: previous, read: .summary(zero)) == zero)
        #expect(zero.showsOnCard() == false)
        #expect(previous.showsOnCard(at: Date(timeIntervalSince1970: 1_950_000_000)) == false)
        #expect(previous.showsOnCard(at: Date(timeIntervalSince1970: 1_800_000_000)) == true)
    }

    @Test("Without a stated count, the available credits listed are the count")
    func counted() {
        let limits: [String: Any] = ["rateLimitResetCredits": ["credits": [["status": "available"], ["status": "used"]]]]
        #expect(CodexAccountUsageService.resetCredits(in: limits) == .available(count: 1, nextExpiry: nil))
        let none: [String: Any] = ["rateLimitResetCredits": ["credits": [[String: Any]]()]]
        #expect(CodexAccountUsageService.resetCredits(in: none) == .available(count: 0, nextExpiry: nil))
    }

    @Test("No reset-credit block is not zero: it is not reported")
    func unreported() {
        #expect(CodexAccountUsageService.resetCredits(in: [:]) == .unreported)
        #expect(CodexAccountUsageService.resetCredits(in: ["rateLimitResetCredits": [String: Any]()]) == .unreported)
        #expect(UsageDetailCard.resetCreditsText(.unreported) == String.localized("None"))
    }

    @Test("Unknown, missing, and differently cased statuses still count until they expire")
    func unknownStatusCounts() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let unknown: [String: Any] = ["rateLimitResetCredits": [
            "availableCount": 1,
            "credits": [["status": "unknown", "expiresAt": 1_800_000_000]],
        ]]
        let summary = CodexAccountUsageService.credits(from: unknown, now: now)
        #expect(summary?.available == 1)
        #expect(summary?.basis == .inventory)
        #expect(summary?.showsOnCard(at: now) == true)
        #expect(summary?.nextExpiresAt == Date(timeIntervalSince1970: 1_800_000_000))

        let untitled: [String: Any] = ["title": "Full reset"]
        let missing: [String: Any] = ["rateLimitResetCredits": [
            "availableCount": 1,
            "credits": [untitled],
        ]]
        #expect(CodexAccountUsageService.credits(from: missing, now: now)?.showsOnCard(at: now) == true)

        let cased: [String: Any] = ["rateLimitResetCredits": [
            "credits": [["status": "Available", "expiresAt": 1_800_000_000]],
        ]]
        #expect(CodexAccountUsageService.resetCredits(in: cased, now: now)
                == .available(count: 1, nextExpiry: Date(timeIntervalSince1970: 1_800_000_000)))

        let past: [String: Any] = ["rateLimitResetCredits": [
            "availableCount": 1,
            "credits": [["status": "unknown", "expiresAt": 1_700_000_000]],
        ]]
        #expect(CodexAccountUsageService.credits(from: past, now: now)?.available == 0)
        #expect(CodexAccountUsageService.credits(from: past, now: now)?.showsOnCard(at: now) == false)

        let word: [String: Any] = ["rateLimitResetCredits": [
            "availableCount": 1,
            "credits": [["status": "expired", "expiresAt": 1_900_000_000]],
        ]]
        #expect(CodexAccountUsageService.credits(from: word, now: now)?.available == 0)
        #expect(CodexAccountUsageService.credits(from: word, now: now)?.showsOnCard(at: now) == false)
    }

    @Test("A shorter list keeps the stated count while any listed card is still usable")
    func shorterMixedListKeepsStatedCount() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let mixed: [String: Any] = ["rateLimitResetCredits": [
            "availableCount": 3,
            "credits": [
                ["status": "available", "expiresAt": 1_800_000_000],
                ["status": "redeemed", "expiresAt": 1_900_000_000],
            ],
        ]]
        let summary = CodexAccountUsageService.credits(from: mixed, now: now)
        #expect(summary?.available == 3)
        #expect(summary?.nextExpiresAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(summary?.showsOnCard(at: now) == true)

        // The list is not shorter than the stated count, so a spent row is zero.
        let caughtUp: [String: Any] = ["rateLimitResetCredits": [
            "availableCount": 1,
            "credits": [["status": "redeemed", "expiresAt": 1_900_000_000]],
        ]]
        #expect(CodexAccountUsageService.credits(from: caughtUp, now: now)?.available == 0)
    }

    @Test("The usage document's snake_case count is the same inventory")
    func snakeCaseUsageCount() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let countBlock: [String: Any] = ["available_count": 2]
        let countOnly: [String: Any] = ["rate_limit_reset_credits": countBlock]
        let summary = CodexAccountUsageService.credits(from: countOnly, now: now)
        #expect(summary?.available == 2)
        #expect(summary?.basis == .countOnly)
        #expect(summary?.nextExpiresAt == nil)
        #expect(summary?.showsOnCard(at: now) == true)
        #expect(CodexAccountUsageService.resetCredits(in: countOnly, now: now) == .available(count: 2, nextExpiry: nil))

        let row: [String: Any] = ["status": "available", "expires_at": "2027-01-15T08:00:00Z"]
        let listed: [String: Any] = ["rate_limit_reset_credits": [
            "available_count": 2,
            "credits": [row],
        ]]
        let inventory = CodexAccountUsageService.credits(from: listed, now: now)
        #expect(inventory?.available == 2)
        #expect(inventory?.basis == .inventory)
        #expect(inventory?.nextExpiresAt == Date(timeIntervalSince1970: 1_800_000_000))

        // A null camel-case field must not hide the snake-case object beside it.
        let snake: [String: Any] = ["available_count": 1]
        let both: [String: Any] = [
            "rateLimitResetCredits": NSNull(),
            "rate_limit_reset_credits": snake,
        ]
        #expect(CodexAccountUsageService.credits(from: both, now: now)?.available == 1)
    }

    @Test("A millisecond expiry is a real date, and one already past is not a card")
    func millisecondExpiry() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let ahead: [String: Any] = ["rateLimitResetCredits": [
            "credits": [["status": "available", "expiresAt": 1_800_000_000_000]],
        ]]
        #expect(CodexAccountUsageService.resetCredits(in: ahead, now: now)
                == .available(count: 1, nextExpiry: Date(timeIntervalSince1970: 1_800_000_000)))

        let gone: [String: Any] = ["rateLimitResetCredits": [
            "availableCount": 1,
            "credits": [["status": "available", "expiresAt": 1_700_000_000_000]],
        ]]
        #expect(CodexAccountUsageService.credits(from: gone, now: now)?.available == 0)
        #expect(CodexAccountUsageService.credits(from: gone, now: now)?.showsOnCard(at: now) == false)
    }

    @Test("A count-only reply fills an empty line and does not restore one an inventory removed")
    func mergingCountAndInventory() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let count = CodexCreditSummary(available: 2, nextExpiresAt: nil, next: nil, basis: .countOnly)
        #expect(CodexCreditSummary.merging(previous: nil, snapshot: count) == count)

        let later = CodexCreditSummary(available: 1, nextExpiresAt: nil, next: nil, basis: .countOnly)
        #expect(CodexCreditSummary.merging(previous: count, snapshot: later) == later)

        let none = CodexCreditSummary(available: 0, nextExpiresAt: nil, next: nil, basis: .inventory)
        #expect(CodexCreditSummary.merging(previous: count, snapshot: none) == none)
        #expect(CodexCreditSummary.merging(previous: none, snapshot: count) == none)
        #expect(none.showsOnCard(at: now) == false)
        #expect(count.showsOnCard(at: now) == true)

        let settings = AppSettings(enabledAccounts: ["codex"])
        let scratch = FileManager.default.temporaryDirectory
            .appending(path: "pulse-reset-cards-\(UUID().uuidString).json")
        let store = UsageStore(
            settings: settings,
            cache: UsageCache(file: scratch),
            clock: { now }
        )
        store.noteCodexCreditSnapshot(count)
        #expect(store.codexCredits == count)
        store.noteCodexCreditSnapshot(none)
        #expect(store.codexCredits == none)
        store.noteCodexCreditSnapshot(count)
        #expect(store.codexCredits == none)

        let fromHistory = CodexAccountUsage(
            days: [],
            lifetimeTokens: 0,
            peakDailyTokens: 0,
            currentStreakDays: 0,
            longestStreakDays: 0,
            availableResetCredits: 4,
            nextExpiringCredit: nil,
            creditsKnown: true,
            resetCreditBasis: .countOnly
        )
        store.noteCodexCredits(fromHistory)
        #expect(store.codexCredits == none)

        let fresh = UsageStore(
            settings: settings,
            cache: UsageCache(file: FileManager.default.temporaryDirectory
                .appending(path: "pulse-reset-cards-\(UUID().uuidString).json")),
            clock: { now }
        )
        fresh.noteCodexCredits(fromHistory)
        #expect(fresh.codexCredits?.available == 4)
        #expect(fresh.codexCredits?.basis == .countOnly)
        let unknown = CodexAccountUsage(
            days: [],
            lifetimeTokens: 0,
            peakDailyTokens: 0,
            currentStreakDays: 0,
            longestStreakDays: 0,
            availableResetCredits: 0,
            nextExpiringCredit: nil,
            creditsKnown: false,
            resetCreditBasis: .countOnly
        )
        fresh.noteCodexCredits(unknown)
        #expect(fresh.codexCredits?.available == 4)
    }

    @Test("The weekly usage reply carries the reset-card count onto the reading")
    func usageReplyCarriesTheCount() {
        let window: [String: Any] = [
            "used_percent": 99,
            "limit_window_seconds": 604_800,
            "reset_at": 1_800_000_000,
        ]
        let countBlock: [String: Any] = ["available_count": 2]
        let http: [String: Any] = [
            "plan_type": "plus",
            "rate_limit": ["primary_window": window],
            "rate_limit_reset_credits": countBlock,
        ]
        let parsed = CodexUsageService.parseUsageResponse(http, for: AccountKey(.codex))
        #expect(parsed.codexResetCredits?.available == 2)
        #expect(parsed.codexResetCredits?.basis == .countOnly)
        #expect(parsed.codexResetCredits?.showsOnCard() == true)
        #expect(parsed.windows.isEmpty == false)

        let primary: [String: Any] = [
            "usedPercent": 99,
            "windowDurationMins": 10_080,
            "resetsAt": 1_800_000_000,
        ]
        let emptyCredits: [String: Any] = [
            "availableCount": 1,
            "credits": [[String: Any]](),
        ]
        let server: [String: Any] = [
            "rateLimits": ["primary": primary],
            "rateLimitResetCredits": emptyCredits,
        ]
        let fallback = CodexUsageService.parseAppServerResponse(server)
        #expect(fallback.codexResetCredits?.available == 0)
        #expect(fallback.codexResetCredits?.basis == .inventory)
        #expect(fallback.codexResetCredits?.showsOnCard() == false)
    }
}

/// Starting `codex app-server` from a GUI app, whose PATH has no `node`.
@Suite("Codex helper environment")
struct CodexHelperEnvironmentTests {
    @Test("The folder codex was found in leads PATH, once, and nothing else changes")
    func pathLeadsWithCodexFolder() {
        let codex = URL(fileURLWithPath: "/Users/me/.nvm/versions/node/v24/bin/codex")
        let environment = CodexAppServer.environment(
            for: codex,
            over: ["PATH": "/usr/bin:/Users/me/.nvm/versions/node/v24/bin:/bin", "HTTPS_PROXY": "http://proxy:8080"]
        )
        #expect(environment["PATH"] == "/Users/me/.nvm/versions/node/v24/bin:/usr/bin:/bin")
        #expect(environment["HTTPS_PROXY"] == "http://proxy:8080")
    }

    @Test("With no PATH at all, the system folders follow")
    func noInheritedPath() {
        let environment = CodexAppServer.environment(for: URL(fileURLWithPath: "/opt/homebrew/bin/codex"), over: [:])
        #expect(environment["PATH"] == "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin")
    }
}

/// Where Pulse looks for `codex`, which a GUI app has to do by hand.
@Suite("Codex locator")
struct CodexLocatorTests {
    @Test("The desktop apps' own codex is looked for, and the newest managed version before older ones")
    func candidates() {
        let listed = CodexAppServer.candidates(home: "/Users/me", path: "/usr/bin:/bin") { root in
            root.hasSuffix(".nvm/versions/node") ? ["v20.1.0", "v24.11.1"] : []
        }
        #expect(listed.first == "/usr/bin/codex")
        #expect(listed.contains("/Applications/Codex.app/Contents/Resources/codex"))
        #expect(listed.contains("/Applications/ChatGPT.app/Contents/Resources/codex"))
        #expect(listed.contains("/Users/me/Applications/ChatGPT.app/Contents/Resources/codex"))
        let nvm = listed.filter { $0.contains(".nvm") }
        #expect(nvm == ["/Users/me/.nvm/versions/node/v24.11.1/bin/codex", "/Users/me/.nvm/versions/node/v20.1.0/bin/codex"])
    }

    @Test("No codex is said apart from Codex reporting none")
    @MainActor
    func missingIsItsOwnWords() {
        #expect(UsageDetailCard.resetCreditsText(.codexMissing) != UsageDetailCard.resetCreditsText(.unreported))
    }
}

@Suite("Codex locator, app from Launch Services")
struct CodexLocatorAppTests {
    @Test("The app Launch Services names is asked before the fixed places")
    func appFirst() {
        let listed = CodexAppServer.candidates(
            home: "/Users/me", path: nil,
            app: URL(fileURLWithPath: "/Volumes/Apps/ChatGPT.app"),
            versions: { _ in [] }
        )
        #expect(Array(listed.prefix(2)) == [
            "/Volumes/Apps/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
            "/Volumes/Apps/ChatGPT.app/Contents/Resources/codex",
        ])
    }

    @Test("ChatGPT 26.924's layout is looked for before the one it replaced (issue #67)")
    func newerLayoutFirst() {
        let listed = CodexAppServer.candidates(home: "/Users/me", path: nil, versions: { _ in [] })
        let new = listed.firstIndex(of: "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex")
        let old = listed.firstIndex(of: "/Applications/ChatGPT.app/Contents/Resources/codex")
        #expect(new != nil && old != nil)
        #expect(new! < old!)
        #expect(listed.contains("/Users/me/Applications/Codex.app/Contents/Resources/codex-cli/bin/codex"))
    }
}
