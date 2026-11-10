// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import Testing
@testable import Pulse

/// The login `codex app-server` was started with, without a process.
@Suite("Codex login stamp")
struct CodexLoginStampTests {
    private func login(account: String, token: String) -> Data {
        Data(#"{"tokens":{"account_id":"\#(account)","access_token":"\#(token)"}}"#.utf8)
    }

    @Test("A new token or a new account is a different login, and the stamp is not the token")
    func stampFollowsTheLogin() {
        let first = CodexAppServer.loginStamp(in: login(account: "acct-a", token: "token-a-do-not-keep"))
        let same = CodexAppServer.loginStamp(in: login(account: "acct-a", token: "token-a-do-not-keep"))
        let newToken = CodexAppServer.loginStamp(in: login(account: "acct-a", token: "token-b-do-not-keep"))
        let newAccount = CodexAppServer.loginStamp(in: login(account: "acct-b", token: "token-a-do-not-keep"))
        #expect(first != nil)
        #expect(first == same)
        #expect(first != newToken)
        #expect(first != newAccount)
        #expect(newToken != newAccount)
        let stamp = first ?? ""
        #expect(!stamp.contains("token-a-do-not-keep"))
        #expect(!stamp.contains("acct-a"))
    }

    @Test("A file with no access token, and a missing file, are no login")
    func missingIsNoStamp() throws {
        #expect(CodexAppServer.loginStamp(in: Data("{}".utf8)) == nil)
        #expect(CodexAppServer.loginStamp(in: Data(#"{"tokens":{"account_id":"acct"}}"#.utf8)) == nil)
        #expect(CodexAppServer.loginStamp(in: Data(#"{"tokens":{"access_token":"  "}}"#.utf8)) == nil)
        let absent = FileManager.default.temporaryDirectory
            .appending(path: "pulse-codex-auth-\(UUID().uuidString).json")
        #expect(CodexAppServer.loginStamp(at: absent) == nil)

        let present = FileManager.default.temporaryDirectory
            .appending(path: "pulse-codex-auth-\(UUID().uuidString).json")
        try login(account: "acct", token: "token-kept-only-as-a-hash").write(to: present)
        defer { try? FileManager.default.removeItem(at: present) }
        #expect(CodexAppServer.loginStamp(at: present) == CodexAppServer.loginStamp(in: login(account: "acct", token: "token-kept-only-as-a-hash")))
    }

    @Test("Only a revoked token restarts the helper; the code may sit in the error data")
    func revokedTokenIsTheRefusal() {
        #expect(CodexAppServer.refusesCredentials("401 token_revoked"))
        #expect(CodexAppServer.refusesCredentials("Token_Revoked"))
        #expect(!CodexAppServer.refusesCredentials("fixture refusal"))
        #expect(!CodexAppServer.refusesCredentials("unknown"))

        let messageOnly = CodexAppServer.serverErrorText(["message": "fixture refusal"])
        #expect(messageOnly == "fixture refusal")
        #expect(!CodexAppServer.refusesCredentials(messageOnly))

        let buried = CodexAppServer.serverErrorText([
            "message": "Unauthorized",
            "data": ["error": ["code": "token_revoked"]],
        ])
        #expect(CodexAppServer.refusesCredentials(buried))
        #expect(buried.contains("token_revoked"))

        let coded = CodexAppServer.serverErrorText([
            "code": "token_revoked",
            "message": "Unauthorized",
        ])
        #expect(CodexAppServer.refusesCredentials(coded))
    }
}

/// A changed CLI login, or a revoked token, starts a new helper.
///
/// The helper is `/bin/sh`. It answers `initialize`, then one account call,
/// and it counts how many times it was started. No `codex` and no real login.
@Suite("Codex login refresh", .serialized)
struct CodexLoginRefreshTests {
    private struct Reply: Decodable { let attempt: Int }

    private func server(_ helper: Helper) -> CodexAppServer {
        CodexAppServer(executable: helper.executable, requestTimeout: .seconds(4), authFile: helper.authFile)
    }

    /// Shuts the helper down even when the body throws, so a failed ask does
    /// not leave the shell process in its read loop.
    private func ask(_ helper: Helper, _ body: @Sendable (CodexAppServer) async throws -> Void) async throws {
        let server = server(helper)
        do {
            try await body(server)
        } catch {
            await server.shutDown()
            throw error
        }
        await server.shutDown()
    }

