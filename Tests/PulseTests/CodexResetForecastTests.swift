import Foundation
import Testing
@testable import Pulse

@Suite("Codex Resets status")
struct CodexResetForecastTests {
    /// Sentence templates, not the process language. Another suite calls
    /// `LocalizationSource.use` while these run.
    private static let english = LocalizationSource.bundle(for: .english)
    private static let simplifiedChinese = LocalizationSource.bundle(for: .chineseSimplified)

    private let scheduledFor = "2026-09-24T18:30:00Z"
    private let expiresAt = "2026-09-23T12:00:00Z"

    @Test("An explicit scheduled_for is the reset time")
    func scheduledWins() throws {
        let status = try #require(CodexResetStatus.parse(json("""
        {
          "data": {
            "latest_reset": null,
            "scheduled_reset": {
              "id": "post-1",
              "status": "scheduled",
              "reset_type": " regular ",
              "announced_at": "2026-09-23T08:00:00Z",
              "scheduled_for": "\(scheduledFor)",
              "text": "Resetting tomorrow.",
              "source": { "type": "x_post", "author": "thsottiaux", "url": "https://x.com/thsottiaux/status/1" }
            },
            "active_watch": {
              "level": "strong",
              "reset_chance_percent": 80,
              "forecast_window": "within 24h",
              "observed_at": "2026-09-23T08:00:00Z",
              "expires_at": "\(expiresAt)",
              "text": "watch",
              "source": { "type": "observed" }
            },
            "stats": { "total": 1, "last_reset_at": null, "days_since_last": null, "avg_interval_days": null }
          },
          "meta": { "api_version": "v1", "generated_at": "2026-09-23T08:00:00Z" }
        }
        """)))

        let when = try #require(CodexResetDates.parse(scheduledFor))
        #expect(status.card == .scheduled(when))
        #expect(status.scheduled?.resetType == "regular")
        #expect(status.explicitReset == when)
        #expect(status.explicitReset != CodexResetDates.parse(expiresAt))
    }

    @Test("A watch is a forecast, and expires_at is not the reset")
    func watchIsNotATime() throws {
        let status = try #require(CodexResetStatus.parse(json("""
        {
          "data": {
            "latest_reset": null,
            "scheduled_reset": {
              "id": "post-2",
              "status": "scheduled",
              "reset_type": "regular",
              "announced_at": "2026-09-23T08:00:00Z",
              "scheduled_for": null,
              "text": "Soon.",
              "source": { "type": "observed" }
            },
            "active_watch": {
              "level": "elevated",
              "reset_chance_percent": 42,
              "forecast_window": "later today",
              "observed_at": "2026-09-23T08:00:00Z",
              "expires_at": "\(expiresAt)",
              "text": "watch",
              "source": { "type": "observed" }
            },
            "stats": { "total": 0, "last_reset_at": null, "days_since_last": null, "avg_interval_days": null }
          },
          "meta": { "api_version": "v1", "generated_at": "2026-09-23T08:00:00Z" }
        }
        """)))

        #expect(status.explicitReset == nil)
        guard case .watch(let watch) = status.card else {
            Issue.record("expected a watch")
            return
        }
        #expect(watch.level == "elevated")
        #expect(watch.chancePercent == 42)
        #expect(watch.forecastWindow == "later today")
        let ends = try #require(CodexResetDates.parse(expiresAt))
        #expect(watch.windowEnds == ends)
        #expect(watch.text == "watch")
        #expect(status.explicitReset != watch.windowEnds)
    }

    @Test("A window end without a phrase is still a watch, and not a reset time")
    func windowEndWithoutProse() throws {
        let endsAt = "2026-09-30T06:59:59.999Z"
        let status = try #require(CodexResetStatus.parse(json("""
        {
          "data": {
            "latest_reset": null,
            "scheduled_reset": null,
            "active_watch": {
              "level": "strong",
              "reset_chance_percent": null,
              "forecast_window": "  ",
              "expires_at": "\(endsAt)",
              "text": "  "
            }
          }
        }
        """)))
        let ends = try #require(CodexResetDates.parse(endsAt))
        guard case .watch(let watch) = status.card else {
            Issue.record("expected a watch")
            return
        }
        #expect(watch.windowEnds == ends)
        #expect(watch.forecastWindow.isEmpty)
        #expect(watch.text == nil)
        #expect(status.explicitReset == nil)
        #expect(CodexResetPresentation.context(forecastWindow: watch.forecastWindow, text: watch.text) == nil)
    }

    @Test("Neither a time nor a watch is an empty card")
    func empty() throws {
        let status = try #require(CodexResetStatus.parse(json("""
        {
          "data": {
            "latest_reset": null,
            "scheduled_reset": null,
            "active_watch": null,
            "stats": { "total": 0, "last_reset_at": null, "days_since_last": null, "avg_interval_days": null }
          },
          "meta": { "api_version": "v1", "generated_at": "2026-09-23T08:00:00Z" }
        }
        """)))
        #expect(status.card == .empty)
        #expect(status.explicitReset == nil)
    }

    @Test("A banked latest announcement is history, not a prediction")
    func bankedLatest() throws {
        let announced = "2026-09-22T18:23:37.000Z"
        let status = try #require(CodexResetStatus.parse(json("""
        {
          "data": {
            "latest_reset": {
              "id": "2102463847714247142",
              "reset_type": "banked",
              "announced_at": "\(announced)",
              "scheduled_for": "2026-09-25T00:00:00Z",
              "text": "We are loading a banked reset.",
              "source": { "type": "x_post", "author": "thsottiaux", "url": "https://x.com/thsottiaux/status/1" }
            },
            "scheduled_reset": null,
            "active_watch": null,
            "stats": { "total": 54, "last_reset_at": "\(announced)", "days_since_last": 0.8, "avg_interval_days": 7 }
          },
          "meta": { "api_version": "v1", "generated_at": "2026-09-23T12:42:24.788Z" }
        }
        """)))

        let when = try #require(CodexResetDates.parse(announced))
        let latest = try #require(status.latest)
        #expect(latest.id == "2102463847714247142")
        #expect(latest.resetType == "banked")
        #expect(latest.announcedAt == when)
        #expect(latest.text == "We are loading a banked reset.")
        #expect(status.card == .empty)
        #expect(status.explicitReset == nil)
        #expect(status.explicitReset != when)
    }

    @Test("A regular latest announcement keeps its type, and a bad instant is dropped")
    func regularLatestAndABrokenOne() throws {
        let announced = "2026-09-20T01:00:00Z"
        let status = try #require(CodexResetStatus.parse(json("""
        {
          "data": {
            "latest_reset": {
              "id": " post-regular ",
              "reset_type": " regular ",
              "announced_at": "\(announced)",
              "text": "Reset.",
              "source": { "type": "x_post" }
            },
            "scheduled_reset": null,
            "active_watch": null,
            "stats": { "total": 1, "last_reset_at": "\(announced)", "days_since_last": 1, "avg_interval_days": null }
          },
          "meta": { "api_version": "v1", "generated_at": "2026-09-23T08:00:00Z" }
        }
        """)))
        #expect(status.latest?.id == "post-regular")
        #expect(status.latest?.resetType == "regular")
        #expect(status.latest?.text == "Reset.")
        #expect(status.card == .empty)

        let broken = try #require(CodexResetStatus.parse(json("""
        {
          "data": {
            "latest_reset": { "id": "nope", "reset_type": "banked", "announced_at": "not-a-date" },
            "scheduled_reset": null,
            "active_watch": null,
            "stats": { "total": 0, "last_reset_at": null, "days_since_last": null, "avg_interval_days": null }
          },
          "meta": { "api_version": "v1", "generated_at": "2026-09-23T08:00:00Z" }
        }
        """)))
        #expect(broken.latest == nil)
        #expect(broken.card == .empty)
        #expect(broken.explicitReset == nil)
    }

    @Test("An unknown type is kept, and an empty prediction still yields when a time is scheduled")
    func unknownTypeAndScheduledStillWins() throws {
        let announced = "2026-09-22T18:23:37.000Z"
        let status = try #require(CodexResetStatus.parse(json("""
        {
          "data": {
            "latest_reset": {
              "id": "later-kind",
              "reset_type": "surprise",
              "announced_at": "\(announced)"
            },
            "scheduled_reset": {
              "id": "post-1",
              "status": "scheduled",
              "reset_type": "regular",
              "announced_at": "2026-09-23T08:00:00Z",
              "scheduled_for": "\(scheduledFor)",
              "text": "Resetting tomorrow.",
              "source": { "type": "x_post" }
            },
            "active_watch": null,
            "stats": { "total": 1, "last_reset_at": "\(announced)", "days_since_last": 1, "avg_interval_days": null }
          },
          "meta": { "api_version": "v1", "generated_at": "2026-09-23T08:00:00Z" }
        }
        """)))
        let when = try #require(CodexResetDates.parse(scheduledFor))
        #expect(status.latest?.resetType == "surprise")
        #expect(status.latest?.text == nil)
        #expect(status.card == .scheduled(when))
        #expect(status.explicitReset == when)
        #expect(status.explicitReset != status.latest?.announcedAt)
    }

    @Test("The latest row is a local clock and a relative interval")
    func presentation() throws {
        let announced = try #require(CodexResetDates.parse("2026-09-22T18:23:37.000Z"))
        var shanghai = Calendar(identifier: .gregorian)
        shanghai.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let local = CodexResetPresentation.absolute(
            announcedAt: announced,
            locale: Locale(identifier: "zh_CN"),
            calendar: shanghai
        )
        #expect(local.contains("2:23"))
        #expect(local.contains("月"))
        #expect(!local.contains("22"))
        #expect(!local.contains("18"))

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let utcText = CodexResetPresentation.absolute(
            announcedAt: announced,
            locale: Locale(identifier: "zh_CN"),
            calendar: utc
        )
        #expect(utcText.contains("22"))
        #expect(utcText.contains("18") || utcText.contains("6:23"))

        let relative = CodexResetPresentation.relative(
            announcedAt: announced,
            now: announced.addingTimeInterval(18 * 3600),
            locale: Locale(identifier: "en_US")
        )
        #expect(relative == "18 hours ago")

        #expect(CodexResetPresentation.detail(resetType: "", absolute: "STAMP") == "STAMP")
        #expect(CodexResetPresentation.detail(resetType: "surprise", absolute: "STAMP").contains("surprise"))
        #expect(CodexResetPresentation.detail(resetType: "surprise", absolute: "STAMP").contains("STAMP"))
        #expect(CodexResetPresentation.typeLabel(resetType: "banked") != CodexResetPresentation.typeLabel(resetType: "regular"))
        #expect(CodexResetPresentation.help(resetType: "banked", announcement: nil)?.isEmpty == false)
        #expect(CodexResetPresentation.help(resetType: "regular", announcement: nil) == nil)
        #expect(CodexResetPresentation.help(resetType: "surprise", announcement: nil) == nil)
    }

    @Test("The type tooltip follows the reset type and does not invent copy")
    func typeTooltip() throws {
        let announced = try #require(CodexResetDates.parse("2026-09-22T18:23:37.000Z"))
        func row(type: String, text: String?) -> CodexResetCardLines.Latest? {
            CodexResetCardLines.make(CodexResetStatus(
                scheduled: nil,
                watch: nil,
                latest: .init(id: "id", resetType: type, announcedAt: announced, text: text)
            ), bundle: Self.english).latest
        }

        let bankedHelp = try #require(CodexResetPresentation.help(
            resetType: "banked", announcement: nil, bundle: Self.english
        ))
        let banked = try #require(row(type: "banked", text: "We are loading a banked reset."))
        #expect(banked.help == bankedHelp)
        #expect(banked.help != "We are loading a banked reset.")
        #expect(banked.typeLabel == CodexResetPresentation.typeLabel(resetType: "banked", bundle: Self.english))
        #expect(banked.detail.contains(banked.typeLabel))
        #expect(banked.detail.contains(banked.absolute))

        #expect(row(type: "regular", text: "  Reset.  ")?.help == "Reset.")
        #expect(row(type: "regular", text: nil)?.help == nil)
        #expect(row(type: "regular", text: " \n ")?.help == nil)
        #expect(row(type: "regular", text: "Reset.")?.typeLabel == CodexResetPresentation.typeLabel(
            resetType: "regular", bundle: Self.english
        ))
        #expect(row(type: "regular", text: "Reset.")?.typeLabel == "Global reset")

        let other = try #require(row(type: "surprise", text: "Something new."))
        #expect(other.help == "Something new.")
        #expect(other.typeLabel == "surprise")
        #expect(row(type: "surprise", text: nil)?.help == nil)

        let blank = try #require(CodexResetStatus.parse(json("""
        {
          "data": {
            "latest_reset": {
              "id": "blank",
              "reset_type": "regular",
              "announced_at": "2026-09-22T18:23:37.000Z",
              "text": "  "
            },
            "scheduled_reset": null,
            "active_watch": null
          }
        }
        """)))
        #expect(blank.latest?.text == nil)
        #expect(CodexResetCardLines.make(blank).latest?.help == nil)

        let withBody = CodexResetStatus(
            scheduled: nil, watch: nil,
            latest: .init(id: "id", resetType: "regular", announcedAt: announced, text: "Reset.")
        )
        let withoutBody = CodexResetStatus(
            scheduled: nil, watch: nil,
            latest: .init(id: "id", resetType: "regular", announcedAt: announced, text: nil)
        )
        #expect(CodexResetCardLines.identity(withBody) != CodexResetCardLines.identity(withoutBody))
    }

    @Test("A cached status from before latest_reset still decodes")
    func decodesWithoutLatest() throws {
        let data = Data(#"{"scheduled":null,"watch":null}"#.utf8)
        let status = try JSONDecoder().decode(CodexResetStatus.self, from: data)
        #expect(status.latest == nil)
        #expect(status.card == .empty)

        let bareLatest = Data(#"{"id":"post","resetType":"regular","announcedAt":700000000}"#.utf8)
        let bareAnnouncement = try JSONDecoder().decode(CodexResetStatus.Latest.self, from: bareLatest)
        #expect(bareAnnouncement.text == nil)
        #expect(bareAnnouncement.resetType == "regular")

        let announced = try #require(CodexResetDates.parse("2026-09-22T18:23:37.000Z"))
        let round = CodexResetStatus(
            scheduled: nil,
            watch: .init(level: "elevated", chancePercent: nil, forecastWindow: "soon"),
            latest: .init(id: "post", resetType: "banked", announcedAt: announced)
        )
        let encoded = try JSONEncoder().encode(round)
        let decoded = try JSONDecoder().decode(CodexResetStatus.self, from: encoded)
        #expect(decoded == round)
        #expect(decoded.card == .watch(.init(level: "elevated", chancePercent: nil, forecastWindow: "soon")))
    }

    @Test("Last reset is an extra row beside an empty prediction")
    func lastResetBesideEmptyPrediction() throws {
        let announced = try #require(CodexResetDates.parse("2026-09-22T18:23:37.000Z"))
        let status = CodexResetStatus(
            scheduled: nil,
            watch: nil,
            latest: .init(id: "2102463847714247142", resetType: "banked", announcedAt: announced)
        )
        #expect(status.card == .empty)
        #expect(status.explicitReset == nil)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let lines = CodexResetCardLines.make(
            status,
            now: announced.addingTimeInterval(18 * 3600),
            locale: Locale(identifier: "en_US"),
            calendar: utc
        )
        let latest = try #require(lines.latest)
        #expect(latest.relative == "18 hours ago")
        #expect(latest.help?.isEmpty == false)
        #expect(latest.detail.isEmpty == false)
        #expect(latest.spoken.contains(latest.relative))
        #expect(CodexResetCardLines.identity(status) != CodexResetCardLines.identity(nil))
        #expect(CodexResetCardLines.identity(status).contains("2102463847714247142"))

        #expect(CodexResetCardLines.make(nil).latest == nil)
        let empty = CodexResetStatus(scheduled: nil, watch: nil)
        #expect(empty.card == .empty)
        #expect(CodexResetCardLines.make(empty).latest == nil)
        #expect(CodexResetCardLines.identity(empty).isEmpty)
    }

    @Test("The on-disk cache delivers latest to the card, including a file from before the field existed")
    @MainActor
    func cacheDeliversLatest() throws {
        let announced = try #require(CodexResetDates.parse("2026-09-22T18:23:37.000Z"))
        let status = CodexResetStatus(
            scheduled: nil,
            watch: nil,
            latest: .init(id: "2102463847714247142", resetType: "banked", announcedAt: announced)
        )
        let record = CodexResetDisk(status: status, etag: "abc", fetchedAt: Date(), maxAge: 600)
        let data = try #require(CodexResetDisk.encode(record))
        let decoded = try #require(CodexResetDisk.decode(data))
        #expect(decoded.status == status)
        #expect(decoded.status.card == .empty)
        #expect(decoded.status.latest?.resetType == "banked")

        let url = FileManager.default.temporaryDirectory
            .appending(path: "pulse-codex-resets-\(UUID().uuidString).json")
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        var delivered: CodexResetStatus?
        let monitor = CodexResetMonitor(settings: AppSettings(), file: url) { delivered = $0 }
        let loaded = monitor.restoreCache()
        #expect(loaded?.latest == status.latest)
        #expect(loaded?.card == .empty)
        #expect(loaded?.explicitReset == nil)
        #expect(delivered == loaded)

        let stale = Data(#"{"status":{"scheduled":null,"watch":null},"etag":"old","fetchedAt":700000000,"maxAge":600}"#.utf8)
        let legacy = try #require(CodexResetDisk.decode(stale))
        #expect(legacy.status.latest == nil)
        #expect(legacy.status.card == .empty)
        #expect(legacy.etag == "old")
        #expect(legacy.schema == CodexResetDisk.legacySchema)
        #expect(legacy.omitsForecastTiming)
    }

    @Test("A fresh etag on a watch that never stored expires_at is fetched again, and a current file is not")
    @MainActor
    func staleForecastTimingIsNotAFinishedCache() throws {
        let announced = try #require(CodexResetDates.parse("2026-09-26T18:17:54.000Z"))
        let phrase = "around OpenAI DevDay 2026 on September 29 (Pacific Time)"
        let staleStatus = CodexResetStatus(
            scheduled: nil,
            watch: .init(level: "strong", chancePercent: nil, forecastWindow: phrase),
            latest: .init(id: "2103911959544610829", resetType: "regular", announcedAt: announced, text: "Resets all propagated.")
        )
        let stale = CodexResetDisk(
            status: staleStatus,
            etag: "live",
            fetchedAt: Date(),
            maxAge: 600,
            schema: CodexResetDisk.legacySchema
        )
        let staleURL = try Self.write(stale)
        defer { try? FileManager.default.removeItem(at: staleURL) }

        let staleMonitor = CodexResetMonitor(settings: AppSettings(), file: staleURL) { _ in }
        let loaded = staleMonitor.restoreCache()
        #expect(loaded?.watch?.level == "strong")
        #expect(loaded?.watch?.windowEnds == nil)
        #expect(loaded?.watch?.forecastWindow == phrase)
        #expect(loaded?.latest?.resetType == "regular")
        #expect(staleMonitor.refetchingForecastTiming)
        #expect(staleMonitor.sendsConditionalRequest == false)
        #expect(staleMonitor.forecastFetchIsDue)

        let ends = try #require(CodexResetDates.parse("2026-09-30T06:59:59.999Z"))
        let note = "OpenAI DevDay 2026 is on September 29 (Pacific Time). We expect a possible Codex reset around the event."
        var watch = try #require(staleStatus.watch)
        watch.windowEnds = ends
        watch.text = note
        let current = CodexResetDisk(
            status: CodexResetStatus(scheduled: nil, watch: watch, latest: staleStatus.latest),
            etag: "live",
            fetchedAt: Date(),
            maxAge: 600
        )
        let encoded = try #require(CodexResetDisk.encode(current))
        let round = try #require(CodexResetDisk.decode(encoded))
        #expect(round.schema == CodexResetDisk.timingSchema)
        #expect(round.omitsForecastTiming == false)
        #expect(round.status.watch?.windowEnds == ends)
        #expect(round.status.watch?.text == note)

        let stripped = try Self.droppingSchema(encoded)
        let missing = try #require(CodexResetDisk.decode(stripped))
        #expect(missing.schema == CodexResetDisk.legacySchema)
        #expect(missing.omitsForecastTiming)
        let restoredEnd = try #require(missing.status.watch?.windowEnds)
        #expect(abs(restoredEnd.timeIntervalSince(ends)) < 0.01)

        let currentURL = try Self.write(current)
        defer { try? FileManager.default.removeItem(at: currentURL) }
        let currentMonitor = CodexResetMonitor(settings: AppSettings(), file: currentURL) { _ in }
        let kept = currentMonitor.restoreCache()
        #expect(kept?.watch?.windowEnds == ends)
        #expect(currentMonitor.refetchingForecastTiming == false)
        #expect(currentMonitor.sendsConditionalRequest)
        #expect(currentMonitor.forecastFetchIsDue == false)
    }

    /// The document codex-resets.com was serving when the card showed only
    /// 「较强」 and a ? — `expires_at` still ahead, so the two timing lines exist.
    @Test("The live DevDay watch counts down to expires_at and keeps the event as the note")
    func liveDevDayWatchShowsTheCountdown() throws {
        let endsAt = "2026-09-30T06:59:59.999Z"
        let prose = "around OpenAI DevDay 2026 on September 29 (Pacific Time)"
        let note = "OpenAI DevDay 2026 is on September 29 (Pacific Time). We expect a possible Codex reset around the event."
        let status = try #require(CodexResetStatus.parse(json("""
        {
          "data": {
            "latest_reset": {
              "id": "2103911959544610829",
              "reset_type": "regular",
              "announced_at": "2026-09-26T18:17:54.000Z",
              "text": "Resets all propagated. That will be all. Have a fantastic weekend.",
              "source": { "type": "x_post", "author": "thsottiaux", "url": "https://x.com/thsottiaux/status/2103911959544610829" }
            },
            "scheduled_reset": null,
            "active_watch": {
              "level": "strong",
              "reset_chance_percent": null,
              "forecast_window": "\(prose)",
              "observed_at": "2026-09-27T10:39:35.426Z",
              "expires_at": "\(endsAt)",
              "text": "\(note)",
              "source": { "type": "observed" }
            },
            "stats": { "total": 55, "last_reset_at": "2026-09-26T18:17:54.000Z", "days_since_last": 2.7, "avg_interval_days": 6.9 }
          },
          "meta": { "api_version": "v1", "generated_at": "2026-09-29T10:27:22.473Z" }
        }
        """)))
        let ends = try #require(CodexResetDates.parse(endsAt))
        let now = try #require(CodexResetDates.parse("2026-09-29T10:27:22.473Z"))
        #expect(ends > now)
        #expect(status.explicitReset == nil)
        #expect(status.watch?.windowEnds == ends)

        var shanghai = Calendar(identifier: .gregorian)
        shanghai.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let zh = Locale(identifier: "zh_CN")
        let lines = CodexResetCardLines.make(
            status, now: now, locale: zh, calendar: shanghai, bundle: Self.simplifiedChinese
        )
        let relative = CodexResetPresentation.relative(announcedAt: ends, now: now, locale: zh)
        #expect(lines.prediction.countdown == CodexResetPresentation.mayReset(
            relative: relative, bundle: Self.simplifiedChinese
        ))
        let stamp = CodexResetPresentation.predictionStamp(date: ends, locale: zh, calendar: shanghai)
        #expect(lines.prediction.bound == CodexResetPresentation.expectedBefore(
            stamp, bundle: Self.simplifiedChinese
        ))
        #expect(lines.prediction.countdown?.contains(prose) == false)
        #expect(lines.prediction.countdown?.contains("DevDay") == false)
        #expect(lines.prediction.bound?.contains("DevDay") == false)
        #expect(lines.prediction.note == note)
        let watch = try #require(status.watch)
        #expect(lines.prediction.trailing == CodexResetPresentation.confidence(watch, bundle: Self.simplifiedChinese))
        #expect(lines.latest?.typeLabel == "全局重置")
        #expect(lines.prediction.typeTag == nil)
        #expect(stamp.contains("30"))
        #expect(stamp.contains("14") || stamp.contains("15") || stamp.contains("2"))
    }

    private static func write(_ disk: CodexResetDisk) throws -> URL {
        let data = try #require(CodexResetDisk.encode(disk))
        let url = FileManager.default.temporaryDirectory
            .appending(path: "pulse-codex-resets-\(UUID().uuidString).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// A file from 1.4.8 that re-saved an older watch has no `schema` key.
    private static func droppingSchema(_ data: Data) throws -> Data {
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var copy = object
        copy.removeValue(forKey: "schema")
        return try JSONSerialization.data(withJSONObject: copy)
    }

    @Test("A watch shows a countdown and a bound, and the event prose is the note")
    func watchCountdownIsNotTheEvent() throws {
        let endsAt = "2026-09-30T06:59:59.999Z"
        let prose = "around OpenAI DevDay 2026 on September 29 (Pacific Time)"
        let note = "OpenAI DevDay 2026 is on September 29 (Pacific Time). We expect a possible Codex reset around the event."
        let status = try #require(CodexResetStatus.parse(json("""
        {
          "data": {
            "latest_reset": null,
            "scheduled_reset": null,
            "active_watch": {
              "level": "strong",
              "reset_chance_percent": null,
              "forecast_window": "\(prose)",
              "observed_at": "2026-09-27T10:39:35.426Z",
              "expires_at": "\(endsAt)",
              "text": "\(note)",
              "source": { "type": "observed" }
            }
          }
        }
        """)))
        let ends = try #require(CodexResetDates.parse(endsAt))
        let now = ends.addingTimeInterval(-21 * 3600)
        #expect(status.explicitReset == nil)
        #expect(status.watch?.windowEnds == ends)
        #expect(status.watch?.text == note)

        var shanghai = Calendar(identifier: .gregorian)
        shanghai.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let zh = Locale(identifier: "zh_CN")
        let stamp = CodexResetPresentation.predictionStamp(date: ends, locale: zh, calendar: shanghai)
        #expect(stamp.contains("30"))
        #expect(stamp.contains("三"))
        #expect(stamp.contains("59"))
        #expect(!stamp.contains(prose))

        let relative = CodexResetPresentation.relative(announcedAt: ends, now: now, locale: zh)
        #expect(relative.contains("小时") || relative.contains("小時"))
        #expect(relative.contains("后") || relative.contains("後"))

        let en = Locale(identifier: "en_US")
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let lines = CodexResetCardLines.make(
            status, now: now, locale: en, calendar: utc, bundle: Self.english
        )
        let enRelative = CodexResetPresentation.relative(announcedAt: ends, now: now, locale: en)
        #expect(enRelative == "in 21 hours")
        #expect(lines.prediction.countdown == CodexResetPresentation.mayReset(
            relative: enRelative, bundle: Self.english
        ))
        #expect(lines.prediction.countdown?.contains(prose) == false)
        #expect(lines.prediction.countdown?.contains("DevDay") == false)
        let enStamp = CodexResetPresentation.predictionStamp(date: ends, locale: en, calendar: utc)
        #expect(lines.prediction.bound == CodexResetPresentation.expectedBefore(enStamp, bundle: Self.english))
        #expect(lines.prediction.bound?.contains(prose) == false)
        #expect(lines.prediction.note == note)
        let watch = try #require(status.watch)
        #expect(lines.prediction.trailing == CodexResetPresentation.confidence(watch, bundle: Self.english))
        #expect(lines.prediction.countdown != lines.prediction.note)

        let past = CodexResetCardLines.make(
            status, now: ends.addingTimeInterval(60), locale: en, calendar: utc, bundle: Self.english
        )
        #expect(past.prediction.countdown == nil)
        #expect(past.prediction.bound == nil)
        #expect(past.prediction.note == note)
        #expect(past.prediction.trailing == lines.prediction.trailing)
    }

    @Test("Prose with no instant stays on the note, and an announced time is definite")
    func proseAndScheduled() throws {
        let proseOnly = CodexResetStatus(
            scheduled: nil,
            watch: .init(level: "elevated", chancePercent: 42, forecastWindow: "within 24h")
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let proseLines = CodexResetCardLines.make(
            proseOnly, now: now, locale: Locale(identifier: "en_US"), bundle: Self.english
        )
        #expect(proseLines.prediction.countdown == nil)
        #expect(proseLines.prediction.bound == nil)
        #expect(proseLines.prediction.note == "within 24h")
        let proseWatch = try #require(proseOnly.watch)
        #expect(proseLines.prediction.trailing == CodexResetPresentation.confidence(
            proseWatch, bundle: Self.english
        ))

        let when = now.addingTimeInterval(21 * 3600)
        let scheduled = CodexResetStatus(
            scheduled: .init(id: "post-1", scheduledFor: when),
            watch: .init(
                level: "strong",
                chancePercent: nil,
                forecastWindow: "around an event",
                windowEnds: when,
                text: "Some event."
            )
        )
        #expect(scheduled.explicitReset == when)
        #expect(scheduled.card == .scheduled(when))
        let lines = CodexResetCardLines.make(
            scheduled, now: now, locale: Locale(identifier: "en_US"), bundle: Self.english
        )
        let relative = CodexResetPresentation.relative(announcedAt: when, now: now, locale: Locale(identifier: "en_US"))
        #expect(relative == "in 21 hours")
        #expect(lines.prediction.countdown == CodexResetPresentation.resets(relative: relative, bundle: Self.english))
        #expect(lines.prediction.countdown != CodexResetPresentation.mayReset(relative: relative, bundle: Self.english))
        #expect(lines.prediction.countdown == "Resets in 21 hours")
        #expect(lines.prediction.bound == CodexResetPresentation.predictionStamp(date: when, locale: Locale(identifier: "en_US")))
        #expect(lines.prediction.note == nil)
        #expect(lines.prediction.trailing == nil)
        #expect(lines.prediction.typeTag == nil)
        #expect(lines.prediction.countdown?.contains("around an event") == false)

        let ago = CodexResetCardLines.make(
            CodexResetStatus(scheduled: .init(id: "old", scheduledFor: now.addingTimeInterval(-3600)), watch: nil),
            now: now,
            locale: Locale(identifier: "en_US"),
            bundle: Self.english
        )
        #expect(ago.prediction.countdown == nil)
        #expect(ago.prediction.bound == nil)
        #expect(ago.prediction.trailing == "No prediction yet")
        #expect(ago.prediction.typeTag == nil)
    }

    @Test("A scheduled type is named on the prediction; a watch without one is not")
    func predictionNamesTheScheduledType() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let when = now.addingTimeInterval(21 * 3600)
        func scheduled(_ type: String?) -> CodexResetStatus {
            CodexResetStatus(
                scheduled: .init(id: "post", scheduledFor: when, resetType: type),
                watch: nil
            )
        }
        let regular = CodexResetCardLines.make(scheduled("regular"), now: now, bundle: Self.english)
        #expect(regular.prediction.countdown != nil)
        #expect(regular.prediction.typeTag == "Global reset")
        #expect(regular.prediction.typeHelp == nil)
        let regularZh = CodexResetCardLines.make(
            scheduled(" regular "), now: now, bundle: Self.simplifiedChinese
        )
        #expect(regularZh.prediction.typeTag == "全局重置")

        let banked = CodexResetCardLines.make(scheduled("banked"), now: now, bundle: Self.english)
        #expect(banked.prediction.typeTag == "Reset card")
        #expect(banked.prediction.typeHelp == CodexResetPresentation.help(
            resetType: "banked", announcement: nil, bundle: Self.english
        ))
        let bankedZh = CodexResetCardLines.make(scheduled("banked"), now: now, bundle: Self.simplifiedChinese)
        #expect(bankedZh.prediction.typeTag == "重置卡")

        let missing = CodexResetCardLines.make(scheduled(nil), now: now, bundle: Self.english)
        #expect(missing.prediction.countdown != nil)
        #expect(missing.prediction.typeTag == nil)
        let blank = CodexResetCardLines.make(scheduled("  "), now: now, bundle: Self.english)
        #expect(blank.prediction.typeTag == nil)
        let surprise = CodexResetCardLines.make(scheduled("surprise"), now: now, bundle: Self.english)
        #expect(surprise.prediction.typeTag == "surprise")
        let both = CodexResetStatus(
            scheduled: .init(id: "post", scheduledFor: when, resetType: "banked"),
            watch: .init(
                level: "strong", chancePercent: nil, forecastWindow: "soon", resetType: "regular"
            )
        )
        #expect(CodexResetCardLines.make(both, now: now, bundle: Self.english).prediction.typeTag == "Reset card")

        let passed = CodexResetCardLines.make(
            scheduled("regular"), now: when.addingTimeInterval(60), bundle: Self.english
        )
        #expect(passed.prediction.countdown == nil)
        #expect(passed.prediction.typeTag == nil)
        #expect(passed.prediction.trailing == "No prediction yet")

        let watchOnly = try #require(CodexResetStatus.parse(json("""
        {
          "data": {
            "scheduled_reset": null,
            "active_watch": {
              "level": "strong",
              "forecast_window": "later today",
              "expires_at": "2026-09-30T06:59:59.999Z",
              "text": "An event."
            },
            "latest_reset": null
          }
        }
        """)))
        #expect(watchOnly.watch?.resetType == nil)
        let watchLines = CodexResetCardLines.make(
            watchOnly,
            now: try #require(CodexResetDates.parse("2026-09-29T10:00:00Z")),
            bundle: Self.english
        )
        #expect(watchLines.prediction.countdown != nil)
        #expect(watchLines.prediction.typeTag == nil)

        let typedWatch = try #require(CodexResetStatus.parse(json("""
        {
          "data": {
            "scheduled_reset": {
              "id": "no-instant",
              "reset_type": "banked",
              "scheduled_for": null
            },
            "active_watch": {
              "level": "elevated",
              "forecast_window": "later today",
              "expires_at": "2026-09-30T06:59:59.999Z",
              "reset_type": "regular"
            },
            "latest_reset": null
          }
        }
        """)))
        #expect(typedWatch.card != .scheduled(try #require(CodexResetDates.parse(scheduledFor))))
        guard case .watch = typedWatch.card else {
            Issue.record("expected a watch")
            return
        }
        #expect(typedWatch.watch?.resetType == "regular")
        #expect(typedWatch.scheduled?.resetType == "banked")
        let typedLines = CodexResetCardLines.make(
            typedWatch,
            now: try #require(CodexResetDates.parse("2026-09-29T10:00:00Z")),
            bundle: Self.english
        )
        #expect(typedLines.prediction.typeTag == "Global reset")

        let bare = Data(#"{"id":"post","scheduledFor":700000000}"#.utf8)
        let decoded = try JSONDecoder().decode(CodexResetStatus.Scheduled.self, from: bare)
        #expect(decoded.id == "post")
        #expect(decoded.resetType == nil)
    }

    @Test("A cached watch from before the window end still decodes")
    func decodesWatchWithoutWindowEnd() throws {
        let data = Data(#"{"level":"elevated","chancePercent":null,"forecastWindow":"soon"}"#.utf8)
        let watch = try JSONDecoder().decode(CodexResetStatus.Watch.self, from: data)
        #expect(watch.level == "elevated")
        #expect(watch.forecastWindow == "soon")
        #expect(watch.windowEnds == nil)
        #expect(watch.text == nil)
        #expect(watch.chancePercent == nil)
        #expect(watch.resetType == nil)

        let withEnd = watch
        var copied = withEnd
        copied.windowEnds = Date(timeIntervalSince1970: 1_800_000_000)
        copied.text = "An event."
        #expect(CodexResetCardLines.identity(CodexResetStatus(scheduled: nil, watch: watch))
            != CodexResetCardLines.identity(CodexResetStatus(scheduled: nil, watch: copied)))
    }

    @Test("The card link opens the site, not the status document")
    func siteLink() {
        #expect(CodexResetClient.site.absoluteString == "https://codex-resets.com")
        #expect(CodexResetClient.endpoint.absoluteString == "https://codex-resets.com/api/v1/status")
    }

    @Test("The status request is not answered from URLSession's cache")
    func requestBypassesTheHTTPCache() {
        let request = CodexResetClient.request(etag: "\"abc\"")
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"abc\"")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(CodexResetClient.request(etag: nil).value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(CodexResetClient.request(etag: "").value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    /// The document the card was still showing at 14:30 UTC+8, and the one the
    /// site was already publishing: a scheduled 15:00, then an announcement
    /// at 13:06 with no schedule left.
    @Test("An announcement replaces a scheduled time that is still ahead")
    func announcedResetReplacesTheScheduledTime() throws {
        let now = try #require(CodexResetDates.parse("2026-10-13T06:30:00Z"))
        let scheduledFor = try #require(CodexResetDates.parse("2026-10-13T07:00:00Z"))
        var shanghai = Calendar(identifier: .gregorian)
        shanghai.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let zh = Locale(identifier: "zh_CN")

        let stale = try #require(CodexResetStatus.parse(json("""
        {
          "data": {
            "latest_reset": {
              "id": "older",
              "reset_type": "regular",
              "announced_at": "2026-10-11T04:01:00Z",
              "text": "Reset."
            },
            "scheduled_reset": {
              "id": "slot",
              "status": "scheduled",
              "reset_type": "regular",
              "scheduled_for": "2026-10-13T07:00:00Z"
            },
            "active_watch": null
          }
        }
        """)))
        let staleLines = CodexResetCardLines.make(
            stale, now: now, locale: zh, calendar: shanghai, bundle: Self.simplifiedChinese
        )
        let relative = CodexResetPresentation.relative(announcedAt: scheduledFor, now: now, locale: zh)
        #expect(staleLines.prediction.countdown == CodexResetPresentation.resets(
            relative: relative, bundle: Self.simplifiedChinese
        ))
        #expect(staleLines.prediction.countdown?.hasSuffix("重置") == true)
        #expect(staleLines.prediction.bound == CodexResetPresentation.predictionStamp(
            date: scheduledFor, locale: zh, calendar: shanghai
        ))
        #expect(staleLines.prediction.bound != CodexResetPresentation.expectedBefore(
            CodexResetPresentation.predictionStamp(date: scheduledFor, locale: zh, calendar: shanghai),
            bundle: Self.simplifiedChinese
        ))
        #expect(stale.latest?.announcedAt == CodexResetDates.parse("2026-10-11T04:01:00Z"))

        let announced = try #require(CodexResetDates.parse("2026-10-13T05:06:06Z"))
        let fresh = try #require(CodexResetStatus.parse(json("""
        {
          "data": {
            "latest_reset": {
              "id": "2109873287853707513",
              "reset_type": "regular",
              "announced_at": "2026-10-13T05:06:06.000Z",
              "text": "It's done."
            },
            "scheduled_reset": null,
            "active_watch": null
          }
        }
        """)))
        let freshLines = CodexResetCardLines.make(
            fresh, now: now, locale: zh, calendar: shanghai, bundle: Self.simplifiedChinese
        )
        #expect(fresh.card == .empty)
        #expect(fresh.explicitReset == nil)
        #expect(freshLines.prediction.countdown == nil)
        #expect(freshLines.prediction.bound == nil)
        #expect(freshLines.prediction.trailing == "暂无预测")
        #expect(freshLines.latest?.absolute == CodexResetPresentation.absolute(
            announcedAt: announced, locale: zh, calendar: shanghai
        ))
    }

    /// 14:34 in Shanghai: the card was still counting to 14:56, and the site
    /// had already published the reset at 14:28 with no schedule left.
    @Test("A countdown that has passed is not left on the card, and the 15 October announcement replaces it")
    func passedCountdownIsNotUpcoming() throws {
        let now = try #require(CodexResetDates.parse("2026-10-15T06:34:00Z"))
        let scheduledFor = try #require(CodexResetDates.parse("2026-10-15T06:56:00Z"))
        var shanghai = Calendar(identifier: .gregorian)
        shanghai.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let zh = Locale(identifier: "zh_CN")

        let stale = try #require(CodexResetStatus.parse(json("""
        {
          "data": {
            "latest_reset": {
              "id": "older",
              "reset_type": "regular",
              "announced_at": "2026-10-13T05:06:06.000Z",
              "text": "Reset."
            },
            "scheduled_reset": {
              "id": "slot",
              "scheduled_for": "2026-10-15T06:56:00Z"
            },
            "active_watch": null
          }
        }
        """)))
        let staleLines = CodexResetCardLines.make(
            stale, now: now, locale: zh, calendar: shanghai, bundle: Self.simplifiedChinese
        )
        let relative = CodexResetPresentation.relative(announcedAt: scheduledFor, now: now, locale: zh)
        #expect(staleLines.prediction.countdown == CodexResetPresentation.resets(
            relative: relative, bundle: Self.simplifiedChinese
        ))
        #expect(staleLines.prediction.countdown?.hasSuffix("重置") == true)
        #expect(staleLines.prediction.bound == CodexResetPresentation.predictionStamp(
            date: scheduledFor, locale: zh, calendar: shanghai
        ))

        let passed = CodexResetCardLines.make(
            stale, now: scheduledFor.addingTimeInterval(60), locale: zh, calendar: shanghai,
            bundle: Self.simplifiedChinese
        )
        #expect(passed.prediction.countdown == nil)
        #expect(passed.prediction.bound == nil)
        #expect(passed.prediction.trailing == "暂无预测")
        #expect(passed.latest?.typeLabel == "全局重置")

        let announced = try #require(CodexResetDates.parse("2026-10-15T06:28:13.000Z"))
        let fresh = try #require(CodexResetStatus.parse(json("""
        {
          "data": {
            "latest_reset": {
              "id": "2110618732666257557",
              "reset_type": "regular",
              "announced_at": "2026-10-15T06:28:13.000Z",
              "text": "Done and dusted https://t.co/0fehr43VS4"
            },
            "scheduled_reset": null,
            "active_watch": null
          }
        }
        """)))
        #expect(fresh.card == .empty)
        #expect(fresh.explicitReset == nil)
        let freshLines = CodexResetCardLines.make(
            fresh,
            now: announced.addingTimeInterval(6 * 60),
            locale: Locale(identifier: "en_US"),
            bundle: Self.english
        )
        #expect(freshLines.prediction.countdown == nil)
        #expect(freshLines.prediction.bound == nil)
        #expect(freshLines.prediction.trailing == "No prediction yet")
        #expect(freshLines.latest?.relative == "6 minutes ago")
        #expect(fresh.predictionKey.isEmpty)
        #expect(stale.predictionKey != fresh.predictionKey)
        let quiet = stale.withoutPrediction()
        #expect(quiet.scheduled == nil)
        #expect(quiet.latest?.id == "older")
        #expect(quiet.predictionKey.isEmpty)
        #expect(quiet.predictionKey != stale.predictionKey)
    }

    @Test("A countdown shortens the wait to the floor, and a look is due after it")
    func countdownShortensTheWait() {
        let scheduled = CodexResetStatus(
            scheduled: .init(id: "slot", scheduledFor: Date().addingTimeInterval(3600)),
            watch: nil
        )
        let empty = CodexResetStatus(scheduled: nil, watch: nil)
        #expect(CodexResetSchedule.paced(CodexResetSchedule.ceiling, status: scheduled) == CodexResetSchedule.floor)
        #expect(CodexResetSchedule.paced(30, status: scheduled) == 30)
        #expect(CodexResetSchedule.paced(CodexResetSchedule.ceiling, status: empty) == CodexResetSchedule.ceiling)
        #expect(CodexResetSchedule.countsDown(scheduled))
        #expect(CodexResetSchedule.countsDown(empty) == false)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(CodexResetSchedule.lookIsDue(fetchedAt: now.addingTimeInterval(-90), now: now) == false)
        #expect(CodexResetSchedule.lookIsDue(fetchedAt: now.addingTimeInterval(-180), now: now))
    }

    @Test("A weekly refill is a restore; a sliding clock and a five-hour window are not")
    func weeklyRefillIsARestore() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let week = 604_800
        let before = UsageWindow(
            id: "week", kind: .weekly, scope: nil, usedFraction: 0.62,
            windowSeconds: week, resetsAt: now
        )
        let refilled = UsageWindow(
            id: "week", kind: .weekly, scope: nil, usedFraction: 0,
            windowSeconds: week, resetsAt: now.addingTimeInterval(180)
        )
        #expect(CodexResetSchedule.weeklyQuotaRestored(previous: [before], current: [refilled]))

        let slid = UsageWindow(
            id: "week", kind: .weekly, scope: nil, usedFraction: 0.62,
            windowSeconds: week, resetsAt: now.addingTimeInterval(180)
        )
        #expect(CodexResetSchedule.weeklyQuotaRestored(previous: [before], current: [slid]) == false)

        let full = UsageWindow(
            id: "week", kind: .weekly, scope: nil, usedFraction: 0,
            windowSeconds: week, resetsAt: now
        )
        let fullSlid = UsageWindow(
            id: "week", kind: .weekly, scope: nil, usedFraction: 0,
            windowSeconds: week, resetsAt: now.addingTimeInterval(180)
        )
        #expect(CodexResetSchedule.weeklyQuotaRestored(previous: [full], current: [fullSlid]) == false)

        let rolled = UsageWindow(
            id: "week", kind: .weekly, scope: nil, usedFraction: 0,
            windowSeconds: week, resetsAt: now.addingTimeInterval(7 * 24 * 3600)
        )
        #expect(CodexResetSchedule.weeklyQuotaRestored(previous: [full], current: [rolled]))

        let fiveBefore = UsageWindow(
            id: "five", kind: .fiveHour, scope: nil, usedFraction: 0.9,
            windowSeconds: 18_000, resetsAt: now
        )
        let fiveAfter = UsageWindow(
            id: "five", kind: .fiveHour, scope: nil, usedFraction: 0,
            windowSeconds: 18_000, resetsAt: now.addingTimeInterval(5 * 3600)
        )
        #expect(CodexResetSchedule.weeklyQuotaRestored(previous: [fiveBefore], current: [fiveAfter]) == false)
    }

    @Test("A cached countdown older than the floor is fetched again, and a weekly refill drops it")
    @MainActor
    func staleCountdownIsDueAndARefillDropsIt() throws {
        let when = Date().addingTimeInterval(22 * 60)
        let announced = Date().addingTimeInterval(-2 * 24 * 3600)
        let status = CodexResetStatus(
            scheduled: .init(id: "slot", scheduledFor: when),
            watch: nil,
            latest: .init(id: "older", resetType: "regular", announcedAt: announced, text: "Reset.")
        )
        let stale = CodexResetDisk(
            status: status, etag: "abc",
            fetchedAt: Date().addingTimeInterval(-10 * 60), maxAge: 14_400
        )
        let staleURL = try Self.write(stale)
        defer { try? FileManager.default.removeItem(at: staleURL) }
        let due = CodexResetMonitor(settings: AppSettings(), file: staleURL) { _ in }
        _ = due.restoreCache()
        #expect(due.forecastFetchIsDue)
        #expect(due.sendsConditionalRequest)

        let fresh = CodexResetDisk(status: status, etag: "abc", fetchedAt: Date(), maxAge: 14_400)
        let freshURL = try Self.write(fresh)
        defer { try? FileManager.default.removeItem(at: freshURL) }
        var delivered: CodexResetStatus?
        let monitor = CodexResetMonitor(settings: AppSettings(), file: freshURL) { delivered = $0 }
        _ = monitor.restoreCache()
        #expect(monitor.forecastFetchIsDue == false)
        #expect(delivered?.scheduled?.id == "slot")
        monitor.noteQuotaRestored()
        #expect(delivered?.scheduled == nil)
        #expect(delivered?.latest?.id == "older")
        #expect(monitor.forecastFetchIsDue)
        let lines = CodexResetCardLines.make(delivered, now: Date())
        #expect(lines.prediction.countdown == nil)
        #expect(lines.prediction.bound == nil)
        #expect(lines.latest != nil)
    }

    @Test("A body that is not a status document is a failure, not an empty card")
    func malformed() {
        #expect(CodexResetStatus.parse(Data("[]".utf8)) == nil)
        #expect(CodexResetStatus.parse(Data(#"{"data":[]}"#.utf8)) == nil)
    }

    @Test("304 keeps the caller on its cache; 429 names a wait; a bad 200 does not")
    func http() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let empty = CodexResetReply.interpret(statusCode: 304, headers: ["ETag": "abc"], body: Data(), now: now)
        #expect(empty.payload == .notModified)
        #expect(empty.etag == "abc")

        let limited = CodexResetReply.interpret(
            statusCode: 429,
            headers: ["Retry-After": "90"],
            body: Data(#"{"status":429}"#.utf8),
            now: now
        )
        #expect(limited.payload == .failed)
        #expect(limited.retryAfter == 90)

        let garbage = CodexResetReply.interpret(statusCode: 200, headers: [:], body: Data("nope".utf8), now: now)
        #expect(garbage.payload == .failed)

        #expect(CodexResetSchedule.delay(maxAge: 30, retryAfter: nil, failed: false) == CodexResetSchedule.floor)
        #expect(CodexResetSchedule.delay(maxAge: nil, retryAfter: 90, failed: true) == 90)
        #expect(CodexResetSchedule.delay(maxAge: nil, retryAfter: nil, failed: true) == CodexResetSchedule.default)
    }

    @Test("Missing reset credits are unknown, not zero")
    func credits() throws {
        #expect(CodexAccountUsageService.credits(from: [:]) == nil)
        let limits = try #require(JSONSerialization.jsonObject(with: Data("""
        {"rateLimitResetCredits":{"availableCount":2,"credits":[
          {"title":"Later","status":"available","expiresAt":1800000000},
          {"title":"Soon","status":"available","expiresAt":1700000000},
          {"title":"Used","status":"consumed","expiresAt":1600000000}
        ]}}
        """.utf8)) as? [String: Any])
        let now = Date(timeIntervalSince1970: 1_600_000_000)
        let summary = CodexAccountUsageService.credits(from: limits, now: now)
        #expect(summary?.available == 2)
        #expect(summary?.nextExpiresAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(summary?.showsOnCard(at: now) == true)
        let empty: [String: Any] = ["rateLimitResetCredits": ["availableCount": 0, "credits": [Any]()] as [String: Any]]
        let none = CodexAccountUsageService.credits(from: empty)
        #expect(none?.available == 0)
        #expect(none?.showsOnCard() == false)
    }

    private func json(_ text: String) -> Data { Data(text.utf8) }
}

@Suite("Advance reset reminders")
struct AdvanceResetReminderTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let lead12: TimeInterval = 12 * 3600
    private let lead48: TimeInterval = 48 * 3600

    @Test("Only an explicit scheduled_for schedules a predicted reminder")
    func predictedRequiresATime() throws {
        let when = now.addingTimeInterval(36 * 3600)
        let timed = CodexResetStatus(
            scheduled: .init(id: "post-9", scheduledFor: when),
            watch: .init(level: "strong", chancePercent: 90, forecastWindow: "soon")
        )
        let reminder = try #require(AdvanceReminderPlanner.predicted(status: timed, lead: lead12, now: now))
        #expect(reminder.identifier == "pulse.advance.predicted|post-9|\(Int(when.timeIntervalSince1970))")
        #expect(reminder.fireAt == when.addingTimeInterval(-lead12))

        let watchOnly = CodexResetStatus(
            scheduled: .init(id: "post-9", scheduledFor: nil),
            watch: .init(
                level: "elevated",
                chancePercent: 40,
                forecastWindow: "this week",
                windowEnds: now.addingTimeInterval(20 * 3600)
            )
        )
        #expect(watchOnly.explicitReset == nil)
        #expect(watchOnly.watch?.windowEnds != nil)
        #expect(AdvanceReminderPlanner.predicted(status: watchOnly, lead: lead12, now: now) == nil)
        #expect(AdvanceReminderPlanner.predicted(
            status: CodexResetStatus(scheduled: nil, watch: nil),
            lead: lead12,
            now: now
        ) == nil)
        #expect(AdvanceReminderPlanner.predicted(
            status: CodexResetStatus(scheduled: .init(id: "old", scheduledFor: now.addingTimeInterval(-60)), watch: nil),
            lead: lead12,
            now: now
        ) == nil)

        let ahead = now.addingTimeInterval(6 * 3600)
        let onlyLatest = CodexResetStatus(
            scheduled: nil,
            watch: nil,
            latest: .init(id: "banked-1", resetType: "banked", announcedAt: ahead)
        )
        #expect(onlyLatest.explicitReset == nil)
        #expect(AdvanceReminderPlanner.predicted(status: onlyLatest, lead: lead12, now: now) == nil)

        let whenLatest = now.addingTimeInterval(36 * 3600)
        let both = CodexResetStatus(
            scheduled: .init(id: "post-future", scheduledFor: whenLatest),
            watch: nil,
            latest: .init(id: "banked-1", resetType: "banked", announcedAt: now.addingTimeInterval(-3600))
        )
        let alongside = try #require(AdvanceReminderPlanner.predicted(status: both, lead: lead12, now: now))
        #expect(alongside.fireAt == whenLatest.addingTimeInterval(-lead12))
        #expect(alongside.identifier.contains("post-future"))
        #expect(!alongside.identifier.contains("banked-1"))
    }

    @Test("Inside the lead, the predicted reminder is due now and is not repeated")
    func predictedDedupes() {
        let when = now.addingTimeInterval(6 * 3600)
        let status = CodexResetStatus(scheduled: .init(id: "post-3", scheduledFor: when), watch: nil)
        let reminder = AdvanceReminderPlanner.predicted(status: status, lead: lead12, now: now)
        #expect(reminder?.fireAt == nil)

        var book = AdvanceReminderBook()
        let first = book.reconcile(desired: reminder.map { [$0] } ?? [], enabled: true, now: now)
        #expect(first.schedule.count == 1)
        let second = book.reconcile(desired: reminder.map { [$0] } ?? [], enabled: true, now: now)
        #expect(second.schedule.isEmpty)
        #expect(second.cancel.isEmpty)
    }

    @Test("A window shorter than the lead is skipped; a longer one is kept")
    func leadSkipsShortWindows() {
        let soon = now.addingTimeInterval(3 * 3600)
        let week = now.addingTimeInterval(5 * 24 * 3600)
        let windows = [
            AdvanceReminderPlanner.Window(
                accountID: "codex", accountLabel: "Codex", windowID: "five",
                windowName: "5-hour limit", resetsAt: soon, length: 5 * 3600
            ),
            AdvanceReminderPlanner.Window(
                accountID: "codex", accountLabel: "Codex", windowID: "week",
                windowName: "Weekly limit", resetsAt: week, length: 7 * 24 * 3600
            ),
            AdvanceReminderPlanner.Window(
                accountID: "kimi", accountLabel: "Kimi", windowID: "rolling",
                windowName: "Weekly limit", resetsAt: week, length: nil
            )
        ]
        let due = AdvanceReminderPlanner.regular(windows: windows, lead: lead12, now: now)
        #expect(due.map(\.identifier) == [
            "pulse.advance.regular|codex|week|\(Int(week.timeIntervalSince1970))"
        ])
        #expect(due.first?.fireAt == week.addingTimeInterval(-lead12))

        let tooSoonForTwoDays = AdvanceReminderPlanner.regular(windows: windows, lead: lead48, now: now)
        #expect(tooSoonForTwoDays.map(\.identifier) == due.map(\.identifier))
    }

    @Test("Turning reminders off cancels a pending one without marking it delivered")
    func disablingCancels() throws {
        let when = now.addingTimeInterval(36 * 3600)
        let status = CodexResetStatus(scheduled: .init(id: "post-4", scheduledFor: when), watch: nil)
        let reminder = try #require(AdvanceReminderPlanner.predicted(status: status, lead: lead12, now: now))
        var book = AdvanceReminderBook()
        let scheduled = book.reconcile(desired: [reminder], enabled: true, now: now)
        #expect(scheduled.schedule.count == 1)
        #expect(book.memory.pending[reminder.identifier] != nil)

        let off = book.reconcile(desired: [], enabled: false, now: now)
        #expect(off.cancel == [reminder.identifier])
        #expect(book.memory.pending.isEmpty)
        #expect(!book.memory.delivered.contains(reminder.identifier))

        let again = book.reconcile(desired: [reminder], enabled: true, now: now)
        #expect(again.schedule.map(\.identifier) == [reminder.identifier])
    }

    @Test("A changed lead moves a pending reminder; once its fire time has passed it is not posted again")
    func replacesPendingOnly() throws {
        let when = now.addingTimeInterval(60 * 3600)
        let status = CodexResetStatus(scheduled: .init(id: "post-5", scheduledFor: when), watch: nil)
        let early = try #require(AdvanceReminderPlanner.predicted(status: status, lead: lead48, now: now))
        let later = try #require(AdvanceReminderPlanner.predicted(status: status, lead: lead12, now: now))
        #expect(early.identifier == later.identifier)
        #expect(early.fireAt == when.addingTimeInterval(-lead48))
        #expect(later.fireAt == when.addingTimeInterval(-lead12))

        var book = AdvanceReminderBook()
        _ = book.reconcile(desired: [early], enabled: true, now: now)
        let moved = book.reconcile(desired: [later], enabled: true, now: now)
        #expect(moved.cancel == [early.identifier])
        #expect(moved.schedule.map(\.identifier) == [later.identifier])
        #expect(book.memory.pending[later.identifier] == later.fireAt)

        let afterFire = try #require(later.fireAt).addingTimeInterval(60)
        let due = try #require(AdvanceReminderPlanner.predicted(status: status, lead: lead12, now: afterFire))
        #expect(due.fireAt == nil)
        let passed = book.reconcile(desired: [due], enabled: true, now: afterFire)
        #expect(passed.schedule.isEmpty)
        #expect(book.memory.delivered.contains(due.identifier))
    }
}
