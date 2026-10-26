// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import Foundation
import Observation
import Sparkle
import UserNotifications

/// Keeping Pulse up to date, through Sparkle.
///
/// **An EdDSA key is what makes this safe without an Apple Developer ID.**
/// Sparkle refuses any archive not signed by the key in `Info.plist`, whoever
/// served it — so the update path is verifiable even though the app itself
/// carries only an ad-hoc signature. Apple's signing and notarisation are
/// recommended by Sparkle rather than required, and the one thing they would
/// fix — Gatekeeper blocking the *first* launch — is not something an updater
/// can help with anyway.
///
/// **Nothing starts unless Pulse is running from a bundle.** Sparkle needs an
/// `Info.plist` carrying the feed URL and that public key, its framework in
/// `Contents/Frameworks`, and a version to compare against; a `swift run`
/// build has none of them. Started anyway it would log complaints about a
/// missing feed forever, and telling a developer their working copy is out of
/// date is noise.
///
/// Sparkle owns the windows and, at an hour or longer, the schedule. The
/// interval is `UpdateCheckCadence`, written to `updateCheckInterval`, which
/// resets Sparkle's cycle without a restart. Sparkle will not arm a timer
/// under an hour, so a shorter choice is a timer here that calls
/// `checkForUpdatesInBackground` — the same scheduled check, so Install
/// silently and Notify first are unchanged. Check for Updates… and Check now
/// stay `checkForUpdates`. What is kept here is only what the rest of the app
/// asks about: whether a check can happen at all, whether one is running, and
/// whether a newer version was found — which is what the menu bar shows. A
/// scheduled find follows `UpdateDiscovery`:
/// notify first posts a notification and leaves the window hidden until that
/// notification is clicked; show the window is Sparkle's offer immediately;
/// install silently downloads, then installs and relaunches, with
/// no notification and no window before that install. The launch that is the
/// new version names the version and that release's notes
/// (`InstalledUpdateNotice`). The decision is `UpdateAnnouncement`, which
/// does not touch Sparkle. The one extra step when the offer window does show
/// is activation: this process is an `.accessory` app, and Sparkle's own
/// driver shows a found update behind every other app unless something has
/// made this one `.regular` first.
///
/// **The installed file name is not changed from this delegate.** Sparkle
/// writes the update over `host.bundlePath` because
/// `SPARKLE_NORMALIZE_INSTALLED_APPLICATION_NAME` is off in the SwiftPM
/// framework, then relaunches that path. `updaterWillRelaunchApplication`
/// runs in the process that is quitting, before the helper installs, so it
/// cannot point the relaunch at `Blinky.app`. `InstalledAppName` renames
/// `Pulse.app` on the launch that follows.
@MainActor
@Observable
final class AppUpdate {
    struct Release: Equatable, Sendable {
        let version: String
    }

    /// Set once Sparkle has found something newer, so the menu bar can say so.
    private(set) var newer: Release?
    private(set) var isChecking = false
    /// The last check couldn't reach the feed. Worth showing, because "no
    /// update" and "no answer" look identical otherwise.
    private(set) var didFail = false

    /// This build's version, or nil when it isn't running from a bundle.
    var current: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    var canCheck: Bool { controller != nil }

