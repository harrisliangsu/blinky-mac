// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import Testing
@testable import Pulse

/// Using a reset card. The first click only asks. No test here talks to Codex
/// or to Zhipu.
@Suite("Reset card redeem")
struct ResetCardRedeemTests {
    @Test("Ask and an idle confirm send nothing")
    func promptDoesNotSendEarly() {
        let asked = ResetCardPrompt.step(.idle, .askCodex)
        #expect(asked.prompt == .confirmingCodex)
        #expect(asked.send == nil)

        let zhipu = ResetCardPrompt.step(.idle, .askZhipu(.weeklyCard, cardID: "22"))
        #expect(zhipu.prompt == .confirmingZhipu(.weeklyCard, cardID: "22"))
        #expect(zhipu.send == nil)

        let idle = ResetCardPrompt.step(.idle, .confirm)
        #expect(idle.prompt == .idle)
        #expect(idle.send == nil)

        let cancelled = ResetCardPrompt.step(.confirmingCodex, .cancel)
        #expect(cancelled.prompt == .idle)
        #expect(cancelled.send == nil)

        let confirmed = ResetCardPrompt.step(.confirmingCodex, .confirm)
        #expect(confirmed.prompt == .idle)
        #expect(confirmed.send == .codex)

        let week = ResetCardPrompt.step(.confirmingZhipu(.fiveHourCard, cardID: "11"), .confirm)
        #expect(week.send == .zhipu(.fiveHourCard, cardID: "11"))
    }

    @Test("A Codex outcome becomes the sentence the card shows")
    func codexReports() {
        #expect(ResetCardRedeemReport.codex(.reset) == .used)
        #expect(ResetCardRedeemReport.codex(.nothingToReset) == .nothingToReset)
        #expect(ResetCardRedeemReport.codex(.noCredit) == .noCard)
        #expect(ResetCardRedeemReport.codex(.alreadyRedeemed) == .alreadyUsed)
        #expect(ResetCardRedeemReport.codex(.unreported) == .failed)
        #expect(ResetCardRedeemReport.openedConsole != .used)
    }

