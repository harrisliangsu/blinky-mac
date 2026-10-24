// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit

/// The Dock icon that follows Pulse's windows.
///
/// Pulse is bundled with `LSUIElement` true, so it starts as an `.accessory`
/// app: no Dock icon and no ⌘-Tab entry, and a window another app has covered
/// cannot be found again. The icon is there while **any** tracked window (the
/// main window, a recap, the service chooser) is on screen and
/// `AppSettings.showsDockIconInSettings` allows it, and Pulse is a menu bar
/// app again the moment neither is true.
///
/// `AppSettings.alwaysShowsDockIcon` overrides that. While it is on, the
/// policy is `.regular` whether or not a window is open. It is applied at
/// the start of launch as well, so the icon is there before a window opens.
/// `LSUIElement` stays true: with the switch off, the Dock is not told about
/// Blinky at all until a window asks.
///
/// Sparkle's update window is not one of those tracked windows. An accessory
/// policy is also why that window opens behind everything else, so while the
/// offer is up the icon stays even if the window switch is off.
///
/// One owner rather than one per window: with each controller setting the
/// policy itself, closing the main window under an open recap — or the
/// other way round — took the Dock icon away from the window still showing.
///
/// `.regular` is also what puts Pulse in ⌘-Tab, which is the point.
@MainActor
final class DockPresence {
    private let settings: AppSettings
    private let windows = NSHashTable<NSWindow>.weakObjects()
    /// Sparkle's update session is showing a window. Cleared when that session ends.
    private var updateOfferVisible = false

    init(settings: AppSettings) {
        self.settings = settings
        settings.onDockIconChange = { [weak self] in self?.apply() }
    }

    /// `.regular` while Always show Dock icon is on, while a tracked window
    /// wants the icon, or while Sparkle is showing an update. Anything else
    /// stays `.accessory`. A tracked window is the main window, a recap, or
    /// the service chooser; the policy does not distinguish them.
    nonisolated static func activationPolicy(
        alwaysShowsDockIcon: Bool,
        trackedWindowOpen: Bool,
        showsDockIconInSettings: Bool,
        updateOfferVisible: Bool
    ) -> NSApplication.ActivationPolicy {
        if alwaysShowsDockIcon { return .regular }
        let settingsWantDock = trackedWindowOpen && showsDockIconInSettings
        return settingsWantDock || updateOfferVisible ? .regular : .accessory
    }

    /// The policy at launch, before any window exists. Always-show is the
    /// only reason to be `.regular` this early; `LSUIElement` has already
    /// kept the icon off, and this is what turns it on without a flash of
    /// the opposite.
    nonisolated static func launchPolicy(alwaysShowsDockIcon: Bool) -> NSApplication.ActivationPolicy {
        activationPolicy(
            alwaysShowsDockIcon: alwaysShowsDockIcon,
            trackedWindowOpen: false,
            showsDockIconInSettings: false,
            updateOfferVisible: false
        )
    }

    /// The update offer is not a window this type tracks. `AppUpdate` says when
    /// Sparkle is showing one, and when that session has finished.
    func setUpdateOfferVisible(_ visible: Bool) {
        updateOfferVisible = visible
        apply()
    }

    func track(_ window: NSWindow) {
        windows.add(window)
    }

    /// Closes every window the Dock icon stands for — the answer to the
    /// Dock's Quit (`DockQuit`) — and the icon goes with the last of them.
    func closeWindows() {
        for window in windows.allObjects where window.isVisible || window.isMiniaturized {
            window.close()
        }
        apply()
    }

