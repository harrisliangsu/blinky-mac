// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Kimi's CLI and its successor Kimi Code, which both write the raw exchange
/// to `wire.jsonl` — in two different shapes, told apart line by line.
///
/// **The legacy Kimi CLI** (`~/.kimi/sessions/<hash>/<uuid>/wire.jsonl`):
///
/// ```json
/// { "timestamp": …,
///   "message": { "payload": { "token_usage": {
///     "input_other": 4340, "output": 38,
///     "input_cache_read": 9216, "input_cache_creation": 0 } } } }
/// ```
///
/// It names no model, anywhere. Neither the wire log nor the session state
/// carries one, so its tokens are counted and never costed — the same answer
/// Pulse gives for any model with no published price, arrived at one step
/// earlier. `unnamedModel` is a placeholder so the buckets have a key, and is
/// deliberately one no price list can match.
///
/// **Kimi Code** (`~/.kimi-code/sessions/wd_<project>_<hash>/session_<uuid>/
/// agents/<agent>/wire.jsonl`, one log for `main` and one per subagent):
///
/// ```json
/// { "type": "usage.record", "time": 1789699677719, "agentId": "main",
///   "model": "kimi-code/k3-256k", "usageScope": "turn",
///   "usage": { "inputOther": 4340, "output": 38,
///              "inputCacheRead": 9216, "inputCacheCreation": 0 } }
/// ```
///
/// **Every request is written three times**: as this `usage.record`, as the
/// `step.end` event's `event.usage`, and as the assistant message's
/// `meta.usage`, with identical counts — checked on a real store, line for
/// line. Only `usage.record` is counted: it is the one that names the model.
/// The model is `<provider>/<id>`, where the provider is the user's own
/// configured name for an endpoint, so the prefix is dropped before pricing
/// (`EditorLog.modelID`). `kimi-for-coding` is the plan's moving alias for
/// whatever Kimi currently serves on it and stays unpriced.
///
/// **`input_other` / `inputOther` is fresh input**, as the name says: the
/// cache figures are counted beside it rather than inside it, which is the
/// same arrangement Claude Code uses and the opposite of Codex's.
///
/// **A request found in both stores is counted once**, from Kimi Code's copy,
/// which names the model. Kimi Code's migrator can carry sessions over from
/// the legacy store; the key is the request's second and its four counts.
///
/// **Output speed is a separate reading from those counts.** A step is timed
/// from the request (`turn.prompt`, or a `tool.result`) to the last model
/// line (`content.part` or `tool.call`) before the next tool result. The
/// legacy log uses `TurnBegin` / `ToolResult` and `ContentPart` / `ToolCall`.
/// The span is committed when the turn-scoped `usage.record` — or the legacy
/// `token_usage` line — arrives, not at that line's own timestamp, and not
/// from `step.end`, whose time includes the tool. `llmStreamDurationMs` alone
/// is not a duration: it leaves out the wait for the first token. A
/// session-scoped `usage.record` is a running total, not a reply. Kimi Code's
/// `llmFirstTokenLatencyMs`, when the step writes it, is the first-token wait.
enum KimiCLIStore {
    static let unnamedModel = "kimi (unnamed)"

    static func ledger(at root: URL, prices: [String: ModelPrice]) -> UsageLedger {
        ledger(at: [root], prices: prices)
    }

