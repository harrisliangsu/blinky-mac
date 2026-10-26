// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// While an account pane is open, notice that a local session log has
/// finished a reply and ask for the ledger again.
///
/// The quota timer and the activity monitor are the wrong signals. A reply's
/// speed exists only once the reply has ended, and a line still being written
/// — Claude Code's `stop_reason` null, a Codex item with no `token_count` yet,
/// a Grok chunk, a Kimi content part — is not that end. The pane polls the
/// recent logs and re-reads only when a file that changed ends on a closed
/// reply.
enum ReplyTimingWatch {
    /// Size and modification time of one session log.
    struct FileStamp: Equatable, Sendable {
        var size: Int
        var modified: TimeInterval
    }

    /// How often the open pane looks. A finished reply should show up with
    /// the table, not on the next quota refresh.
    static let poll = Duration.seconds(2)

    /// Logs quiet for longer than this are not a live reply.
    static let recentWindow: TimeInterval = 30 * 60

    /// Whether a file that changed since `previous` now ends on a closed reply.
    /// The tail is read off the main actor; the pane decides what to reload.
    static func includesClosedReply(
        provider: Provider,
        previous: [String: FileStamp],
        next: [String: FileStamp]
    ) async -> Bool {
        shouldRefresh(previous: previous, next: next) { path in
            isClosedReply(provider: provider, at: path)
        }
    }

    /// True when some path in `next` is new or has moved, and that file's
    /// tail is a closed reply. A file that only grew mid-reply, and a file
    /// that disappeared, are not a reason to re-read.
    static func shouldRefresh(
        previous: [String: FileStamp],
        next: [String: FileStamp],
        isClosed: (String) -> Bool
    ) -> Bool {
        for (path, stamp) in next {
            guard previous[path] != stamp else { continue }
            if isClosed(path) { return true }
        }
        return false
    }

