// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Zhipu and z.ai quota reset cards.
///
/// GLM Coding Plan hands out two kinds: a 5-hour card and a weekly card.
/// Both storefronts answer the same undocumented console route the quota
/// call already uses the key for:
///
/// `GET {host}/api/biz/customer-package-reset/list?targetType=PERSONAL`
///
/// z.ai's host is `api.z.ai`. The mainland plan is asked on
/// `open.bigmodel.cn` first — the host the quota call uses — and on
/// `bigmodel.cn` if that one does not answer. The list that was captured
/// from the mainland console on 2026-10-22 came from `bigmodel.cn`.
///
/// A card counts only when the reply says `available: true`, names a
/// numeric `recordId`, and gives an `expireTime` that is still ahead.
/// `expireTime` is `yyyy-MM-dd HH:mm:ss` in China Standard Time (UTC+8),
/// which is how that console writes a wall clock. A missing list, a
/// refusal, or a body that is not this object is unreported: the card
/// draws nothing rather than a zero Pulse made up.
///
/// Using one posts `POST {host}/api/biz/customer-package-reset/use`.
/// `resetType` is `FIVE_HOUR` or `WEEK`. `WEEK` is the body the mainland
/// console sent; `FIVE_HOUR` is the token the same route uses for the
/// other list. The caller confirms before this runs.
enum ZhipuResetKind: String, Equatable, Sendable {
    case fiveHour
    case weekly

    /// The `resetType` the use route expects.
    var wireResetType: String {
        switch self {
        case .fiveHour: "FIVE_HOUR"
        case .weekly: "WEEK"
        }
    }
}

/// One card the list said can still be used.
struct ZhipuResetCard: Equatable, Sendable, Identifiable {
    /// `recordId` as text, which is what the row and the prompt share.
    var id: String
    var recordID: Int
    /// Sent back on use. The captured body used `GLOBAL`.
    var grantType: String
    var expiresAt: Date
}

/// Both kinds, from one successful list, including a kind that came back empty.
struct ZhipuResetInventory: Equatable, Sendable {
    var fiveHour: [ZhipuResetCard]
    var weekly: [ZhipuResetCard]
    /// `https://host` of the list that answered. Use posts to the same host.
    var serviceHost: String

    func cards(for kind: ZhipuResetKind) -> [ZhipuResetCard] {
        switch kind {
        case .fiveHour: fiveHour
        case .weekly: weekly
        }
    }

    /// The card that expires first. That is the one a confirmed use spends.
    func soonest(_ kind: ZhipuResetKind) -> ZhipuResetCard? {
        cards(for: kind).min { $0.expiresAt < $1.expiresAt }
    }

    func card(_ kind: ZhipuResetKind, id: String) -> ZhipuResetCard? {
        cards(for: kind).first { $0.id == id }
    }
}

enum ZhipuResetCards {
    private static let listPath = "/api/biz/customer-package-reset/list?targetType=PERSONAL"
    private static let usePath = "/api/biz/customer-package-reset/use"
    /// China Standard Time. The console writes `expireTime` in this zone.
    static let expiryTimeZone = TimeZone(secondsFromGMT: 8 * 3600)!

    /// Where each storefront keeps the list. Mainland tries the quota host,
    /// then the console host the list was captured on.
    static func listURLs(for provider: Provider) -> [URL] {
        let hosts: [String]
        switch provider {
        case .zai:
            hosts = ["https://api.z.ai"]
        case .glmCoding:
            hosts = ["https://open.bigmodel.cn", "https://bigmodel.cn"]
        default:
            hosts = []
        }
        return hosts.compactMap { URL(string: $0 + listPath) }
    }

    /// The storefront root, opened only when the use route is not there.
    static func consoleURL(for provider: Provider) -> URL? {
        switch provider {
        case .zai: URL(string: "https://z.ai")
        case .glmCoding: URL(string: "https://open.bigmodel.cn")
        default: nil
        }
    }

    static func useURL(host: String) -> URL? {
        let root = host.hasSuffix("/") ? String(host.dropLast()) : host
        guard !root.isEmpty else { return nil }
        return URL(string: root + usePath)
    }

    /// The first list that parses. Later hosts are only asked when an
    /// earlier one does not return this object.
    static func firstReported(
        urls: [URL],
        now: Date = Date(),
        load: (URL) async -> Data?
    ) async -> ZhipuResetInventory? {
        for url in urls {
            guard let data = await load(url), let parsed = parse(data, now: now) else { continue }
            return ZhipuResetInventory(
                fiveHour: parsed.fiveHour,
                weekly: parsed.weekly,
                serviceHost: hostString(url)
            )
        }
        return nil
    }

