// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import Testing
@testable import Pulse

/// Antigravity's sign-in must open one page, and a failed or repeated start
/// must not open another. The activity mark is not part of this: it only
/// reads conversation databases.
@Suite("Antigravity sign-in")
struct AntigravityLoginTests {
    private let page = "https://accounts.google.com/o/oauth2/auth?client_id=example&redirect_uri=https%3A%2F%2Fantigravity.google%2Foauth-callback"

    @Test("The sign-in URL is the Google page, once, and a code is one line")
    func transcript() {
        let text = "Please visit the URL to log in:\n\(page)\n"
        #expect(AntigravityLoginTranscript.loginURL(in: text) == URL(string: page))
        #expect(AntigravityLoginTranscript.loginURL(in: text + "\n" + page) == URL(string: page))
        #expect(AntigravityLoginTranscript.asksToSignIn("Authentication required. Please visit the URL to log in:"))
        #expect(!AntigravityLoginTranscript.asksToSignIn(#"{"status":"SUCCESS","command":{"name":"usage"}}"#))
        #expect(AntigravityLoginTranscript.unsupportedRegion("Antigravity is not available in your region."))
        #expect(AntigravityLoginTranscript.unsupportedRegion("这个账号所在的地区无法使用"))
        // A copy from the page often carries a trailing line break. A paste
        // of several lines is a different thing and is not a code.
        #expect(AntigravityLoginTranscript.submission(from: "  abcd-1234 \n") == "abcd-1234")
        #expect(AntigravityLoginTranscript.submission(from: " abcd-1234 ") == "abcd-1234")
        #expect(AntigravityLoginTranscript.submission(from: "abcd\n1234") == nil)
        #expect(AntigravityLoginTranscript.submission(from: " ") == nil)
    }

    @Test("A sign-in opens one page, and printing the link again does not open another")
    func onePage() {
        var machine = AntigravityLoginMachine()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(machine.begin(now: now) == .start)
        let first = machine.observe("open \(page)")
        #expect(first == URL(string: page))
        #expect(machine.browserOpens == 1)
        #expect(machine.observe("open \(page) again \(page)") == nil)
        #expect(machine.browserOpens == 1)
        for _ in 0..<20 {
            #expect(machine.begin(now: now) == .alreadyRunning)
        }
        #expect(machine.browserOpens == 1)
    }

    @Test("A failure, a cancel, or an unsupported region does not start another page")
    func noImmediateRetry() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        for sample in ["error: something failed", "not available in your country", ""] {
            var machine = AntigravityLoginMachine()
            #expect(machine.begin(now: now) == .start)
            _ = machine.observe(page)
            if sample.isEmpty {
                machine.cancel(now: now)
            } else {
                _ = machine.finish(status: 1, output: sample, now: now)
            }
            #expect(machine.begin(now: now) != .start)
            #expect(!machine.mayProbe(now: now))
            let later = now.addingTimeInterval(sample.contains("country") ? 15 * 60 : 30)
            #expect(machine.begin(now: later) == .start)
            #expect(machine.observe("not available in your region \(page)") == nil)
        }
    }

    @Test("A probe that was told to sign in waits, and Sign in is still allowed once")
    func probeHoldsWithoutBlockingTheButton() {
        var machine = AntigravityLoginMachine()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        machine.noteProbe(.antigravitySignInRequired, now: now)
        #expect(!machine.mayProbe(now: now))
        #expect(machine.heldProbeReason() == .antigravitySignInRequired)
        #expect(machine.begin(now: now) == .start)
        _ = machine.finish(status: 0, output: page, now: now)
        #expect(machine.mayProbe(now: now))

        machine.noteProbe(.antigravityUnsupportedRegion, now: now)
        #expect(machine.begin(now: now) == .paused(.unsupportedRegion(now.addingTimeInterval(15 * 60))))
        #expect(!machine.mayProbe(now: now))
    }

    @Test("One sign-in opens one page, and a failure does not open another")
    func sessionDoesNotStorm() async {
        let opened = OpenedPages()
        let clock = LoginClock(Date(timeIntervalSince1970: 1_700_000_000))
        let link = page
        let session = AntigravitySession(
            opener: { opened.add($0) },
            launch: { _ in ScriptedAntigravityLogin(link) },
            clock: { clock.date }
        )
        let binary = URL(fileURLWithPath: "/tmp/agy")
        let first = Task { await session.signIn(binary: binary) { _ in } }
        #expect(await waitForWaiting(session))
        #expect(opened.count == 1)
        #expect(await session.signIn(binary: binary) { _ in } == .alreadyRunning)
        #expect(await session.signIn(binary: binary) { _ in } == .alreadyRunning)
        #expect(opened.count == 1)
        await session.cancel()
        #expect(await first.value == .cancelled)
        #expect(await session.signIn(binary: binary) { _ in } == .paused)
        #expect(opened.count == 1)

        clock.date.addTimeInterval(31)
        let second = Task { await session.signIn(binary: binary) { _ in } }
        #expect(await waitForWaiting(session))
        #expect(opened.count == 2)
        #expect(await session.submit("abcd-1234"))
        #expect(await second.value == .signedIn)
    }

    @Test("A region refusal opens no page, and the next start opens none either")
    func regionOpensNothing() async {
        let opened = OpenedPages()
        let link = page
        let session = AntigravitySession(
            opener: { opened.add($0) },
            launch: { _ in ScriptedAntigravityLogin("Antigravity is not available in your region. \(link)") },
            clock: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let binary = URL(fileURLWithPath: "/tmp/agy")
        #expect(await session.signIn(binary: binary) { _ in } == .unsupportedRegion)
        #expect(opened.count == 0)
        #expect(await session.signIn(binary: binary) { _ in } == .unsupportedRegion)
        #expect(opened.count == 0)
    }

    @Test("Two usage probes share one run, and a sign-in answer holds the next")
    func probesDoNotStack() async {
        let runs = ProbeRuns()
        let session = AntigravitySession(opener: { _ in }, launch: { _ in nil }, clock: { Date() })
        async let first = session.probe {
            runs.add()
            try? await Task.sleep(for: .milliseconds(80))
            return .failed(.antigravitySignInRequired)
        }
        async let second = session.probe {
            runs.add()
            return .failed(.unreadableReply)
        }
        let (a, b) = await (first, second)
        #expect(a == .failed(.antigravitySignInRequired))
        #expect(b == a)
        #expect(runs.count == 1)
        let third = await session.probe {
            runs.add()
            return .noLimits
        }
        #expect(third == .failed(.antigravitySignInRequired))
        #expect(runs.count == 1)
    }

    private func waitForWaiting(_ session: AntigravitySession) async -> Bool {
        for _ in 0..<50 {
            if await session.currentSnapshot().mode == .waiting { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }
}

private final class OpenedPages: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    func add(_ url: URL) {
        lock.lock()
        urls.append(url)
        lock.unlock()
    }
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return urls.count
    }
}

private final class ProbeRuns: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func add() {
        lock.lock()
        value += 1
        lock.unlock()
    }
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class LoginClock: @unchecked Sendable {
    var date: Date
    init(_ date: Date) { self.date = date }
}

private final class ScriptedAntigravityLogin: AntigravityLoginRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let text: String
    private var code: Int32?
    init(_ text: String) { self.text = text }
    func output() -> String { text }
    func status() -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        return code
    }
    func send(_ line: String) {
        lock.lock()
        code = 0
        lock.unlock()
    }
    func stop() {
        lock.lock()
        if code == nil { code = 1 }
        lock.unlock()
    }
}
