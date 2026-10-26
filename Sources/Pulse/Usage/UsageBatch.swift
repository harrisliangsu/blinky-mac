import Foundation

/// One pass's primary-account reads, started together.
///
/// **One case per provider, and the only place a pass fetches one.**
/// The 1.4.3 sync kept two `async let qoderUsage` bindings: this fork and
/// upstream each added Qoder in a different part of `UsageStore.refresh`,
/// and git kept both. A second `case .qoder` in `read` does not compile.
/// A second `async let qoderUsage` pasted back into `UsageStore` is what
/// `Scripts/fork-compat-check.sh` rejects. Add a `load` line in `collect`
/// and a case in `read`. Do not add an `async let` block beside the call.
struct UsageBatch: Sendable {
    var wanted: Set<Provider>
    var codex: CodexUsageService
    var codexSource: UsageSource
    var kiro: KiroUsageService
    var claudeCode: ClaudeCodeUsageService
    var claudeSource: UsageSource
    var antigravity: AntigravityUsageService
    var antigravitySource: UsageSource
    var cursor: CursorUsageService
    var openCode: OpenCodeGoUsageService
    var kimi: KimiCodeUsageService
    var kimiSource: UsageSource
    var ollama: OllamaCloudUsageService
    var qoder: QoderUsageService
    var xiaomi: XiaomiMiMoUsageService
    var zai: ZaiUsageService
    var glm: ZaiUsageService
    var minimax: MiniMaxUsageService
    var copilot: CopilotUsageService
    var grok: GrokUsageService
    var grokSource: UsageSource
    var grokBot: GrokBotUsageService
    var volcengine: VolcengineUsageService
    var volcengineSource: UsageSource
    var commandCode: CommandCodeUsageService
    var deepSeek: DeepSeekUsageService
    var devin: DevinUsageService
    var devinSource: UsageSource
    var sub2api: Sub2APIUsageService
    var newAPI: NewAPIUsageService
    var v2ex: V2EXUsageService
    var stepFun: StepFunUsageService
    /// Profiled providers due on this pass, keyed by provider. Empty when
    /// none of them were asked. Their fetch uses only this context.
    var profiles: [Provider: (ProviderProfile, ProfileContext)] = [:]

    /// Side by side, on this function's main actor. That is where the old
    /// `async let` list in `UsageStore.refresh` ran, so a fetch that touches
    /// the keychain or a browser store stays there. A task group does not
    /// inherit that actor: `addTask { @MainActor in }` is rejected by Swift 6
    /// (`pattern that the region-based isolation checker does not understand
    /// how to check`).
    ///
    /// `load` calls `read` only when the provider is due. Anything else keeps
    /// the reading it already has. The names here are the only `async let`
    /// list; `Scripts/fork-compat-check.sh` requires one `load` per provider.
    @MainActor
    func collect() async -> [Provider: ProviderUsage] {
        async let claudeUsage = load(.claudeCode)
        async let codexUsage = load(.codex)
        async let kiroUsage = load(.kiro)
        async let antigravityUsage = load(.antigravity)
        async let cursorUsage = load(.cursor)
        async let openCodeUsage = load(.openCodeGo)
        async let kimiUsage = load(.kimiCode)
        async let ollamaUsage = load(.ollamaCloud)
        async let zaiUsage = load(.zai)
        async let glmUsage = load(.glmCoding)
        async let minimaxUsage = load(.minimax)
        async let copilotUsage = load(.copilot)
        async let grokUsage = load(.grok)
        async let grokBotUsage = load(.grokBot)
        async let volcengineUsage = load(.volcengine)
        async let qoderUsage = load(.qoder)
        async let commandCodeUsage = load(.commandCode)
        async let deepSeekUsage = load(.deepSeek)
        async let devinUsage = load(.devin)
        async let xiaomiUsage = load(.xiaomiMiMo)
        async let sub2apiUsage = load(.sub2api)
        async let newAPIUsage = load(.newAPI)
        async let v2exUsage = load(.v2ex)
        async let stepFunUsage = load(.stepFun)
        // Started beside the hand-written reads, not after they return.
        async let profiledRows = profiledReadings()

        var readings: [Provider: ProviderUsage] = [:]
        for row in [
            await claudeUsage, await codexUsage, await kiroUsage, await antigravityUsage,
            await cursorUsage, await openCodeUsage, await kimiUsage, await ollamaUsage,
            await zaiUsage, await glmUsage, await minimaxUsage,
            await copilotUsage, await grokUsage, await grokBotUsage, await volcengineUsage,
            await qoderUsage, await commandCodeUsage, await deepSeekUsage, await devinUsage,
            await xiaomiUsage, await sub2apiUsage, await newAPIUsage, await v2exUsage,
            await stepFunUsage,
        ] {
            guard let (provider, usage) = row else { continue }
            readings[provider] = usage
        }
        for (provider, usage) in await profiledRows {
            readings[provider] = usage
        }
        return readings
    }

