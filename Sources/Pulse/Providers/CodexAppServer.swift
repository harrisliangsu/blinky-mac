// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import CryptoKit

/// A JSON-RPC client for `codex app-server`.
///
/// This is Codex's own documented protocol, and it is the reason Pulse doesn't
/// have to hold Codex credentials: the app server is already signed in, so
/// Pulse asks it for figures instead of reading `~/.codex/auth.json` and
/// calling an undocumented HTTP endpoint itself. It also pushes
/// `account/rateLimits/updated` when the numbers move, so the refresh loop is
/// a fallback rather than the main path.
///
/// The cost is a resident child process, started lazily on the first request
/// and restarted if it dies, or when the CLI login in `~/.codex/auth.json`
/// is no longer the one this process started with.
actor CodexAppServer {
    /// Called when the server reports that limits changed.
    private var onRateLimitsChanged: (@Sendable () -> Void)?

    private var process: Process?
    private var stdin: FileHandle?
    /// The handle the helper's stdout is read through, held so that a restart
    /// or a shutdown can take its `readabilityHandler` off. **A handler left
    /// on a closed pipe is a busy loop**, not a leak that merely wastes
    /// memory — see `startReading`.
    private var reader: FileHandle?
    // Keep IDs unique across helper restarts, including callbacks already
    // queued on the actor when an old request was completed or cancelled.
    private var nextID = 1
    // Results cross an actor boundary, and a JSON dictionary isn't Sendable,
    // so they travel as raw bytes and are decoded on the far side.
    private struct PendingRequest {
        let continuation: CheckedContinuation<Data, Error>
        let timeout: Task<Void, Never>
    }
    private var pending: [Int: PendingRequest] = [:]
    private var buffer = Data()
    private let executable: URL?
    private let requestTimeout: Duration
    /// Codex's saved login, the same file the usage bar reads. A test points
    /// this at a temporary file so the real `~/.codex/auth.json` stays unread.
    private let authFile: URL
    /// Hash of the login this helper was started with. Nil when that file
    /// could not be read. Not the token.
    private var startedLogin: String?

    // Tests use an isolated helper without changing PATH or touching a login.
    init(
        executable: URL? = nil,
        requestTimeout: Duration = .seconds(20),
        authFile: URL? = nil
    ) {
        self.executable = executable
        self.requestTimeout = requestTimeout
        self.authFile = authFile
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".codex/auth.json")
    }

    enum Failure: Error {
        /// Codex isn't installed, or isn't anywhere we thought to look.
        case executableNotFound
        case startFailed
        case timedOut
        case server(String)
    }

    func setRateLimitsChangedHandler(_ handler: @escaping @Sendable () -> Void) {
        onRateLimitsChanged = handler
    }

    /// The account's limits, as `account/rateLimits/read` reports them, still
    /// encoded as JSON.
    func rateLimits() async throws -> Data {
        try await invoke(method: "account/rateLimits/read")
    }

    /// Spends one limit reset credit. The dictionary is built here: a
    /// `[String: Any]` cannot cross into this actor.
    ///
    /// `creditID` empty leaves the choice to the app server. A non-empty id
    /// is sent as `creditId`, which is the field that route documents.
    func consumeResetCredit(idempotencyKey: String, creditID: String?) async throws -> Data {
        var params: [String: Any] = ["idempotencyKey": idempotencyKey]
        if let creditID, !creditID.isEmpty {
            params["creditId"] = creditID
        }
        return try await invoke(method: CodexAccountUsageService.ConsumeRequest.method, params: params)
    }

    /// The models the account may use, as `model/list` reports them, still
    /// encoded as JSON.
    func models() async throws -> Data {
        try await invoke(method: "model/list")
    }

    /// The account's token history, as `account/usage/read` reports it, still
    /// encoded as JSON.
    func accountUsage() async throws -> Data {
        try await invoke(method: "account/usage/read")
    }

    func shutDown() {
        stopReading()
        process?.terminate()
        process = nil
        stdin = nil
        startedLogin = nil
        failAllPending()
    }

    /// Take the handler off the pipe we are done with.
    ///
    /// Terminating the child is not enough: the handler belongs to the file
    /// handle, and a handle whose far end has closed stays readable for ever.
    func stopReading() {
        reader?.readabilityHandler = nil
        reader = nil
        buffer.removeAll(keepingCapacity: false)
    }

    private func failAllPending() {
        for id in Array(pending.keys) { finish(id, with: .failure(Failure.startFailed)) }
    }

    // MARK: - Process

    private func ensureRunning() async throws {
        // The helper reads `auth.json` when it starts and then keeps that
        // login. Switching ChatGPT accounts rewrites the file and revokes the
        // token this process still holds, so the usage bar — which reads the
        // file on every request — follows the new account while reset cards
        // keep asking the old one. A different login shuts it down first.
        // An unreadable file is not a new login: a transient read must not
        // kill a helper that is already answering.
        let login = Self.loginStamp(at: authFile)
        if let process, process.isRunning {
            if login == nil || login == startedLogin { return }
        }

        // **Before starting another one.** Getting here with a process set
        // means the last one died, or its login was replaced, and its pipe
        // is still wired to a handler.
        // Without this, every restart left one more spinning thread behind:
        // three of them was 290% of a CPU for eleven hours, with no child
        // process left to blame (issue #25).
        shutDown()

        guard let executable = executable ?? Self.locateCodex() else { throw Failure.executableNotFound }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server"]
        process.environment = Self.environment(for: executable, over: BoundedProcess.inheritedEnvironment)

        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let reader = output.fileHandleForReading
        startReading(reader)

        do {
            try process.run()
        } catch {
            stopReading()
            throw Failure.startFailed
        }

        self.process = process
        self.stdin = input.fileHandleForWriting
        self.startedLogin = login

        // The protocol opens with a handshake before anything else is accepted.
        _ = try await send(
            method: "initialize",
            params: ["clientInfo": ["name": "Pulse", "title": "Pulse", "version": "0.1"]]
        )
        notify(method: "initialized")
    }

    /// Read the helper's stdout, and stop the moment it closes.
    ///
    /// **An empty `availableData` is EOF, and the handler must come off right
    /// there.** A pipe whose far end has closed is readable for ever, so a
    /// handler that merely returns is called again immediately, and again,
    /// for as long as the app runs — one core, flat out, for something that
    /// has already finished. Returning without clearing it is what issue #25
    /// was: 290% of a CPU for eleven hours after `codex app-server` exited.
    ///
    /// Cleared **on this queue**, synchronously, rather than by hopping to the
    /// actor. The hop is the whole window the loop needs: the fd stays
    /// readable until the handler is gone, and the handler is not gone until
    /// the actor gets round to it.
    ///
    /// `VolcengineUsageService` has done this correctly since it was written;
    /// this path simply never learned it.
    // Not private: `CodexAppServerTests` drives these against a plain pipe,
    // because the invariant they carry cannot be checked from the outside and
    // the cost of getting it wrong is a core at 100% for as long as the app
    // runs.
    func startReading(_ reader: FileHandle) {
        self.reader = reader
        reader.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                Task { await self?.readerClosed(handle) }
                return
            }
            Task { await self?.consume(chunk, from: handle) }
        }
    }

    /// Take ownership of a helper and its pipe, for `CodexAppServerTests`.
    ///
    /// `ensureRunning` is the only caller in the app; a test cannot use it
    /// without `codex` installed, and the invariant worth testing — that EOF
    /// terminates rather than forgets — needs a real process to observe.
    func adopt(_ process: Process, reader: FileHandle) {
        self.process = process
        startReading(reader)
    }

    /// The helper's stdout reached EOF: it has exited, or is exiting.
    ///
    /// Anything still waiting is waiting for a process that will not answer,
    /// so it is failed now rather than at the twenty-second timeout — and the
    /// handles are dropped so the next request starts a fresh helper instead
    /// of writing into a dead pipe.
    ///
    /// Guarded on identity because a restart installs a new reader: the old
    /// one's EOF must not tear down the helper that replaced it.
    func readerClosed(_ handle: FileHandle) {
        guard handle === reader else { return }
        // **Terminated, not merely forgotten.** EOF on stdout usually means
        // the helper exited, but it can also mean a helper that is still
        // running with its output closed. Dropping the `Process` there leaves
        // it with nothing able to kill it — not even `shutDown`, which
        // terminates a `process` that is by then nil — so quitting Pulse would
        // leave it behind. `terminate()` on one that has already exited is a
        // no-op.
        shutDown()
    }

    /// The helper's environment, with the folder `codex` was found in first on
    /// `PATH` — see `BoundedProcess.environment(leading:over:)`.
    static func environment(for executable: URL, over inherited: [String: String]) -> [String: String] {
        BoundedProcess.environment(leading: executable, over: inherited)
    }

    /// Where `codex` tends to live. A GUI app inherits almost no `PATH`, so
    /// the usual install locations have to be checked by hand rather than
    /// relying on the environment.
    static func locateCodex() -> URL? {
        let fileManager = FileManager.default
        // Wherever the app actually is — a second drive, a folder of its own
        // — Launch Services knows it by its bundle id. Both the ChatGPT app
        // and the Codex app answer to this one (checked on ChatGPT 26.917).
        let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")
        return candidates(
            home: NSHomeDirectory(),
            path: ProcessInfo.processInfo.environment["PATH"],
            app: installed,
            versions: { (try? fileManager.contentsOfDirectory(atPath: $0))?.sorted() ?? [] }
        )
        .first { fileManager.isExecutableFile(atPath: $0) }
        .map { URL(fileURLWithPath: $0) }
    }

    /// Every place, in order. Internal and fed its listing so a test can see
    /// the order without a disk.
    ///
    /// **The desktop apps carry their own.** ChatGPT's and Codex's Mac apps
    /// ship a signed `codex` in `Contents/Resources`, and somebody who uses
    /// Codex only through one of them has no other: every place below that
    /// came up empty, so the reset credits read "Not available" on two Macs
    /// that had several (issue #67, where the reporter found the one at
    /// `/Applications/ChatGPT.app/Contents/Resources/codex`, codex-cli
    /// 0.155.0-alpha). It is a native binary, so it needs no `node` beside
    /// it. `app` is wherever Launch Services says the app is; the fixed
    /// paths catch a copy it has not registered.
    ///
    /// **Where inside the app has moved once already.** ChatGPT 26.924 put it
    /// at `Contents/Resources/codex-cli/bin/codex` and dropped the old place,
    /// and the reporter was back the day 1.5.1 shipped. Both are listed,
    /// newer first, for every app location (`bundled`).
    ///
    /// Node version managers put it under a version directory, so those are
    /// listed; the folder it is found in leads the helper's `PATH`, which is
    /// where each of them keeps `node` (`BoundedProcess.environment`).
    /// Where the desktop apps keep `codex`, relative to the app, newest
    /// layout first.
    static let bundled = [
        "Contents/Resources/codex-cli/bin/codex",
        "Contents/Resources/codex",
    ]

    static func candidates(
        home: String,
        path: String?,
        app: URL? = nil,
        versions: (String) -> [String]
    ) -> [String] {
        var candidates = (path ?? "").split(separator: ":").map { "\($0)/codex" }
        if let app {
            candidates += bundled.map { app.appending(path: $0).path }
        }
        candidates += CommandLocator.directories(home: home).map { "\($0)/codex" }
        for app in ["/Applications/Codex.app", "\(home)/Applications/Codex.app",
                    "/Applications/ChatGPT.app", "\(home)/Applications/ChatGPT.app"] {
            candidates += bundled.map { "\(app)/\($0)" }
        }
        return candidates + CommandLocator.managed("codex", home: home, versions: versions)
    }

    // MARK: - Login

    /// A hash of `tokens.account_id` and `tokens.access_token`, or nil when
    /// the file has no access token. The token is not retained and not logged.
    ///
    /// Internal so a test can show that a new token or a new account is a
    /// different login, and that the stamp is not the token itself.
    static func loginStamp(in data: Data) -> String? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = root["tokens"] as? [String: Any],
            let token = tokens["access_token"] as? String
        else { return nil }
        let access = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !access.isEmpty else { return nil }
        let account = (tokens["account_id"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let material = Data("\(account)\n\(access)".utf8)
        return SHA256.hash(data: material).map { String(format: "%02x", $0) }.joined()
    }

    /// Nil when the file is missing or has no access token.
    static func loginStamp(at file: URL) -> String? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return loginStamp(in: data)
    }

    /// Whether this JSON-RPC error is the revoked login the helper kept
    /// after the CLI wrote a new one. Anything else is left to fail as it
    /// did: a refusal that is not this login must not restart the helper.
    static func refusesCredentials(_ text: String) -> Bool {
        text.range(of: "token_revoked", options: .caseInsensitive) != nil
    }

    /// The error's message, plus its `data` when that carries the code the
    /// message left out. A message-only error stays the message, so an
    /// existing refusal still compares equal to the text the helper sent.
    static func serverErrorText(_ error: [String: Any]) -> String {
        var parts: [String] = []
        if let message = error["message"] as? String {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { parts.append(trimmed) }
        }
        if let code = error["code"] as? String {
            let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { parts.append(trimmed) }
        }
        if let data = error["data"] {
            if let text = data as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { parts.append(trimmed) }
            } else if JSONSerialization.isValidJSONObject(data),
                      let encoded = try? JSONSerialization.data(withJSONObject: data),
                      let text = String(data: encoded, encoding: .utf8),
                      !text.isEmpty {
                parts.append(text)
            }
        }
        return parts.isEmpty ? "unknown" : parts.joined(separator: " ")
    }

    // MARK: - Messaging

    /// One authenticated call. The handshake stays on `send`: it does not
    /// ask the account, and retrying it here would start a second helper
    /// before the first had failed an account call.
    ///
    /// A `token_revoked` reply means this helper is still signed in as a
    /// login the server has already refused. Shut it down and ask once more,
    /// so the new process reads whatever `auth.json` says now. A second
    /// refusal propagates: restarting forever would hide a login that is
    /// actually dead.
    private func invoke(method: String, params: [String: Any] = [:]) async throws -> Data {
        try await ensureRunning()
        do {
            return try await send(method: method, params: params)
        } catch let Failure.server(let message) where Self.refusesCredentials(message) {
            shutDown()
            try await ensureRunning()
            return try await send(method: method, params: params)
        }
    }

    private func send(method: String, params: [String: Any] = [:]) async throws -> Data {
        let id = nextID
        nextID += 1

        let message: [String: Any] = [
            "jsonrpc": "2.0", "id": id, "method": method, "params": params
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: message) else {
            throw Failure.startFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Nothing to write to means nothing will ever answer, and a
            // continuation nobody answers suspends its caller for ever.
            guard let stdin else {
                continuation.resume(throwing: Failure.startFailed)
                return
            }

            // Strongly held, deliberately. Weakly, this server going away
            // before the timeout fires leaves every request it was carrying
            // suspended with nobody left to resume them — which Swift reports
            // as a leaked continuation and the caller experiences as a hang.
            // A strong reference costs at most twenty seconds of lifetime and
            // makes that impossible.
            let timeout = Task { [self] in
                do { try await Task.sleep(for: requestTimeout) }
                catch { return }
                finish(id, with: .failure(Failure.timedOut))
            }
            pending[id] = PendingRequest(continuation: continuation, timeout: timeout)
            write(data, to: stdin)
        }
    }

    private func notify(method: String, params: [String: Any] = [:]) {
        let message: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
        guard
            let data = try? JSONSerialization.data(withJSONObject: message),
            let stdin
        else { return }

        write(data, to: stdin)
    }

    /// One line to the helper's standard input; close the connection if it has gone.
    ///
    /// **Writing to a pipe whose far end has closed raises SIGPIPE, and the
    /// default for SIGPIPE is to kill the process.** The helper exiting — it
    /// crashed, it was killed with the terminal it was started from, the user
    /// quit Codex — would take Pulse down with it, and from the outside that
    /// looks like the app crashing at random. `SIGPIPE` is ignored process-wide
    /// (see `AppDelegate`) so the write returns an error instead; this is the
    /// half that then treats the error as "the helper is gone" rather than
    /// carrying on writing into a dead pipe.
    private func write(_ data: Data, to handle: FileHandle) {
        do {
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data("\n".utf8))
        } catch {
            // Whatever is left of it is not usable, and the next call will
            // start a fresh one.
            shutDown()
        }
    }

    private func finish(_ id: Int, with result: Result<Data, Error>) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.timeout.cancel()
        request.continuation.resume(with: result)
    }

    /// Messages arrive as newline-delimited JSON, and a read can land
    /// mid-line, so hold the remainder until the next chunk completes it.
    private func consume(_ chunk: Data, from source: FileHandle) {
        guard source === reader else { return }
        buffer.append(chunk)

        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer = buffer[buffer.index(after: newline)...]
            guard !line.isEmpty,
                  let message = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
            else { continue }
            handle(message)
        }
    }

    private func handle(_ message: [String: Any]) {
        if let id = message["id"] as? Int, pending[id] != nil {
            if let error = message["error"] as? [String: Any] {
                finish(id, with: .failure(Failure.server(Self.serverErrorText(error))))
            } else {
                let result = message["result"] as? [String: Any] ?? [:]
                let data = (try? JSONSerialization.data(withJSONObject: result)) ?? Data("{}".utf8)
                finish(id, with: .success(data))
            }
            return
        }

        if message["method"] as? String == "account/rateLimits/updated" {
            onRateLimitsChanged?()
        }
    }
}
