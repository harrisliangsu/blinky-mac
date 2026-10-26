// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import UserNotifications

/// How a newer Blinky is announced.
///
/// Notify first is the shipped default. A scheduled check posts a notification
/// and leaves Sparkle's window hidden until that notification is clicked.
/// Show the window is the previous behaviour: the offer comes forward as soon
/// as the check finds a version. Install silently downloads on that scheduled
/// check, then installs and relaunches Blinky, with no notification and no
/// window before that install. What the new version says is
/// `InstalledUpdateNotice`. Check for Updates… and About's Check now are none
/// of those — the reader asked, so the window opens either way.
///
/// **This type decides. It does not post, activate, or talk to Sparkle.**
/// `AppUpdate` performs the action. The cases are the whole of the policy, so
/// a test can pin them without a window server or a notification centre.
enum UpdateDiscovery: String, CaseIterable, Identifiable, Sendable {
    /// A notification. The update window opens when that notification is clicked.
    case notifyFirst
    /// Sparkle's update window, as soon as a scheduled check finds a version.
    case showWindow
    /// A scheduled check downloads the update, installs it, and relaunches
    /// Blinky. No notification and no update window before that install.
    /// The launch that is the new version is `InstalledUpdateNotice`.
    case installSilently

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notifyFirst: String.localized("Notify first")
        case .showWindow: String.localized("Show the window")
        case .installSilently: String.localized("Install silently")
        }
    }
}

enum UpdateAnnouncement {
    /// The notification's identifier. One at a time: a later find replaces it.
    static let notificationIdentifier = "blinky-update"

    /// What the system has said about posting a notification.
    ///
    /// A provisional grant can still deliver one, so it counts as authorized.
    /// Only an explicit denial falls straight through to the window. Not
    /// determined means nobody has been asked, which is its own step rather
    /// than a silent loss.
    enum Permission: Equatable, CaseIterable, Sendable {
        case notDetermined
        case authorized
        case denied
    }

    /// Who the find is for. A scheduled check is Sparkle's timer. Manual is
    /// Check for Updates… and About's Check now. A click on the notice is the
    /// reader asking to see the offer that check already found.
    enum Origin: Equatable, Sendable {
        case scheduled
        case manual
        case notificationClick
    }

    /// What `AppUpdate` should do. It does not include the Dock or the window
    /// server: showing the offer is one action, wherever it is performed.
    enum Action: Equatable, Sendable {
        /// Sparkle's offer window, brought forward. No notification.
        case showOffer
        /// Post the notification and leave the offer hidden.
        case notify
        /// Ask for notification permission, then `actionAfterPermission`.
        case askPermission
        /// Download on the scheduled check, then install and relaunch. No notice, no window.
        case installSilently
    }

    /// What `AppUpdate.check` does. Both end at the offer window: a held
    /// offer is the one already found, and a fresh check is the user-initiated
    /// path on which Sparkle shows the window itself.
    enum Check: Equatable, Sendable {
        case revealHeldOffer
        case startUserInitiatedCheck
    }

    static func permission(_ status: UNAuthorizationStatus) -> Permission {
        switch status {
        case .authorized, .provisional:
            .authorized
        case .denied:
            .denied
        case .notDetermined:
            .notDetermined
        @unknown default:
            .notDetermined
        }
    }

    /// The policy for a find, or for the reader asking to see one.
    ///
    /// Manual and a notification click ignore the setting and the grant: the
    /// window is what was asked for. A scheduled check under Show the window
    /// does the same. Install silently never notifies and never opens the
    /// window, whatever the grant is. Notify first posts when it can, asks
    /// when it has not been allowed to, and shows the window when the grant
    /// was refused — a refused grant must not swallow the update.
    static func action(
        origin: Origin,
        discovery: UpdateDiscovery,
        permission: Permission
    ) -> Action {
        switch origin {
        case .manual, .notificationClick:
            return .showOffer
        case .scheduled:
            switch discovery {
            case .showWindow:
                return .showOffer
            case .installSilently:
                return .installSilently
            case .notifyFirst:
                switch permission {
                case .authorized: return .notify
                case .denied: return .showOffer
                case .notDetermined: return .askPermission
                }
            }
        }
    }

    /// The answer to `askPermission`.
    ///
    /// A grant posts the notice only while Notify first is still the choice.
    /// Install silently stays silent if the reader switches to it while the
    /// prompt is up. Anything else — denied, the centre unavailable, or the
    /// reader switching to Show the window — shows the offer.
    static func actionAfterPermission(granted: Bool, discovery: UpdateDiscovery) -> Action {
        if discovery == .installSilently { return .installSilently }
        if granted, discovery == .notifyFirst { return .notify }
        return .showOffer
    }

    /// Whether Sparkle should download a scheduled find without an offer window.
    ///
    /// Only Install silently. Notify first and Show the window leave
    /// `automaticallyDownloadsUpdates` false, so a fresh install stays
    /// offer-only until the reader picks this case. `SUAutomaticallyUpdate`
    /// in the plist stays false for the same reason: the download begins only
    /// after the reader chooses Install silently.
    static func automaticallyDownloadsUpdates(for discovery: UpdateDiscovery) -> Bool {
        discovery == .installSilently
    }

    /// Whether a finished download installs and relaunches in this session.
    ///
    /// Install silently is that choice. The other two leave the package for
    /// the reader to install from the offer window. A menu-bar app often
    /// never quits, so waiting for the next quit leaves the download unused.
    static func installsImmediately(for discovery: UpdateDiscovery) -> Bool {
        discovery == .installSilently
    }

    /// Sparkle's install-on-quit question.
    ///
    /// Returning true and running `install` is what installs and relaunches
    /// now. The block is scheduled, not called here, so Sparkle can finish
    /// this delegate before the process starts quitting. Returning false
    /// leaves the package until Blinky quits, which is every choice except
    /// Install silently.
    static func immediateInstall(
        discovery: UpdateDiscovery,
        install: @escaping () -> Void,
        schedule: (@escaping () -> Void) -> Void
    ) -> Bool {
        guard installsImmediately(for: discovery) else { return false }
        schedule(install)
        return true
    }

    /// Whether Sparkle's standard driver should present a scheduled find.
    ///
    /// `immediateFocus` is Sparkle's own moment (just launched, or the Mac has
    /// been idle). It does not change the answer: a scheduled check near
    /// launch is still a scheduled check, and Notify first still notifies.
    /// Returning false means this app posts the notice or asks first, and
    /// shows the offer later. Returning true means Sparkle shows it now.
    static func sparkleShowsScheduledUpdate(
        discovery: UpdateDiscovery,
        permission: Permission,
        immediateFocus _: Bool = false
    ) -> Bool {
        action(origin: .scheduled, discovery: discovery, permission: permission) == .showOffer
    }

    /// `AppUpdate.check`, which is what Check for Updates…, Check now, and a
    /// click on the notice all call. A held offer is revealed. Anything else
    /// starts the user-initiated check, which shows Sparkle's window itself.
    static func check(holdingScheduledOffer: Bool) -> Check {
        holdingScheduledOffer ? .revealHeldOffer : .startUserInitiatedCheck
    }
}
