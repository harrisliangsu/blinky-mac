// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import Testing
@testable import Pulse

/// When opening a tracked window should claim the menu bar.
///
/// The decision is `MainWindowActivation`. The call sites all go through
/// `DockPresence.apply(showingWindow:)`: Settings (the usage card's grid symbol, the
/// panel menu's Settings…, the menu bar item, ⌘,, a reopen, `pulse://settings`,
/// and a clicked notification), the recap, and the service chooser. An update
/// offer uses `apply()` with no window; a policy change still waits a turn.
@Suite("Main window activation")
struct MainWindowActivationTests {
    @Test("Becoming a regular app waits a turn, and an accessory app does not claim the menu")
    func timing() {
        #expect(MainWindowActivation.timing(
            policy: .regular, policyChanged: true, wantsAttention: true
        ) == .nextTurn)
        // Always show Dock icon, turned on with no new window, still activates
        // once the policy has changed.
        #expect(MainWindowActivation.timing(
            policy: .regular, policyChanged: true, wantsAttention: false
        ) == .nextTurn)
        #expect(MainWindowActivation.timing(
            policy: .regular, policyChanged: false, wantsAttention: true
        ) == .now)
        #expect(MainWindowActivation.timing(
            policy: .regular, policyChanged: false, wantsAttention: false
        ) == .skip)
        #expect(MainWindowActivation.timing(
            policy: .accessory, policyChanged: true, wantsAttention: true
        ) == .skip)
        #expect(MainWindowActivation.timing(
            policy: .accessory, policyChanged: false, wantsAttention: false
        ) == .skip)
    }
}
