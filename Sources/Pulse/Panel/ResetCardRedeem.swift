// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

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
