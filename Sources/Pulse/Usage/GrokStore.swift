// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Grok Build's transcripts.
///
/// `~/.grok/sessions/<directory>/<session id>/updates.jsonl`, where the
/// directory is the working directory **percent-encoded** — `%2FUsers%2Fme%2FCode`
/// — which is the one agent here that gives its project away in the path
/// without losing anything.
///
/// One line per event, and the one that counts is the end of a turn:
///
/// ```json
/// { "timestamp": 1786775595,
///   "params": { "update": { "sessionUpdate": "turn_completed",
///     "usage": { "inputTokens": 33379, "outputTokens": 91,
///                "cachedReadTokens": 22272, "cacheCreationTokens": 0,
///                "reasoningTokens": 42,
///                "modelUsage": { "grok-4.6-build": { … } } } } } }
/// ```
///
/// **`modelUsage` is what names the model**, and a turn can touch more than
/// one — so the per-model counts are read from it and the flat totals beside
/// it are used only when it is absent.
///
/// **Output speed is a separate reading from those totals.** A turn is timed
/// from the request (the first `user_message_chunk`, or a finished
/// `tool_call_update`) to the last model line before the next tool result or
/// `turn_completed` — not from `turn_completed`'s own timestamp, and not from
/// `apiDurationMs`, which is a sum the log does not promise is complete.
/// Several model rounds in one turn add their spans and count as one reply.
/// The turn is left untimed when the log has no such pair, when more than one
/// model shared it (there is no per-model span), or when `modelCalls` does
/// not match the rounds the log actually shows. A fork that copies the same
/// `prompt_id` is timed once, from the earlier start.
enum GrokStore {
    static func ledger(at root: URL, prices: [String: ModelPrice]) -> UsageLedger {
        var lookup = ModelPriceLookup(prices)
        var buckets: [String: [String: TokenTally]] = [:]
        var sessions: [UsageLedger.Session] = []
        var pendingTimings: [TimedTurn] = []

        let manager = FileManager.default
        let directories = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []

        for directory in directories {
            guard !Task.isCancelled else { return .empty }
            // The folder is the working directory, percent-encoded.
            let project = UsageProject(directory.lastPathComponent.removingPercentEncoding)

            let runs = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for run in runs {
                guard !Task.isCancelled else { return .empty }
                let file = run.appending(path: "updates.jsonl")

                var tokens = 0
                var cost = 0.0
                var unpricedTokens = 0
                var first: Date?
                var last: Date?
                var title: String?
                var runSlots: [String: (tokens: Int, cost: Double, unpriced: Int)] = [:]
                var clock = TurnClock()

                for root in AgentLogIO.jsonLines(at: file) {
                    guard let params = root["params"] as? [String: Any],
                          let update = params["update"] as? [String: Any]
                    else { continue }

                    let kind = update["sessionUpdate"] as? String
                    if let at = eventDate(root, update) {
                        switch kind {
                        case "user_message_chunk":
                            clock.user(at: at, prompt: promptID(root, update))
                        case "agent_message_chunk", "agent_thought_chunk", "tool_call":
                            clock.wrote(at: at)
                        case "tool_call_update":
                            let status = update["status"] as? String
                            if status == "completed" || status == "failed" {
                                clock.toolResult(at: at)
                            }
                        default:
                            break
                        }
                    }

                    // The opening prompt, for a row that would otherwise be a
                    // uuid.
                    if title == nil, kind == "user_message_chunk",
                       let text = UsageLedgerReader.text(in: update["content"]),
                       let opening = UsageLedgerReader.title(from: text) {
                        title = opening
                    }

                    guard kind == "turn_completed",
                          let usage = update["usage"] as? [String: Any],
                          let seconds = root["timestamp"] as? Double ?? (root["timestamp"] as? Int).map(Double.init)
                    else { continue }

                    let at = Date(timeIntervalSince1970: seconds)
                    first = min(first ?? at, at)
                    last = max(last ?? at, at)
                    let key = UsageLedgerReader.slotKey(for: at)
                    if let timed = clock.finish(usage, prompt: promptID(root, update)) {
                        pendingTimings.append(TimedTurn(
                            promptID: timed.promptID, start: timed.start, slot: key,
                            model: timed.model, timing: timed.timing
                        ))
                    }

                    let perModel = usage["modelUsage"] as? [String: [String: Any]]
                        ?? ["grok": usage]

                    for (model, counts) in perModel {
                        // `inputTokens` already holds the cached read and
                        // `outputTokens` the reasoning: `totalTokens` is
                        // their sum alone, a read never exceeds the input,
                        // and Grok Build's own cost meter prices them that
                        // way (#91). Adding them again doubled the totals
                        // and held the hit rate under 50%.
                        let cacheRead = int(counts["cachedReadTokens"])
                        let tally = TokenTally(
                            input: max(int(counts["inputTokens"]) - cacheRead, 0),
                            cacheWrite: int(counts["cacheCreationTokens"]),
                            cacheRead: cacheRead,
                            output: int(counts["outputTokens"])
                        )
                        guard tally.total > 0 else { continue }

                        let price = lookup.price(for: model)
                        let money = price.map { tally.cost(at: $0) } ?? 0
                        let unpriced = price == nil ? tally.total : 0
                        buckets[key, default: [:]][model] = (buckets[key]?[model] ?? TokenTally()) + tally
                        tokens += tally.total
                        cost += money
                        unpricedTokens += unpriced

                        var slot = runSlots[key] ?? (tokens: 0, cost: 0, unpriced: 0)
                        slot.tokens += tally.total
                        slot.cost += money
                        slot.unpriced += unpriced
                        runSlots[key] = slot
                    }
                }

                guard tokens > 0, let first, let last else { continue }
                sessions.append(
                    UsageLedger.Session(
                        id: file.path, name: run.lastPathComponent, title: title,
                        project: project, start: first, end: last, tokens: tokens, cost: cost, unpricedTokens: unpricedTokens,
                        slots: UsageLedgerReader.sessionSlots(runSlots)
                    )
                )
            }
        }

        guard !buckets.isEmpty else { return .empty }
        var ledger = UsageLedgerReader.price(buckets, with: prices, timings: Self.timings(pendingTimings))
        ledger.sessions = sessions.sorted { $0.end > $1.end }
        return ledger
    }