    /// Recent session logs for the providers whose replies can be timed.
    /// Async so the walk does not run on the main actor.
    static func snapshot(
        for provider: Provider,
        now: Date = Date(),
        home: URL = URL(fileURLWithPath: NSHomeDirectory()),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        recent: TimeInterval = recentWindow
    ) async -> [String: FileStamp] {
        guard provider.timesLocalReplies else { return [:] }
        var found: [String: FileStamp] = [:]
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        for root in roots(for: provider, home: home, environment: environment) {
            guard !Task.isCancelled else { return found }
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                guard !Task.isCancelled else { return found }
                guard isSessionLog(url, provider: provider) else { continue }
                guard
                    let values = try? url.resourceValues(forKeys: keys),
                    values.isRegularFile == true,
                    let modified = values.contentModificationDate,
                    now.timeIntervalSince(modified) >= 0,
                    now.timeIntervalSince(modified) <= recent,
                    let size = values.fileSize
                else { continue }
                found[url.path] = FileStamp(size: size, modified: modified.timeIntervalSince1970)
            }
        }
        return found
    }

    /// Whether the end of this log is a reply that has finished, rather than
    /// a line still being written. Unreadable is not finished.
    static func isClosedReply(provider: Provider, at path: String) -> Bool {
        guard let text = tailText(at: path) else { return false }
        return isClosedTail(text, provider: provider)
    }

    /// The same rule over a log's tail, so a test can hand in the lines.
    static func isClosedTail(_ text: String, provider: Provider) -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        var seen = 0
        for line in lines.reversed() {
            seen += 1
            if seen > 40 { return false }
            guard
                let data = line.data(using: .utf8),
                let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            if let closed = closed(root, provider: provider) { return closed }
        }
        return false
    }

    // MARK: - Tails

    /// True when this line closes a reply, false when it is still the
    /// reply, nil when it says nothing and an earlier line might.
    private static func closed(_ root: [String: Any], provider: Provider) -> Bool? {
        switch provider {
        case .claudeCode: return claudeClosed(root)
        case .codex: return codexClosed(root)
        case .grok: return grokClosed(root)
        case .kimiCode: return kimiClosed(root)
        default: return nil
        }
    }

    /// An explicit null `stop_reason` is a message still being written. Any
    /// other assistant line, and a user line after it, means the reply ended.
    private static func claudeClosed(_ root: [String: Any]) -> Bool? {
        switch root["type"] as? String {
        case "assistant":
            let message = root["message"] as? [String: Any]
            return message?["stop_reason"] is NSNull ? false : true
        case "user":
            return true
        default:
            return nil
        }
    }

    /// Codex writes the count after the reply, and after the tool output
    /// that is also the next request. A model line with no count yet is open.
    private static func codexClosed(_ root: [String: Any]) -> Bool? {
        let payload = root["payload"] as? [String: Any]
        switch (payload?["type"] as? String) ?? (root["type"] as? String) {
        case "token_count", "task_complete", "turn_aborted":
            return true
        case "task_started", "message", "reasoning",
             "function_call", "function_call_output",
             "custom_tool_call", "web_search_call", "local_shell_call":
            return false
        default:
            return nil
        }
    }

    private static func grokClosed(_ root: [String: Any]) -> Bool? {
        let update = (root["params"] as? [String: Any])?["update"] as? [String: Any]
        switch update?["sessionUpdate"] as? String {
        case "turn_completed":
            return true
        case "user_message_chunk", "agent_message_chunk", "agent_thought_chunk",
             "tool_call", "tool_call_update":
            return false
        default:
            return nil
        }
    }

    /// A turn-scoped usage record, a finished step, or the legacy status
    /// line. A session total is not a reply, so the line before it is asked.
    private static func kimiClosed(_ root: [String: Any]) -> Bool? {
        switch root["type"] as? String {
        case "usage.record":
            return (root["usageScope"] as? String) == "session" ? nil : true
        case "turn.prompt", "turn.steer":
            return false
        case "context.append_loop_event":
            switch (root["event"] as? [String: Any])?["type"] as? String {
            case "step.end": return true
            case "step.begin", "content.part", "tool.call", "tool.result": return false
            default: return nil
            }
        default:
            break
        }
        guard let message = root["message"] as? [String: Any] else { return nil }
        let type = message["type"] as? String
        let payload = message["payload"] as? [String: Any]
        if payload?["token_usage"] != nil, type == nil || type == "StatusUpdate" { return true }
        switch type {
        case "TurnBegin", "StepBegin", "ContentPart", "ToolCall", "ToolCallPart", "ToolResult":
            return false
        default:
            return nil
        }
    }

    // MARK: - Files

    private static func roots(for provider: Provider, home: URL, environment: [String: String]) -> [URL] {
        switch provider {
        case .claudeCode: return SpendAgent.claudeCode.inputs(home: home, environment: environment)
        case .codex: return SpendAgent.codex.inputs(home: home, environment: environment)
        case .grok: return SpendAgent.grok.inputs(home: home, environment: environment)
        case .kimiCode: return SpendAgent.kimiCLI.inputs(home: home, environment: environment)
        default: return []
        }
    }

    private static func isSessionLog(_ url: URL, provider: Provider) -> Bool {
        switch provider {
        case .grok: return url.lastPathComponent == "updates.jsonl"
        case .kimiCode: return url.lastPathComponent == "wire.jsonl"
        case .claudeCode, .codex: return url.pathExtension == "jsonl"
        default: return false
        }
    }

    /// The last stretch of a log. A read that starts mid-line drops that line.
    private static func tailText(at path: String, bytes: Int = 48 * 1024) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        let offset = end > UInt64(bytes) ? end - UInt64(bytes) : 0
        try? handle.seek(toOffset: offset)
        guard var data = try? handle.readToEnd(), !data.isEmpty else { return nil }
        if offset > 0, let newline = data.firstIndex(of: 0x0A) {
            data = Data(data[data.index(after: newline)...])
        }
        return String(data: data, encoding: .utf8)
    }
}
