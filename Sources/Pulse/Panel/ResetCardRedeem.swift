// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import CoreGraphics
import Foundation

/// Which coupon the card's detail mark has open.
enum ResetCouponSlot: Hashable, Sendable {
    case codex
    case zhipu(ZhipuResetKind)
}

/// One coupon row. The card shows `title` and `count`. Expiry and the use
/// button stay in the detail, so the row does not list them.
struct ResetCouponLine: Equatable, Sendable {
    var slot: ResetCouponSlot
    var title: String
    var count: String
    var expiry: String?
    /// The soonest card, when this row can spend one.
    var cardID: String?
    var useTitle: String?
    var question: String?
    var detail: String?
    var ask: ResetCardPrompt.Action?

    /// There is something to open: a date, or a card that can be used.
    var hasDetail: Bool { expiry != nil || ask != nil }

    /// The use control is a button. It is not a line of body text.
    static let useControlIsButton = true

    @MainActor
    static func codex(_ credits: CodexResetCredits, canRedeem: Bool) -> Self {
        let redeem: Bool = {
            guard canRedeem, case .available(let count, _) = credits, count > 0 else { return false }
            return true
        }()
        return Self(
            slot: .codex,
            title: String.localized("Limit reset credits"),
            count: UsageDetailCard.resetCreditsText(credits),
            expiry: UsageDetailCard.resetCreditExpiryText(credits),
            cardID: nil,
            useTitle: redeem ? String.localized("Use a Codex reset card") : nil,
            question: redeem ? String.localized("Use one Codex reset card?") : nil,
            detail: redeem ? String.localized("Codex resets the limits this card covers.") : nil,
            ask: redeem ? .askCodex : nil
        )
    }

    @MainActor
    static func zhipu(_ kind: ZhipuResetKind, inventory: ZhipuResetInventory, canRedeem: Bool) -> Self {
        let cards = inventory.cards(for: kind)
        let soonest = inventory.soonest(kind)
        let redeem = canRedeem && soonest != nil
        return Self(
            slot: .zhipu(kind),
            title: UsageDetailCard.zhipuKindTitle(kind),
            count: UsageDetailCard.availableCountText(cards.count),
            expiry: soonest.map { UsageDetailCard.expiryText($0.expiresAt) },
            cardID: soonest?.id,
            useTitle: redeem ? UsageDetailCard.zhipuUseTitle(kind) : nil,
            question: redeem ? UsageDetailCard.zhipuQuestion(kind) : nil,
            detail: redeem ? UsageDetailCard.zhipuDetail(kind) : nil,
            ask: redeem ? soonest.map { .askZhipu(kind, cardID: $0.id) } : nil
        )
    }
}

/// Where the coupon detail sits inside the card body.
///
/// Below the row when the card has room there, the same direction as the
/// prediction note. Above the row when the foot of the card would cut the
/// date or the use button off. The result stays inside the body, so the
/// panel is on screen and the button can be clicked.
enum ResetCouponDetailPlacement {
    static func originY(
        rowMinY: CGFloat,
        rowMaxY: CGFloat,
        panelHeight: CGFloat,
        contentHeight: CGFloat,
        gap: CGFloat = 4
    ) -> CGFloat {
        guard panelHeight > 1, contentHeight > 1, rowMaxY > rowMinY else { return 0 }
        let below = rowMaxY + gap
        if below + panelHeight <= contentHeight {
            return below
        }
        let above = rowMinY - gap - panelHeight
        if above >= 0 {
            return above
        }
        return max(0, contentHeight - panelHeight)
    }
}

/// Whether a click closes an in-card detail.
///
/// The detail is the coupon panel or the prediction note. A click on the
/// panel, or on the mark that opened it, leaves it up: the mark toggles on
/// its own, and Use has to receive the click. Anywhere else closes it,
/// including the rest of the card and a click outside the card. An empty
/// detail has not been laid out, so it is left up. This does not close a
/// window. The Token window still closes only from its close button.
enum InCardDetailDismiss {
    static func shouldDismiss(point: CGPoint, detail: CGRect, mark: CGRect) -> Bool {
        guard detail.width > 1, detail.height > 1, !detail.isNull, !detail.isInfinite else { return false }
        if detail.contains(point) { return false }
        if mark.width > 1, mark.height > 1, !mark.isNull, !mark.isInfinite, mark.contains(point) {
            return false
        }
        return true
    }
}

/// Using a reset card from the usage card.
///
/// The first click only asks. Nothing is sent until the reader confirms,
/// and a confirm with nothing pending sends nothing. Codex and Zhipu share
/// this gate; each provider's own call sits behind `Send`.
enum ResetCardPrompt: Equatable, Sendable {
    case idle
    case confirmingCodex
    case confirmingZhipu(ZhipuResetKind, cardID: String)

    enum Action: Equatable, Sendable {
        case askCodex
        case askZhipu(ZhipuResetKind, cardID: String)
        case confirm
        case cancel
    }

    /// The call a confirm is allowed to make.
    enum Send: Equatable, Sendable {
        case codex
        case zhipu(ZhipuResetKind, cardID: String)
    }

    static func step(_ prompt: Self, _ action: Action) -> (prompt: Self, send: Send?) {
        switch action {
        case .cancel:
            return (.idle, nil)
        case .askCodex:
            return (.confirmingCodex, nil)
        case .askZhipu(let kind, let cardID):
            return (.confirmingZhipu(kind, cardID: cardID), nil)
        case .confirm:
            switch prompt {
            case .idle:
                return (.idle, nil)
            case .confirmingCodex:
                return (.idle, .codex)
            case .confirmingZhipu(let kind, let cardID):
                return (.idle, .zhipu(kind, cardID: cardID))
            }
        }
    }
}

/// What the card says after a confirmed use. The words are the whole of the
/// result the reader sees; the call itself stays off this type.
enum ResetCardRedeemReport: Equatable, Sendable {
    case used
    case noCard
    case nothingToReset
    case alreadyUsed
    case failed
    /// The use route is not on this host. The console was opened.
    case openedConsole

    var message: String {
        switch self {
        case .used:
            String.localized("The reset card was used.")
        case .noCard:
            String.localized("No reset card is available.")
        case .nothingToReset:
            String.localized("Nothing to reset.")
        case .alreadyUsed:
            String.localized("That reset card was already used.")
        case .failed:
            String.localized("Could not use the reset card.")
        case .openedConsole:
            String.localized("Could not use the reset card here. The console is open so you can use it there.")
        }
    }

    static func codex(_ outcome: CodexAccountUsageService.ConsumeOutcome) -> Self {
        switch outcome {
        case .reset: .used
        case .nothingToReset: .nothingToReset
        case .noCredit: .noCard
        case .alreadyRedeemed: .alreadyUsed
        case .unreported: .failed
        }
    }
}
