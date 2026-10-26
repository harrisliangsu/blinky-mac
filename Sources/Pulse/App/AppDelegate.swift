// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// Not private: the status-item menu reads the language from it so the
    /// menu rebuilds when the language changes.
    let settings: AppSettings
    /// Not private for the same reason: the status-item menu shows a newer
    /// version when there is one.
    let update: AppUpdate
    private let placement = PanelPlacement.restored()
    /// Not private: the settings pane shows what the system says about
    /// permission, which is not the same as what the switches say.
    private(set) lazy var alerts = UsageAlerts(settings: settings)
    /// Not private for the same reason: the settings pane is the only place
    /// that can report a combination the window server refused.
    let shortcuts = GlobalShortcutMonitor()
    private lazy var store = UsageStore(settings: settings, alerts: alerts, elsewhere: .shared)
    /// Reads Token spend in the background while it is on.
    private lazy var spendWarmer = SpendWarmer(settings: settings)
    /// The day's exchange rates, while a currency other than the dollar is chosen.
    private lazy var rateKeeper = ExchangeRateKeeper(settings: settings)
    /// Which tab the menu bar's menu last had open, kept between openings.
    private let dashboard = MenuDashboardModel()
    /// Starts usage windows after they reset, for the providers switched on.
    private lazy var primer = WindowPrimer(store: store, settings: settings)
    /// Bumped on every redraw of the status item. A tracking closure re-arms
    /// only while it still holds the latest, so the chain started by each
    /// settings change replaces the one before instead of running beside it.
    private var menuBarGeneration = 0

    /// The app's own settings, restored — which moves the process-wide panel
    /// metrics and the language to match them (`AppSettings.restored()`).
    override convenience init() {
        self.init(settings: .restored())
    }

    /// **A test passes settings on its own defaults.** Restored ones rewrite
    /// `PanelMetrics` and the language for the whole test process, mid-run and
    /// without putting them back, from whatever the test runner's own domain
    /// holds: building a delegate in a menu test changed the window budget
    /// under the layout suites (`FreeAcrossTests` failed now and then).
    init(settings: AppSettings) {
        self.settings = settings
        update = AppUpdate(settings: settings)
        super.init()
        // Sparkle's window is not one DockPresence tracks. The updater says
        // when that window is up; the Dock icon follows, as it does for Settings.
        update.onUpdateOfferVisible = { [weak self] visible in
            self?.dock.setUpdateOfferVisible(visible)
        }
        update.askToNotify = { [weak self] in
            guard let self else { return false }
            return await self.alerts.requestUpdateNoticeAuthorization()
        }
        update.onShowInstalledNotes = { [weak self] notice in
            self?.showInstalledNotes(notice)
        }
    }

    private var panelController: FloatingPanelController?
    private var spendGlance: SpendGlanceController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: SettingsWindowController?
    private var recapWindow: RecapWindowController?
    private var installedNotesWindow: InstalledUpdateWindowController?
    /// One owner of the Dock icon for every window Pulse opens.
    private lazy var dock = DockPresence(settings: settings)
    /// "Your September recap is ready", when it is switched on.
    private lazy var recapNotice = RecapNotice(settings: settings, alerts: alerts)
    private var providerSetupWindow: ProviderSetupWindowController?
    private var preparedClaude = false
    /// The status-line question and the desktop keychain prompt have been
    /// put on this launch. Separate from `preparedClaude`, which also covers
    /// the path repair that still runs when those prompts are held back.
    private var offeredClaudePrompts = false
    /// Signals read from the open-application event and the parent process.
    /// Filled in `applicationWillFinishLaunching` and again once launching
    /// has finished, because the event can arrive in either place.
    private var launchSignals = LaunchSignals.unknown
    /// A login launch held the chooser and the other first-run prompts.
    /// Cleared on a manual open or a reopen, which is when they are shown.
    private var holdFirstRunPrompts = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Installed before the open event is delivered when that delivery
        // comes after this returns. `currentAppleEvent` covers the case
        // where it is already the current event.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleOpenApplication(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEOpenApplication)
        )
        absorbLaunchEvent(NSAppleEventManager.shared().currentAppleEvent)
        launchSignals = LaunchSignalReader.withParent(launchSignals)

        // `LSUIElement` has kept the Dock icon off. Always show Dock icon is
        // the one reason to become `.regular` before any window exists;
        // anything else stays an accessory, which is also what `swift run`
        // needs because that binary has no bundle key.
        NSApplication.shared.setActivationPolicy(
            DockPresence.launchPolicy(alwaysShowsDockIcon: settings.alwaysShowsDockIcon)
        )
    }

    /// Records `keyAELaunchedAsLogInItem` when the open-application event is
    /// the one in hand. A later event that is not that one leaves a flag
    /// already read alone.
    @objc private func handleOpenApplication(
        _ event: NSAppleEventDescriptor,
        withReplyEvent reply: NSAppleEventDescriptor
    ) {
        absorbLaunchEvent(event)
    }

    private func absorbLaunchEvent(_ event: NSAppleEventDescriptor?) {
        launchSignals = LaunchSignalReader.merge(existing: launchSignals, event: event)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        absorbLaunchEvent(NSAppleEventManager.shared().currentAppleEvent)
        if launchSignals.parentBundleIdentifier == nil, launchSignals.parentExecutableName == nil {
            launchSignals = LaunchSignalReader.withParent(launchSignals)
        }

        settings.onMenuBarIconChange = { [weak self] in
            self?.updateMenuBarItem()
        }

        // **Writing to a pipe whose far end has closed raises SIGPIPE, whose
        // default is to kill the process.** Pulse writes to one: the Codex
        // helper's standard input. So that helper exiting — crashing, being
        // killed with the terminal it was started from, the user quitting
        // Codex — took Pulse down with it, with nothing in the log but
        // "Terminated due to signal 13". Ignored here rather than in
        // `CodexAppServer` because it is a property of the whole process, and
        // because the failure it prevents is not local to the caller that
        // happened to trigger it. The write then returns an error, which
        // `CodexAppServer.write(_:to:)` reads as the helper being gone.
        signal(SIGPIPE, SIG_IGN)

        // Caches whose format changed are invalidated by renaming the file;
        // this takes the orphans away rather than leaving them on disk.
        PulseStorage.removeSupersededFiles()

        // A launch agent left over from a loose build has to be handed over
        // before anything reads the state, or both builds start at login.
        LoginItem.adoptBundleIfNeeded()

        // On by default, decided once — and repaired rather than re-added, so
        // switching it off stays off.
        LoginItem.applyDefaultOnFirstRun()
        LoginItem.repairPathIfNeeded()

        alerts.onAuthorizationChange = { [weak self] status in
            self?.update.noteNotificationPermission(UpdateAnnouncement.permission(status))
        }
        settings.onUpdateDiscoveryChange = { [weak self] in
            self?.updateDiscoveryChanged()
        }
        installNotificationHandler()
        // After the click handler, so the notice can open its notes. A launch
        // with nothing stored returns immediately.
        Task { await update.announceInstalledUpdateIfNeeded() }
        // Daily at most, and only from a bundle — see `AppUpdate`.
        update.checkIfDue()
        rateKeeper.start()

        settings.onChange = { [weak self] in
            self?.settingsChanged()
        }
        // Size, spacing, glass and the rest of what only changes how the panel
        // is drawn: re-place it and stop there. `onChange` also refreshes every
        // provider, which a layout change must not cost.
        settings.onLayoutChange = { [weak self] in
            self?.layoutChanged()
        }

        // Same issue, from the other side: a combination that works with no
        // pointer involved. Both unset until somebody sets one.
        shortcuts.on(.openSettings) { [weak self] in self?.showSettings() }
        shortcuts.on(.togglePanel) { [weak self] in
            // Through the setting rather than `controller.toggle()`, so the
            // panel is in the state the switch in settings claims it is, and
            // stays that way across a launch.
            self?.settings.isPanelVisible.toggle()
        }
        shortcuts.apply(settings)
        shortcuts.onRegistrationChange = { [weak self] in
            self?.restoreMenuBarEntryPointIfNeeded()
        }

        // A stored shortcut is only an entry point after Carbon accepts it.
        // Repair an impossible combination before removing the status item,
        // including settings written by a previous build.
        restoreMenuBarEntryPointIfNeeded()
        updateMenuBarItem()

        let decision = LaunchPlanner.onLaunch(
            kind: LaunchClassification.kind(launchSignals),
            showMainWindowAtLogin: settings.showMainWindowAtLogin,
            needsProviderSelection: settings.needsProviderSelection,
            hasSuggestedProviders: !settings.suggestedProviders.isEmpty
        )
        holdFirstRunPrompts = decision.deferFirstRunPrompts
        if UpgradeOfferStamp.shouldWithhold(
            deferFirstRunPrompts: decision.deferFirstRunPrompts,
            hasSuggestedProviders: !settings.suggestedProviders.isEmpty
        ) {
            settings.withholdUpgradeOfferStamp()
        }

        // Monitoring stays stopped until a service is chosen. The chooser
        // itself waits when this launch was at login.
        if !settings.needsProviderSelection {
            startMonitoring()
        }
        // The window first, then the chooser, so a fresh install's chooser
        // is the front window and the main window is the one behind it.
        if decision.showMainWindow {
            showSettings(link: nil, userInitiated: false)
        }
        if decision.showProviderChooser {
            showPendingProviderChooser()
        }
    }

    /// Closing the last window leaves Blinky running: the panel and the menu
    /// bar are the app, and the windows are something it shows.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        AppLifetime.terminatesWhenLastWindowCloses
    }

    /// The Dock's Quit closes Pulse's windows rather than Pulse (`DockQuit`);
    /// every other way of quitting quits.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard DockQuit.isFromDock(NSAppleEventManager.shared().currentAppleEvent) else { return .terminateNow }
        dock.closeWindows()
        return .terminateCancel
    }

    private func showProviderSelection(providers: Set<Provider>, isInitial: Bool) {
        let window = ProviderSetupWindowController(
            settings: settings, providers: providers, isInitial: isInitial, dock: dock
        )
        providerSetupWindow = window
        window.show()
    }

    /// The chooser a launch or a reopen still owes: the initial one when no
    /// service is chosen, otherwise the upgrade suggestion. An open chooser
    /// is brought forward rather than replaced.
    private func showPendingProviderChooser() {
        if let chooser = providerSetupWindow {
            chooser.show()
            return
        }
        if settings.needsProviderSelection {
            showProviderSelection(providers: Set(Provider.builtIn), isInitial: true)
        } else if !settings.suggestedProviders.isEmpty {
            showProviderSelection(providers: settings.suggestedProviders, isInitial: false)
        }
    }

    /// Lets the prompts a login launch held go ahead, and stamps the upgrade
    /// offer so it is not asked again. The chooser itself is the caller's,
    /// so it can be ordered after the main window.
    private func releaseDeferredFirstRunPrompts() {
        guard holdFirstRunPrompts else { return }
        holdFirstRunPrompts = false
        settings.stampOfferedProviders()
        prepareClaudeIfSelected()
    }

    private func settingsChanged() {
        restoreMenuBarEntryPointIfNeeded()
        // Settings has no title to re-read: it is the open pane's name,
        // SwiftUI's, and the view is rebuilt in the new language.
        recapWindow?.refreshTitle()
        providerSetupWindow?.refreshTitle()
        guard !settings.needsProviderSelection else { return }
        if panelController == nil {
            // Enabling a service in Settings is also an initial choice.
            providerSetupWindow?.close()
            startMonitoring()
        } else {
            panelController?.settingsChanged()
            store.settingsChanged()
            prepareClaudeIfSelected()
        }
    }

    /// The answer to `AppSettings.onLayoutChange`: the panel is brought in line
    /// with the setting and nothing is fetched. Before monitoring starts there
    /// is no panel to re-place, and starting it is `settingsChanged`'s job.
    private func layoutChanged() {
        panelController?.settingsChanged()
    }

    private func startMonitoring() {
        guard !settings.needsProviderSelection, panelController == nil else { return }
        alerts.start(
            openSettings: { [weak self] in self?.showSettings() },
            openRecap: { [weak self] period in self?.showRecap(period: period) },
            openUpdate: { [weak self] in self?.update.check() },
            openInstalledUpdate: { [weak self] version, notes in
                self?.update.presentInstalledNotes(version: version, notes: notes)
            }
        )
        recapNotice.start()
        let glance = SpendGlanceController(settings: settings, dock: dock)
        spendGlance = glance
        let controller = FloatingPanelController(
            store: store,
            settings: settings,
            placement: placement,
            openSettings: { [weak self] in self?.showSettings() },
            openTokenSpend: { glance.toggle() },
            onTokenSpendFrame: { glance.entryRect = $0 }
        )
        glance.anchor = { [weak controller] in controller?.glanceAnchor() }
        panelController = controller
        controller.contextMenu = { [weak self] in self?.panelMenu() ?? NSMenu() }
        if settings.isPanelVisible { controller.show() }
        store.start()
        spendWarmer.start()
        primer.start()
        prepareClaudeIfSelected()
    }

    private func prepareClaudeIfSelected() {
        let claude = AccountKey(.claudeCode)
        guard settings.isEnabled(claude) else { return }
        // Repair runs once. The two prompts wait until a launch that is
        // allowed to ask — a login launch holds them, and a later manual
        // open is what lets this run a second time for the prompts alone.
        let offerPrompts = !holdFirstRunPrompts && !offeredClaudePrompts
        guard !preparedClaude || offerPrompts else { return }
        let firstPreparation = !preparedClaude
        preparedClaude = true
        if offerPrompts { offeredClaudePrompts = true }
        // Let the selection window close before either system prompt appears.
        Task { [weak self] in
            guard let self else { return }
            guard self.settings.isEnabled(claude) else {
                self.preparedClaude = false
                self.offeredClaudePrompts = false
                return
            }
            if firstPreparation { StatusLineHook.repairPathIfNeeded() }
            guard offerPrompts else { return }
            ClaudeDesktopSession.requestPermissionAtLaunch(
                willBeUsed: [.automatic, .desktopApp].contains(self.settings.source(for: claude))
            ) { [weak self] in
                guard let self, self.settings.isEnabled(claude) else { return }
                self.store.refresh(claude)
            }
            StatusLineHook.offerOnFirstRun(willBeUsed: self.settings.isEnabled(claude))
        }
    }

    func showSettings() {
        showSettings(link: nil)
    }

    /// The rail's own menu: the same three things the menu bar offers, because
    /// this exists for the Mac where that menu cannot be reached.
    ///
    /// Built on each click rather than kept, so an update found since the last
    /// one is on it — an `NSMenu` held as a property would still be showing
    /// whatever was true when it was made.
    private func panelMenu() -> NSMenu {
        makeMenu()
    }

    private func updateMenuBarItem() {
        restoreMenuBarEntryPointIfNeeded()
        if settings.hidesMenuBarIcon {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
            }
            return
        }

        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            let menu = makeMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
        }
        showMenuBarReading()
    }

    /// The menu bar item's face: Pulse's mark alone, or — with
    /// `showsUsageInMenuBar` on — the mark of the account whose ring is
    /// fullest and that ring's percentage, red past the warning line.
    ///
    /// Re-read whenever anything it reads changes: the tracking is armed
    /// again on every change, because `withObservationTracking` fires once.
    private func showMenuBarReading() {
        guard let button = statusItem?.button else { return }
        menuBarGeneration += 1
        let generation = menuBarGeneration
        let (reading, remaining, style, label) = withObservationTracking {
            let reading = settings.showsUsageInMenuBar
                ? MenuBarReading.choose(
                    among: settings.shownAccounts,
                    chosen: settings.menuBarAccount.flatMap(AccountKey.init(id:)),
                    usage: store.usage(for:),
                    pinned: settings.pinnedWindow(for:),
                    warningAt: settings.warningThreshold.fraction
                )
                : nil
            // The label inside too: renaming the account is a change to show.
            return (reading, settings.showsRemaining, settings.menuBarStyle,
                    reading.map { settings.label(for: $0.account) })
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.menuBarGeneration == generation else { return }
                self.showMenuBarReading()
            }
        }

        MenuBarReading.draw(reading, remaining: remaining, style: style, label: label, on: button)
    }

    /// An accessory app has no Dock icon. When the panel is also hidden, a
    /// successfully registered global shortcut is the only replacement for
    /// the status item; a stored shortcut that Carbon refused does not count.
    /// Internal and pure so the launch-safety rule can be pinned by a test.
    nonisolated static func menuBarIconMustRemainVisible(
        panelVisible: Bool,
        hasRegisteredShortcut: Bool
    ) -> Bool {
        !panelVisible && !hasRegisteredShortcut
    }

    private func restoreMenuBarEntryPointIfNeeded() {
        // Before a provider is selected there is no panel controller,
        // whatever the persisted visibility preference says.
        let mustRemain = Self.menuBarIconMustRemainVisible(
            panelVisible: !settings.needsProviderSelection && settings.isPanelVisible,
            hasRegisteredShortcut: shortcuts.hasRegisteredEntryPoint
        )
        let note = MenuBarRestoreNote.record(
            currentlyRecorded: settings.menuBarIconRestoreNote,
            hidesMenuBarIcon: settings.hidesMenuBarIcon,
            mustRemainVisible: mustRemain
        )
        if settings.menuBarIconRestoreNote != note {
            settings.menuBarIconRestoreNote = note
        }
        guard settings.hidesMenuBarIcon, mustRemain else { return }
        settings.hidesMenuBarIcon = false
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        // Only the menu bar's menu: the rail's own menu opens beside the rings
        // it would be repeating. The dashboard only when it is switched on;
        // Refresh either way, since it is one plain item and not the detail.
        if menu === statusItem?.menu {
            if settings.showsMenuDashboard {
                addDashboard(to: menu)
            } else if !settings.needsProviderSelection, !settings.shownAccounts.isEmpty {
                menu.addItem(refreshItem())
                menu.addItem(.separator())
            }
        }
        populateMenu(menu)
    }

    private func refreshItem() -> NSMenuItem {
        let refresh = NSMenuItem(title: .localized("Refresh"), action: #selector(refreshAll), keyEquivalent: "r")
        refresh.target = self
        refresh.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        return refresh
    }

    /// The tabbed view at the top of the menu bar's menu, and the items that
    /// go with whichever tab is open. See `MenuDashboard`.
    private func addDashboard(to menu: NSMenu) {
        guard !settings.needsProviderSelection, !settings.shownAccounts.isEmpty else { return }

        let item = NSMenuItem()
        let hosting = NSHostingView(rootView: AnyView(EmptyView()))
        hosting.rootView = AnyView(MenuDashboard(
            store: store,
            settings: settings,
            model: dashboard,
            onResize: { [weak hosting] size in
                // The menu lays itself out from its items' frames, so a tab
                // of a different height has to say so here.
                guard let hosting, hosting.frame.size != size else { return }
                hosting.setFrameSize(size)
            }
        ))
        hosting.setFrameSize(hosting.fittingSize)
        item.view = hosting
        menu.addItem(item)
        menu.addItem(.separator())

        let page = NSMenuItem(title: "", action: #selector(openUsagePage(_:)), keyEquivalent: "")
        page.target = self
        page.image = NSImage(systemSymbolName: "safari", accessibilityDescription: nil)
        menu.addItem(page)

        menu.addItem(refreshItem())
        menu.addItem(.separator())

        // The page item names the open tab's provider, and is there only when
        // that provider has a page Pulse knows.
        let showPage = { [weak self, weak page] in
            guard let self, let page else { return }
            let account = self.dashboard.selected.flatMap(AccountKey.init(id:))
                .flatMap { self.settings.shownAccounts.contains($0) ? $0 : nil }
            if let account, let url = account.provider.usagePage {
                page.title = .localized("Open \(account.provider.displayName) usage page")
                page.representedObject = url
                page.isHidden = false
            } else {
                page.isHidden = true
            }
        }
        dashboard.onSelect = showPage
        showPage()
    }

    @objc private func openUsagePage(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func togglePanelFromMenu() {
        settings.isPanelVisible.toggle()
    }

    @objc private func refreshAll() {
        store.refresh()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        populateMenu(menu)
        return menu
    }

    private func populateMenu(_ menu: NSMenu) {
        // With no service chosen there is no rail, and nothing else on screen
        // says why. Rebuilt on every open, so it goes once a choice is made.
        if settings.needsProviderSelection {
            let item = NSMenuItem(
                title: .localized("Choose services to start monitoring…"),
                action: #selector(chooseServices),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
        }

        if let newer = update.newer {
            let item = NSMenuItem(
                title: .localized("Blinky \(newer.version) is available"),
                action: #selector(checkForUpdate),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
        }

        // Some people want the menu bar and nothing at the screen's edge. The
        // switch lives in Settings → Position too; here it is one click from
        // where such a person already is. Through the setting, like the
        // shortcut, so a hidden panel stays hidden across a launch and hiding
        // the last way back brings the menu bar icon back (`settingsChanged`).
        if !settings.needsProviderSelection {
            let panelItem = NSMenuItem(
                title: .localized("Show floating panel"),
                action: #selector(togglePanelFromMenu),
                keyEquivalent: ""
            )
            panelItem.target = self
            panelItem.state = settings.isPanelVisible ? .on : .off
            menu.addItem(panelItem)
        }

        let settingsItem = NSMenuItem(
            title: .localized("Settings…"),
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: .localized("Quit Blinky"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        menu.addItem(quit)
    }

    @objc private func chooseServices() {
        // The menu item is the reader asking. A login launch that was holding
        // the question lets it go, and the upgrade offer is spent.
        holdFirstRunPrompts = false
        settings.stampOfferedProviders()
        providerSetupWindow?.close()
        showProviderSelection(providers: Set(Provider.builtIn), isInitial: true)
    }

    @objc private func openSettingsFromMenu() {
        showSettings()
    }

    @objc private func checkForUpdate() {
        update.check()
    }

    /// Opening Pulse while it is already running — the Dock, a double-click
    /// in Applications, Spotlight, Launchpad — brings the main window forward.
    ///
    /// An accessory app has no Dock icon, and with the panel and the menu bar
    /// icon both hidden (allowed once a global shortcut is registered) nothing
    /// of it is on screen. A forgotten shortcut then left no way back short
    /// of Activity Monitor; opening the app again is the way everybody tries
    /// first. A chooser that was held back at login, or that is still the
    /// way to pick a first service, comes forward with the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let decision = LaunchPlanner.onReopen(
            needsProviderSelection: settings.needsProviderSelection,
            hasSuggestedProviders: !settings.suggestedProviders.isEmpty,
            surface: reopenSurface()
        )
        if decision.showMainWindow {
            showSettings(link: nil, userInitiated: false)
        }
        if decision.releaseDeferredPrompts {
            releaseDeferredFirstRunPrompts()
        }
        if decision.showProviderChooser {
            showPendingProviderChooser()
        }
        return false
    }

    private func reopenSurface() -> LaunchPlanner.ReopenSurface {
        if settingsWindow?.isOnScreen == true { return .mainWindowOpen }
        if recapWindow?.isOnScreen == true { return .recapOnly }
        return .noWindow
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let link = PulseLink(url: url) { showSettings(link: link) }
        }
    }

    /// `userInitiated` is a menu, a shortcut, or a link. The launch path and
    /// a reopen pass false: a reopen releases held prompts itself, and a
    /// login launch must not, or the window it was allowed to open would
    /// also pop the chooser.
    private func showSettings(link: PulseLink?, pane: SettingsPane? = nil, userInitiated: Bool = true) {
        let window = settingsWindow ?? SettingsWindowController(
            store: store, settings: settings, placement: placement, update: update, alerts: alerts,
            shortcuts: shortcuts, dock: dock,
            openRecap: { [weak self] period in self?.showRecap(period: period) }
        )
        settingsWindow = window
        window.show(link: link, pane: pane)
        guard userInitiated else { return }
        let held = holdFirstRunPrompts
        releaseDeferredFirstRunPrompts()
        if held { showPendingProviderChooser() }
    }

    private func installNotificationHandler() {
        alerts.installTapHandler(
            openSettings: { [weak self] in self?.showSettings() },
            openRecap: { [weak self] period in self?.showRecap(period: period) },
            openUpdate: { [weak self] in self?.update.check() },
            openInstalledUpdate: { [weak self] version, notes in
                self?.update.presentInstalledNotes(version: version, notes: notes)
            }
        )
    }

    /// Notify first asks when it is chosen. Show the window opens an offer
    /// that was waiting on a notification, so the switch is not a silent loss.
    /// Install silently withdraws that notice and does not open the window.
    private func updateDiscoveryChanged() {
        update.applyAutomaticDownloads()
        switch settings.updateDiscovery {
        case .notifyFirst:
            Task { _ = await alerts.requestUpdateNoticeAuthorization() }
        case .showWindow:
            update.showPendingOfferIfNeeded()
        case .installSilently:
            update.suppressScheduledOffer()
        }
    }

    /// The notes for a silent install: the notification's click, or the launch
    /// itself when a notification cannot be posted.
    private func showInstalledNotes(_ notice: InstalledUpdateNotice) {
        let window = installedNotesWindow ?? InstalledUpdateWindowController(dock: dock)
        installedNotesWindow = window
        window.show(notice)
    }

    /// The recap window, on a period if one is named: the Token spend pane's
    /// button and a clicked "recap is ready" notification name one.
    private func showRecap(period: Recap.Period?) {
        let window = recapWindow ?? RecapWindowController(
            settings: settings, dock: dock,
            openTokenSpend: { [weak self] in self?.showSettings(link: nil, pane: .spend) }
        )
        recapWindow = window
        window.show(period: period)
    }
}