    /// Whether scheduled checks run. The interval is `AppSettings.updateCheckCadence`.
    /// Sparkle stores this switch, so it can't drift from what the updater is doing.
    var checksAutomatically: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            controller?.updater.automaticallyChecksForUpdates = newValue
            // Sparkle allows automatic downloads only while checks are on.
            // Turning checks back on has to put Install silently back.
            applyAutomaticDownloads()
            applyCheckCadence()
        }
    }

    /// Blinky's timer for an interval Sparkle will not arm. Invalidated when
    /// the interval moves to an hour or more, or when automatic checks go off.
    private var cadenceTimer: Timer?

    private let settings: AppSettings
    private var controller: SPUStandardUpdaterController?
    private let relay = UpdaterRelay()
    /// True from the moment a Sparkle window needs to be in front until that
    /// session ends. `DockPresence` is the only writer of the activation policy;
    /// this tells it the offer is up.
    private var updateOfferVisible = false
    var onUpdateOfferVisible: ((Bool) -> Void)?
    /// A scheduled find is waiting on a notification, or on the permission
    /// prompt that comes before one. Check for Updates…, Check now, and a
    /// click on the notice reveal it instead of starting a second check.
    private var holdingScheduledOffer = false
    /// Bumped when the reader asks for the window or the session ends, so a
    /// permission prompt that returns late does not also post a notice.
    private var offerGeneration = 0
    /// What the system last said about posting. Refreshed before a scheduled
    /// find is announced. `.notDetermined` until that read lands.
    private(set) var notificationPermission: UpdateAnnouncement.Permission = .notDetermined
    /// Asks for the update notice. Nil until the app has wired `UsageAlerts`,
    /// and a nil answer is treated as not granted — the window is shown.
    var askToNotify: (@MainActor () async -> Bool)?

    init(settings: AppSettings) {
        self.settings = settings
        // The feed URL is the tell: present only in a bundle built by
        // Scripts/bundle.sh, which is also the only place the framework is.
        guard
            Bundle.main.bundleIdentifier != nil,
            Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        else { return }

        relay.owner = self
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: relay,
            userDriverDelegate: relay
        )
        applyAutomaticDownloads()
        applyCheckCadence()
        Task { await refreshNotificationPermission() }
    }

    /// Put the reader's interval into effect, without waiting for a restart.
    ///
    /// Sparkle resets its cycle when `updateCheckInterval` is assigned, even
    /// to the value it already has, so the assignment is skipped when the
    /// length is unchanged. Under an hour that cycle would still wait an
    /// hour, and `cadenceTimer` runs the real interval instead. The check it
    /// starts is the background one, which is the scheduled path: Install
    /// silently still downloads, and Notify first still notifies. Check now
    /// does not come through here.
    func applyCheckCadence(justFired: Bool = false) {
        let plan = UpdateCheckSchedule.application(
            interval: settings.updateCheckCadence.timeInterval,
            checksAutomatically: checksAutomatically,
            currentSparkleInterval: controller?.updater.updateCheckInterval,
            lastCheck: controller?.updater.lastUpdateCheckDate,
            now: Date(),
            justFired: justFired
        )
        if let next = plan.sparkleInterval {
            controller?.updater.updateCheckInterval = next
        }
        armOwnTimer(after: plan.ownTimerDelay)
    }

    private func armOwnTimer(after delay: TimeInterval?) {
        cadenceTimer?.invalidate()
        cadenceTimer = nil
        guard controller != nil, let delay, delay > 0 else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            // The run loop calls this off the actor. The updater is main-thread only.
            MainActor.assumeIsolated { self?.ownTimerFired() }
        }
        // `.common` so a menu or a drag, which take the run loop out of the
        // default mode, does not hold the check past its time.
        RunLoop.main.add(timer, forMode: .common)
        cadenceTimer = timer
    }

    /// The short-interval timer. A session already running — Sparkle's own
    /// hour-clamped check, or a download — is left to finish; the next wait
    /// is a full interval either way, so a due check cannot re-fire every second.
    private func ownTimerFired() {
        cadenceTimer = nil
        if checksAutomatically, let updater = controller?.updater, !updater.sessionInProgress {
            updater.checkForUpdatesInBackground()
        }
        applyCheckCadence(justFired: true)
    }

    /// Blinky's About picker is the only automatic-install control.
    ///
    /// `SUAutomaticallyUpdate` stays false, so a fresh install does not
    /// download on its own. Install silently sets
    /// `automaticallyDownloadsUpdates`, which is what selects Sparkle's
    /// automatic driver for a scheduled check. That value is also stored by
    /// Sparkle, so it is written again whenever the choice or the check
    /// switch changes, and a stored Sparkle value cannot disagree.
    /// `SUAllowsAutomaticUpdates` is left unset: Sparkle 2.9 treats an
    /// explicit false as a ban, and `setAutomaticallyDownloadsUpdates` then
    /// returns without writing. The checkbox that key would show is hidden
    /// by `SparkleAutomaticCheckbox` when the offer window is on screen.
    func applyAutomaticDownloads() {
        controller?.updater.automaticallyDownloadsUpdates = UpdateAnnouncement.automaticallyDownloadsUpdates(
            for: settings.updateDiscovery
        )
    }

    /// Install silently installs and relaunches when the download finishes.
    /// The other choices leave that package until the reader installs it.
    var installsDownloadedUpdateImmediately: Bool {
        UpdateAnnouncement.installsImmediately(for: settings.updateDiscovery)
    }

    /// The silent install is about to quit this process. The next launch of
    /// that version reads what was stored. A windowed install does not come
    /// through here: Sparkle only asks this question from the automatic driver.
    func rememberSilentInstall(version: String, description: String?, format: String?) {
        guard let notice = InstalledUpdateNotice.make(version: version, description: description, format: format) else { return }
        notice.save(to: settings.defaults)
    }

    /// Opens the notes. Set by the app, which owns the window and the Dock.
    var onShowInstalledNotes: ((InstalledUpdateNotice) -> Void)?
    /// Kept for a click in this process, so the notes are the full text even
    /// if the notification's payload was shortened. The launch record itself
    /// is cleared once the choice is made, so the next launch does not announce again.
    private var postedInstalledNotice: InstalledUpdateNotice?

    /// The launch that is a version installed silently. Nothing, when no
    /// silent install was stored. The permission is read first: the value from
    /// init may still be "not asked", and that would open the window for a
    /// reader who can be notified.
    func announceInstalledUpdateIfNeeded() async {
        guard InstalledUpdateNotice.load(from: settings.defaults) != nil else { return }
        await refreshNotificationPermission()
        let pending = InstalledUpdateNotice.load(from: settings.defaults)
        switch InstalledUpdateNotice.launchAction(
            pending: pending,
            runningVersion: current,
            permission: notificationPermission,
            canNotify: UsageAlerts.isSupported
        ) {
        case .absent:
            return
        case .discard:
            InstalledUpdateNotice.clear(from: settings.defaults)
        case .notify(let notice):
            InstalledUpdateNotice.clear(from: settings.defaults)
            postedInstalledNotice = notice
            postInstalledNotification(notice)
        case .showNotes(let notice):
            InstalledUpdateNotice.clear(from: settings.defaults)
            postedInstalledNotice = notice
            onShowInstalledNotes?(notice)
        }
    }

    /// A click on the installed-version notice. The copy kept in this process
    /// wins when it is the same version, because that copy was not trimmed to
    /// fit a notification payload.
    func presentInstalledNotes(version: String?, notes: String?) {
        let clicked = version.flatMap {
            InstalledUpdateNotice.make(version: $0, description: notes, format: "plain-text")
        }
        let notice: InstalledUpdateNotice?
        if let memory = postedInstalledNotice, clicked == nil || clicked?.version == memory.version {
            notice = memory
        } else {
            notice = clicked
        }
        guard let notice else { return }
        onShowInstalledNotes?(notice)
    }

    private func postInstalledNotification(_ notice: InstalledUpdateNotice) {
        guard UsageAlerts.isSupported else {
            onShowInstalledNotes?(notice)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = String.localized("Blinky \(notice.version) is installed")
        content.body = InstalledUpdateNotice.announcementBody(notes: notice.notes)
        content.sound = .default
        content.userInfo = [
            InstalledUpdateNotice.versionUserInfoKey: notice.version,
            InstalledUpdateNotice.notesUserInfoKey: notice.notes,
        ]
        let request = UNNotificationRequest(
            identifier: InstalledUpdateNotice.notificationIdentifier,
            content: content,
            trigger: nil
        )
        Task { @MainActor in
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                self.onShowInstalledNotes?(notice)
            }
        }
    }

    /// This fork's update files on GitHub. Upstream's `update.qunqin.org`
    /// mirror and the qunqin24 raw feed are not hosts here: every check reads
    /// harrisliangsu/blinky-mac, and a failed check is not retried against anything else.
    /// The repository was renamed from harrisliangsu/Pulse. A plist that still
    /// names that old path is not a second feed; checks read blinky-mac.
    /// A constant string, so it can be the default of the nonisolated feed helpers
    /// below. On this `@MainActor` type an unmarked `static let` is isolated, and
    /// a default argument is evaluated off the actor.
    nonisolated static let githubBase = "https://raw.githubusercontent.com/harrisliangsu/blinky-mac/main/"

    /// The feed for the language Pulse is set to, on this fork's GitHub files.
    ///
    /// The notes in the update window come in one language: each item in
    /// `appcast.xml` carries one `<description xml:lang>` per language and
    /// Sparkle shows the one the **system's** languages pick, which Pulse's own
    /// language setting cannot reach. So a Pulse set to a language reads that
    /// language's copy of the feed (`appcast-zh.xml`, `appcast-en.xml`, written
    /// by `Scripts/appcast.py` beside the main one). The changelog is written in
    /// Chinese and English; Japanese, Korean and Russian read the English.
    ///
    /// `base` defaults to this fork. A bundle's `SUFeedURL` is used only when
    /// it already names harrisliangsu/blinky-mac on `raw.githubusercontent.com`, so
    /// a plist cannot point the app at upstream or at the mirror.
    nonisolated static func feedURL(for language: AppLanguage, base: String = githubBase) -> String {
        let file = switch language {
        case .system: "appcast.xml"
        case .chineseSimplified, .chineseTraditional: "appcast-zh.xml"
        case .english, .japanese, .korean, .russian: "appcast-en.xml"
        }
        let root = base.hasSuffix("/") ? base : base + "/"
        return root + file
    }

    /// The directory of `SUFeedURL` when that URL is this fork's GitHub feed.
    nonisolated static func feedBase(from infoURL: String?) -> String {
        guard
            let infoURL,
            let url = URL(string: infoURL),
            url.host == "raw.githubusercontent.com",
            url.path.hasPrefix("/harrisliangsu/blinky-mac/")
        else { return githubBase }
        let directory = url.deletingLastPathComponent().absoluteString
        return directory.hasSuffix("/") ? directory : directory + "/"
    }

    /// Asks now, and shows Sparkle's own window with whatever it finds.
    ///
    /// Check for Updates…, About's Check now, and a click on the update
    /// notification all come here. A scheduled find that is waiting on a
    /// notification is revealed instead of checked again. The checking window
    /// is created on a later turn, after Sparkle's install probe. By then this
    /// process is `.regular` and has been activated. Left as `.accessory`,
    /// Sparkle's `showWindow` opens behind everything else —
    /// `activateIgnoringOtherApps` included, which is why the permission prompt
    /// is not shown.
    func check() {
        guard let updater = controller?.updater else { return }
        offerGeneration += 1
        switch UpdateAnnouncement.check(holdingScheduledOffer: holdingScheduledOffer) {
        case .revealHeldOffer:
            revealDeferredUpdate()
        case .startUserInitiatedCheck:
            isChecking = true
            didFail = false
            if updateOfferVisible || !updater.sessionInProgress {
                showUpdateOffer()
            }
            updater.checkForUpdates()
            // Sparkle refused the check (nothing started, so nothing will finish).
            // A session that was already running is left to its own finish.
            if !updater.sessionInProgress {
                hideUpdateOffer()
            }
        }
    }

    /// Asks quietly, for a screen that is about to state the result: no
    /// Sparkle window, just `newer` / `didFail` brought up to date. Opening
    /// About calls this, so "up to date" there is an answer, not a default.
    /// Skipped while any check or update is already under way — that one will
    /// report, and starting another would only abort it.
    func probe() {
        guard
            let updater = controller?.updater,
            !isChecking,
            !updater.sessionInProgress,
            updater.canCheckForUpdates
        else { return }
        isChecking = true
        didFail = false
        updater.checkForUpdateInformation()
    }

    /// Nothing to do. Sparkle arms its timer when it starts, and
    /// `applyCheckCadence` has already put the reader's interval on it.
    /// Kept so the app's launch path doesn't have to know which updater is
    /// behind this.
    func checkIfDue() {}

    fileprivate func finishCheck(found item: SUAppcastItem?) {
        isChecking = false
        didFail = false
        newer = item.map { Release(version: $0.displayVersionString) }
    }

    fileprivate func failCheck(_ failed: Bool) {
        isChecking = false
        if failed { didFail = true }
    }

    /// The feed Sparkle asks for at the start of each check: this fork's
    /// GitHub file for the language Pulse is set to.
    fileprivate var feedURLForNextCheck: String {
        let info = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        return Self.feedURL(for: LocalizationSource.language, base: Self.feedBase(from: info))
    }

    /// Every cycle ends here, whichever of the calls above it made first, so a
    /// cycle that made none of them cannot leave the row saying "Checking…".
    fileprivate func endCycle() {
        isChecking = false
    }

    /// The reader chose Show the window while a notice was still held.
    func showPendingOfferIfNeeded() {
        guard holdingScheduledOffer else { return }
        offerGeneration += 1
        revealDeferredUpdate()
    }

    /// The reader chose Install silently. A notice already posted is
    /// withdrawn, and a held offer is not brought forward. A session Sparkle
    /// has already started keeps going; the next scheduled check uses the
    /// automatic driver.
    func suppressScheduledOffer() {
        offerGeneration += 1
        holdingScheduledOffer = false
        withdrawUpdateNotification()
    }

    func noteNotificationPermission(_ permission: UpdateAnnouncement.Permission) {
        notificationPermission = permission
    }

    /// Sparkle is about to run a scheduled check. The grant is read now so the
    /// decision at the end of it is the one System Settings currently holds.
    fileprivate func schedulePermissionRefresh() {
        Task { await refreshNotificationPermission() }
    }

    fileprivate func refreshNotificationPermission() async {
        guard UsageAlerts.isSupported else {
            notificationPermission = .denied
            return
        }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notificationPermission = UpdateAnnouncement.permission(status)
    }

    /// Sparkle found a scheduled update and was told not to show it. The
    /// window stays hidden until the notice is clicked, unless the grant
    /// cannot carry a notice — then the window is the offer.
    fileprivate func beginHoldingScheduledOffer(version: String) {
        // Sparkle calls this on the next runloop. Check for Updates… may have
        // brought the offer forward in between, and that path already shows
        // the window. Don't also post a notice for it.
        guard !updateOfferVisible else { return }
        holdingScheduledOffer = true
        Task { await deliverScheduledOffer(version: version) }
    }

    private func deliverScheduledOffer(version: String) async {
        let generation = offerGeneration
        await refreshNotificationPermission()
        guard generation == offerGeneration, holdingScheduledOffer else { return }
        switch UpdateAnnouncement.action(
            origin: .scheduled,
            discovery: settings.updateDiscovery,
            permission: notificationPermission
        ) {
        case .notify:
            postUpdateNotification(version: version)
        case .showOffer:
            revealDeferredUpdate()
        case .askPermission:
            await askThenOffer(version: version, generation: generation)
        case .installSilently:
            holdingScheduledOffer = false
            withdrawUpdateNotification()
        }
    }

    /// The permission dialog has to be in front. An accessory app's own
    /// prompts open behind everything else, so this uses the same activation
    /// as the offer window and drops it when the grant comes through.
    private func askThenOffer(version: String, generation: Int) async {
        showUpdateOffer()
        let granted = await askToNotify?() ?? false
        guard generation == offerGeneration, holdingScheduledOffer else { return }
        switch UpdateAnnouncement.actionAfterPermission(
            granted: granted,
            discovery: settings.updateDiscovery
        ) {
        case .notify:
            hideUpdateOffer()
            await refreshNotificationPermission()
            guard generation == offerGeneration, holdingScheduledOffer else { return }
            postUpdateNotification(version: version)
        case .installSilently:
            hideUpdateOffer()
            holdingScheduledOffer = false
            withdrawUpdateNotification()
        case .showOffer, .askPermission:
            revealDeferredUpdate()
        }
    }

    private func postUpdateNotification(version: String) {
        guard UsageAlerts.isSupported else {
            revealDeferredUpdate()
            return
        }
        let content = UNMutableNotificationContent()
        content.title = String.localized("Blinky \(version) is available")
        content.body = String.localized("Open this notification to review and install it.")
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UpdateAnnouncement.notificationIdentifier,
            content: content,
            trigger: nil
        )
        let generation = offerGeneration
        Task { @MainActor in
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                guard generation == self.offerGeneration, self.holdingScheduledOffer else { return }
                self.revealDeferredUpdate()
            }
        }
    }

    private func withdrawUpdateNotification() {
        guard UsageAlerts.isSupported else { return }
        let identifier = UpdateAnnouncement.notificationIdentifier
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    /// The held offer, brought forward.
    ///
    /// Sparkle has already created the offer and set `showingUpdate`.
    /// `checkForUpdates` in that state calls `showUpdateInFocus` rather than
    /// starting another check. It does not call `willHandleShowingUpdate`
    /// again, so the focus step that call usually performs is done here.
    private func revealDeferredUpdate() {
        holdingScheduledOffer = false
        withdrawUpdateNotification()
        showUpdateOffer()
        controller?.updater.checkForUpdates()
        let appUpdate = self
        Task { @MainActor in
            appUpdate.focusUpdateOffer()
        }
    }

    /// The reader has the offer in front of them. The notice has done its job.
    fileprivate func noteUpdateAttention() {
        holdingScheduledOffer = false
        withdrawUpdateNotification()
    }

    fileprivate func endUpdateSession() {
        offerGeneration += 1
        holdingScheduledOffer = false
        withdrawUpdateNotification()
        hideUpdateOffer()
    }

    /// Whether Sparkle should present this scheduled find itself.
    /// No side effects: Sparkle requires the answer to be pure.
    fileprivate func sparkleShouldShowScheduledUpdate(immediateFocus: Bool) -> Bool {
        UpdateAnnouncement.sparkleShowsScheduledUpdate(
            discovery: settings.updateDiscovery,
            permission: notificationPermission,
            immediateFocus: immediateFocus
        )
    }

    /// Bring Sparkle's standard window forward. Called when the offer window
    /// is about to show — a manual check, Show the window, a refused
    /// notification grant, or a click on the notice — and before a modal
    /// alert. Not called for a scheduled find that is only posting a
    /// notification. `SUAutomaticallyUpdate` stays false: this shows the
    /// offer, it does not install.
    fileprivate func showUpdateOffer() {
        updateOfferVisible = true
        onUpdateOfferVisible?(true)
    }

    fileprivate func hideUpdateOffer() {
        guard updateOfferVisible else { return }
        updateOfferVisible = false
        onUpdateOfferVisible?(false)
    }

    /// Sparkle has already decided whether to order the offer front, behind,
    /// or not at all. The next turn is after that decision, so the offer can
    /// be made key here whichever way it went.
    ///
    /// The frame name is Sparkle's (`SUUpdateAlert.windowDidLoad`, 2.9.6). The
    /// controller class is the same window when the frame name is missing.
    fileprivate func focusUpdateOffer() {
        NSApp.activate(ignoringOtherApps: true)
        hideSparkleAutomaticCheckboxes()
        for window in NSApp.windows where Self.isSparkleUpdateOffer(
            frameAutosaveName: window.frameAutosaveName,
            windowControllerClassName: window.windowController.map { String(describing: type(of: $0)) }
        ) {
            window.orderFrontRegardless()
            window.makeKey()
        }
        // `SUUpdateAlert.windowDidLoad` may run after this return and add the
        // checkbox then. Hide it again on the next turn.
        Task { @MainActor in
            self.hideSparkleAutomaticCheckboxes()
        }
    }

    private func hideSparkleAutomaticCheckboxes() {
        for window in NSApp.windows where Self.isSparkleUpdateOffer(
            frameAutosaveName: window.frameAutosaveName,
            windowControllerClassName: window.windowController.map { String(describing: type(of: $0)) }
        ) {
            hideSparkleAutomaticCheckboxes(in: window.contentView)
        }
    }

    private func hideSparkleAutomaticCheckboxes(in view: NSView?) {
        guard let view else { return }
        if let button = view as? NSButton,
           SparkleAutomaticCheckbox.shouldHide(
               buttonType: SparkleAutomaticCheckbox.buttonType(isBordered: button.isBordered),
               title: button.title
           ) {
            button.isHidden = true
        }
        for subview in view.subviews {
            hideSparkleAutomaticCheckboxes(in: subview)
        }
    }

    nonisolated static func isSparkleUpdateOffer(frameAutosaveName: String, windowControllerClassName: String?) -> Bool {
        frameAutosaveName == "SUUpdateAlert2" || windowControllerClassName == "SUUpdateAlert"
    }
}

