import Foundation
import Testing
@testable import Pulse

/// The agent catalogue: the seven readers Pulse verified on a real machine and
/// the forty-seven it added from format facts, the family each is routed to, and
/// the metadata that keeps "recognised" from reading as "counted".
///
/// Nothing here touches a user store. Roots are injected, presence is decided
/// under a temporary home, and the one parsing check is a synthetic capture
/// written by the test itself.
@Suite("Spend agent catalog")
struct SpendAgentCatalogTests {
    /// The readers that predate the catalogue and keep their own stores.
    private static let legacy: Set<SpendAgent> = [
        .claudeCode, .codex, .openCode, .kiloCLI, .grok, .kimiCLI, .devinCLI,
    ]

    private static var newClients: [SpendAgent] {
        SpendAgent.allCases.filter { !legacy.contains($0) }
    }

    /// Group E: read only from an explicit export, cache or capture.
    private static let capture: Set<SpendAgent> = [
        .cursor, .antigravity, .trae, .warp, .hindsight, .mcode,
    ]

    /// The three whose stores expose no usable token counters.
    private static let tokenless: Set<SpendAgent> = [.crush, .warp, .freebuff]

    /// The canonical inventory, id for id.
    ///
    /// A count alone would pass with two ids swapped; matching the whole set
    /// fails on any single spelling change. Grouped as the readers are.
    private static let canonicalIDs: Set<String> = [
        // The seven legacy readers.
        "claude", "codex", "opencode", "kilo", "grok", "kimi", "devin-cli",
        // Group A: session logs.
        "pi", "omp", "senpi", "kimchi", "prime-agent", "gemini", "qwen", "amp", "droid", "openclaw",
        // Group B: editor logs.
        "roocode", "kilocode", "cline", "codebuddy", "workbuddy",
        "cherrystudio", "commandcode", "opencodereview", "zcode",
        // Group C: databases.
        "hermes", "goose", "zed", "kiro", "crush", "unsloth",
        "antigravity-cli", "antigravity-ide", "micode", "devin-desktop",
        // Group D: structured logs.
        "mux", "codebuff", "freebuff", "jcode", "augment", "gjc",
        "junie", "dsh", "fx", "lmstudio", "reasonix",
        // Group E: explicit exports and captures.
        "cursor", "antigravity", "trae", "warp", "hindsight", "mcode",
        // Group F: Copilot.
        "copilot",
    ]

    private static func temporary(_ name: String) throws -> URL {
        let root = URL.temporaryDirectory.appending(
            path: "PulseSpendCatalogTests-\(name)-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    // MARK: - Shape

    @Test("The catalogue is the seven legacy readers plus the forty-seven new clients")
    func catalogueSize() {
        #expect(SpendAgent.allCases.count == 54)
        #expect(SpendAgent.allCases.filter { Self.legacy.contains($0) }.count == 7)
        #expect(Self.newClients.count == 47)
    }

    @Test("The canonical id inventory is exactly the fifty-four clients")
    func canonicalInventory() {
        let ids = Set(SpendAgent.allCases.map(\.sourceID))
        #expect(ids.count == 54)
        #expect(ids == Self.canonicalIDs)
        // The two spellings that are not the case name or a plain conversion.
        #expect(SpendAgent.claudeCode.sourceID == "claude")
        #expect(SpendAgent.devinCLI.sourceID == "devin-cli")
    }

    @Test("Every new client is routed to a family")
    func newClientsRoute() {
        for agent in Self.newClients {
            #expect(
                AgentRecordReaders.supportedClients.contains(agent.sourceID),
                "\(agent.sourceID) is not in any family"
            )
            #expect(
                AgentRecordReaders.family(for: agent.sourceID) != nil,
                "\(agent.sourceID) has no route"
            )
        }
        #expect(AgentRecordReaders.supportedClients.count == 47)
    }

