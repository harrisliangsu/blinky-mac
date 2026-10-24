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
}