    static func ledger(at roots: [URL], prices: [String: ModelPrice]) -> UsageLedger {
        var lookup = ModelPriceLookup(prices)
        var requests: [Request] = []

        for file in AgentLogIO.files(in: roots, names: ["wire.jsonl"]) {
            guard !Task.isCancelled else { return .empty }
            var clock = StepClock()
            var amend: Int?
            var inFile: [Request] = []
            for line in AgentLogIO.jsonLines(at: file) {
                Self.observe(line, file: file, clock: &clock, amend: &amend, requests: &inFile)
            }
            requests.append(contentsOf: inFile)
        }

        let migrated = Set(requests.lazy.filter { !$0.legacy }.map(\.identity))
        var buckets: [String: [String: TokenTally]] = [:]
        var timings: [String: [String: ReplyTiming]] = [:]
        var runs: [URL: Run] = [:]

        for request in requests where !request.legacy || !migrated.contains(request.identity) {
            let key = UsageLedgerReader.slotKey(for: request.at)
            let price = lookup.price(for: request.model)
            let money = price.map { request.tally.cost(at: $0) } ?? 0
            let unpriced = price == nil ? request.tally.total : 0
            buckets[key, default: [:]][request.model] =
                (buckets[key]?[request.model] ?? TokenTally()) + request.tally
            if let timing = request.timing {
                timings[key, default: [:]][request.model] =
                    (timings[key]?[request.model] ?? ReplyTiming()) + timing
            }

            var run = runs[request.session] ?? Run(legacy: request.legacy)
            run.tokens += request.tally.total
            run.cost += money
            run.unpriced += unpriced
            run.first = min(run.first ?? request.at, request.at)
            run.last = max(run.last ?? request.at, request.at)
            var slot = run.slots[key] ?? (tokens: 0, cost: 0, unpriced: 0)
            slot.tokens += request.tally.total
            slot.cost += money
            slot.unpriced += unpriced
            run.slots[key] = slot
            runs[request.session] = run
        }

        guard !buckets.isEmpty else { return .empty }
        var workspaces: [URL: [String: String]] = [:]
        let sessions = runs.compactMap { directory, run -> UsageLedger.Session? in
            guard run.tokens > 0, let first = run.first, let last = run.last else { return nil }
            let state = Self.state(in: directory)
            let project: UsageProject?
            if run.legacy {
                // Neither the legacy wire log nor its state carries a working
                // directory.
                project = nil
            } else {
                let bucket = directory.deletingLastPathComponent()
                let home = bucket.deletingLastPathComponent().deletingLastPathComponent()
                if workspaces[home] == nil { workspaces[home] = Self.workspaces(in: home) }
                project = UsageProject(state?["cwd"] as? String)
                    ?? UsageProject(workspaces[home]?[bucket.lastPathComponent])
            }
            return UsageLedger.Session(
                // The legacy store keeps one log per session and has always
                // been keyed by it; Kimi Code's session is the directory that
                // holds its agents' logs.
                id: run.legacy ? directory.appending(path: "wire.jsonl").path : directory.path,
                name: directory.lastPathComponent,
                title: Self.title(in: state, legacy: run.legacy),
                project: project,
                start: first, end: last, tokens: run.tokens, cost: run.cost, unpricedTokens: run.unpriced,
                slots: UsageLedgerReader.sessionSlots(run.slots)
            )
        }

        var ledger = UsageLedgerReader.price(buckets, with: prices, timings: timings)
        ledger.sessions = sessions.sorted { $0.end > $1.end }
        return ledger
    }

    // MARK: - Lines

    private struct Request {
        let at: Date
        let tally: TokenTally
        let model: String
        let legacy: Bool
        /// The session directory the request belongs to.
        let session: URL

        /// What makes two copies of one request the same request.
        var identity: String {
            "\(Int(at.timeIntervalSince1970.rounded(.down)))|\(tally.input)|\(tally.cacheWrite)|\(tally.cacheRead)|\(tally.output)"
        }

        /// The step this request closed, when the log could pair its start
        /// and its last model line. Absent when it could not — the tokens
        /// are still counted.
        var timing: ReplyTiming? = nil
    }

    private struct Run {
        let legacy: Bool
        var tokens = 0
        var cost = 0.0
        var unpriced = 0
        var first: Date?
        var last: Date?
        var slots: [String: (tokens: Int, cost: Double, unpriced: Int)] = [:]
    }