    @Test("The seven legacy clients are not catalog clients")
    func legacyClientsStayOut() {
        for agent in Self.legacy {
            #expect(
                AgentRecordReaders.family(for: agent.sourceID) == nil,
                "\(agent.sourceID) was routed into the catalog"
            )
        }
    }

    @Test("Every family is non-empty and the six are disjoint")
    func familiesAreDisjoint() {
        let families = AgentRecordReaders.Family.allCases
        for family in families {
            #expect(!family.clients.isEmpty, "\(family.rawValue) is empty")
        }
        let counted = families.reduce(0) { $0 + $1.clients.count }
        #expect(counted == AgentRecordReaders.supportedClients.count)
    }

    // MARK: - Inputs

    @Test("Every routed client names at least one input root")
    func everyClientHasInputs() {
        let home = URL(fileURLWithPath: "/tmp/pulse-catalog-home")
        for agent in Self.newClients {
            let inputs = agent.inputs(home: home, environment: [:])
            #expect(!inputs.isEmpty, "\(agent.sourceID) has no inputs")
            #expect(
                AgentRecordReaders.inputs(client: agent.sourceID, home: home, environment: [:]) == inputs,
                "\(agent.sourceID) routed to different roots"
            )
        }
    }

    @Test("The legacy readers keep their verified default paths")
    func legacyPaths() {
        let home = URL(fileURLWithPath: "/tmp/pulse-home")
        #expect(SpendAgent.claudeCode.inputs(home: home, environment: [:])
            == [home.appending(path: ".claude/projects")])
        #expect(SpendAgent.codex.inputs(home: home, environment: [:])
            == [home.appending(path: ".codex/sessions"), home.appending(path: ".codex/archived_sessions")])
        #expect(SpendAgent.openCode.inputs(home: home, environment: [:])
            == [home.appending(path: ".local/share/opencode/opencode.db")])
        #expect(SpendAgent.kiloCLI.inputs(home: home, environment: [:])
            == [home.appending(path: ".local/share/kilo/kilo.db")])
        #expect(SpendAgent.grok.inputs(home: home, environment: [:])
            == [home.appending(path: ".grok/sessions")])
        #expect(SpendAgent.kimiCLI.inputs(home: home, environment: [:])
            == [home.appending(path: ".kimi/sessions"), home.appending(path: ".kimi-code/sessions")])
        #expect(SpendAgent.devinCLI.inputs(home: home, environment: [:])
            == [home.appending(path: ".local/share/devin/cli/sessions.db")])
    }

    @Test("An injected environment moves a capture root")
    func environmentOverride() {
        let home = URL(fileURLWithPath: "/tmp/pulse-home")
        let overridden = SpendAgent.cursor.inputs(
            home: home, environment: ["TOKSCALE_CONFIG_DIR": "/custom/config"]
        )
        #expect(overridden.first == URL(fileURLWithPath: "/custom/config/cursor-cache"))

        let fallback = AgentRecordReaders.inputs(client: "cursor", home: home, environment: [:])
        #expect(fallback.first == home.appending(path: ".config/tokscale/cursor-cache"))
    }

    @Test("Presence follows the roots that exist")
    func presenceFollowsRoots() throws {
        let home = try Self.temporary("presence")
        defer { try? FileManager.default.removeItem(at: home) }

        #expect(!SpendAgent.present(home: home, environment: [:]).contains(.claudeCode))
        try FileManager.default.createDirectory(
            at: home.appending(path: ".claude/projects"), withIntermediateDirectories: true
        )
        #expect(SpendAgent.present(home: home, environment: [:]).contains(.claudeCode))
        #expect(!SpendAgent.claudeCode.stores(home: home, environment: [:]).isEmpty)
    }

    @Test("Devin Desktop is present only when its own event tree exists")
    func devinDesktopPresence() throws {
        let home = try Self.temporary("devin")
        defer { try? FileManager.default.removeItem(at: home) }

        // The CLI database Devin Desktop borrows for a title lookup.
        let cliDatabase = home.appending(path: ".local/share/devin/cli/sessions.db")
        try FileManager.default.createDirectory(
            at: cliDatabase.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data().write(to: cliDatabase)

        // A machine with only the CLI has no Desktop agent to show: the
        // borrowed database alone is not evidence.
        #expect(SpendAgent.devinDesktop.stores(home: home, environment: [:]).isEmpty)
        #expect(!SpendAgent.present(home: home, environment: [:]).contains(.devinDesktop))

        // A Desktop `acp-events` tree is the evidence.
        let events = home.appending(path: "Library/Application Support/Devin/User/acp-events")
        try FileManager.default.createDirectory(at: events, withIntermediateDirectories: true)

        let stores = SpendAgent.devinDesktop.stores(home: home, environment: [:])
        #expect(stores.map(\.path).contains(events.path))
        // Once Desktop is present the lookup database stays watched.
        #expect(stores.map(\.path).contains(cliDatabase.path))
        #expect(SpendAgent.present(home: home, environment: [:]).contains(.devinDesktop))
    }

    @Test("A partial read is never persisted, and an unchanged clean read is")
    func cachePersistRule() {
        let a = AgentCache.stamp(for: [URL(fileURLWithPath: "/tmp/pulse-catalog-a")], prices: [:])
        let b = AgentCache.stamp(for: [URL(fileURLWithPath: "/tmp/pulse-catalog-b")], prices: [:])
        #expect(a != b)

        #expect(AgentLedgers.canPersist(notes: [], before: a, after: a))
        // A reader limit — history it could not decode — must not be frozen.
        #expect(!AgentLedgers.canPersist(notes: ["limit"], before: a, after: a))
        // A store that moved under the read.
        #expect(!AgentLedgers.canPersist(notes: [], before: a, after: b))
        #expect(!AgentLedgers.canPersist(notes: [], before: a, after: nil))
        #expect(!AgentLedgers.canPersist(notes: [], before: nil, after: a))
    }

    // MARK: - Metadata

    @Test("Capture, token counters and validation are declared, not inferred")
    func metadataIsDeclared() {
        for agent in SpendAgent.allCases {
            #expect(
                agent.requiresUsageExport == Self.capture.contains(agent),
                "\(agent.sourceID) export flag"
            )
            #expect(
                agent.reportsTokenCounts == !Self.tokenless.contains(agent),
                "\(agent.sourceID) token flag"
            )
            #expect(
                agent.hasCapturedValidation == Self.legacy.contains(agent),
                "\(agent.sourceID) validation flag"
            )
        }
    }

    @Test("Only the two legacy readers keep a provider; no new client is cast to one")
    func noNewClientIsAProvider() {
        for agent in SpendAgent.allCases {
            let keepsProvider = agent == .claudeCode || agent == .codex
            #expect((agent.provider != nil) == keepsProvider, "\(agent.sourceID)")
        }
    }

    @Test("A client that reports no tokens is still recognised")
    func recognisedIsNotCounted() {
        for agent in Self.tokenless {
            #expect(AgentRecordReaders.supportedClients.contains(agent.sourceID))
            #expect(!agent.reportsTokenCounts)
        }
    }

    @Test("Reader limits are routed, and an absent root is not a limit")
    func notesAreRouted() {
        let missing = URL(fileURLWithPath: "/tmp/pulse-catalog-missing-\(UUID().uuidString)")
        // Freebuff is the one unconditional note — it reports no counters at
        // all, so it states that wherever it is asked. Every other client
        // reports nothing for a root that is not there: Zed and DSH only note
        // a limit once they have actually met a compressed transcript.
        for agent in Self.newClients where agent != .freebuff {
            #expect(
                AgentRecordReaders.notes(client: agent.sourceID, roots: [missing]).isEmpty,
                "\(agent.sourceID) claimed a limit with no root"
            )
        }
        #expect(!AgentRecordReaders.notes(client: "freebuff", roots: [missing]).isEmpty)
        #expect(AgentRecordReaders.notes(client: "not-a-client", roots: [missing]).isEmpty)
    }

    // MARK: - Parsing

    @Test("A synthetic capture becomes records through the catalog")
    func syntheticCapture() throws {
        let root = try Self.temporary("cursor")
        defer { try? FileManager.default.removeItem(at: root) }

        let json = """
        {"usageEventsDisplay":[
          {"conversationId":"c1","timestamp":"1789372800000","model":"priced",
           "tokenUsage":{"inputTokens":100,"outputTokens":10,"cacheReadTokens":300,"cacheWriteTokens":20}}
        ]}
        """
        try Data(json.utf8).write(to: root.appending(path: "usage.json"))

        let records = AgentRecordReaders.records(client: "cursor", roots: [root])
        let record = try #require(records.first)
        #expect(record.model == "priced")
        #expect(record.tally == TokenTally(input: 100, cacheWrite: 20, cacheRead: 300, output: 10))
        // The conversation is scoped by the account it was read under, so two
        // accounts' identical ids cannot collide.
        #expect(record.sessionID == "cursor:active:c1")
    }

    @Test("A missing root yields no records rather than a crash")
    func missingRootYieldsNothing() {
        let missing = URL(fileURLWithPath: "/tmp/pulse-catalog-missing-\(UUID().uuidString)")
        for agent in Self.newClients {
            #expect(AgentRecordReaders.records(client: agent.sourceID, roots: [missing]).isEmpty)
        }
    }
}