/// Sparkle's delegate, kept apart from `AppUpdate` itself.
///
/// `SPUUpdaterDelegate` is an `@objc` protocol, so it has to be an `NSObject`
/// and its methods cannot be main-actor-isolated. Rather than fight that on a
/// type that is also `@Observable`, this stands between the two and hops onto
/// the main actor — where Sparkle calls it from in any case.
private final class UpdaterRelay: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    /// Weak: the app owns the updater, not the other way round.
    weak var owner: AppUpdate?

    /// Read at every check, so a language changed in Settings applies to the
    /// next one. The URL is always this fork's GitHub feed.
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        MainActor.assumeIsolated { owner?.feedURLForNextCheck }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        MainActor.assumeIsolated { owner?.finishCheck(found: item) }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        MainActor.assumeIsolated { owner?.finishCheck(found: nil) }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        // Sparkle aborts for benign reasons too — the user closing its window
        // is one — and reporting those as "couldn't reach the feed" would be a
        // lie on the one row that exists to tell the truth about that. Only a
        // failure to *reach or read* the feed counts. This fork does not retry
        // the check on another host.
        let failed = (error as NSError).domain == NSURLErrorDomain
            || (error as NSError).code == Int(SUError.appcastError.rawValue)
        MainActor.assumeIsolated { owner?.failCheck(failed) }
    }

    nonisolated func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        MainActor.assumeIsolated { owner?.endCycle() }
    }

    nonisolated func updater(_: SPUUpdater, willScheduleUpdateCheckAfterDelay _: TimeInterval) {
        MainActor.assumeIsolated { owner?.schedulePermissionRefresh() }
    }

    /// Background apps that schedule checks are asked to implement gentle
    /// reminders. Notify first is that reminder; Show the window still answers
    /// the question by letting Sparkle present the offer.
    ///
    /// `nonisolated`, like every other method here. Left unmarked, the property
    /// is main-actor isolated and cannot witness Sparkle's requirement.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// No side effects. `immediateFocus` is passed through and does not change
    /// the answer: a scheduled check near launch still follows the setting.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        MainActor.assumeIsolated {
            owner?.sparkleShouldShowScheduledUpdate(immediateFocus: immediateFocus) ?? true
        }
    }

    /// Before Sparkle shows a found update, or before this app handles one it
    /// asked to handle.
    ///
    /// When Sparkle is showing the offer, returning with the app still
    /// `.accessory` is the bug: for a background app whose check was not just
    /// now, the standard driver shows the offer with `showWindow` and does not
    /// activate, or `orderBack` when this app already has a key window. A
    /// regular app that is already active can instead wait for the *next*
    /// activation and never show it. Side effects do not belong in
    /// `shouldHandle`, so the activation is here — and only when the window
    /// is actually going up. A scheduled Notify first find (`handleShowingUpdate`
    /// false) posts a notification instead and does not activate.
    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        MainActor.assumeIsolated {
            if handleShowingUpdate {
                owner?.showUpdateOffer()
                let appUpdate = owner
                // After this returns, Sparkle orders the offer front, behind, or
                // not at all. The task runs once that call has returned.
                Task { @MainActor in
                    appUpdate?.focusUpdateOffer()
                }
            } else {
                owner?.beginHoldingScheduledOffer(version: update.displayVersionString)
            }
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate _: SUAppcastItem) {
        MainActor.assumeIsolated { owner?.noteUpdateAttention() }
    }

    /// "Up to date", and a failure Sparkle puts in an alert. `runModal` follows
    /// this return, so the app has to be activable before that call.
    nonisolated func standardUserDriverWillShowModalAlert() {
        MainActor.assumeIsolated { owner?.showUpdateOffer() }
    }

    /// The offer was dismissed, skipped, or failed. Settings may still want
    /// the Dock icon; `DockPresence` is what decides. A notice still on screen
    /// is withdrawn with the session.
    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { owner?.endUpdateSession() }
    }

    /// Install silently installs and relaunches when the download finishes.
    /// Returning true and running the block is that path. Returning false
    /// waits until Blinky quits, which is every other choice: a menu-bar app
    /// often never quits, and a downloaded package would then sit unused.
    /// The block runs on the next turn so Sparkle can leave this delegate
    /// before the install starts quitting the process.
    nonisolated func updater(
        _: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        // Copied before the hop. The item is Sparkle's object, and the next
        // launch needs the version and the description as plain values.
        let version = item.displayVersionString
        let notes = item.itemDescription
        let format = item.itemDescriptionFormat
        let installNow = MainActor.assumeIsolated {
            let now = owner?.installsDownloadedUpdateImmediately ?? false
            if now {
                owner?.rememberSilentInstall(version: version, description: notes, format: format)
            }
            return now
        }
        // The block Sparkle hands over is not `Sendable`. The next main turn
        // is the same isolation this process already runs on; the copy is
        // only so the queue can take a `@Sendable` closure.
        nonisolated(unsafe) let handler = immediateInstallHandler
        return UpdateAnnouncement.immediateInstall(
            discovery: installNow ? .installSilently : .notifyFirst,
            install: handler,
            schedule: { work in
                nonisolated(unsafe) let scheduled = work
                DispatchQueue.main.async { scheduled() }
            }
        )
    }
}

