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
    @Test("The card shows the count; the date and Use stay in the detail")
    func couponRowIsTheCount() {
        LocalizationSource.use(.english)
        defer { LocalizationSource.use(.system) }
        let none = ResetCouponLine.codex(
            .available(count: 0, nextExpiry: Date(timeIntervalSince1970: 1_800_000_000)),
            canRedeem: true
        )
        #expect(none.title == "Limit reset credits")
        #expect(none.count == "None")
        #expect(none.expiry == nil)
        #expect(none.ask == nil)
        #expect(!none.hasDetail)

        let expiry = Date(timeIntervalSince1970: 1_800_000_000)
        let some = ResetCouponLine.codex(.available(count: 2, nextExpiry: expiry), canRedeem: true)
        #expect(some.hasDetail)
        #expect(some.ask == .askCodex)
        #expect(some.useTitle == "Use a Codex reset card")
        #expect(some.expiry != nil)
        #expect(!some.count.contains("Use"))
        #expect(ResetCouponLine.useControlIsButton)

        let blocked = ResetCouponLine.codex(.available(count: 2, nextExpiry: expiry), canRedeem: false)
        #expect(blocked.ask == nil)
        #expect(blocked.hasDetail)

        let soon = Date(timeIntervalSince1970: 1_800_000_000)
        let later = Date(timeIntervalSince1970: 1_900_000_000)
        let inventory = ZhipuResetInventory(
            fiveHour: [
                ZhipuResetCard(id: "11", recordID: 11, grantType: "GLOBAL", expiresAt: later),
                ZhipuResetCard(id: "9", recordID: 9, grantType: "", expiresAt: soon),
            ],
            weekly: [],
            serviceHost: "https://z.ai"
        )
        let hour = ResetCouponLine.zhipu(.fiveHourCard, inventory: inventory, canRedeem: true)
        #expect(hour.count == "2 available")
        #expect(hour.cardID == "9")
        #expect(hour.ask == .askZhipu(.fiveHourCard, cardID: "9"))
        #expect(hour.useTitle == "Use a 5-hour reset card")
        #expect(hour.title == "5-hour reset cards")
        let week = ResetCouponLine.zhipu(.weeklyCard, inventory: inventory, canRedeem: true)
        #expect(week.count == "None")
        #expect(week.ask == nil)
        #expect(!week.hasDetail)
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
    @Test("A reported zero and a missing count both say None")
    func noneIsTheWord() {
        LocalizationSource.use(.english)
        defer { LocalizationSource.use(.system) }
        #expect(UsageDetailCard.availableCountText(0) == "None")
        #expect(UsageDetailCard.resetCreditsText(.unreported) == "None")
        #expect(UsageDetailCard.resetCreditsText(.codexMissing) != "None")
        LocalizationSource.use(.chineseSimplified)
        let zero = UsageDetailCard.availableCountText(0)
        let missing = UsageDetailCard.resetCreditsText(.unreported)
        #expect(zero == "无")
        #expect(missing == "无")
        #expect(!zero.contains("不可用"))
        #expect(!missing.contains("不可用"))
    }
}
