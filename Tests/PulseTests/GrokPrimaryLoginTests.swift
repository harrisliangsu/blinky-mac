import Foundation
import Testing
@testable import Pulse

/// Primary Grok's automatic route: the CLI's access token first, then the
/// login Blinky holds. The CLI file is only ever read.
@Suite("Grok primary login")
struct GrokPrimaryLoginTests {
    private final class Exchange: @unchecked Sendable {
        var authorizations: [String] = []
        var tokenAuth: [String] = []
        let lock = NSLock()
        var statusForToken: [String: Int] = [:]
        let billing: Data
        let settings = Data(#"{"subscription_tier_display":"SuperGrok"}"#.utf8)

        init(billing: Data) { self.billing = billing }

        func send(_ request: URLRequest) -> (Data, URLResponse) {
            let authorization = request.value(forHTTPHeaderField: "Authorization") ?? ""
            let mark = request.value(forHTTPHeaderField: "x-xai-token-auth") ?? ""
            lock.withLock {
                authorizations.append(authorization)
                tokenAuth.append(mark)
            }
            let path = request.url?.path ?? ""
            let status: Int
            let body: Data
            if path.hasSuffix("settings") {
                status = 200
                body = settings
            } else {
                let token = authorization.replacingOccurrences(of: "Bearer ", with: "")
                status = statusForToken[token] ?? 200
                body = status == 200 ? billing : Data()
            }
            let url = request.url ?? URL(string: "https://cli-chat-proxy.grok.com/v1/billing")!
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (body, response)
        }
    }

    private final class Renewals: @unchecked Sendable {
        var count = 0
        var refreshTokens: [String] = []
        let lock = NSLock()
        var result: AccountCredentials?

        func renew(_ credentials: AccountCredentials) -> AccountCredentials? {
            lock.withLock {
                count += 1
                refreshTokens.append(credentials.refreshToken)
            }
            return result
        }
    }

