// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import Testing
@testable import Pulse

/// Zhipu and z.ai quota reset cards, from the console list.
///
/// The body is the list captured from the mainland console and the same
/// object z.ai documents. Nothing here calls a live host.
@Suite("Zhipu reset cards")
struct ZhipuResetCardTests {
    private static let now = Date(timeIntervalSince1970: 1_761_264_000) // 2025-10-24 00:00 UTC

    @Test("A list counts only an available card whose expiry is still ahead")
    func parsesBothKinds() throws {
        let data = Data(Self.list.utf8)
        let parsed = try #require(ZhipuResetCards.parse(data, now: Self.now))
        #expect(parsed.fiveHour.map(\.recordID) == [11])
        #expect(parsed.weekly.map(\.recordID) == [22])
        #expect(parsed.fiveHour[0].grantType == "GLOBAL")
        #expect(parsed.weekly[0].grantType == "GLOBAL")
        #expect(parsed.fiveHour[0].expiresAt == ZhipuResetCards.expiry("2026-10-25 08:00:00"))
    }

    @Test("Expiry is a wall clock in China Standard Time")
    func expiryIsChinaStandardTime() {
        let date = ZhipuResetCards.expiry("2026-01-02 03:04:05")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ZhipuResetCards.expiryTimeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date!)
        #expect(parts.year == 2026)
        #expect(parts.month == 1)
        #expect(parts.day == 2)
        #expect(parts.hour == 3)
        #expect(parts.minute == 4)
        #expect(parts.second == 5)
        #expect(ZhipuResetCards.expiry("not a date") == nil)
        #expect(ZhipuResetCards.expiry(1_700_000_000) == nil)
    }

    @Test("Spent, expired, and unnamed rows are left out of the count")
    func dropsUnusableRows() throws {
        let parsed = try #require(ZhipuResetCards.parse(Data(Self.mixed.utf8), now: Self.now))
        #expect(parsed.fiveHour.map(\.id) == ["11"])
        #expect(parsed.weekly.isEmpty)
    }

    @Test("Empty arrays are a reported zero, and a body without the lists is not")
    func emptyIsReported() {
        let empty = ZhipuResetCards.parse(Data(Self.empty.utf8), now: Self.now)
        #expect(empty?.fiveHour.isEmpty == true)
        #expect(empty?.weekly.isEmpty == true)
        #expect(ZhipuResetCards.parse(Data(#"{"success":true,"code":200,"data":{}}"#.utf8)) == nil)
        #expect(ZhipuResetCards.parse(Data(#"{"success":false,"code":500}"#.utf8)) == nil)
        #expect(ZhipuResetCards.parse(Data("not json".utf8)) == nil)
    }

    @Test("Each storefront is asked on its own host, mainland on the quota host first")
    func listURLs() {
        #expect(ZhipuResetCards.listURLs(for: .zai).map(\.absoluteString) == [
            "https://api.z.ai/api/biz/customer-package-reset/list?targetType=PERSONAL",
        ])
        #expect(ZhipuResetCards.listURLs(for: .glmCoding).map(\.host) == [
            "open.bigmodel.cn", "bigmodel.cn",
        ])
        #expect(ZhipuResetCards.listURLs(for: .codex).isEmpty)
        #expect(ZhipuResetCards.consoleURL(for: .zai)?.absoluteString == "https://z.ai")
        #expect(ZhipuResetCards.consoleURL(for: .glmCoding)?.absoluteString == "https://open.bigmodel.cn")
    }

    @Test("The first host that returns a list is the one a use posts to")
    func firstReported() async throws {
        let urls = ZhipuResetCards.listURLs(for: .glmCoding)
        var asked: [String] = []
        let inventory = await ZhipuResetCards.firstReported(urls: urls, now: Self.now) { url in
            asked.append(url.host ?? "")
            if url.host == "open.bigmodel.cn" { return Data("no".utf8) }
            return Data(Self.empty.utf8)
        }
        let found = try #require(inventory)
        #expect(asked == ["open.bigmodel.cn", "bigmodel.cn"])
        #expect(found.serviceHost == "https://bigmodel.cn")
        #expect(found.fiveHour.isEmpty)
        #expect(found.soonest(.weeklyCard) == nil)
    }

    @Test("Use sends the captured body, and a missing route is not a spent card")
    func useBodyAndVerdict() throws {
        let card = ZhipuResetCard(id: "22", recordID: 22, grantType: "GLOBAL", expiresAt: Self.now)
        let week = ZhipuResetCards.useBody(kind: .weeklyCard, card: card, requestID: "req-1")
        #expect(week["targetType"] as? String == "PERSONAL")
        #expect(week["resetType"] as? String == "WEEK")
        #expect(week["recordId"] as? Int == 22)
        #expect(week["grantType"] as? String == "GLOBAL")
        #expect(week["requestId"] as? String == "req-1")
        let hour = ZhipuResetCard(id: "11", recordID: 11, grantType: "", expiresAt: Self.now)
        let five = ZhipuResetCards.useBody(kind: .fiveHourCard, card: hour, requestID: "req-2")
        #expect(five["resetType"] as? String == "FIVE_HOUR")
        #expect(five["grantType"] == nil)
        let encoded = try JSONSerialization.data(withJSONObject: week)
        let again = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(again["recordId"] as? Int == 22)

        #expect(ZhipuResetCards.interpretUse(status: 200, body: Data(#"{"code":200,"success":true}"#.utf8)) == .used)
        #expect(ZhipuResetCards.interpretUse(status: 200, body: Data(#"{"code":0,"success":true}"#.utf8)) == .used)
        #expect(ZhipuResetCards.interpretUse(status: 404, body: Data()) == .unavailable)
        #expect(ZhipuResetCards.interpretUse(status: 405, body: Data()) == .unavailable)
        #expect(ZhipuResetCards.interpretUse(status: 500, body: Data(#"{"success":false}"#.utf8)) == .failed)
        #expect(ZhipuResetCards.interpretUse(status: 200, body: Data(#"{"code":1000,"success":false}"#.utf8)) == .failed)
        #expect(ZhipuResetCards.useURL(host: "https://bigmodel.cn")?.absoluteString ==
            "https://bigmodel.cn/api/biz/customer-package-reset/use")
    }

    private static let list = """
    {"code":200,"success":true,"data":{
      "fiveHourResets":[
        {"recordId":11,"grantType":"GLOBAL","expireTime":"2026-10-25 08:00:00","available":true},
        {"recordId":12,"grantType":"GLOBAL","expireTime":"2020-01-01 00:00:00","available":true}
      ],
      "weekResets":[
        {"recordId":22,"grantType":"GLOBAL","expireTime":"2026-11-01 00:00:00","available":true}
      ]
    }}
    """

    private static let mixed = """
    {"code":200,"success":true,"data":{
      "fiveHourResets":[
        {"recordId":11,"grantType":"GLOBAL","expireTime":"2026-10-25 08:00:00","available":true},
        {"recordId":"nope","grantType":"GLOBAL","expireTime":"2026-10-25 08:00:00","available":true},
        {"recordId":true,"expireTime":"2026-10-25 08:00:00","available":true},
        {"recordId":13,"expireTime":"2026-10-25 08:00:00","available":false}
      ],
      "weekResets":null
    }}
    """

    private static let empty = """
    {"code":200,"success":true,"data":{"fiveHourResets":[],"weekResets":[]}}
    """
}