    @Test("Consume names the soonest usable credit and omits an empty id")
    func consumeRequest() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let limits: [String: Any] = [
            "rateLimitResetCredits": [
                "availableCount": 2,
                "credits": [
                    [
                        "id": "later",
                        "status": "available",
                        "expiresAt": now.addingTimeInterval(10_000).timeIntervalSince1970,
                    ],
                    [
                        "id": "sooner",
                        "status": "available",
                        "expiresAt": now.addingTimeInterval(100).timeIntervalSince1970,
                    ],
                    [
                        "id": "spent",
                        "status": "redeemed",
                        "expiresAt": now.addingTimeInterval(1).timeIntervalSince1970,
                    ],
                ],
            ] as [String: Any],
        ]
        #expect(CodexAccountUsageService.preferredCreditID(in: limits, now: now) == "sooner")
        let picked = CodexAccountUsageService.consumeRequest(idempotencyKey: "key-1", creditID: "sooner")
        #expect(picked.idempotencyKey == "key-1")
        #expect(picked.includesCreditID)
        #expect(CodexAccountUsageService.ConsumeRequest.method == "account/rateLimitResetCredit/consume")
        let omitted = CodexAccountUsageService.consumeRequest(idempotencyKey: "key-2", creditID: "")
        #expect(!omitted.includesCreditID)
        #expect(!CodexAccountUsageService.consumeRequest(idempotencyKey: "key-3", creditID: nil).includesCreditID)
        #expect(CodexAccountUsageService.consumeOutcome(in: ["type": "reset"]) == .reset)
        #expect(CodexAccountUsageService.consumeOutcome(in: ["outcome": "nothingToReset"]) == .nothingToReset)
        #expect(CodexAccountUsageService.consumeOutcome(in: ["noCredit": [:]]) == .noCredit)
        #expect(CodexAccountUsageService.consumeOutcome(in: ["status": "alreadyRedeemed"]) == .alreadyRedeemed)
        #expect(CodexAccountUsageService.consumeOutcome(in: ["type": "surprise"]) == .unreported)
    }

    @MainActor
    @Test("Codex shows the count and the soonest expiry; Use stays in the detail")
    func couponRowIsTheCount() {
        let held = LocalizationSource.hold(.english)
        defer { held.end() }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let none = ResetCouponLine.codex(
            .available(count: 0, nextExpiry: Date(timeIntervalSince1970: 1_800_000_000)),
            canRedeem: true,
            now: now
        )
        #expect(none.title == "Reset cards")
        #expect(none.count == "None")
        #expect(none.expiry == nil)
        #expect(none.rowNote == nil)
        #expect(none.ask == nil)
        #expect(none.help?.isEmpty == false)
        #expect(none.hasDetail)

        let expiry = Date(timeIntervalSince1970: 1_800_000_000)
        let some = ResetCouponLine.codex(.available(count: 2, nextExpiry: expiry), canRedeem: true, now: now)
        #expect(some.hasDetail)
        #expect(some.ask == .askCodex)
        #expect(some.useTitle == "Use a Codex reset card")
        #expect(some.expiry == nil)
        #expect(some.rowNote == UsageDetailCard.nextExpiryText(until: expiry, now: now))
        #expect(some.rowNote?.hasPrefix("Next expires in ") == true)
        #expect(!some.count.contains("Use"))
        #expect(ResetCouponLine.useControlIsButton)

        let blocked = ResetCouponLine.codex(.available(count: 2, nextExpiry: expiry), canRedeem: false, now: now)
        #expect(blocked.ask == nil)
        #expect(blocked.hasDetail)
        #expect(blocked.rowNote != nil)

        let past = ResetCouponLine.codex(
            .available(count: 1, nextExpiry: now.addingTimeInterval(-60)),
            canRedeem: true,
            now: now
        )
        #expect(past.rowNote == nil)
        #expect(past.ask == .askCodex)

        LocalizationSource.use(.chineseSimplified)
        let zh = ResetCouponLine.codex(.available(count: 1, nextExpiry: expiry), canRedeem: true, now: now)
        #expect(zh.title == "重置卡")
        #expect(zh.rowNote?.contains("最近一张") == true)
        #expect(zh.title.contains("额度重置") == false)
        #expect(String.localized("Use a Codex reset card") == "使用一张 Codex 重置卡")
        #expect(String.localized("Use one Codex reset card?") == "要使用一张 Codex 重置卡吗？")
        #expect(String.localized("The reset card was used.") == "已使用这张重置卡。")
        #expect(!String.localized("The reset card was used.").contains("券"))
    }

    @MainActor
    @Test("Zhipu and z.ai share one row for both kinds")
    func zhipuRowIsOneLine() {
        let held = LocalizationSource.hold(.english)
        defer { held.end() }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let soon = Date(timeIntervalSince1970: 1_800_000_000)
        let later = Date(timeIntervalSince1970: 1_900_000_000)
        let weeklySooner = Date(timeIntervalSince1970: 1_750_000_000)
        let hour = ZhipuResetCard(id: "9", recordID: 9, grantType: "", expiresAt: soon)
        let hourLater = ZhipuResetCard(id: "11", recordID: 11, grantType: "GLOBAL", expiresAt: later)
        let week = ZhipuResetCard(id: "3", recordID: 3, grantType: "GLOBAL", expiresAt: weeklySooner)

        let both = ZhipuResetInventory(
            fiveHour: [hourLater, hour],
            weekly: [week],
            serviceHost: "https://z.ai"
        )
        let line = ResetCouponLine.zhipu(both, canRedeem: true, now: now)
        #expect(line?.slot == .zhipu)
        #expect(line?.title == "Reset cards")
        #expect(line?.count == "5h ×2 · Weekly ×1")
        #expect(line?.expiry == nil)
        #expect(line?.ask == nil)
        #expect(line?.useTitle == nil)
        #expect(line?.rowNote == UsageDetailCard.nextExpiryText(until: weeklySooner, now: now))
        #expect(line?.rowNote?.hasPrefix("Next expires in ") == true)
        #expect(line?.help?.contains("apply a reset card yourself") == true)
        #expect(line?.help?.contains("5-hour quota returns to full") == true)
        #expect(line?.help?.contains("weekly quota returns to full") == true)
        #expect(line?.hasDetail == true)
        #expect(line?.choices.map(\.ask) == [
            .askZhipu(.fiveHourCard, cardID: "9"),
            .askZhipu(.weeklyCard, cardID: "3"),
        ])
        #expect(line?.choices.map(\.title) == [
            "Use a 5-hour reset card",
            "Use a weekly reset card",
        ])
        #expect(UsageDetailCard.zhipuSummary(both, now: now)?.hasPrefix("5h ×2 · Weekly ×1 · ") == true)
        #expect(UsageDetailCard.zhipuSummary(both, now: now)?.hasSuffix(UsageDetailCard.expiryText(weeklySooner)) == true)

        let hoursOnly = ZhipuResetInventory(
            fiveHour: [hourLater, hour],
            weekly: [],
            serviceHost: "https://api.z.ai"
        )
        let oneKind = ResetCouponLine.zhipu(hoursOnly, canRedeem: true, now: now)
        #expect(oneKind?.count == "5h ×2")
        #expect(oneKind?.choices.map(\.ask) == [.askZhipu(.fiveHourCard, cardID: "9")])
        #expect(oneKind?.rowNote == UsageDetailCard.nextExpiryText(until: soon, now: now))
        #expect(oneKind?.count.contains("Weekly") == false)

        let empty = ZhipuResetInventory(fiveHour: [], weekly: [], serviceHost: "https://z.ai")
        #expect(ResetCouponLine.zhipu(empty, canRedeem: true, now: now) == nil)
        #expect(UsageDetailCard.zhipuAvailabilityText(empty) == nil)
        #expect(UsageDetailCard.zhipuSummary(empty) == nil)

        let blocked = ResetCouponLine.zhipu(both, canRedeem: false, now: now)
        #expect(blocked?.choices.isEmpty == true)
        #expect(blocked?.help?.isEmpty == false)
        #expect(blocked?.hasDetail == true)
        #expect(blocked?.rowNote != nil)

        let past = ZhipuResetInventory(
            fiveHour: [ZhipuResetCard(id: "1", recordID: 1, grantType: "", expiresAt: now.addingTimeInterval(-60))],
            weekly: [week],
            serviceHost: "https://z.ai"
        )
        let stale = ResetCouponLine.zhipu(past, canRedeem: true, now: now)
        #expect(stale?.count == "5h ×1 · Weekly ×1")
        #expect(stale?.rowNote == UsageDetailCard.nextExpiryText(until: weeklySooner, now: now))

        #expect(ZhipuResetCardGate.inventory(
            both, provider: .zai, showsZaiResetCards: true, showsZhipuResetCards: false
        ) == both)
        #expect(ZhipuResetCardGate.inventory(
            both, provider: .zai, showsZaiResetCards: false, showsZhipuResetCards: true
        ) == nil)
        #expect(ZhipuResetCardGate.inventory(
            both, provider: .glmCoding, showsZaiResetCards: false, showsZhipuResetCards: true
        ) == both)
        #expect(ZhipuResetCardGate.inventory(
            both, provider: .glmCoding, showsZaiResetCards: true, showsZhipuResetCards: false
        ) == nil)
        #expect(ZhipuResetCardGate.inventory(
            both, provider: .codex, showsZaiResetCards: true, showsZhipuResetCards: true
        ) == nil)
        #expect(ZhipuResetCardGate.inventory(
            nil, provider: .zai, showsZaiResetCards: true, showsZhipuResetCards: true
        ) == nil)

        LocalizationSource.use(.chineseSimplified)
        let zh = ResetCouponLine.zhipu(both, canRedeem: true, now: now)
        #expect(zh?.title == "重置卡")
        #expect(zh?.count == "5h ×2 · 每周 ×1")
        #expect(zh?.rowNote?.contains("最近一张") == true)
        #expect(zh?.help?.contains("重置卡") == true)
        #expect(zh?.help?.contains("券") == false)
        #expect(zh?.choices.map(\.title) == [
            "使用一张 5 小时重置卡",
            "使用一张每周重置卡",
        ])
        #expect(String.localized("Use one 5-hour reset card?") == "要使用一张 5 小时重置卡吗？")
        #expect(String.localized("Use one weekly reset card?") == "要使用一张每周重置卡吗？")
    }

    @Test("The detail stays inside the card, below the row or above it")
    func detailStaysInsideTheCard() {
        let below = ResetCouponDetailPlacement.originY(
            rowMinY: 100, rowMaxY: 114, panelHeight: 40, contentHeight: 300
        )
        #expect(below == CGFloat(118))
        #expect(below + 40 <= 300)

        let above = ResetCouponDetailPlacement.originY(
            rowMinY: 250, rowMaxY: 264, panelHeight: 40, contentHeight: 280
        )
        #expect(above == CGFloat(206))
        #expect(above >= 0)
        #expect(above + 40 <= 280)
        #expect(above + 40 <= 250)

        let pinned = ResetCouponDetailPlacement.originY(
            rowMinY: 10, rowMaxY: 24, panelHeight: 80, contentHeight: 100
        )
        #expect(pinned == CGFloat(20))
        #expect(pinned + 80 <= 100)

        #expect(ResetCouponDetailPlacement.originY(
            rowMinY: 0, rowMaxY: 0, panelHeight: 40, contentHeight: 200
        ) == 0)
    }

    @Test("A click outside the detail closes it; a click on it or its mark does not")
    func clickOutsideTheDetail() {
        let detail = CGRect(x: 100, y: 100, width: 160, height: 48)
        let mark = CGRect(x: 40, y: 160, width: 16, height: 16)
        #expect(!InCardDetailDismiss.shouldDismiss(
            point: CGPoint(x: 120, y: 120), detail: detail, mark: mark
        ))
        #expect(!InCardDetailDismiss.shouldDismiss(
            point: CGPoint(x: 48, y: 168), detail: detail, mark: mark
        ))
        #expect(InCardDetailDismiss.shouldDismiss(
            point: CGPoint(x: 10, y: 10), detail: detail, mark: mark
        ))
        #expect(InCardDetailDismiss.shouldDismiss(
            point: CGPoint(x: 80, y: 180), detail: detail, mark: mark
        ))
        #expect(InCardDetailDismiss.shouldDismiss(
            point: CGPoint(x: 10, y: 10), detail: detail, mark: .null
        ))
        #expect(!InCardDetailDismiss.shouldDismiss(
            point: CGPoint(x: 120, y: 120), detail: detail, mark: .null
        ))
        #expect(!InCardDetailDismiss.shouldDismiss(
            point: CGPoint(x: 10, y: 10), detail: .null, mark: mark
        ))
        #expect(!InCardDetailDismiss.shouldDismiss(
            point: CGPoint(x: 10, y: 10), detail: .zero, mark: mark
        ))
        #expect(!InCardDetailDismiss.shouldDismiss(
            point: CGPoint(x: 10, y: 10),
            detail: CGRect(x: 0, y: 0, width: 1, height: 40),
            mark: mark
        ))
    }

    @MainActor
    @Test("A reported zero says None; a failed read does not")
    func noneIsTheWord() {
        let held = LocalizationSource.hold(.english)
        defer { held.end() }
        #expect(UsageDetailCard.availableCountText(0) == "None")
        #expect(UsageDetailCard.resetCreditsText(.available(count: 0, nextExpiry: nil)) == "None")
        #expect(UsageDetailCard.resetCreditsText(.available(count: 1, nextExpiry: nil)) == "1 available")
        #expect(UsageDetailCard.resetCreditsText(.available(count: 2, nextExpiry: nil)) == "2 available")
        #expect(UsageDetailCard.resetCreditsText(.unreported) == "Couldn't read")
        #expect(UsageDetailCard.resetCreditsText(.codexMissing) != "None")
        #expect(UsageDetailCard.resetCreditsText(.codexMissing) != "Couldn't read")
        LocalizationSource.use(.chineseSimplified)
        let zero = UsageDetailCard.availableCountText(0)
        let reportedZero = UsageDetailCard.resetCreditsText(.available(count: 0, nextExpiry: nil))
        let one = UsageDetailCard.resetCreditsText(.available(count: 1, nextExpiry: nil))
        let two = UsageDetailCard.resetCreditsText(.available(count: 2, nextExpiry: nil))
        let missing = UsageDetailCard.resetCreditsText(.unreported)
        #expect(zero == "无")
        #expect(reportedZero == "无")
        #expect(one == "可用 1 张")
        #expect(two == "可用 2 张")
        #expect(missing == "未能读取")
        #expect(missing != "无")
    }
}
