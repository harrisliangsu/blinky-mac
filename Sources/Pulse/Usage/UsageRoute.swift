// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// The route that actually answered, rather than the user's routing preference.
enum UsageRoute: String, Codable, Sendable {
    case endpoint
    case statusLine
    case desktopSession
    case appServer
    case kiroACP
    case languageServer
    case webSession
    case arkCLI
    /// Antigravity's `agy` CLI, asked `/usage` in print mode.
    case antigravityCLI
    /// A reading taken out of a desktop app's own saved state rather than
    /// asked of anybody. Devin's: written when that app starts.
    case appCache
    /// A program in the extensions folder, which answered on stdout.
    case extensionProgram = "extension"
    /// A login Blinky obtained itself and refreshes itself. Grok's primary
    /// account uses it when the CLI's token is missing or refused. The
    /// request is still the CLI proxy; the credential is not the CLI's file.
    case heldLogin

    var title: String {
        switch self {
        case .endpoint: .localized("Usage endpoint")
        case .statusLine: .localized("Claude Code status line")
        case .desktopSession: .localized("Desktop app session")
        case .appServer: .localized("Codex app server")
        case .kiroACP: .localized("Kiro CLI ACP")
        case .languageServer: .localized("Local language server")
        case .webSession: .localized("Signed-in web page")
        case .arkCLI: "arkcli"
        case .antigravityCLI: "agy"
        case .appCache: .localized("The app's saved plan")
        case .extensionProgram: .localized("Extension program")
        case .heldLogin: .localized("Blinky login")
        }
    }

    /// Only single-route providers can be labelled outside their service.
    static func soleRoute(for account: AccountKey) -> UsageRoute? {
        // Before the added-account rule: every extension is an account of
        // one provider, and none of them is its first.
        if account.provider == .pulseExtension { return .extensionProgram }
        if !account.isPrimary { return .endpoint }
        guard let written = account.provider.handWritten else {
            switch account.provider.profile?.credential {
            case .sessionCookie, .browserStorage: return .webSession
            default: return .endpoint
            }
        }
        switch written {
        // Antigravity has the language server and the `agy` CLI. Kimi has a
        // device-code login and a pasted key. Grok's primary has the CLI file
        // and Blinky's own login. None of those has a single route.
        case .claudeCode, .codex, .volcengine, .kimiCode, .devin, .antigravity, .grok: return nil
        // Browser session rather than a key (Ollama, Xiaomi, Qoder, StepFun).
        case .ollamaCloud, .xiaomiMiMo, .qoder, .stepFun: return .webSession
        case .kiro: return .kiroACP
        case .cursor, .openCodeGo, .zai, .glmCoding, .minimax,
             .copilot, .grokBot, .commandCode, .deepSeek,
             .sub2api, .newAPI, .v2ex:
            return .endpoint
        case .pulseExtension: return .extensionProgram
        }
    }
}

extension ProviderUsage {
    /// Retains earlier route outcomes when automatic routing falls through.
    /// Contains only typed outcomes, never request headers or response bodies.
    func recording(_ route: UsageRoute, after earlier: [ConnectionDiagnostic.Attempt] = []) -> Self {
        var result = self
        result.origin = reportsSomething ? route : nil
        result.attempts = earlier + [.init(route: route, state: state)]
        return result
    }

    func recordingSoleRoute() -> Self {
        guard attempts.isEmpty, let route = UsageRoute.soleRoute(for: account) else { return self }
        return recording(route)
    }
}