    private static func billing() throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: "grok-billing-weekly", withExtension: "json", subdirectory: "Fixtures"
        ))
        return try Data(contentsOf: url)
    }

    private func login(_ token: String, refresh: String, fresh: Bool) -> AccountCredentials {
        AccountCredentials(
            accessToken: token,
            refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(fresh ? 3_600 : 10),
            accountName: "reader@example.com"
        )
    }

    /// Writes a stand-in for `~/.grok/auth.json`. `refresh` is present so a
    /// test can see it was not the token that got sent, and was not replaced.
    private func authFile(token: String, expires: String, refresh: String = "cli-refresh-do-not-copy") throws -> (url: URL, bytes: Data) {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "grok-auth-\(UUID().uuidString).json")
        let json = """
        {"issuer|client":{"key":"\(token)","refresh_token":"\(refresh)","expires_at":"\(expires)"}}
        """
        let bytes = Data(json.utf8)
        try bytes.write(to: url)
        return (url, bytes)
    }

    private func service(
        authFile: URL,
        exchange: Exchange,
        credentials: AccountCredentials?,
        renewals: Renewals
    ) -> GrokUsageService {
        var service = GrokUsageService(authFile: authFile)
        service.transport = { exchange.send($0) }
        service.primaryCredentials = { credentials }
        service.renewPrimary = { renewals.renew($0) }
        return service
    }

    private func unchanged(_ url: URL, _ before: Data) throws {
        let after = try Data(contentsOf: url)
        #expect(after == before)
    }

    @Test("A usable CLI token is the reading, and Blinky's login is not asked")
    func cliTokenSucceedsWithoutBlinky() async throws {
        let exchange = Exchange(billing: try Self.billing())
        let renewals = Renewals()
        let (url, before) = try authFile(token: "cli-token", expires: "2099-01-01T00:00:00Z")
        let held = login("blinky-token", refresh: "blinky-refresh", fresh: true)
        let usage = await service(authFile: url, exchange: exchange, credentials: held, renewals: renewals)
            .fetch(source: .automatic)

        #expect(usage.state == .live)
        #expect(usage.plan == "SuperGrok")
        #expect(abs((usage.windows.first?.usedFraction ?? -1) - 0.425) < 0.000_001)
        #expect(usage.origin == .endpoint)
        #expect(usage.attempts.map(\.route) == [.endpoint])
        #expect(exchange.authorizations.allSatisfy { $0 == "Bearer cli-token" })
        #expect(exchange.tokenAuth.allSatisfy { $0 == "xai-grok-cli" })
        #expect(!exchange.authorizations.isEmpty)
        #expect(renewals.count == 0)
        try unchanged(url, before)
    }

    @Test("An expired CLI file falls through to a fresh Blinky login")
    func expiredCLIUsesBlinkyLogin() async throws {
        let exchange = Exchange(billing: try Self.billing())
        let renewals = Renewals()
        let (url, before) = try authFile(token: "expired-token", expires: "2020-01-01T00:00:00Z")
        let held = login("blinky-token", refresh: "blinky-refresh", fresh: true)
        let usage = await service(authFile: url, exchange: exchange, credentials: held, renewals: renewals)
            .fetch(source: .automatic)

        #expect(usage.state == .live)
        #expect(usage.origin == .heldLogin)
        #expect(usage.attempts.map(\.route) == [.endpoint, .heldLogin])
        #expect(usage.attempts[0].state == .unavailable(.grokLoginExpired))
        #expect(exchange.authorizations.allSatisfy { $0 == "Bearer blinky-token" })
        #expect(!exchange.authorizations.contains("Bearer expired-token"))
        #expect(renewals.count == 0)
        try unchanged(url, before)
        #expect(!String(decoding: before, as: UTF8.self).contains("blinky-refresh"))
    }

    @Test("A refused CLI token falls through, and the CLI file is not rewritten")
    func refusedCLIUsesBlinkyLogin() async throws {
        let exchange = Exchange(billing: try Self.billing())
        exchange.statusForToken["cli-token"] = 401
        let renewals = Renewals()
        let (url, before) = try authFile(token: "cli-token", expires: "2099-01-01T00:00:00Z")
        let held = login("blinky-token", refresh: "blinky-refresh", fresh: true)
        let usage = await service(authFile: url, exchange: exchange, credentials: held, renewals: renewals)
            .fetch(source: .automatic)

        #expect(usage.state == .live)
        #expect(usage.origin == .heldLogin)
        #expect(exchange.authorizations.first == "Bearer cli-token")
        #expect(exchange.authorizations.contains("Bearer blinky-token"))
        #expect(renewals.refreshTokens.isEmpty)
        try unchanged(url, before)
        let text = String(decoding: before, as: UTF8.self)
        #expect(text.contains("cli-refresh-do-not-copy"))
        #expect(!text.contains("blinky-refresh"))
    }

    @Test("CLI and Blinky both missing asks for one Settings sign-in")
    func bothMissingAsksForSettings() async throws {
        let exchange = Exchange(billing: try Self.billing())
        let renewals = Renewals()
        let url = FileManager.default.temporaryDirectory
            .appending(path: "grok-missing-\(UUID().uuidString).json")
        let usage = await service(authFile: url, exchange: exchange, credentials: nil, renewals: renewals)
            .fetch(source: .automatic)

        #expect(usage.state == .unavailable(.grokAccountSignInRequired))
        #expect(usage.attempts.map(\.route) == [.endpoint, .heldLogin])
        #expect(usage.attempts[0].state == .unavailable(.grokSignInRequired))
        #expect(exchange.authorizations.isEmpty)
        #expect(renewals.count == 0)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(ConnectionRemedy.forReason(.grokAccountSignInRequired, account: AccountKey(.grok)) == .signIn)
        #expect(ConnectionRemedy.forReason(.grokSignInRequired, account: AccountKey(.grok)) == .copyCommand("grok"))
        #expect(ConnectionRemedy.forReason(.grokLoginExpired, account: AccountKey(.grok)) == .copyCommand("grok"))
    }

    @Test("A stale Blinky login is refreshed, and the new token is what is sent")
    func staleBlinkyLoginIsRefreshed() async throws {
        let exchange = Exchange(billing: try Self.billing())
        let renewals = Renewals()
        renewals.result = login("renewed-token", refresh: "rotated-refresh", fresh: true)
        let (url, before) = try authFile(token: "expired-token", expires: "2020-01-01T00:00:00Z")
        let held = login("stale-token", refresh: "blinky-refresh", fresh: false)
        let usage = await service(authFile: url, exchange: exchange, credentials: held, renewals: renewals)
            .fetch(source: .automatic)

        #expect(usage.state == .live)
        #expect(usage.origin == .heldLogin)
        #expect(exchange.authorizations.allSatisfy { $0 == "Bearer renewed-token" })
        #expect(!exchange.authorizations.contains("Bearer stale-token"))
        #expect(!exchange.authorizations.contains("Bearer expired-token"))
        #expect(renewals.count == 1)
        #expect(renewals.refreshTokens == ["blinky-refresh"])
        try unchanged(url, before)
        let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        #expect(text.contains("cli-refresh-do-not-copy"))
        #expect(!text.contains("rotated-refresh"))
        #expect(!text.contains("blinky-refresh"))
    }

    @Test("A Blinky token the proxy refuses is refreshed once")
    func refusedBlinkyLoginIsRefreshed() async throws {
        let exchange = Exchange(billing: try Self.billing())
        exchange.statusForToken["blinky-token"] = 401
        let renewals = Renewals()
        renewals.result = login("renewed-token", refresh: "rotated-refresh", fresh: true)
        let (url, before) = try authFile(token: "expired-token", expires: "2020-01-01T00:00:00Z")
        let held = login("blinky-token", refresh: "blinky-refresh", fresh: true)
        let usage = await service(authFile: url, exchange: exchange, credentials: held, renewals: renewals)
            .fetch(source: .automatic)

        #expect(usage.state == .live)
        #expect(renewals.count == 1)
        #expect(renewals.refreshTokens == ["blinky-refresh"])
        #expect(exchange.authorizations.contains("Bearer blinky-token"))
        #expect(exchange.authorizations.contains("Bearer renewed-token"))
        try unchanged(url, before)
    }

    @Test("A Blinky login that will not refresh says to sign in again")
    func failedRefreshSaysSignInAgain() async throws {
        let exchange = Exchange(billing: try Self.billing())
        let renewals = Renewals()
        let (url, before) = try authFile(token: "expired-token", expires: "2020-01-01T00:00:00Z")
        let held = login("stale-token", refresh: "blinky-refresh", fresh: false)
        let usage = await service(authFile: url, exchange: exchange, credentials: held, renewals: renewals)
            .fetch(source: .automatic)

        #expect(usage.state == .unavailable(.grokAccountLoginExpired))
        #expect(exchange.authorizations.isEmpty)
        #expect(renewals.count == 1)
        #expect(ConnectionRemedy.forReason(.grokAccountLoginExpired, account: AccountKey(.grok)) == .signIn)
        try unchanged(url, before)
    }

    @Test("Pinned to the CLI, an expired file stays expired even when Blinky has a login")
    func pinnedCLIDoesNotUseBlinky() async throws {
        let exchange = Exchange(billing: try Self.billing())
        let renewals = Renewals()
        let (url, before) = try authFile(token: "expired-token", expires: "2020-01-01T00:00:00Z")
        let held = login("blinky-token", refresh: "blinky-refresh", fresh: true)
        let usage = await service(authFile: url, exchange: exchange, credentials: held, renewals: renewals)
            .fetch(source: .endpoint)

        #expect(usage.state == .unavailable(.grokLoginExpired))
        #expect(usage.attempts.map(\.route) == [.endpoint])
        #expect(exchange.authorizations.isEmpty)
        #expect(renewals.count == 0)
        try unchanged(url, before)
    }

    @Test("A server error on the CLI token is not treated as a refused login")
    func serverErrorDoesNotFallThrough() async throws {
        let exchange = Exchange(billing: try Self.billing())
        exchange.statusForToken["cli-token"] = 500
        let renewals = Renewals()
        let (url, before) = try authFile(token: "cli-token", expires: "2099-01-01T00:00:00Z")
        let held = login("blinky-token", refresh: "blinky-refresh", fresh: true)
        let usage = await service(authFile: url, exchange: exchange, credentials: held, renewals: renewals)
            .fetch(source: .automatic)

        #expect(usage.state == .unavailable(.serverError))
        #expect(exchange.authorizations == ["Bearer cli-token"])
        #expect(renewals.count == 0)
        try unchanged(url, before)
    }

    @Test("An added account uses the token it was handed and does not open the CLI file")
    func addedAccountIgnoresCLIFile() async throws {
        let exchange = Exchange(billing: try Self.billing())
        let renewals = Renewals()
        let (url, before) = try authFile(token: "cli-token", expires: "2099-01-01T00:00:00Z")
        let held = login("blinky-token", refresh: "blinky-refresh", fresh: true)
        let service = service(authFile: url, exchange: exchange, credentials: held, renewals: renewals)
        let usage = await service.fetch(account: AccountKey(.grok, slot: "work"), token: "added-token")

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.grok, slot: "work"))
        #expect(exchange.authorizations.allSatisfy { $0 == "Bearer added-token" })
        #expect(renewals.count == 0)
        try unchanged(url, before)
    }

    @Test("Read usage from names Automatic as CLI, then Blinky's login")
    func sourceNames() {
        #expect(Provider.grok.hasSourceChoice)
        #expect(Provider.grok.soleRoute == nil)
        #expect(UsageSource.options(for: AccountKey(.grok)) == [.automatic, .endpoint, .tooling])
        #expect(UsageSource.automatic.title(for: .grok) == String.localized("Automatic"))
        #expect(UsageSource.endpoint.title(for: .grok) == String.localized("CLI login"))
        #expect(UsageSource.tooling.title(for: .grok) == String.localized("Blinky login"))
        #expect(UsageSource.automatic.detail(for: .grok) == String.localized(
            "Uses the CLI login while it is still good, then the login Blinky holds."
        ))
        #expect(UsageRoute.heldLogin.title == String.localized("Blinky login"))
        #expect(AlertMemory.standing(of: .grokAccountSignInRequired) == .neutral)
        #expect(AlertMemory.standing(of: .grokAccountLoginExpired) == .failure)
    }
}