    /// Profiled providers, side by side. Each fetch was handed its credential
    /// already, so this does not touch the keychain or settings.
    private func profiledReadings() async -> [(Provider, ProviderUsage)] {
        let jobs = profiles
        return await withTaskGroup(of: (Provider, ProviderUsage).self) { group in
            for provider in wanted where jobs[provider] != nil {
                let pair = jobs[provider]!
                let profile = pair.0
                let context = pair.1
                group.addTask { (provider, await profile.fetch(context)) }
            }
            var rows: [(Provider, ProviderUsage)] = []
            for await row in group { rows.append(row) }
            return rows
        }
    }

    /// `nil` when this pass did not ask. The child still starts, and it
    /// finishes without calling the service, so a provider that is off or
    /// not yet due does not spend a request.
    @MainActor
    private func load(_ provider: Provider) async -> (Provider, ProviderUsage)? {
        guard wanted.contains(provider) else { return nil }
        return (provider, await read(provider))
    }

    @MainActor
    private func read(_ provider: Provider) async -> ProviderUsage {
        switch provider.handWritten {
        case .codex:
            await codex.fetch(source: codexSource)
        case .kiro:
            await kiro.fetch()
        case .claudeCode:
            await claudeCode.fetch(source: claudeSource)
        case .antigravity:
            await antigravity.fetch(source: antigravitySource)
        case .cursor:
            await cursor.fetch()
        case .openCodeGo:
            await openCode.fetch()
        case .kimiCode:
            await kimi.fetch(source: kimiSource)
        case .ollamaCloud:
            await ollama.fetch()
        case .qoder:
            await qoder.fetch()
        case .xiaomiMiMo:
            await xiaomi.fetch()
        case .zai:
            await zai.fetch()
        case .glmCoding:
            await glm.fetch()
        case .minimax:
            await minimax.fetch()
        case .copilot:
            await copilot.fetch()
        case .grok:
            await grok.fetch(source: grokSource)
        case .grokBot:
            await grokBot.fetch()
        case .volcengine:
            await volcengine.fetch(source: volcengineSource)
        case .commandCode:
            await commandCode.fetch()
        case .deepSeek:
            await deepSeek.fetch()
        case .devin:
            await devin.fetch(source: devinSource)
        case .sub2api:
            await sub2api.fetch()
        case .newAPI:
            await newAPI.fetch()
        case .v2ex:
            await v2ex.fetch()
        case .stepFun:
            await stepFun.fetch()
        case .pulseExtension:
            // Extensions are programs, fetched beside this batch. There is
            // never a primary account of this provider.
            .unavailable(AccountKey(.pulseExtension), reason: .extensionMissing)
        case nil:
            if let pair = profiles[provider] {
                await pair.0.fetch(pair.1)
            } else {
                .unavailable(AccountKey(provider), reason: .loading)
            }
        }
    }
}