    private static func request(in line: [String: Any], file: URL) -> Request? {
        let parent = file.deletingLastPathComponent()

        if line["type"] as? String == "usage.record" {
            guard let usage = line["usage"] as? [String: Any] else { return nil }
            let tally = TokenTally(
                input: int(usage["inputOther"]),
                cacheWrite: int(usage["inputCacheCreation"]),
                cacheRead: int(usage["inputCacheRead"]),
                output: int(usage["output"])
            )
            guard tally.total > 0, let at = date(line["time"]) else { return nil }
            // `session_<uuid>/agents/<agent>/wire.jsonl`; a log anywhere else
            // is its own session.
            let agents = parent.deletingLastPathComponent()
            let session = agents.lastPathComponent == "agents" ? agents.deletingLastPathComponent() : parent
            return Request(
                at: at, tally: tally,
                model: EditorLog.modelID(line["model"] as? String) ?? unnamedModel,
                legacy: false, session: session
            )
        }

        guard let message = line["message"] as? [String: Any],
              let payload = message["payload"] as? [String: Any],
              let usage = payload["token_usage"] as? [String: Any]
        else { return nil }
        let tally = TokenTally(
            input: int(usage["input_other"]),
            cacheWrite: int(usage["input_cache_creation"]),
            cacheRead: int(usage["input_cache_read"]),
            output: int(usage["output"])
        )
        guard tally.total > 0, let at = date(line["timestamp"]) else { return nil }
        return Request(at: at, tally: tally, model: unnamedModel, legacy: true, session: parent)
    }

