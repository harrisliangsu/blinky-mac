import Foundation
import Testing
@testable import Pulse

/// Output speed and first-token wait, read from transcripts built by hand —
/// never from the user's own `~/.claude` or `~/.codex`.
@Suite("Reply timing")
struct ReplyTimingTests {
    private static func claudeLine(_ type: String, _ time: String, id: String? = nil, output: Int = 0, stop: String? = nil) -> String {
        guard type == "assistant", let id else {
            return #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"{\"type\":\"user\",\"timestamp\":\"2000-01-01T00:00:00Z\"}"}]},"timestamp":"\#(time)"}"#
        }
        let stopField = stop.map { #","stop_reason":\#($0)"# } ?? ""
        return #"{"type":"assistant","message":{"id":"\#(id)","model":"claude-test"\#(stopField),"usage":{"input_tokens":10,"cache_read_input_tokens":90,"output_tokens":\#(output)}},"timestamp":"\#(time)"}"#
    }

    private static func summed(_ ledger: UsageLedger) -> ReplyTiming {
        ledger.slots.flatMap(\.timings.values).reduce(ReplyTiming(), +)
    }

    @Test("A reply over several lines counts its last line's output, timed from the request to its last line")
    func claudeCodeReply() async {
        let lines = [
            Self.claudeLine("user", "2026-09-20T10:00:00.000Z"),
            Self.claudeLine("assistant", "2026-09-20T10:00:04.000Z", id: "a", output: 12),
            Self.claudeLine("assistant", "2026-09-20T10:00:10.000Z", id: "a", output: 500),
            // A tool result between two lines of the next reply's request does
            // not start the clock before this reply ended.
            Self.claudeLine("user", "2026-09-20T10:00:09.000Z"),
            Self.claudeLine("assistant", "2026-09-20T10:00:20.000Z", id: "b", output: 300),
            // Too short to stand for a speed, still counted as tokens.
            Self.claudeLine("user", "2026-09-20T10:00:21.000Z"),
            Self.claudeLine("assistant", "2026-09-20T10:00:23.000Z", id: "c", output: 40),
        ]
        let scanned = await UsageLedgerReader(cacheDirectory: URL.temporaryDirectory)
            .parseClaudeCode(Data(lines.joined(separator: "\n").utf8))

        let output = scanned.allDays.values.flatMap(\.values).reduce(0) { $0 + $1.output }
        #expect(output == 500 + 300 + 40)
        let timing = scanned.allTimings.values.flatMap(\.values).reduce(ReplyTiming(), +)
        #expect(timing.replies == 2)
        #expect(timing.outputTokens == 800)
        #expect(abs(timing.seconds - (10 + 10)) < 0.001)
        #expect(timing.firstTokenTurns == 0)
    }

    @Test("A reply copied into a resumed session's transcript is counted once, for the original")
    func resumedCopiesCountOnce() async throws {
        let root = URL.temporaryDirectory.appending(path: "PulseResumed-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: ".claude/projects/-Users-me-Code-Pulse")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let history = [
            Self.claudeLine("user", "2026-09-20T10:00:00.000Z"),
            Self.claudeLine("assistant", "2026-09-20T10:00:10.000Z", id: "a", output: 500),
        ]
        // The original, then a resumed session: the same history, then its own reply.
        try history.joined(separator: "\n").write(to: folder.appending(path: "original.jsonl"), atomically: true, encoding: .utf8)
        try (history + [
            Self.claudeLine("user", "2026-09-21T09:00:00.000Z"),
            Self.claudeLine("assistant", "2026-09-21T09:00:05.000Z", id: "b", output: 300),
        ]).joined(separator: "\n").write(to: folder.appending(path: "resumed.jsonl"), atomically: true, encoding: .utf8)

        let cache = root.appending(path: "cache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let ledger = await UsageLedgerReader(home: root, cacheDirectory: cache)
            .ledger(for: .claudeCode, refresh: true, prices: [:])
        let output = ledger.days.reduce(0) { $0 + $1.tally.output }
        #expect(output == 500 + 300)
        let sessions = Dictionary(uniqueKeysWithValues: ledger.sessions.map { ($0.name, $0.tokens) })
        #expect(sessions["original"] == 10 + 90 + 500)
        #expect(sessions["resumed"] == 10 + 90 + 300)
    }

    @Test("Codex pairs a late count with the reply before the request that preceded it, and keeps its first-token wait")
    func codexReply() async throws {
        func line(_ time: String, _ payload: String, type: String = "response_item") -> String {
            #"{"timestamp":"\#(time)","type":"\#(type)","payload":\#(payload)}"#
        }
        let lines = [
            line("2026-09-20T10:00:00.000Z", #"{"model":"gpt-test"}"#, type: "turn_context"),
            line("2026-09-20T10:00:00.000Z", #"{"type":"message","role":"user","content":[{"type":"input_text","text":"hi"}]}"#),
            line("2026-09-20T10:00:03.000Z", #"{"type":"reasoning"}"#),
            line("2026-09-20T10:00:05.000Z", #"{"type":"function_call","name":"shell"}"#),
            // The tool runs, its output goes back — and only then the count.
            line("2026-09-20T10:00:30.000Z", #"{"type":"function_call_output","output":"x"}"#),
            line("2026-09-20T10:00:30.001Z", #"{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":900,"output_tokens":400}}}"#, type: "event_msg"),
            line("2026-09-20T10:00:34.000Z", #"{"type":"message","role":"assistant","content":[]}"#),
            line("2026-09-20T10:00:34.001Z", #"{"type":"token_count","info":{"total_token_usage":{"input_tokens":2000,"cached_input_tokens":1900,"output_tokens":600}}}"#, type: "event_msg"),
            line("2026-09-20T10:00:34.002Z", #"{"type":"task_complete","duration_ms":34000,"time_to_first_token_ms":2500}"#, type: "event_msg"),
        ]
        let file = URL.temporaryDirectory.appending(path: "PulseReplyTiming-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)

        let scanned = await UsageLedgerReader(cacheDirectory: URL.temporaryDirectory).parse(file, provider: .codex)
        let timing = scanned.timings.values.flatMap(\.values).reduce(ReplyTiming(), +)
        // 400 over 0:00 → 0:05, 200 over 0:30 → 0:34.
        #expect(timing.replies == 2)
        #expect(timing.outputTokens == 600)
        #expect(abs(timing.seconds - 9) < 0.001)
        #expect(timing.firstTokenTurns == 1)
        #expect(timing.firstTokenSeconds == 2.5)
    }

    @Test("Speeds and waits need five timed replies or turns per model, within the last day")
    func perModel() {
        let now = Date()
        func slot(_ ago: TimeInterval, _ timings: [String: ReplyTiming]) -> UsageLedger.Slot {
            UsageLedger.Slot(start: now.addingTimeInterval(-ago), tokens: 1, cost: 0, timings: timings)
        }
        let ledger = UsageLedger(
            days: [], earliest: nil, unpricedModels: [], modelNames: ["fast": "Fast"],
            slots: [
                // Two days old: a speed for a server that has moved on.
                slot(2 * 86_400, ["fast": ReplyTiming(outputTokens: 100_000, seconds: 10, replies: 50)]),
                slot(3_600, [
                    "fast": ReplyTiming(outputTokens: 1_000, seconds: 10, replies: 5),
                    "rare": ReplyTiming(outputTokens: 5_000, seconds: 10, replies: 4),
                    "codex": ReplyTiming(outputTokens: 600, seconds: 20, replies: 6, firstTokenSeconds: 15, firstTokenTurns: 5),
                ]),
            ]
        )
        let speeds = ledger.outputSpeedsByModel(since: now.addingTimeInterval(-UsageLedger.speedSpan))
        #expect(speeds.map(\.name) == ["Fast", "codex"])
        #expect(speeds[0].tokensPerSecond == 100)
        #expect(speeds[0].firstToken == nil)
        #expect(speeds[1].tokensPerSecond == 30)
        #expect(speeds[1].firstToken == 3)
        #expect(ledger.outputSpeedsByModel(since: now).isEmpty)
    }

    @Test("A wait or reply outside the plausible range is not timed")
    func bounds() {
        let start = Date()
        #expect(ReplyTiming(output: 99, from: start, to: start.addingTimeInterval(1)) == nil)
        #expect(ReplyTiming(output: 500, from: start, to: start) == nil)
        #expect(ReplyTiming(output: 500, from: start, to: start.addingTimeInterval(ReplyTiming.longest + 1)) == nil)
        #expect(ReplyTiming.firstToken(after: 0) == nil)
        #expect(ReplyTiming.firstToken(after: ReplyTiming.longestFirstToken + 1) == nil)
    }

    @Test("An assistant line still being written is not a speed; a finished one is, including a tool use")
    func claudeStreamingIsNotTimed() async {
        let open = [
            Self.claudeLine("user", "2026-09-20T10:00:00.000Z"),
            Self.claudeLine("assistant", "2026-09-20T10:00:10.000Z", id: "a", output: 500, stop: "null"),
        ]
        let streaming = await UsageLedgerReader(cacheDirectory: URL.temporaryDirectory)
            .parseClaudeCode(Data(open.joined(separator: "\n").utf8))
        let output = streaming.allDays.values.flatMap(\.values).reduce(0) { $0 + $1.output }
        #expect(output == 500)
        #expect(streaming.allTimings.isEmpty)

        for stop in ["\"end_turn\"", "\"tool_use\""] {
            let lines = [
                Self.claudeLine("user", "2026-09-20T10:00:00.000Z"),
                Self.claudeLine("assistant", "2026-09-20T10:00:04.000Z", id: "a", output: 40, stop: "null"),
                Self.claudeLine("assistant", "2026-09-20T10:00:10.000Z", id: "a", output: 500, stop: stop),
            ]
            let scanned = await UsageLedgerReader(cacheDirectory: URL.temporaryDirectory)
                .parseClaudeCode(Data(lines.joined(separator: "\n").utf8))
            let timing = scanned.allTimings.values.flatMap(\.values).reduce(ReplyTiming(), +)
            #expect(timing.replies == 1)
            #expect(timing.outputTokens == 500)
            #expect(abs(timing.seconds - 10) < 0.001)
        }
    }

    @Test("Grok times model rounds, not tool time or apiDurationMs, and skips a turn the log cannot split")
    func grokReply() throws {
        let root = URL.temporaryDirectory.appending(path: "PulseGrokTiming-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let base = 1_700_000_000
        func line(_ offset: Int, _ update: String, prompt: String = "p") -> String {
            let ms = (base + offset) * 1000
            let meta = #"{"promptId":"\#(prompt)","agentTimestampMs":\#(ms)}"#
            return #"{"timestamp":\#(base + offset),"params":{"_meta":\#(meta),"update":\#(update)}}"#
        }
        func usage(_ output: Int, calls: Int, models: String) -> String {
            #"{"sessionUpdate":"turn_completed","usage":{"outputTokens":\#(output),"inputTokens":10,"modelCalls":\#(calls),"apiDurationMs":100000,"modelUsage":\#(models)}}"#
        }
        let one = #"{"grok-test":{"outputTokens":200,"inputTokens":10,"cachedReadTokens":0}}"#
        let round = [
            line(0, #"{"sessionUpdate":"user_message_chunk","content":"hi"}"#),
            line(3, #"{"sessionUpdate":"tool_call"}"#),
            line(30, #"{"sessionUpdate":"tool_call_update","status":"completed"}"#),
            line(31, #"{"sessionUpdate":"agent_message_chunk"}"#),
            line(34, usage(200, calls: 2, models: one)),
        ]
        try Self.writeGrok(round, under: root, session: "one")
        var ledger = GrokStore.ledger(at: root, prices: [:])
        var timing = Self.summed(ledger)
        // (3 − 0) + (31 − 30). Not the wall clock, and not apiDurationMs.
        #expect(timing.replies == 1)
        #expect(timing.outputTokens == 200)
        #expect(abs(timing.seconds - 4) < 0.001)
        #expect(timing.firstTokenTurns == 0)
        #expect(ledger.days.reduce(0) { $0 + $1.tally.output } == 200)

        // The same second, and no millisecond: there is no span to time.
        let sameSecond = [
            #"{"timestamp":\#(base),"params":{"update":{"sessionUpdate":"user_message_chunk","content":"hi"}}}"#,
            #"{"timestamp":\#(base),"params":{"update":{"sessionUpdate":"agent_message_chunk"}}}"#,
            #"{"timestamp":\#(base),"params":{"update":{"sessionUpdate":"turn_completed","usage":{"outputTokens":200,"inputTokens":10,"modelUsage":\#(one)}}}}"#,
        ]
        try Self.writeGrok(sameSecond, under: root, session: "same")
        ledger = GrokStore.ledger(at: root, prices: [:])
        #expect(Self.summed(ledger).replies == 1)
        #expect(ledger.days.reduce(0) { $0 + $1.tally.output } == 400)

        // No model line: the tokens stay, the speed does not.
        let bare = [
            #"{"timestamp":\#(base),"params":{"update":{"sessionUpdate":"turn_completed","usage":{"outputTokens":200,"inputTokens":10}}}}"#,
        ]
        try Self.writeGrok(bare, under: root, session: "bare")
        ledger = GrokStore.ledger(at: root, prices: [:])
        #expect(Self.summed(ledger).replies == 1)
        #expect(ledger.days.reduce(0) { $0 + $1.tally.output } == 600)

        // modelCalls counts work this file does not show as rounds.
        let mismatch = [
            line(0, #"{"sessionUpdate":"user_message_chunk","content":"hi"}"#, prompt: "mismatch"),
            line(4, #"{"sessionUpdate":"agent_message_chunk"}"#, prompt: "mismatch"),
            line(4, usage(200, calls: 3, models: one), prompt: "mismatch"),
        ]
        try Self.writeGrok(mismatch, under: root, session: "mismatch")
        ledger = GrokStore.ledger(at: root, prices: [:])
        #expect(Self.summed(ledger).replies == 1)

        let twoModels = #"{"grok-a":{"outputTokens":120,"inputTokens":5},"grok-b":{"outputTokens":80,"inputTokens":5}}"#
        let split = [
            line(0, #"{"sessionUpdate":"user_message_chunk","content":"hi"}"#, prompt: "split"),
            line(4, #"{"sessionUpdate":"agent_message_chunk"}"#, prompt: "split"),
            line(4, usage(200, calls: 1, models: twoModels), prompt: "split"),
        ]
        try Self.writeGrok(split, under: root, session: "split")
        ledger = GrokStore.ledger(at: root, prices: [:])
        #expect(Self.summed(ledger).replies == 1)
        #expect(ledger.days.reduce(0) { $0 + $1.tally.output } == 1000)
    }

    @Test("A copied Grok prompt is timed once, from the earlier start, and five recent turns make a speed")
    func grokDedupesAndPublishes() throws {
        let root = URL.temporaryDirectory.appending(path: "PulseGrokSpeed-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        func turn(_ start: Int, _ span: Int, prompt: String, output: Int = 200) -> [String] {
            func line(_ ms: Int, _ update: String) -> String {
                let meta = #"{"promptId":"\#(prompt)","agentTimestampMs":\#(ms)}"#
                return #"{"timestamp":\#(ms / 1000),"params":{"_meta":\#(meta),"update":\#(update)}}"#
            }
            let model = #"{"grok-test":{"outputTokens":\#(output),"inputTokens":1,"cachedReadTokens":0}}"#
            return [
                line(start, #"{"sessionUpdate":"user_message_chunk","content":"hi"}"#),
                line(start + span, #"{"sessionUpdate":"agent_message_chunk"}"#),
                line(start + span, #"{"sessionUpdate":"turn_completed","usage":{"outputTokens":\#(output),"inputTokens":1,"modelCalls":1,"apiDurationMs":100000,"modelUsage":\#(model)}}"#),
            ]
        }
        let early = 1_700_000_000_000
        try Self.writeGrok(turn(early, 4_000, prompt: "copied"), under: root, session: "early")
        try Self.writeGrok(turn(early + 100_000, 8_000, prompt: "copied"), under: root, session: "late")
        var ledger = GrokStore.ledger(at: root, prices: [:])
        var timing = Self.summed(ledger)
        #expect(timing.replies == 1)
        #expect(timing.outputTokens == 200)
        #expect(abs(timing.seconds - 4) < 0.001)
        #expect(ledger.days.reduce(0) { $0 + $1.tally.output } == 400)

        let recent = Int(Date().timeIntervalSince1970 * 1000) - 3_600_000
        var lines: [String] = []
        for index in 0..<5 {
            lines += turn(recent + index * 30_000, 4_000, prompt: "live-\(index)")
        }
        try Self.writeGrok(lines, under: root, session: "live")
        ledger = GrokStore.ledger(at: root, prices: [:])
        let speeds = ledger.outputSpeedsByModel(since: Date().addingTimeInterval(-UsageLedger.speedSpan))
        let live = try #require(speeds.first { $0.name == "grok-test" })
        #expect(live.tokensPerSecond == 50)
        #expect(live.firstToken == nil)
    }

    @Test("Kimi times a step up to the last model line, and a session total is not a speed")
    func kimiReply() throws {
        let root = URL.temporaryDirectory.appending(path: "PulseKimiTiming-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appending(path: "legacy/session")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let legacyLines = [
            #"{"timestamp":1000,"message":{"type":"TurnBegin","payload":{"user_input":"hi"}}}"#,
            #"{"timestamp":1002,"message":{"type":"ContentPart","payload":{"type":"text","text":"a"}}}"#,
            #"{"timestamp":1004,"message":{"type":"ToolCall","payload":{"function":{"name":"shell"}}}}"#,
            #"{"timestamp":1020,"message":{"type":"ToolResult","payload":{"result":"ok"}}}"#,
            #"{"timestamp":1021,"message":{"type":"StatusUpdate","payload":{"token_usage":{"input_other":1,"output":200,"input_cache_read":0,"input_cache_creation":0}}}}"#,
        ]
        try legacyLines.joined(separator: "\n").write(to: legacy.appending(path: "wire.jsonl"), atomically: true, encoding: .utf8)
        var ledger = KimiCLIStore.ledger(at: root.appending(path: "legacy"), prices: [:])
        var timing = Self.summed(ledger)
        #expect(timing.replies == 1)
        #expect(timing.outputTokens == 200)
        #expect(abs(timing.seconds - 4) < 0.001)
        #expect(timing.firstTokenTurns == 0)
        #expect(ledger.slots.flatMap(\.timings.keys) == [KimiCLIStore.unnamedModel])

        let bare = root.appending(path: "bare/session")
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        try [
            #"{"timestamp":1000,"message":{"type":"TurnBegin","payload":{}}}"#,
            #"{"timestamp":1001,"message":{"type":"StatusUpdate","payload":{"token_usage":{"input_other":1,"output":200,"input_cache_read":0,"input_cache_creation":0}}}}"#,
        ].joined(separator: "\n").write(to: bare.appending(path: "wire.jsonl"), atomically: true, encoding: .utf8)
        ledger = KimiCLIStore.ledger(at: root.appending(path: "bare"), prices: [:])
        #expect(Self.summed(ledger).replies == 0)
        #expect(ledger.days.reduce(0) { $0 + $1.tally.output } == 200)

        let code = root.appending(path: "code/session")
        try FileManager.default.createDirectory(at: code, withIntermediateDirectories: true)
        let usage = #"{"inputOther":1,"output":200,"inputCacheRead":0,"inputCacheCreation":0}"#
        let start = 1_700_000_000_000
        let codeLines = [
            #"{"type":"turn.prompt","time":\#(start),"origin":{"kind":"user"},"input":[{"type":"text","text":"hi"}]}"#,
            #"{"type":"context.append_loop_event","time":\#(start + 2_000),"event":{"type":"content.part","part":{"type":"text","text":"a"}}}"#,
            #"{"type":"context.append_loop_event","time":\#(start + 4_000),"event":{"type":"tool.call","name":"shell"}}"#,
            #"{"type":"context.append_loop_event","time":\#(start + 20_000),"event":{"type":"tool.result","toolCallId":"1"}}"#,
            #"{"type":"usage.record","time":\#(start + 21_000),"model":"kimi-code/priced","usageScope":"turn","usage":\#(usage)}"#,
            #"{"type":"context.append_loop_event","time":\#(start + 21_010),"event":{"type":"step.end","llmFirstTokenLatencyMs":2500,"llmStreamDurationMs":999999}}"#,
            #"{"type":"usage.record","time":\#(start + 22_000),"model":"kimi-code/priced","usageScope":"session","usage":\#(usage)}"#,
        ]
        try codeLines.joined(separator: "\n").write(to: code.appending(path: "wire.jsonl"), atomically: true, encoding: .utf8)
        ledger = KimiCLIStore.ledger(at: root.appending(path: "code"), prices: [:])
        timing = Self.summed(ledger)
        #expect(timing.replies == 1)
        #expect(timing.outputTokens == 200)
        #expect(abs(timing.seconds - 4) < 0.001)
        #expect(timing.firstTokenTurns == 1)
        #expect(timing.firstTokenSeconds == 2.5)
        // The session record is counted and not timed.
        #expect(ledger.days.reduce(0) { $0 + $1.tally.output } == 400)

        let reversed = root.appending(path: "reversed/session")
        try FileManager.default.createDirectory(at: reversed, withIntermediateDirectories: true)
        try [
            #"{"type":"turn.prompt","time":\#(start),"input":[{"type":"text","text":"hi"}]}"#,
            #"{"type":"context.append_loop_event","time":\#(start + 4_000),"event":{"type":"content.part","part":{"type":"text"}}}"#,
            #"{"type":"context.append_loop_event","time":\#(start + 4_000),"event":{"type":"step.end","llmFirstTokenLatencyMs":1800,"llmStreamDurationMs":4000}}"#,
            #"{"type":"usage.record","time":\#(start + 9_000),"model":"kimi-code/priced","usageScope":"turn","usage":\#(usage)}"#,
        ].joined(separator: "\n").write(to: reversed.appending(path: "wire.jsonl"), atomically: true, encoding: .utf8)
        ledger = KimiCLIStore.ledger(at: root.appending(path: "reversed"), prices: [:])
        timing = Self.summed(ledger)
        #expect(timing.replies == 1)
        #expect(abs(timing.seconds - 4) < 0.001)
        #expect(timing.firstTokenTurns == 1)
        #expect(timing.firstTokenSeconds == 1.8)

        let alone = root.appending(path: "alone/session")
        try FileManager.default.createDirectory(at: alone, withIntermediateDirectories: true)
        try #"{"type":"usage.record","time":\#(start),"model":"kimi-code/priced","usageScope":"turn","usage":\#(usage)}"#
            .write(to: alone.appending(path: "wire.jsonl"), atomically: true, encoding: .utf8)
        ledger = KimiCLIStore.ledger(at: root.appending(path: "alone"), prices: [:])
        #expect(Self.summed(ledger).replies == 0)
        #expect(ledger.days.reduce(0) { $0 + $1.tally.output } == 200)
    }

    @Test("The pane re-reads only when a changed log ends on a closed reply")
    func watchClosedTail() {
        let before = ReplyTimingWatch.FileStamp(size: 10, modified: 1)
        let after = ReplyTimingWatch.FileStamp(size: 20, modified: 2)
        #expect(!ReplyTimingWatch.shouldRefresh(previous: ["a": before], next: ["a": before], isClosed: { _ in true }))
        #expect(ReplyTimingWatch.shouldRefresh(previous: ["a": before], next: ["a": after], isClosed: { _ in true }))
        #expect(!ReplyTimingWatch.shouldRefresh(previous: ["a": before], next: ["a": after], isClosed: { _ in false }))
        #expect(!ReplyTimingWatch.shouldRefresh(previous: ["a": before], next: [:], isClosed: { _ in true }))
        #expect(ReplyTimingWatch.shouldRefresh(previous: [:], next: ["a": after], isClosed: { _ in true }))

        #expect(!ReplyTimingWatch.isClosedTail(
            #"{"type":"assistant","message":{"stop_reason":null}}"#, provider: .claudeCode
        ))
        #expect(ReplyTimingWatch.isClosedTail(
            #"{"type":"assistant","message":{"stop_reason":"end_turn"}}"#, provider: .claudeCode
        ))
        #expect(!ReplyTimingWatch.isClosedTail(
            #"{"type":"response_item","payload":{"type":"reasoning"}}"#, provider: .codex
        ))
        #expect(ReplyTimingWatch.isClosedTail(
            #"{"type":"event_msg","payload":{"type":"token_count"}}"#, provider: .codex
        ))
        #expect(!ReplyTimingWatch.isClosedTail(
            #"{"params":{"update":{"sessionUpdate":"agent_message_chunk"}}}"#, provider: .grok
        ))
        #expect(ReplyTimingWatch.isClosedTail(
            #"{"params":{"update":{"sessionUpdate":"turn_completed"}}}"#, provider: .grok
        ))
        #expect(!ReplyTimingWatch.isClosedTail(
            #"{"type":"context.append_loop_event","event":{"type":"content.part"}}"#, provider: .kimiCode
        ))
        #expect(ReplyTimingWatch.isClosedTail(
            #"{"type":"usage.record","usageScope":"turn"}"#, provider: .kimiCode
        ))
        #expect(!ReplyTimingWatch.isClosedTail(
            #"{"type":"usage.record","usageScope":"session"}"#, provider: .kimiCode
        ))
        #expect(ReplyTimingWatch.isClosedTail(
            #"{"type":"context.append_loop_event","event":{"type":"step.end"}}"# + "\n"
                + #"{"type":"usage.record","usageScope":"session"}"#,
            provider: .kimiCode
        ))
    }

    private static func writeGrok(_ lines: [String], under root: URL, session: String) throws {
        let directory = root.appending(path: "project/\(session)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(to: directory.appending(path: "updates.jsonl"), atomically: true, encoding: .utf8)
    }
}