    /// Re-reads which windows are open. `closing` is a window `close()` is in
    /// the middle of: it still reports visible, so it is left out of the count.
    ///
    /// `showingWindow` is the window this call is about to order front. It
    /// counts as open before that, so the policy can become `.regular` first.
    /// Activation follows `MainWindowActivation`: a change into `.regular`
    /// waits until the next turn, or the menu bar keeps the name of whichever
    /// app was frontmost.
    func apply(closing: NSWindow? = nil, showingWindow: NSWindow? = nil) {
        // The window being shown is not visible yet: ordering it front is
        // what this call does, after the policy. Leaving it out kept Blinky
        // an accessory app, so the window stayed behind the one that was key.
        let listed = windows.allObjects
        let showingUntracked = showingWindow.map { showing in
            showing !== closing && !listed.contains { $0 === showing }
        } ?? false
        let open = Self.anyOpen(
            listed.map { window in
                (
                    closing: window === closing,
                    showing: window === showingWindow,
                    visible: window.isVisible,
                    miniaturized: window.isMiniaturized
                )
            },
            showingUntracked: showingUntracked
        )
        let policy = Self.activationPolicy(
            alwaysShowsDockIcon: settings.alwaysShowsDockIcon,
            trackedWindowOpen: open,
            showsDockIconInSettings: settings.showsDockIconInSettings,
            updateOfferVisible: updateOfferVisible
        )
        let changed = NSApp.activationPolicy() != policy
        if changed { NSApp.setActivationPolicy(policy) }
        // After the policy. `makeKeyAndOrderFront` only orders among this
        // app's windows, so a window opened while another app is key stays
        // behind it. `orderFrontRegardless` puts it on top either way.
        if let showingWindow {
            MainWindowActivation.orderFront(showingWindow)
        }
        let timing = MainWindowActivation.timing(
            policy: policy,
            policyChanged: changed,
            wantsAttention: showingWindow != nil || updateOfferVisible
        )
        MainWindowActivation.perform(timing) { [weak showingWindow] in
            MainWindowActivation.orderFront(showingWindow)
        }
    }

    /// Whether one tracked window counts as open for the Dock policy.
    ///
    /// The window being shown counts before AppKit has ordered it front.
    /// A window `close()` is still inside of reports visible and does not.
    nonisolated static func countsAsOpen(
        isClosing: Bool,
        isShowing: Bool,
        isVisible: Bool,
        isMiniaturized: Bool
    ) -> Bool {
        if isClosing { return false }
        return isShowing || isVisible || isMiniaturized
    }

    /// True when any tracked window is open, including one that is about to
    /// be shown and is not in the tracked list yet.
    nonisolated static func anyOpen(
        _ windows: [(closing: Bool, showing: Bool, visible: Bool, miniaturized: Bool)],
        showingUntracked: Bool
    ) -> Bool {
        if showingUntracked { return true }
        return windows.contains {
            countsAsOpen(
                isClosing: $0.closing,
                isShowing: $0.showing,
                isVisible: $0.visible,
                isMiniaturized: $0.miniaturized
            )
        }
    }
}

/// When a tracked window should claim the menu bar.
///
/// Blinky starts as an `.accessory` app (`LSUIElement`, no Dock icon). The
/// menu bar names whichever app is active. Opening Settings, a recap, or the
/// service chooser has to become `.regular` and then activate, or the menu
/// bar keeps the previous app's name while the window's own title already
/// says Blinky.
///
/// Activating in the same turn as `setActivationPolicy(.regular)` is too
/// early: macOS still treats the process as an accessory, and the click that
/// opened the window often came from the non-activating usage panel. One
/// `NSApp.activate` in that turn, or on the next one, was still leaving the
/// previous app as the menu-bar owner. The claim is repeated on the following
/// turn, through `NSRunningApplication` as well as `NSApp`, and the window is
/// made main after that claim. Staying `.accessory` — the while-open Dock
/// switch is off, and always-show is off — still tries; an accessory app has
/// no application menu for the system to put Blinky's name on, and the
/// default while-open Dock switch is what makes the policy `.regular`.
///
/// Call sites, all through `DockPresence.apply(showingWindow:)`: the main
/// window (`SettingsWindowController.show` — the usage card's grid symbol, the panel
/// menu's Settings…, the menu bar item, ⌘,, a reopen, `pulse://settings`, and
/// a clicked notification), the recap window, and the service chooser. An
/// update offer uses `apply()` without a window; the offer's own focus runs
/// on the next turn as well.
enum MainWindowActivation {
    enum Timing: Equatable, Sendable {
        /// Already `.regular`. Activate in this turn.
        case now
        /// The policy just became `.regular`. Activate on the next turn.
        case nextTurn
        /// Staying `.accessory`. The window comes forward, and Blinky still
        /// tries to become the frontmost app. The menu bar names Blinky only
        /// once the policy is `.regular`.
        case orderOnly
        /// Nothing is asking for attention.
        case skip
    }

    static func timing(
        policy: NSApplication.ActivationPolicy,
        policyChanged: Bool,
        wantsAttention: Bool
    ) -> Timing {
        guard policy == .regular else {
            return wantsAttention ? .orderOnly : .skip
        }
        if policyChanged { return .nextTurn }
        return wantsAttention ? .now : .skip
    }

