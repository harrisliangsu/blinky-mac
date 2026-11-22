// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// What `agy` prints when it wants a Google sign-in, and what Blinky may do
/// about it.
///
/// On a Mac with a browser, a signed-out `agy` opens the system browser and
/// then waits for the code that page shows to be typed back into **that same
/// process**. A usage probe used to start `agy -p /usage` on every refresh
/// with standard input closed, so each probe opened another window and the
/// code had nowhere to go. The next refresh, two minutes later while the
/// panel was in use, did it again. Nothing in that path is the activity
/// mark: that only reads conversation databases.
enum AntigravityLoginTranscript {
    /// A usage probe sets these so `agy` prints the sign-in line and exits,
    /// instead of opening a browser. `CI` and the noninteractive switch are
    /// what make it exit; without them a local run opens the page and waits.
    static let quietEnvironment: [String: String] = [
        "AGY_CLI_NONINTERACTIVE_HEADLESS": "1",
        "AGY_CLI_INTERACTIVE_HEADLESS": "1",
        "BROWSER": "none",
        "CI": "1",
    ]

    /// A sign-in sets these so `agy` prints the URL and keeps reading. The
    /// noninteractive switch and `CI` are absent on purpose: those make the
    /// process exit, and then the code has nowhere to go. Blinky opens the
    /// page itself, once.
    static let loginEnvironment: [String: String] = [
        "AGY_CLI_INTERACTIVE_HEADLESS": "1",
        "BROWSER": "none",
    ]

    static let loginArguments = ["--log-file", "/dev/null", "acp", "--login"]

    /// The first Google sign-in URL in `text`, if `agy` printed one.
    static func loginURL(in text: String) -> URL? {
        guard let start = text.range(of: "https://accounts.google.com/") else { return nil }
        let rest = text[start.lowerBound...]
        let end = rest.firstIndex { character in
            character.isWhitespace || character == "\"" || character == "'" || character == "<" || character == ">"
        } ?? rest.endIndex
        let raw = String(rest[..<end]).trimmingCharacters(in: CharacterSet(charactersIn: ").,;"))
        guard let url = URL(string: raw), url.scheme == "https", url.host == "accounts.google.com" else { return nil }
        return url
    }

    /// Whether this output is `agy` asking for a sign-in rather than reporting
    /// usage. A successful `/usage` document does not say these things.
    static func asksToSignIn(_ text: String) -> Bool {
        if loginURL(in: text) != nil { return true }
        let folded = text.lowercased()
        return folded.contains("authentication required")
            || folded.contains("please visit the url")
            || folded.contains("not signed in")
            || folded.contains("sign in to continue")
    }

    /// Whether Google or `agy` refused the account because of where its Terms
    /// of Service say it is. Antigravity does not serve every region; opening
    /// the page again does not change that.
    static func unsupportedRegion(_ text: String) -> Bool {
        let folded = text.lowercased()
        let phrases = [
            "not available in your country",
            "not available in your region",
            "not available in your location",
            "not available in this country",
            "not available in this region",
            "isn't available in your",
            "is not available in your",
            "not supported in your",
            "unsupported region",
            "unsupported country",
            "country is not supported",
            "region is not supported",
            "terms of service country",
            "所在的地区",
            "所在地区",
            "所在的國家",
            "所在國家",
            "不支持的地区",
            "不支持的地區",
        ]
        return phrases.contains { folded.contains($0.lowercased()) }
    }

    /// The code, or the page address, ready to hand to `agy`. Empty and
    /// multi-line pastes are refused: the CLI reads one line.
    static func submission(from pasted: String) -> String? {
        let value = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(where: \.isNewline), value.count <= 2048 else { return nil }
        return value
    }
}

/// What the sign-in row is showing, and why a button did nothing.
struct AntigravityLoginSnapshot: Equatable, Sendable {
    enum Mode: Equatable, Sendable {
        case idle
        case starting
        case waiting
        case submitting
    }