/// Every agent's mark resolves to a file that ships, and nothing is approximated.
@Suite("Agent icons")
@MainActor
struct AgentIconTests {
    /// Through the production loader, not `Bundle.module`: a test's own
    /// `Bundle.module` is the **test target's** bundle and carries none of
    /// these, so asking it answers nil for every mark including the ones that
    /// have shipped since the first release. This also proves the file loads
    /// as an image rather than merely existing.
    @Test("Every named icon loads")
    func resourcesExist() {
        for agent in SpendAgent.allCases {
            guard let resource = agent.iconResource else { continue }
            #expect(
                LobeIconStore.image(named: resource) != nil,
                "\(agent.rawValue) names \(resource).svg, which does not load"
            )
        }
    }

    /// An agent that is a provider Pulse already draws must reuse that exact
    /// file rather than a second copy that could drift from it.
    @Test("A provider-backed agent reuses the provider's own file")
    func borrowsRatherThanCopies() {
        for agent in SpendAgent.allCases {
            guard let provider = agent.iconProvider else { continue }
            #expect(agent.iconResource == provider.iconResource, "\(agent.rawValue)")
        }
    }

    /// Not a count to keep updated for its own sake: it is the line between
    /// "has a mark" and "has none", and a mark appearing for a client the icon
    /// set has nothing for would mean one was approximated.
    @Test("The clients with no mark in the set stay blank")
    func blanksStayBlank() {
        let blank: Set<SpendAgent> = [
            .omp, .senpi, .kimchi, .primeAgent, .droid,
            .crush, .zed, .warp, .hindsight, .mux, .codebuff, .freebuff,
            .jcode, .augment, .gjc, .fx, .reasonix, .zcode,
        ]
        // **Equality, not one-way.** The first version only asserted that the
        // listed agents were blank, so an icon that was declared but landed in
        // the wrong switch left its agent blank and the suite still passed —
        // which is exactly how OpenClaw shipped without the mark it had.
        #expect(Set(SpendAgent.allCases.filter { $0.iconResource == nil }) == blank)
    }
}