    /// One prompt timed once. A fork copies the log and rewrites the envelope
    /// times but keeps `prompt_id`; the earlier start is the original span.
    private static func timings(_ turns: [TimedTurn]) -> [String: [String: ReplyTiming]] {
        var named: [String: TimedTurn] = [:]
        var unnamed: [TimedTurn] = []
        for turn in turns {
            guard let id = turn.promptID else {
                unnamed.append(turn)
                continue
            }
            if let kept = named[id] {
                if turn.start < kept.start { named[id] = turn }
            } else {
                named[id] = turn
            }
        }
        var chosen = unnamed
        chosen.append(contentsOf: named.values)
        var timings: [String: [String: ReplyTiming]] = [:]
        for turn in chosen {
            timings[turn.slot, default: [:]][turn.model] =
                (timings[turn.slot]?[turn.model] ?? ReplyTiming()) + turn.timing
        }
        return timings
    }

    private struct TimedTurn {
        let promptID: String?
        let start: Date
        let slot: String
        let model: String
        let timing: ReplyTiming
    }

    /// One user turn's model rounds. Tool time sits between a tool call and
    /// its result and is not part of any round.
    private struct TurnClock {
        private var sent: Date?
        private var wrote: Date?
        private var started: Date?
        private var seconds = 0.0
        private var rounds = 0
        private var stalled = false
        private var prompt: String?
        private var heardUser = false

        mutating func user(at date: Date, prompt id: String?) {
            if let id {
                if id != prompt {
                    reset()
                    prompt = id
                } else if heardUser {
                    return
                }
            } else if heardUser {
                return
            }
            heardUser = true
            sent(at: date)
        }

