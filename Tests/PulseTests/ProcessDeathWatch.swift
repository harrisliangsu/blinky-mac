// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import Darwin
@testable import Pulse

/// When a spawned process actually died, timed from a thread of its own.
///
/// **Why not time the `await`.** A runner's deadline is enforced on a global
/// queue, but the caller only learns of it when its task resumes, and that
/// needs a free cooperative thread. Swift Testing runs synchronous tests on
/// that pool too, so on a three-core CI runner a few long ones held it for
/// ~19 seconds and every test that started meanwhile — pure parsing ones
/// included — reported 18–19 seconds. A child killed at three seconds was
/// measured at twenty-two and failed `< 20` (the 1.12.1 build, 2026-10-16).
/// Saturating the pool locally reproduces it: the child dies on time, the
/// caller resumes when the pool frees.
///
/// So the claim "killed at the deadline" is timed here, by polling `kill(pid,
/// 0)` on a dedicated thread that no test can starve. The script writes its
/// own pid to `pidFile`; anything still alive at `giveUpAfter` is killed so a
/// failing test does not leak it.
///
/// **The clock it is compared with has to start just as late.** This instant
/// is not, by itself, how long the program was given. A clock started before
/// `run` or `fetch` still includes the wait for a utility-QoS thread, and
/// that wait is not the time limit — the 1.4.28 Build measured 12.9 seconds
/// that way, with the program already dead and the call back under a second
/// later. `OwnThreadTiming` starts its clock on the thread that runs the
/// synchronous runner, and the tests subtract that.
///
/// **A program stopped before its first line writes no pid.** On a loaded
/// machine `/bin/sh` can take longer than a one-second deadline to start, so
/// the runner kills it before `echo $$` runs — correctly — and a watch waiting
/// for the pid waited thirty seconds and called it a survivor. That failed
/// most local full runs of 1.12.5's checks. So the caller says when the run
/// has returned (`runReturned()`); by then the runner has stopped the whole
/// group, and a pid still unwritten a moment later never will be: the watch
/// ends with `neverStarted` set instead.
final class ProcessDeathWatch: @unchecked Sendable {
    let pidFile: URL
    private let lock = NSLock()
    private var outcome: ContinuousClock.Instant??
    private var waiter: CheckedContinuation<ContinuousClock.Instant?, Never>?
    private var returnedAt: ContinuousClock.Instant?
    private var stoppedEarly = false

    /// Read after `death`: the program was stopped before it wrote its pid,
    /// so there was nothing left to outlive the run.
    var neverStarted: Bool { lock.withLock { stoppedEarly } }

    /// The run has returned. See the type's comment.
    func runReturned() {
        lock.withLock { if returnedAt == nil { returnedAt = .now } }
    }

    init(giveUpAfter: Duration = .seconds(30)) {
        pidFile = FileManager.default.temporaryDirectory.appending(path: "pulse-watched-\(UUID()).pid")
        let thread = Thread { [self] in watch(until: .now + giveUpAfter) }
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    /// The moment the process was first seen gone, or nil if it outlived the
    /// watch. Waits for the watch to finish; the instant itself was taken on
    /// the watching thread, so a slow resumption here cannot inflate it.
    var death: ContinuousClock.Instant? {
        get async {
            await withCheckedContinuation { continuation in
                let finished: ContinuousClock.Instant?? = lock.withLock {
                    if outcome == nil { waiter = continuation }
                    return outcome
                }
                if let finished { continuation.resume(returning: finished) }
            }
        }
    }

    private func watch(until giveUp: ContinuousClock.Instant) {
        var pid: Int32?
        while ContinuousClock.now < giveUp {
            if pid == nil,
               let text = try? String(contentsOf: pidFile, encoding: .utf8),
               let written = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), written > 1 {
                pid = written
            }
            if let pid, kill(pid, 0) == -1, errno == ESRCH {
                return finish(.now)
            }
            if pid == nil, let returnedAt = lock.withLock({ returnedAt }),
               ContinuousClock.now > returnedAt + .seconds(2) {
                lock.withLock { stoppedEarly = true }
                return finish(nil)
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        if let pid { kill(pid, SIGKILL) }
        finish(nil)
    }

    private func finish(_ instant: ContinuousClock.Instant?) {
        try? FileManager.default.removeItem(at: pidFile)
        let waiting = lock.withLock {
            outcome = .some(instant)
            defer { waiter = nil }
            return waiter
        }
        waiting?.resume(returning: instant)
    }
}

/// How long a synchronous runner took, measured on a thread of its own.
///
/// `run` and `fetch` queue on a utility-QoS queue before the deadline starts,
/// and the caller only resumes when a cooperative thread is free. Either wait
/// has exceeded the kill's own budget on a loaded CI runner. The clock in
/// `measure` starts inside the thread that does the work. Waiting for that
/// thread, or for `measure` to resume, is not part of `elapsed`.
enum OwnThreadTiming {
    /// How long creating the process may take on a busy runner, before its
    /// deadline starts. Not slack for the kill. That budget is
    /// `BoundedProcess.escalationBudget`.
    static let creationAllowance: TimeInterval = 5

    /// Longer than `ProcessDeathWatch`'s thirty-second backstop. A runner that
    /// never stops its child comes back after that backstop and fails the
    /// ceiling; this fires only when the call never comes back at all.
    static let hangLimit: TimeInterval = 45

    /// The deadline, then every wait the runner still has, then process creation.
    static func ceiling(deadline: TimeInterval) -> TimeInterval {
        deadline + BoundedProcess.escalationBudget + creationAllowance
    }

    /// Runs `body` on a new user-initiated thread. Returns nil when `body` is
    /// still going after `limit`. The wait for that sits on a dispatch queue,
    /// not the cooperative pool — blocking the pool is the stall this exists
    /// to keep out of the measurement.
    static func measure<Value>(
        givingUpAfter limit: TimeInterval = hangLimit,
        _ body: @escaping () -> Value
    ) async -> OwnThreadSample<Value>? {
        let work = OwnThreadWork(body)
        let thread = Thread { work.run() }
        thread.qualityOfService = .userInitiated
        thread.start()

        let finished: Bool = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let done = work.finished.wait(timeout: .now() + limit) == .success
                continuation.resume(returning: done)
            }
        }
        guard finished, let outcome = work.take() else { return nil }
        return OwnThreadSample(value: outcome.value, started: outcome.started, elapsed: outcome.elapsed)
    }
}

/// The result of `OwnThreadTiming.measure`, taken on the runner thread.
struct OwnThreadSample<Value>: @unchecked Sendable {
    let value: Value
    /// Taken on the runner thread, before it did the work.
    let started: ContinuousClock.Instant
    /// How long that thread spent doing the work.
    let elapsed: Duration
}

/// Written on the runner thread, read after `finished` has been signalled.
private final class OwnThreadWork<Value>: @unchecked Sendable {
    private let body: () -> Value
    private let lock = NSLock()
    private var outcome: (value: Value, started: ContinuousClock.Instant, elapsed: Duration)?
    let finished = DispatchSemaphore(value: 0)

    init(_ body: @escaping () -> Value) {
        self.body = body
    }

    func run() {
        let started = ContinuousClock.now
        let value = body()
        let elapsed = started.duration(to: .now)
        lock.lock()
        outcome = (value, started, elapsed)
        lock.unlock()
        finished.signal()
    }

    func take() -> (value: Value, started: ContinuousClock.Instant, elapsed: Duration)? {
        lock.lock()
        defer { lock.unlock() }
        return outcome
    }
}
