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
        // No menu bar to claim, and the window is still brought forward.
        #expect(MainWindowActivation.timing(
            policy: .accessory, policyChanged: true, wantsAttention: true
        ) == .orderOnly)
        #expect(MainWindowActivation.timing(
            policy: .accessory, policyChanged: false, wantsAttention: true
        ) == .orderOnly)
        #expect(MainWindowActivation.timing(
            policy: .accessory, policyChanged: false, wantsAttention: false
        ) == .skip)
        #expect(MainWindowActivation.timing(
            policy: .regular, policyChanged: false, wantsAttention: true
        ) != .skip)
    }

    @Test("Opening claims the frontmost app, and claims again on the next turn")
    func claimsFrontmost() {
        #expect(MainWindowActivation.claims(for: .skip).isEmpty)
        #expect(MainWindowActivation.claims(for: .now) == [
            .claimFrontmost(deferred: false),
            .claimFrontmost(deferred: true),
        ])
        let deferred = [
            MainWindowActivation.Claim.orderFront,
            .claimFrontmost(deferred: true),
            .claimFrontmost(deferred: true),
        ]
        #expect(MainWindowActivation.claims(for: .nextTurn) == deferred)
        #expect(MainWindowActivation.claims(for: .orderOnly) == deferred)
    }

    @Test("A window being shown counts as open before it is visible")
    func showingWindowCountsBeforeItIsVisible() {
        #expect(DockPresence.countsAsOpen(
            isClosing: false, isShowing: true, isVisible: false, isMiniaturized: false
        ))
        #expect(!DockPresence.countsAsOpen(
            isClosing: true, isShowing: true, isVisible: true, isMiniaturized: false
        ))
        #expect(DockPresence.countsAsOpen(
            isClosing: false, isShowing: false, isVisible: true, isMiniaturized: false
        ))
        #expect(DockPresence.countsAsOpen(
            isClosing: false, isShowing: false, isVisible: false, isMiniaturized: true
        ))
        #expect(!DockPresence.countsAsOpen(
            isClosing: false, isShowing: false, isVisible: false, isMiniaturized: false
        ))
        #expect(DockPresence.anyOpen(
            [(closing: false, showing: true, visible: false, miniaturized: false)],
            showingUntracked: false
        ))
        #expect(!DockPresence.anyOpen(
            [(closing: true, showing: false, visible: true, miniaturized: false)],
            showingUntracked: false
        ))
        #expect(DockPresence.anyOpen([], showingUntracked: true))
        #expect(!DockPresence.anyOpen([], showingUntracked: false))
    }
}