    @Test("A changed auth file restarts the helper; the same login keeps it")
    func loginChangeRestartsHelper() async throws {
        let helper = try Helper(mode: "ok")
        defer { helper.remove() }
        try helper.writeLogin(account: "acct-a", token: "token-a")
        try await ask(helper) { server in
            let first = try JSONDecoder().decode(Reply.self, from: try await server.rateLimits())
            #expect(first.attempt == 1)
            // Rewriting the same login is not a switch.
            try helper.writeLogin(account: "acct-a", token: "token-a")
            let same = try JSONDecoder().decode(Reply.self, from: try await server.rateLimits())
            #expect(same.attempt == 1)
            #expect(helper.attempts() == 1)

            try helper.writeLogin(account: "acct-b", token: "token-b")
            let switched = try JSONDecoder().decode(Reply.self, from: try await server.rateLimits())
            #expect(switched.attempt == 2)
            #expect(helper.attempts() == 2)

            // A new access token for the account already showing is still a new login.
            try helper.writeLogin(account: "acct-b", token: "token-c")
            let refreshed = try JSONDecoder().decode(Reply.self, from: try await server.rateLimits())
            #expect(refreshed.attempt == 3)
            #expect(helper.attempts() == 3)

            let settled = try JSONDecoder().decode(Reply.self, from: try await server.rateLimits())
            #expect(settled.attempt == 3)
            #expect(helper.attempts() == 3)
        }
    }

    @Test("A revoked token starts one new helper and reads again")
    func revokedTokenRetriesOnce() async throws {
        let helper = try Helper(mode: "revoked-once")
        defer { helper.remove() }
        try helper.writeLogin(account: "acct-a", token: "token-a")
        try await ask(helper) { server in
            let reply = try JSONDecoder().decode(Reply.self, from: try await server.rateLimits())
            #expect(reply.attempt == 2)
            #expect(helper.attempts() == 2)
        }
    }

    @Test("A second revoked token is reported, and the helper is not restarted again")
    func revokedTokenDoesNotLoop() async throws {
        let helper = try Helper(mode: "revoked")
        defer { helper.remove() }
        try helper.writeLogin(account: "acct-a", token: "token-a")
        try await ask(helper) { server in
            do {
                _ = try await server.rateLimits()
                Issue.record("a revoked login succeeded")
            } catch CodexAppServer.Failure.server(let message) {
                #expect(CodexAppServer.refusesCredentials(message))
            }
            #expect(helper.attempts() == 2)
        }
    }

    private struct Helper: Sendable {
        let root: URL
        let executable: URL
        let authFile: URL
        var countFile: URL { URL(fileURLWithPath: executable.path + ".count") }

        init(mode: String) throws {
            root = FileManager.default.temporaryDirectory.appending(path: "PulseCodexLogin-\(UUID().uuidString)")
            executable = root.appending(path: "helper")
            authFile = root.appending(path: "auth.json")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let script = #"""
            #!/bin/sh
            attempt=$(/bin/cat "$0.count" 2>/dev/null || printf '0')
            attempt=$((attempt + 1))
            printf '%s' "$attempt" > "$0.count"
            mode=$(/bin/cat "$0.mode" 2>/dev/null || printf 'ok')
            n=0
            while IFS= read -r line; do
                id=$(printf '%s\n' "$line" | /usr/bin/sed -n 's/.*"id":[[:space:]]*\([0-9][0-9]*\).*/\1/p')
                [ -n "$id" ] || continue
                n=$((n + 1))
                if [ "$n" -eq 1 ]; then
                    printf '{"id":%s,"result":{}}\n' "$id"
                    continue
                fi
                refuse=0
                if [ "$mode" = "revoked" ]; then
                    refuse=1
                fi
                if [ "$mode" = "revoked-once" ] && [ "$attempt" -eq 1 ]; then
                    refuse=1
                fi
                if [ "$refuse" -eq 1 ]; then
                    printf '{"id":%s,"error":{"message":"401 token_revoked"}}\n' "$id"
                    continue
                fi
                printf '{"id":%s,"result":{"attempt":%s}}\n' "$id" "$attempt"
            done
            """#
            try Data(script.utf8).write(to: executable)
            try Data(mode.utf8).write(to: URL(fileURLWithPath: executable.path + ".mode"))
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        }

        func writeLogin(account: String, token: String) throws {
            let body = #"{"tokens":{"account_id":"\#(account)","access_token":"\#(token)"}}"#
            try Data(body.utf8).write(to: authFile)
        }

        func attempts() -> Int {
            Int(String(decoding: (try? Data(contentsOf: countFile)) ?? Data(), as: UTF8.self)) ?? 0
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