    /// A sentence the row can show. The words live in the view, not here.
    enum Notice: Equatable, Sendable {
        case alreadyOpen
        case paused
        case unsupportedRegion
        case pasteTheCode
        case couldNotStart
        case cliTooOld
        case missingCLI
        case signedIn
    }

    var mode: Mode
    var notice: Notice?

    static let idle = Self(mode: .idle, notice: nil)
}

/// How one Antigravity sign-in is allowed to proceed.
///
/// One process at a time, one browser window for it, and a sign-in that
/// failed, was cancelled, or was refused for the account's region does not
/// start another straight away. A usage probe that was told to sign in does
/// not start `agy` again for a quarter of an hour; pressing Sign in still
/// can, once.
struct AntigravityLoginMachine: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case starting
        case waiting
        case submitting
    }

    enum Hold: Equatable, Sendable {
        case none
        case failed(Date)
        case cancelled(Date)
        case unsupportedRegion(Date)
        /// The refresh loop heard "sign in" and must not start `agy` again
        /// yet. Pressing Sign in is still allowed: that is how the code gets
        /// entered.
        case needsSignIn(Date)

        func deadline() -> Date? {
            switch self {
            case .none: nil
            case .failed(let date), .cancelled(let date), .unsupportedRegion(let date), .needsSignIn(let date):
                date
            }
        }

        /// A failed, cancelled, or region-blocked sign-in. `needsSignIn` is
        /// not one of these: it only stops the probe.
        func blocksSignIn(at now: Date) -> Bool {
            switch self {
            case .none, .needsSignIn: false
            case .failed(let date), .cancelled(let date), .unsupportedRegion(let date):
                now < date
            }
        }
    }

    enum Begin: Equatable, Sendable {
        case start
        case alreadyRunning
        case paused(Hold)
    }

    enum Outcome: Equatable, Sendable {
        case signedIn
        case alreadyRunning
        case paused
        case unsupportedRegion
        case failed
        case cancelled
        case missingCLI
        case couldNotStart
        case cliTooOld
    }

    /// How long a failed or cancelled sign-in stays quiet. Long enough that
    /// a click landing twice cannot open a second page; short enough that
    /// typing the code again is still the same sitting.
    static let retryPause: TimeInterval = 30
    /// A region Antigravity does not serve, and a probe that was told to
    /// sign in. Neither is going to succeed by being asked again at once.
    static let regionPause: TimeInterval = 15 * 60
    static let probePause: TimeInterval = 15 * 60

    private(set) var phase: Phase = .idle
    private(set) var hold: Hold = .none
    /// How many times this sign-in has been allowed to open a page.
    private(set) var browserOpens = 0

    var mode: AntigravityLoginSnapshot.Mode {
        switch phase {
        case .idle: .idle
        case .starting: .starting
        case .waiting: .waiting
        case .submitting: .submitting
        }
    }

    var isActive: Bool {
        switch phase {
        case .idle: false
        case .starting, .waiting, .submitting: true
        }
    }

    /// Whether a usage probe may start `agy`. Never while a sign-in is up,
    /// and never during a hold.
    func mayProbe(now: Date) -> Bool {
        guard case .idle = phase else { return false }
        if let until = hold.deadline(), now < until { return false }
        return true
    }

    func heldProbeReason() -> ProviderUsage.Unavailability {
        if case .unsupportedRegion = hold { return .antigravityUnsupportedRegion }
        return .antigravitySignInRequired
    }

    mutating func begin(now: Date) -> Begin {
        if isActive { return .alreadyRunning }
        if hold.blocksSignIn(at: now) { return .paused(hold) }
        phase = .starting
        hold = .none
        browserOpens = 0
        return .start
    }

    /// The CLI printed something while it was starting. Returns the URL the
    /// first time it appears, and nil after that — a second copy of the same
    /// link is not a second page.
    mutating func observe(_ text: String) -> URL? {
        guard case .starting = phase else { return nil }
        if AntigravityLoginTranscript.unsupportedRegion(text) { return nil }
        guard let url = AntigravityLoginTranscript.loginURL(in: text) else { return nil }
        guard browserOpens == 0 else { return nil }
        browserOpens += 1
        phase = .waiting
        return url
    }

    /// The code the person pasted, once the page is up. Nil when it is not
    /// a single line, or when no sign-in is waiting for one.
    mutating func accept(_ raw: String) -> String? {
        guard case .waiting = phase else { return nil }
        guard let code = AntigravityLoginTranscript.submission(from: raw) else { return nil }
        phase = .submitting
        return code
    }

    mutating func cancel(now: Date) {
        guard isActive else { return }
        phase = .idle
        browserOpens = 0
        hold = .cancelled(now.addingTimeInterval(Self.retryPause))
    }

    @discardableResult
    mutating func finish(status: Int32, output: String, now: Date) -> Outcome {
        phase = .idle
        browserOpens = 0
        if AntigravityLoginTranscript.unsupportedRegion(output) {
            hold = .unsupportedRegion(now.addingTimeInterval(Self.regionPause))
            return .unsupportedRegion
        }
        if status == 0 {
            hold = .none
            return .signedIn
        }
        if AntigravityLoginTranscript.loginURL(in: output) == nil, output.contains("Usage:") {
            hold = .failed(now.addingTimeInterval(Self.retryPause))
            return .cliTooOld
        }
        hold = .failed(now.addingTimeInterval(Self.retryPause))
        return .failed
    }

    /// A usage probe was told to sign in, or that the region is unsupported.
    /// Further probes wait. A person can still press Sign in, except after
    /// a region refusal, which `finish` records instead.
    mutating func noteProbe(_ reason: ProviderUsage.Unavailability, now: Date) {
        guard case .idle = phase else { return }
        switch reason {
        case .antigravityUnsupportedRegion:
            hold = .unsupportedRegion(now.addingTimeInterval(Self.regionPause))
        case .antigravitySignInRequired:
            hold = .needsSignIn(now.addingTimeInterval(Self.probePause))
        default:
            break
        }
    }
}

