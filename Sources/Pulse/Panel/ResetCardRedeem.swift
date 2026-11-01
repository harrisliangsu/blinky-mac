// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import CoreGraphics
import Foundation

/// Which coupon the card's detail mark has open.
enum ResetCouponSlot: Hashable, Sendable {
    case codex
    /// Zhipu and z.ai share one row. The kind is chosen inside the detail.
    case zhipu
}

/// One way to spend a card from the detail. Zhipu lists one of these per
/// kind that still has stock. Codex keeps a single Use control on the line.
struct ResetCouponChoice: Equatable, Sendable, Identifiable {
    /// The kind's wire name, so the buttons stay put while the card refreshes.
    var id: String
    var title: String
    var question: String
    var detail: String
    var ask: ResetCardPrompt.Action
}

/// One coupon row. The card shows `title` and `count`, and the soonest
/// expiry under that row (`rowNote`) when a card has a date. The explanation
/// and every Use button stay in the detail.
struct ResetCouponLine: Equatable, Sendable {
    var slot: ResetCouponSlot
    var title: String
    var count: String
    /// Soonest expiry, on the row. Nil leaves the row as one line.
    var rowNote: String?
    /// Absolute date in the detail. Codex and Zhipu leave it nil; the date
    /// is the row note.
    var expiry: String?
    /// The soonest card, when this row can spend one. Codex leaves it nil.
    var cardID: String?
    var useTitle: String?
    var question: String?
    var detail: String?
    /// How the cards work. Shown in the detail, not on the row.
    var help: String?
    var ask: ResetCardPrompt.Action?
    /// Use controls for a row that can spend more than one kind. Empty for Codex.
    var choices: [ResetCouponChoice] = []

    /// There is something to open: a date, an explanation, or a card that can be used.
    var hasDetail: Bool {
        expiry != nil || ask != nil || help?.isEmpty == false || !choices.isEmpty
    }

    /// The use control is a button. It is not a line of body text.
    static let useControlIsButton = true

    @MainActor
    static func codex(_ credits: CodexResetCredits, canRedeem: Bool, now: Date = Date()) -> Self {
        let redeem: Bool = {
            guard canRedeem, case .available(let count, _) = credits, count > 0 else { return false }
            return true
        }()
        let rowNote: String? = {
            guard case .available(let count, let expiry?) = credits, count > 0 else { return nil }
            return UsageDetailCard.nextExpiryText(until: expiry, now: now)
        }()
        return Self(
            slot: .codex,
            title: String.localized("Reset cards"),
            count: UsageDetailCard.resetCreditsText(credits),
            rowNote: rowNote,
            expiry: nil,
            cardID: nil,
            useTitle: redeem ? String.localized("Use a Codex reset card") : nil,
            question: redeem ? String.localized("Use one Codex reset card?") : nil,
            detail: redeem ? String.localized("Codex resets the limits this card covers.") : nil,
            help: CodexResetPresentation.help(resetType: "banked", announcement: nil),
            ask: redeem ? .askCodex : nil
        )
    }

    /// One row for both kinds, or nil when neither has a card left. A kind
    /// with none is left out of the count and out of the Use list. The note
    /// is the soonest expiry across the kinds that remain.
    @MainActor
    static func zhipu(
        _ inventory: ZhipuResetInventory,
        canRedeem: Bool,
        now: Date = Date()
    ) -> Self? {
        guard let count = UsageDetailCard.zhipuAvailabilityText(inventory) else { return nil }
        let soonest = inventory.soonestCard(after: now)
        return Self(
            slot: .zhipu,
            title: String.localized("Reset cards"),
            count: count,
            rowNote: soonest.flatMap { UsageDetailCard.nextExpiryText(until: $0.expiresAt, now: now) },
            expiry: nil,
            cardID: nil,
            useTitle: nil,
            question: nil,
            detail: nil,
            help: String.localized("You apply a reset card yourself. For a 5-hour card, the 5-hour quota returns to full, and its next reset is counted from now. For a weekly card, the weekly quota returns to full. The 5-hour quota returns with it, and both reset times are counted from now."),
            ask: nil,
            choices: zhipuChoices(inventory, canRedeem: canRedeem)
        )
    }

    @MainActor
    private static func zhipuChoices(
        _ inventory: ZhipuResetInventory,
        canRedeem: Bool
    ) -> [ResetCouponChoice] {
        guard canRedeem else { return [] }
        return [ZhipuResetKind.fiveHourCard, .weeklyCard].compactMap { kind in
            guard let card = inventory.soonest(kind) else { return nil }
            return ResetCouponChoice(
                id: kind.rawValue,
                title: UsageDetailCard.zhipuUseTitle(kind),
                question: UsageDetailCard.zhipuQuestion(kind),
                detail: UsageDetailCard.zhipuDetail(kind),
                ask: .askZhipu(kind, cardID: card.id)
            )
        }
    }
}

/// Whether the usage card may draw a Zhipu or z.ai reset-card row.
///
/// The list is still read with the quota. The switch only decides whether
/// the card gets that list. Off, the row and its mark are absent.
enum ZhipuResetCardGate {
    static func inventory(
        _ inventory: ZhipuResetInventory?,
        provider: Provider,
        showsZaiResetCards: Bool,
        showsZhipuResetCards: Bool
    ) -> ZhipuResetInventory? {
        guard let inventory else { return nil }
        switch provider {
        case .zai: return showsZaiResetCards ? inventory : nil
        case .glmCoding: return showsZhipuResetCards ? inventory : nil
        default: return nil
        }
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