    /// One step of becoming the frontmost app. The order is `claims(for:)`.
    enum Claim: Equatable, Sendable {
        /// Bring the window forward and make it main.
        case orderFront
        /// Become the active app. A deferred claim runs on a later turn,
        /// after a policy change and after the click that opened the window
        /// has finished.
        case claimFrontmost(deferred: Bool)
    }

    /// How `perform` claims the menu bar for this timing.
    ///
    /// `.now` claims in this turn and again on the next one: the first claim
    /// is what an already-regular app can take, and the second is what a
    /// click from the non-activating panel was swallowing. `.nextTurn` and
    /// `.orderOnly` order the window now and claim twice after this turn,
    /// because a policy that just became `.regular` is not visible yet, and
    /// one deferred activate was not enough to take the menu bar.
    static func claims(for timing: Timing) -> [Claim] {
        switch timing {
        case .skip:
            []
        case .now:
            [.claimFrontmost(deferred: false), .claimFrontmost(deferred: true)]
        case .nextTurn, .orderOnly:
            [.orderFront, .claimFrontmost(deferred: true), .claimFrontmost(deferred: true)]
        }
    }

    /// Puts `window` in front of other apps and makes it key and main.
    ///
    /// `makeKeyAndOrderFront` only orders among this app's own windows. While
    /// Blinky is still an accessory, or while `activate` has not landed, that
    /// leaves the window behind whichever app was key. `makeMain` after the
    /// app is active is what puts Blinky's name on the menu bar.
    @MainActor
    static func orderFront(_ window: NSWindow?) {
        guard let window else { return }
        window.orderFrontRegardless()
        window.makeKey()
        window.makeMain()
    }

    /// Asks macOS to make this process the frontmost app.
    ///
    /// `NSRunningApplication.activate(options: [.activateAllWindows])` brings
    /// this process's windows forward. `NSApp.activate(ignoringOtherApps:)` is
    /// the call the rest of AppKit's window ordering is watching. Unhide
    /// first, so a hidden process can become frontmost.
    @MainActor
    static func claimFrontmostApplication() {
        NSApp.unhide(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Runs `claims(for:)`. `after` orders the window again once a claim lands.
    @MainActor
    static func perform(_ timing: Timing, after: (@MainActor () -> Void)? = nil) {
        for claim in claims(for: timing) {
            switch claim {
            case .orderFront:
                after?()
            case .claimFrontmost(let deferred):
                if deferred {
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            claimFrontmostApplication()
                            after?()
                        }
                    }
                } else {
                    claimFrontmostApplication()
                    after?()
                }
            }
        }
    }
}

/// The Dock's Quit, told apart from every other.
///
/// **Pulse's Dock icon stands for its windows, not for Pulse.** It is there
/// while a tracked window is open (`DockPresence`), or the whole time when
/// Always show Dock icon is on, so its menu's Quit reads as "close this" —
/// and quitting the whole app from it took the panel and every reading away
/// from someone who meant to close the main window.
/// So the Dock's Quit closes the windows, and Pulse stays in the menu bar.
/// Pulse's own Quit — ⌘Q, the app menu, the menu bar icon's — still quits.
///
/// **Told apart by the Apple event that asked**: the Dock asks with a quit
/// event sent from the Dock's own process. Logging out, restarting and shutting
/// down send one too, from loginwindow and with a reason attached; those
/// always quit — holding up a logout is worse than any closed window.
enum DockQuit {
    static func isFromDock(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event else { return false }
        let sender = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))
            .flatMap { pid_t(exactly: $0.int32Value) }
            .flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
        return closesWindowsOnly(
            eventClass: event.eventClass,
            eventID: event.eventID,
            sender: sender,
            hasQuitReason: event.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason)) != nil
                || event.paramDescriptor(forKeyword: AEKeyword(kAEQuitReason)) != nil
        )
    }

    static func closesWindowsOnly(eventClass: AEEventClass, eventID: AEEventID, sender: String?, hasQuitReason: Bool) -> Bool {
        eventClass == AEEventClass(kCoreEventClass)
            && eventID == AEEventID(kAEQuitApplication)
            && sender == "com.apple.dock"
            && !hasQuitReason
    }
}