/// The running `agy acp --login`, or a stand-in a test drives.
protocol AntigravityLoginRunning: Sendable {
    func output() -> String
    func status() -> Int32?
    func send(_ line: String)
    func stop()
}

/// One Antigravity sign-in, and the gate in front of every usage probe.
///
/// The probe and the sign-in share this so a refresh cannot start `agy`
/// while a page is already open, and a page that failed cannot be opened
/// again by the next tick.
actor AntigravitySession {
    static let shared = AntigravitySession(
        opener: { url in
            #if canImport(AppKit)
            Task { @MainActor in _ = NSWorkspace.shared.open(url) }
            #endif
        },
        launch: { AntigravityLoginChild.start($0) },
        clock: { Date() }
    )

    private var machine = AntigravityLoginMachine()
    private var probeTask: Task<AntigravityUsageService.CLIAnswer, Never>?
    private var running: AntigravityLoginRunning?
    private var queuedCode: String?
    private let opener: @Sendable (URL) -> Void
    private let launch: @Sendable (URL) -> AntigravityLoginRunning?
    private let clock: @Sendable () -> Date
    private var snapshot = AntigravityLoginSnapshot.idle

    init(
        opener: @escaping @Sendable (URL) -> Void,
        launch: @escaping @Sendable (URL) -> AntigravityLoginRunning?,
        clock: @escaping @Sendable () -> Date
    ) {
        self.opener = opener
        self.launch = launch
        self.clock = clock
    }

    func currentSnapshot() -> AntigravityLoginSnapshot { snapshot }

    /// Runs `body` if a probe is allowed, and never two at once. A second
    /// caller waits for the first instead of starting another `agy`.
    func probe(_ body: @escaping @Sendable () async -> AntigravityUsageService.CLIAnswer) async -> AntigravityUsageService.CLIAnswer {
        if let probeTask { return await probeTask.value }
        let now = clock()
        guard machine.mayProbe(now: now) else {
            return .failed(machine.heldProbeReason())
        }
        let task = Task { await body() }
        probeTask = task
        let answer = await task.value
        probeTask = nil
        if case .failed(let reason) = answer {
            machine.noteProbe(reason, now: clock())
        }
        return answer
    }

    /// Starts one sign-in. A second call while it is up does not launch
    /// anything and does not open a page. `onUpdate` is told when the row
    /// should show the paste field.
    func signIn(
        binary: URL?,
        onUpdate: @escaping @MainActor (AntigravityLoginSnapshot) -> Void
    ) async -> AntigravityLoginMachine.Outcome {
        let now = clock()
        // A usage probe already has `agy` running. Starting a sign-in on
        // top of it would be a second process, and a second page.
        if probeTask != nil { return .alreadyRunning }
        switch machine.begin(now: now) {
        case .alreadyRunning:
            return .alreadyRunning
        case .paused(let hold):
            return holdPause(hold)
        case .start:
            break
        }
        await publish(onUpdate)

        guard let binary else {
            // Missing the CLI is not a failed exchange: installing it and
            // pressing Sign in again should work at once, so the pause
            // `finish` would record is thrown away.
            _ = machine.finish(status: 1, output: "", now: clock())
            machine = AntigravityLoginMachine()
            await publish(onUpdate)
            return .missingCLI
        }
        guard let child = launch(binary) else {
            _ = machine.finish(status: 1, output: "", now: clock())
            await publish(onUpdate)
            return .couldNotStart
        }
        running = child

        let startup = ContinuousClock.now + .seconds(30)
        while ContinuousClock.now < startup {
            if !machine.isActive {
                child.stop()
                running = nil
                await publish(onUpdate)
                return .cancelled
            }
            let text = child.output()
            if AntigravityLoginTranscript.unsupportedRegion(text) {
                child.stop()
                running = nil
                let outcome = machine.finish(status: 1, output: text, now: clock())
                await publish(onUpdate)
                return outcome
            }
            if let url = machine.observe(text) {
                opener(url)
                await publish(onUpdate)
                break
            }
            if let status = child.status() {
                running = nil
                let outcome = machine.finish(status: status, output: text, now: clock())
                await publish(onUpdate)
                return outcome
            }
            try? await Task.sleep(for: .milliseconds(40))
        }

        // Waiting, or the code was already pasted while the page was being
        // shown. That paste happens on this actor during `publish`, before
        // this function resumes, so `.submitting` is still this sign-in.
        // Idle means it was cancelled in that same gap: `finish` would
        // replace the cancel with a failure and the next press would be
        // allowed to open another page.
        guard machine.mode == .waiting || machine.mode == .submitting else {
            child.stop()
            running = nil
            await publish(onUpdate)
            return .cancelled
        }

        let codeDeadline = ContinuousClock.now + .seconds(15 * 60)
        var code: String?
        while ContinuousClock.now < codeDeadline {
            if !machine.isActive {
                child.stop()
                running = nil
                await publish(onUpdate)
                return .cancelled
            }
            if let status = child.status() {
                running = nil
                let outcome = machine.finish(status: status, output: child.output(), now: clock())
                await publish(onUpdate)
                return outcome
            }
            if let queued = queuedCode {
                queuedCode = nil
                code = queued
                break
            }
            try? await Task.sleep(for: .milliseconds(40))
        }

        guard let code else {
            child.stop()
            running = nil
            let outcome = machine.isActive
                ? machine.finish(status: 1, output: child.output(), now: clock())
                : AntigravityLoginMachine.Outcome.cancelled
            await publish(onUpdate)
            return outcome
        }

        child.send(code)
        let exchange = ContinuousClock.now + .seconds(60)
        while ContinuousClock.now < exchange {
            if !machine.isActive {
                child.stop()
                running = nil
                await publish(onUpdate)
                return .cancelled
            }
            if let status = child.status() {
                running = nil
                let outcome = machine.finish(status: status, output: child.output(), now: clock())
                await publish(onUpdate)
                return outcome
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
        child.stop()
        running = nil
        let outcome = machine.finish(status: child.status() ?? 1, output: child.output(), now: clock())
        await publish(onUpdate)
        return outcome
    }

    /// Hands `agy` the code. False when nothing is waiting or the paste is
    /// not a single line; the page stays as it is.
    func submit(_ raw: String) -> Bool {
        guard let code = machine.accept(raw) else { return false }
        queuedCode = code
        snapshot.mode = machine.mode
        return true
    }

    func cancel() {
        queuedCode = nil
        machine.cancel(now: clock())
        running?.stop()
        running = nil
        snapshot = AntigravityLoginSnapshot(mode: .idle, notice: .paused)
    }

    private func holdPause(_ hold: AntigravityLoginMachine.Hold) -> AntigravityLoginMachine.Outcome {
        if case .unsupportedRegion = hold { return .unsupportedRegion }
        return .paused
    }

    private func publish(_ onUpdate: @escaping @MainActor (AntigravityLoginSnapshot) -> Void) async {
        snapshot = AntigravityLoginSnapshot(mode: machine.mode, notice: nil)
        let snap = snapshot
        await MainActor.run { onUpdate(snap) }
    }
}

/// `agy acp --login`, with its stdin left open for the code.
///
/// Not `BoundedProcess`: that closes stdin, which is what made the code
/// impossible to deliver. This one stays up until the code is written or
/// the sign-in is cancelled.
final class AntigravityLoginChild: AntigravityLoginRunning, @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let standardOutputPipe = Pipe()
    private let standardErrorPipe = Pipe()
    private let lock = NSLock()
    private var buffer = Data()
    private var statusCode: Int32?
    private var group: Int32?
    private var inputClosed = false

    static func start(_ binary: URL) -> AntigravityLoginChild? {
        let child = AntigravityLoginChild()
        return child.run(binary) ? child : nil
    }

    func output() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: buffer, as: UTF8.self)
    }

    func status() -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        return statusCode
    }

    func send(_ line: String) {
        let data = Data((line + "\n").utf8)
        lock.lock()
        let closed = inputClosed
        lock.unlock()
        guard !closed else { return }
        input.fileHandleForWriting.write(data)
    }

    func stop() {
        lock.lock()
        let processGroup = group
        lock.unlock()
        if let processGroup, processGroup > 1 {
            kill(-processGroup, SIGTERM)
            let until = Date().addingTimeInterval(BoundedProcess.termGrace)
            while kill(-processGroup, 0) == 0, Date() < until {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if kill(-processGroup, 0) == 0 { kill(-processGroup, SIGKILL) }
        } else if process.isRunning {
            process.terminate()
        }
        closeInput()
    }

    private func run(_ binary: URL) -> Bool {
        process.executableURL = binary
        process.arguments = AntigravityLoginTranscript.loginArguments
        var environment = BoundedProcess.environment(leading: binary, over: BoundedProcess.inheritedEnvironment)
        for (key, value) in AntigravityLoginTranscript.loginEnvironment {
            environment[key] = value
        }
        process.environment = environment
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = input
        process.standardOutput = standardOutputPipe
        process.standardError = standardErrorPipe
        process.terminationHandler = { [weak self] process in
            guard let self else { return }
            self.lock.lock()
            self.statusCode = process.terminationStatus
            self.lock.unlock()
        }
        do {
            try process.run()
        } catch {
            return false
        }
        let pid = process.processIdentifier
        let reported = getpgid(pid)
        if pid > 1, reported == pid || (reported == -1 && errno == ESRCH && kill(-pid, 0) == 0) {
            lock.lock()
            group = pid
            lock.unlock()
        }
        for pipe in [standardOutputPipe, standardErrorPipe] {
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    handle.readabilityHandler = nil
                    return
                }
                guard let self else { return }
                self.lock.lock()
                self.buffer.append(chunk)
                self.lock.unlock()
            }
        }
        return true
    }

    private func closeInput() {
        lock.lock()
        let closed = inputClosed
        inputClosed = true
        lock.unlock()
        if !closed { try? input.fileHandleForWriting.close() }
    }
}