/// Sparkle's own "automatically download and install" checkbox stays off the
/// offer window. Blinky's About picker is the control for that choice.
///
/// `SUAllowsAutomaticUpdates` is not set in the bundle. An explicit false
/// would hide the checkbox and also make `setAutomaticallyDownloadsUpdates`
/// a no-op (Sparkle 2.9, `SPUUpdaterSettings`), so Install silently could
/// not turn the download on. The checkbox is hidden here instead, inside the
/// offer window `AppUpdate.isSparkleUpdateOffer` matches.
enum SparkleAutomaticCheckbox {
    static let allowsSparkleAutomaticCheckbox = false
    /// The English title Sparkle sets in `SUUpdateAlert.windowDidLoad`.
    static let englishTitle = "Automatically download and install updates in the future"

    /// `NSButton` has `setButtonType` and no getter. Sparkle's checkbox
    /// (`SUUpdateAlert.xib`, `type="check"`) is not bordered. Install, Later,
    /// and Skip are bordered push buttons.
    static func buttonType(isBordered: Bool) -> NSButton.ButtonType {
        isBordered ? .momentaryPushIn : .switch
    }

    static func shouldHide(buttonType: NSButton.ButtonType, title: String = "") -> Bool {
        guard !allowsSparkleAutomaticCheckbox else { return false }
        if buttonType == .switch { return true }
        return title == englishTitle
    }
}
