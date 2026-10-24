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
    /// `showingWindow` is a window that was just ordered front. The policy is
    /// applied first, then activation follows `MainWindowActivation`: a change
    /// into `.regular` waits until the next turn, or the menu bar keeps the
    /// name of whichever app was frontmost.
    func apply(closing: NSWindow? = nil, showingWindow: NSWindow? = nil) {
        let open = windows.allObjects.contains { $0 !== closing && ($0.isVisible || $0.isMiniaturized) }
        let policy = Self.activationPolicy(
            alwaysShowsDockIcon: settings.alwaysShowsDockIcon,
            trackedWindowOpen: open,
            showsDockIconInSettings: settings.showsDockIconInSettings,
            updateOfferVisible: updateOfferVisible
        )
        let changed = NSApp.activationPolicy() != policy
        if changed { NSApp.setActivationPolicy(policy) }
        let timing = MainWindowActivation.timing(
            policy: policy,
            policyChanged: changed,
            wantsAttention: showingWindow != nil || updateOfferVisible
        )
        MainWindowActivation.perform(timing) { [weak showingWindow] in
            showingWindow?.makeKeyAndOrderFront(nil)
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
/// opened the window often came from the non-activating usage panel. The
/// activation waits until the next turn. An app that is already `.regular`
/// (Always show Dock icon, or another tracked window already open) activates
/// immediately. Staying `.accessory` — the while-open Dock switch is off, and
/// always-show is off — has no application menu to claim.
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
        /// Staying `.accessory`, or nothing is asking for attention.
        case skip
    }

    static func timing(
        policy: NSApplication.ActivationPolicy,
        policyChanged: Bool,
        wantsAttention: Bool
    ) -> Timing {
        guard policy == .regular else { return .skip }
        if policyChanged { return .nextTurn }
        return wantsAttention ? .now : .skip
    }

    /// Activates, then runs `after` (the window being made key again).
    @MainActor
    static func perform(_ timing: Timing, after: (@MainActor () -> Void)? = nil) {
        switch timing {
        case .skip:
            break
        case .now:
            NSApp.activate(ignoringOtherApps: true)
            after?()
        case .nextTurn:
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    NSApp.activate(ignoringOtherApps: true)
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