        mutating func wrote(at date: Date) {
            guard let sent, date > sent else { return }
            wrote = date
        }

        /// The tool's result is the next request. It closes the round that
        /// asked for the tool, and does not extend that round through the tool.
        mutating func toolResult(at date: Date) {
            sent(at: date)
        }

        /// The completed turn's output speed, or nothing when the log cannot
        /// support one. Always leaves the clock ready for the next prompt.
        mutating func finish(_ usage: [String: Any], prompt completed: String?) -> (model: String, timing: ReplyTiming, promptID: String?, start: Date)? {
            defer { reset() }
            closeRound()
            if let completed, let prompt, completed != prompt { return nil }
            let promptID = completed ?? prompt
            guard !stalled, rounds > 0, let started, seconds > 0, seconds <= ReplyTiming.longest else { return nil }
            let calls = GrokStore.int(usage["modelCalls"])
            if calls > 0, calls != rounds { return nil }
            let model: String
            let output: Int
            if let perModel = usage["modelUsage"] as? [String: [String: Any]], !perModel.isEmpty {
                // One span cannot be split across models without inventing
                // which of them the seconds belonged to.
                guard perModel.count == 1, let entry = perModel.first else { return nil }
                model = entry.key
                output = GrokStore.int(entry.value["outputTokens"])
            } else {
                model = "grok"
                output = GrokStore.int(usage["outputTokens"])
            }
            guard output >= ReplyTiming.minimumOutput else { return nil }
            let timing = ReplyTiming(outputTokens: output, seconds: seconds, replies: 1)
            return (model, timing, promptID, started)
        }

        private mutating func sent(at date: Date) {
            closeRound()
            sent = date
            wrote = nil
            if started == nil { started = date }
        }

        private mutating func closeRound() {
            guard let sent, let wrote else {
                self.sent = nil
                self.wrote = nil
                return
            }
            let span = wrote.timeIntervalSince(sent)
            if span > ReplyTiming.longest { stalled = true }
            else if span > 0 {
                seconds += span
                rounds += 1
            }
            self.sent = nil
            self.wrote = nil
        }

        private mutating func reset() {
            sent = nil
            wrote = nil
            started = nil
            seconds = 0
            rounds = 0
            stalled = false
            prompt = nil
            heardUser = false
        }

    }

    /// Milliseconds from `_meta.agentTimestampMs` when the line has them —
    /// the envelope `timestamp` is whole seconds — else that envelope.
    private static func eventDate(_ root: [String: Any], _ update: [String: Any]) -> Date? {
        for meta in metas(root, update) {
            if let ms = double(meta["agentTimestampMs"]), ms > 0 {
                return Date(timeIntervalSince1970: ms / 1000)
            }
        }
        guard let seconds = double(root["timestamp"]), seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func promptID(_ root: [String: Any], _ update: [String: Any]) -> String? {
        if let id = text(update["prompt_id"] ?? update["promptId"]) { return id }
        for meta in metas(root, update) {
            if let id = text(meta["promptId"] ?? meta["prompt_id"]) { return id }
        }
        return nil
    }

    private static func metas(_ root: [String: Any], _ update: [String: Any]) -> [[String: Any]] {
        var found: [[String: Any]] = []
        if let meta = root["_meta"] as? [String: Any] { found.append(meta) }
        if let params = root["params"] as? [String: Any], let meta = params["_meta"] as? [String: Any] {
            found.append(meta)
        }
        if let meta = update["_meta"] as? [String: Any] { found.append(meta) }
        return found
    }

    private static func text(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func double(_ value: Any?) -> Double? {
        (value as? Double) ?? (value as? Int).map(Double.init) ?? (value as? NSNumber)?.doubleValue
    }

    private static func int(_ value: Any?) -> Int {
        (value as? Int) ?? (value as? Double).map(Int.init) ?? (value as? NSNumber)?.intValue ?? 0
    }
}