    /// The list, with the account's own key. Nil when no host answered.
    static func fetch(key: String, provider: Provider, now: Date = Date()) async -> ZhipuResetInventory? {
        await firstReported(urls: listURLs(for: provider), now: now) { url in
            await load(listRequest(url, key: key))
        }
    }

    /// What one use call did. `unavailable` means the route is not on this
    /// host (404 or 405); the caller opens the console instead of pretending
    /// the card was spent.
    enum UseVerdict: Equatable, Sendable {
        case used
        case unavailable
        case failed
    }

    /// Posts the use. The caller has already confirmed.
    static func use(
        kind: ZhipuResetKind,
        card: ZhipuResetCard,
        key: String,
        host: String,
        requestID: String = UUID().uuidString
    ) async -> UseVerdict {
        guard let url = useURL(host: host) else { return .unavailable }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: useBody(
            kind: kind, card: card, requestID: requestID
        ))
        guard let (data, status) = await loadStatus(request) else { return .failed }
        return interpretUse(status: status, body: data)
    }

    /// The JSON body. `recordId` stays a number, matching the captured call.
    static func useBody(kind: ZhipuResetKind, card: ZhipuResetCard, requestID: String) -> [String: Any] {
        var body: [String: Any] = [
            "targetType": "PERSONAL",
            "resetType": kind.wireResetType,
            "recordId": card.recordID,
            "requestId": requestID,
        ]
        if !card.grantType.isEmpty {
            body["grantType"] = card.grantType
        }
        return body
    }

    static func interpretUse(status: Int, body: Data) -> UseVerdict {
        if status == 404 || status == 405 { return .unavailable }
        guard status == 200,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { return .failed }
        if let success = object["success"] as? Bool, !success { return .failed }
        if let code = integer(object["code"]), code != 200, code != 0 { return .failed }
        return .used
    }

    /// Nil when this body is not a reset-card list. Empty arrays are a list
    /// that reported none, which is different from a body that said nothing.
    static func parse(_ data: Data, now: Date = Date()) -> (fiveHour: [ZhipuResetCard], weekly: [ZhipuResetCard])? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            (object["success"] as? Bool) != false,
            integer(object["code"]).map({ $0 == 200 || $0 == 0 }) != false,
            let dataObject = object["data"] as? [String: Any],
            dataObject["fiveHourResets"] != nil || dataObject["weekResets"] != nil
        else { return nil }
        return (
            cards(in: dataObject["fiveHourResets"], now: now),
            cards(in: dataObject["weekResets"], now: now)
        )
    }

    private static func cards(in value: Any?, now: Date) -> [ZhipuResetCard] {
        let rows: [Any]
        if value == nil || value is NSNull {
            rows = []
        } else if let listed = value as? [Any] {
            rows = listed
        } else {
            return []
        }
        return rows.compactMap { row in
            guard let object = row as? [String: Any] else { return nil }
            return card(object, now: now)
        }
    }

    /// A row that can still be spent. Anything else is left out of the count.
    private static func card(_ object: [String: Any], now: Date) -> ZhipuResetCard? {
        guard (object["available"] as? Bool) == true,
              let recordID = integer(object["recordId"]),
              let expiresAt = expiry(object["expireTime"]),
              expiresAt > now
        else { return nil }
        let grant = (object["grantType"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ZhipuResetCard(
            id: String(recordID),
            recordID: recordID,
            grantType: grant,
            expiresAt: expiresAt
        )
    }

    /// `yyyy-MM-dd HH:mm:ss` in UTC+8. Anything else is not a date.
    static func expiry(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = expiryTimeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func listRequest(_ url: URL, key: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func load(_ request: URLRequest) async -> Data? {
        guard let (data, status) = await loadStatus(request), status == 200 else { return nil }
        return data
    }

    private static func loadStatus(_ request: URLRequest) async -> (Data, Int)? {
        guard
            let (data, response) = try? await NetworkSession.shared.recordedData(for: request),
            let status = (response as? HTTPURLResponse)?.statusCode
        else { return nil }
        return (data, status)
    }

    private static func hostString(_ url: URL) -> String {
        guard let host = url.host else { return "" }
        let scheme = url.scheme ?? "https"
        return "\(scheme)://\(host)"
    }

    private static func integer(_ value: Any?) -> Int? {
        if let text = value as? String { return Int(text) }
        guard let number = value as? NSNumber else { return nil }
        // JSON `true` is an NSNumber too. A boolean is not a record id.
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        return number.intValue
    }
}
