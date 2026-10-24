// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import Foundation
import Testing
import UserNotifications
@testable import Pulse

/// How a newer version is announced. The decision is `UpdateAnnouncement`;
/// these tests pin it without a window server or a notification centre.
/// `AppUpdate` performs whatever the decision returns.
@MainActor
@Suite("Update announcement")
struct UpdateAnnouncementTests {
    @Test("Notify first is the shipped default, and it does not turn usage alerts on")
    func notifyFirstIsTheShippedDefault() {
        let (defaults, cleanup) = isolatedDefaults()
        defer { cleanup() }
        let settings = AppSettings(defaults: defaults)

        #expect(settings.updateDiscovery == .notifyFirst)
        #expect(UpdateAnnouncement.action(
            origin: .scheduled,
            discovery: settings.updateDiscovery,
            permission: .authorized
        ) == .notify)
        // The time-to-empty notice starts on, so the grant can already be
        // wanted. Notify first does not add itself to that gate: with every
        // usage notice off, the grant stays unwanted either way.
        settings.exhaustionAlerts = false
        #expect(!settings.wantsNotificationPermission)
        settings.updateDiscovery = .showWindow
        #expect(settings.updateDiscovery == .showWindow)
        #expect(!settings.wantsNotificationPermission)
    }

    @Test("An unknown stored choice restores notify first")
    func unknownStoredChoiceRestoresNotifyFirst() {
        let (defaults, cleanup) = isolatedDefaults()
        defer { cleanup() }
        defaults.set("nope", forKey: "settings.updateDiscovery")

        let back = AppSettings.restoredSettings(from: defaults, detected: [], scan: ExtensionCatalog.Scan())

        #expect(back.updateDiscovery == .notifyFirst)
    }

    @Test("Show the window opens the scheduled offer without a notification click")
    func showTheWindowOpensTheScheduledOffer() {
        let (defaults, cleanup) = isolatedDefaults()
        defer { cleanup() }
        let settings = AppSettings(defaults: defaults)
        var discoveryChanges = 0
        var providerRefreshes = 0
        settings.onUpdateDiscoveryChange = { discoveryChanges += 1 }
        settings.onChange = { providerRefreshes += 1 }

        #expect(UpdateAnnouncement.action(
            origin: .scheduled,
            discovery: settings.updateDiscovery,
            permission: .authorized
        ) == .notify)

        settings.updateDiscovery = .showWindow

        #expect(discoveryChanges == 1)
        #expect(providerRefreshes == 0)
        #expect(defaults.string(forKey: "settings.updateDiscovery") == "showWindow")
        for permission in UpdateAnnouncement.Permission.allCases {
            #expect(UpdateAnnouncement.action(
                origin: .scheduled,
                discovery: settings.updateDiscovery,
                permission: permission
            ) == .showOffer)
            #expect(UpdateAnnouncement.sparkleShowsScheduledUpdate(
                discovery: settings.updateDiscovery,
                permission: permission,
                immediateFocus: false
            ))
            #expect(UpdateAnnouncement.sparkleShowsScheduledUpdate(
                discovery: settings.updateDiscovery,
                permission: permission,
                immediateFocus: true
            ))
        }
    }

    @Test("Check for Updates and Check now open the offer, whatever the setting is")
    func manualCheckOpensTheOffer() {
        for discovery in UpdateDiscovery.allCases {
            for permission in UpdateAnnouncement.Permission.allCases {
                #expect(UpdateAnnouncement.action(
                    origin: .manual,
                    discovery: discovery,
                    permission: permission
                ) == .showOffer)
            }
        }
        #expect(UpdateAnnouncement.check(holdingScheduledOffer: false) == .startUserInitiatedCheck)
    }

    @Test("Clicking the update notice presents the held offer")
    func clickingTheNoticePresentsTheHeldOffer() {
        #expect(NotificationTapHandler.destination(for: UpdateAnnouncement.notificationIdentifier) == .update)
        #expect(NotificationTapHandler.destination(
            for: UpdateAnnouncement.notificationIdentifier,
            actionIdentifier: UNNotificationDismissActionIdentifier
        ) == nil)
        #expect(NotificationTapHandler.destination(
            for: "some-other-notice",
            actionIdentifier: UNNotificationDismissActionIdentifier
        ) == .settings)
        for discovery in UpdateDiscovery.allCases {
            for permission in UpdateAnnouncement.Permission.allCases {
                #expect(UpdateAnnouncement.action(
                    origin: .notificationClick,
                    discovery: discovery,
                    permission: permission
                ) == .showOffer)
            }
        }
        #expect(UpdateAnnouncement.check(holdingScheduledOffer: true) == .revealHeldOffer)
        // A click after relaunch has nothing held. It is still the direct window path.
        #expect(UpdateAnnouncement.check(holdingScheduledOffer: false) == .startUserInitiatedCheck)
    }

    @Test("A granted scheduled check notifies, including one that lands near launch")
    func aGrantedScheduledCheckNotifies() {
        #expect(UpdateAnnouncement.permission(.authorized) == .authorized)
        #expect(UpdateAnnouncement.permission(.provisional) == .authorized)
        #expect(UpdateAnnouncement.action(
            origin: .scheduled,
            discovery: .notifyFirst,
            permission: .authorized
        ) == .notify)
        #expect(!UpdateAnnouncement.sparkleShowsScheduledUpdate(
            discovery: .notifyFirst,
            permission: .authorized,
            immediateFocus: false
        ))
        #expect(!UpdateAnnouncement.sparkleShowsScheduledUpdate(
            discovery: .notifyFirst,
            permission: .authorized,
            immediateFocus: true
        ))
    }

    @Test("A denied notification grant still surfaces the update")
    func aDeniedGrantStillSurfacesTheUpdate() {
        #expect(UpdateAnnouncement.permission(.denied) == .denied)
        #expect(UpdateAnnouncement.action(
            origin: .scheduled,
            discovery: .notifyFirst,
            permission: .denied
        ) == .showOffer)
        #expect(UpdateAnnouncement.sparkleShowsScheduledUpdate(
            discovery: .notifyFirst,
            permission: .denied
        ))
        #expect(UpdateAnnouncement.actionAfterPermission(granted: false, discovery: .notifyFirst) == .showOffer)
    }

    @Test("An undecided grant asks, and a refusal then shows the window")
    func anUndecidedGrantAsks() {
        #expect(UpdateAnnouncement.permission(.notDetermined) == .notDetermined)
        #expect(UpdateAnnouncement.action(
            origin: .scheduled,
            discovery: .notifyFirst,
            permission: .notDetermined
        ) == .askPermission)
        #expect(!UpdateAnnouncement.sparkleShowsScheduledUpdate(
            discovery: .notifyFirst,
            permission: .notDetermined,
            immediateFocus: true
        ))
        #expect(UpdateAnnouncement.actionAfterPermission(granted: true, discovery: .notifyFirst) == .notify)
        #expect(UpdateAnnouncement.actionAfterPermission(granted: false, discovery: .notifyFirst) == .showOffer)
        #expect(UpdateAnnouncement.actionAfterPermission(granted: true, discovery: .showWindow) == .showOffer)
    }

    @Test("A refused update-notice request is the window fallback")
    func aRefusedUpdateNoticeRequestShowsTheWindow() async {
        let (alerts, settings, cleanup) = scratch()
        defer { cleanup() }

        let granted = await alerts.requestUpdateNoticeAuthorization { false }

        #expect(!granted)
        #expect(settings.updateDiscovery == .notifyFirst)
        #expect(UpdateAnnouncement.actionAfterPermission(
            granted: granted,
            discovery: settings.updateDiscovery
        ) == .showOffer)
    }

    @Test("Notify first can ask even when no usage alert is switched on")
    func notifyFirstAsksWithoutUsageAlerts() async {
        let (alerts, settings, cleanup) = scratch()
        defer { cleanup() }
        settings.exhaustionAlerts = false
        #expect(!settings.wantsNotificationPermission)
        var called = false

        let granted = await alerts.requestUpdateNoticeAuthorization {
            called = true
            return true
        }

        #expect(called)
        #expect(granted)
        #expect(!settings.wantsNotificationPermission)
        #expect(UpdateAnnouncement.actionAfterPermission(
            granted: granted,
            discovery: settings.updateDiscovery
        ) == .notify)
    }

    @Test("Show the window does not ask for notification permission")
    func showTheWindowDoesNotAsk() async {
        let (alerts, settings, cleanup) = scratch()
        defer { cleanup() }
        settings.updateDiscovery = .showWindow
        var called = false

        let granted = await alerts.requestUpdateNoticeAuthorization {
            called = true
            return true
        }

        #expect(!called)
        #expect(!granted)
    }

    @Test("Switching to Show the window while the prompt is up does not count as a grant")
    func switchingAwayWhileThePromptIsUp() async {
        let (alerts, settings, cleanup) = scratch()
        defer { cleanup() }

        let granted = await alerts.requestUpdateNoticeAuthorization {
            settings.updateDiscovery = .showWindow
            return true
        }

        #expect(!granted)
        #expect(UpdateAnnouncement.actionAfterPermission(granted: true, discovery: settings.updateDiscovery) == .showOffer)
    }

    @Test("Install silently downloads on a scheduled check and never opens the window")
    func installSilentlyDoesNotAnnounce() {
        for permission in UpdateAnnouncement.Permission.allCases {
            #expect(UpdateAnnouncement.action(
                origin: .scheduled,
                discovery: .installSilently,
                permission: permission
            ) == .installSilently)
            #expect(!UpdateAnnouncement.sparkleShowsScheduledUpdate(
                discovery: .installSilently,
                permission: permission,
                immediateFocus: false
            ))
            #expect(!UpdateAnnouncement.sparkleShowsScheduledUpdate(
                discovery: .installSilently,
                permission: permission,
                immediateFocus: true
            ))
        }
        #expect(UpdateAnnouncement.actionAfterPermission(granted: true, discovery: .installSilently) == .installSilently)
        #expect(UpdateAnnouncement.actionAfterPermission(granted: false, discovery: .installSilently) == .installSilently)
        #expect(UpdateAnnouncement.automaticallyDownloadsUpdates(for: .installSilently))
        #expect(!UpdateAnnouncement.automaticallyDownloadsUpdates(for: .notifyFirst))
        #expect(!UpdateAnnouncement.automaticallyDownloadsUpdates(for: .showWindow))
        #expect(UpdateAnnouncement.installsImmediately(for: .installSilently))
        #expect(!UpdateAnnouncement.installsImmediately(for: .notifyFirst))
        #expect(!UpdateAnnouncement.installsImmediately(for: .showWindow))
        var installed = false
        var scheduled = false
        let accepted = UpdateAnnouncement.immediateInstall(discovery: .installSilently, install: {
            installed = true
        }, schedule: { work in
            scheduled = true
            #expect(!installed)
            work()
        })
        #expect(accepted)
        #expect(scheduled)
        #expect(installed)
        let declined = UpdateAnnouncement.immediateInstall(discovery: .notifyFirst, install: {
            installed = false
        }, schedule: { _ in
            Issue.record("Install silently is the only choice that installs now")
        })
        #expect(!declined)
        #expect(installed)
        #expect(!SparkleAutomaticCheckbox.allowsSparkleAutomaticCheckbox)
        #expect(SparkleAutomaticCheckbox.buttonType(isBordered: false) == .switch)
        #expect(SparkleAutomaticCheckbox.buttonType(isBordered: true) == .momentaryPushIn)
        #expect(SparkleAutomaticCheckbox.shouldHide(buttonType: .switch))
        #expect(SparkleAutomaticCheckbox.shouldHide(
            buttonType: .momentaryPushIn,
            title: SparkleAutomaticCheckbox.englishTitle
        ))
        #expect(!SparkleAutomaticCheckbox.shouldHide(buttonType: .momentaryPushIn, title: "Install"))
    }

    @Test("Install silently does not ask for notification permission")
    func installSilentlyDoesNotAsk() async {
        let (alerts, settings, cleanup) = scratch()
        defer { cleanup() }
        settings.updateDiscovery = .installSilently
        var called = false

        let granted = await alerts.requestUpdateNoticeAuthorization {
            called = true
            return true
        }

        #expect(!called)
        #expect(!granted)
        #expect(settings.updateDiscovery == .installSilently)
    }

    @Test("The bundle leaves Sparkle's automatic-install checkbox unset")
    func bundleOmitsSparklesAutomaticCheckbox() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = try String(contentsOf: root.appendingPathComponent("Scripts/bundle.sh"), encoding: .utf8)
        #expect(script.contains("<key>SUAutomaticallyUpdate</key><false/>"))
        #expect(!script.contains("<key>SUAllowsAutomaticUpdates</key>"))
        #expect(script.contains("SparkleAutomaticCheckbox"))
    }

    @Test("The About control has English and simplified Chinese copy, and the other languages too")
    func aboutControlHasCopy() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let keys = [
            "When an update is found",
            "Notify first",
            "Show the window",
            "A scheduled check posts a notification, and the update window opens when that notification is clicked. Check now still opens the window.",
            "A scheduled check opens the update window.",
            "Install silently",
            "A scheduled check downloads the update, installs it, and relaunches Blinky, with no notification and no update window. Check now still opens the window.",
            "Every two hours. The choice below decides whether Blinky notifies you, opens the update window, or installs without asking.",
            "Open this notification to review and install it.",
        ]
        for language in ["en", "zh-Hans", "zh-Hant", "ja", "ko", "ru"] {
            let file = root.appendingPathComponent("Sources/Pulse/Resources/\(language).lproj/Localizable.strings")
            let pairs = try Self.pairs(in: file)
            for key in keys {
                let value = try #require(pairs[key], "\(language) is missing \(key)")
                #expect(!value.isEmpty)
                if language != "en" {
                    #expect(value != key)
                }
            }
        }
        let chinese = try Self.pairs(in: root.appendingPathComponent("Sources/Pulse/Resources/zh-Hans.lproj/Localizable.strings"))
        #expect(chinese["When an update is found"] == "发现更新时")
        #expect(chinese["Notify first"] == "先通知")
        #expect(chinese["Show the window"] == "直接打开窗口")
        #expect(chinese["Install silently"] == "自动安装")
    }

    private static func pairs(in file: URL) throws -> [String: String] {
        let text = try String(contentsOf: file, encoding: .utf8)
        var pairs: [String: String] = [:]
        let pattern = #/^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"/#
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let match = line.firstMatch(of: pattern) else { continue }
            pairs[String(match.1)] = String(match.2)
        }
        return pairs
    }

    private func isolatedDefaults() -> (UserDefaults, () -> Void) {
        let name = "UpdateAnnouncementTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }

    private func scratch() -> (UsageAlerts, AppSettings, () -> Void) {
        let (defaults, cleanDefaults) = isolatedDefaults()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("update-announcement-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let settings = AppSettings(defaults: defaults)
        let alerts = UsageAlerts(
            settings: settings,
            file: directory.appendingPathComponent("alerts.json"),
            outageFile: directory.appendingPathComponent("status-alerts.json")
        )
        return (alerts, settings, {
            cleanDefaults()
            try? FileManager.default.removeItem(at: directory)
        })
    }
}