    /// Seconds in the legacy log, milliseconds in Kimi Code's; told apart by
    /// size, since no date this century reaches ten billion seconds.
    private static func date(_ value: Any?) -> Date? {
        let seconds = (value as? Double) ?? (value as? Int).map(Double.init) ?? 0
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1000 : seconds)
    }

    // MARK: - Session state

    private static func state(in directory: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: directory.appending(path: "state.json")) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// The legacy state keeps only a title the user set; Kimi Code's keeps the
    /// title its own session list shows.
    private static func title(in state: [String: Any]?, legacy: Bool) -> String? {
        guard let text = state?[legacy ? "custom_title" : "title"] as? String else { return nil }
        return UsageLedgerReader.title(from: text)
    }

    /// Kimi Code's `workspaces.json`: each `wd_…` session bucket's folder, for
    /// a session whose state does not name its own.
    private static func workspaces(in home: URL) -> [String: String] {
        guard
            let data = try? Data(contentsOf: home.appending(path: "workspaces.json")),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entries = root["workspaces"] as? [String: [String: Any]]
        else { return [:] }
        return entries.compactMapValues { $0["root"] as? String }
    }

    /// One line of a wire log: move the clock, and keep a request when the
    /// line is one. Token totals stay on `request(in:file:)`.
    private static func observe(
        _ line: [String: Any], file: URL, clock: inout StepClock, amend: inout Int?, requests: inout [Request]
    ) {
        if line["type"] as? String == "turn.prompt" || line["type"] as? String == "turn.steer" {
            let kind = (line["origin"] as? [String: Any])?["kind"] as? String
            if kind != "injection", let at = date(line["time"]) {
                clock.beginTurn(at: at)
                amend = nil
            }
            return
        }

        if line["type"] as? String == "context.append_loop_event",
           let event = line["event"] as? [String: Any] {
            let eventType = event["type"] as? String
            if let at = date(line["time"]) {
                switch eventType {
                case "step.begin": clock.sentIfIdle(at: at)
                case "content.part", "tool.call": clock.wrote(at: at)
                case "tool.result": clock.sent(at: at)
                default: break
                }
            }
            if eventType == "step.end" {
                let first = double(event["llmFirstTokenLatencyMs"])
                let stream = double(event["llmStreamDurationMs"])
                if let index = amend, requests.indices.contains(index) {
                    requests[index].timing = withLatency(
                        requests[index].timing, output: requests[index].tally.output, firstMs: first, streamMs: stream
                    )
                } else {
                    clock.noteLatency(firstMs: first, streamMs: stream)
                }
            }
            return
        }

        if line["type"] as? String == "usage.record" {
            guard var request = request(in: line, file: file) else { return }
            // A session record is the running total, not one reply.
            if (line["usageScope"] as? String) == "session" {
                requests.append(request)
                return
            }
            request.timing = clock.commit(output: request.tally.output)
            requests.append(request)
            amend = requests.count - 1
            return
        }

        if let message = line["message"] as? [String: Any] {
            let type = message["type"] as? String
            if let at = date(line["timestamp"]) {
                switch type {
                case "TurnBegin":
                    clock.beginTurn(at: at)
                    amend = nil
                case "StepBegin":
                    clock.sentIfIdle(at: at)
                case "ContentPart", "ToolCall", "ToolCallPart":
                    clock.wrote(at: at)
                case "ToolResult":
                    clock.sent(at: at)
                default:
                    break
                }
            }
            guard var request = request(in: line, file: file) else { return }
            request.timing = clock.commit(output: request.tally.output)
            requests.append(request)
            amend = requests.count - 1
        }
    }

    /// A first-token wait, and a speed from Kimi Code's own two durations
    /// only when the log has no model line to time from. `llmStreamDurationMs`
    /// by itself is not a duration.
    private static func withLatency(
        _ existing: ReplyTiming?, output: Int, firstMs: Double?, streamMs: Double?
    ) -> ReplyTiming? {
        var timing = existing ?? ReplyTiming()
        var changed = false
        if timing.replies == 0, let firstMs, let streamMs, firstMs > 0, streamMs > 0 {
            let seconds = (firstMs + streamMs) / 1000
            if output >= ReplyTiming.minimumOutput, seconds > 0, seconds <= ReplyTiming.longest {
                timing = timing + ReplyTiming(outputTokens: output, seconds: seconds, replies: 1)
                changed = true
            }
        }
        if timing.firstTokenTurns == 0, let firstMs, let wait = ReplyTiming.firstToken(after: firstMs / 1000) {
            timing = timing + wait
            changed = true
        }
        return changed ? timing : existing
    }

    /// One step's model span. A tool result closes the step that asked for
    /// the tool and starts the next request; it does not extend the span
    /// through the tool.
    private struct StepClock {
        private var sent: Date?
        private var wrote: Date?
        private var closed: (sent: Date, finished: Date)?
        private var pendingFirst: Double?
        private var pendingStream: Double?

        mutating func beginTurn(at date: Date) {
            pendingFirst = nil
            pendingStream = nil
            closed = nil
            sent = date
            wrote = nil
        }

        mutating func sent(at date: Date) {
            if let sent, let wrote, wrote > sent { closed = (sent, wrote) }
            sent = date
            wrote = nil
        }

        /// A `step.begin` must not move a start `turn.prompt` already set.
        mutating func sentIfIdle(at date: Date) {
            guard sent == nil else { return }
            sent = date
            wrote = nil
        }

        mutating func wrote(at date: Date) {
            guard let sent, date > sent else { return }
            wrote = date
        }

        mutating func noteLatency(firstMs: Double?, streamMs: Double?) {
            if let firstMs, firstMs > 0 { pendingFirst = firstMs }
            if let streamMs, streamMs > 0 { pendingStream = streamMs }
        }

        /// The step's speed, paired with the span already closed — never with
        /// the usage line's own time. Clears that span so the next record
        /// cannot time it again.
        mutating func commit(output: Int) -> ReplyTiming? {
            let first = pendingFirst
            let stream = pendingStream
            pendingFirst = nil
            pendingStream = nil

            var span = closed
            closed = nil
            if span == nil, let sent, let wrote, wrote > sent {
                span = (sent, wrote)
                self.sent = nil
                self.wrote = nil
            }

            var timing = ReplyTiming()
            var any = false
            if let span, let speed = ReplyTiming(output: output, from: span.sent, to: span.finished) {
                timing = timing + speed
                any = true
            } else if let first, let stream, first > 0, stream > 0 {
                let seconds = (first + stream) / 1000
                if output >= ReplyTiming.minimumOutput, seconds > 0, seconds <= ReplyTiming.longest {
                    timing = timing + ReplyTiming(outputTokens: output, seconds: seconds, replies: 1)
                    any = true
                }
            }
            if let first, let wait = ReplyTiming.firstToken(after: first / 1000) {
                timing = timing + wait
                any = true
            }
            return any ? timing : nil
        }
    }

    private static func double(_ value: Any?) -> Double? {
        let number = (value as? Double) ?? (value as? Int).map(Double.init) ?? (value as? NSNumber)?.doubleValue
        guard let number, number.isFinite else { return nil }
        return number
    }

    private static func int(_ value: Any?) -> Int {
        (value as? Int) ?? (value as? Double).map(Int.init) ?? (value as? NSNumber)?.intValue ?? 0
    }
}
