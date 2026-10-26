// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import Testing
@testable import Pulse

/// When opening a tracked window should claim the menu bar.
///
/// The decision is `MainWindowActivation`. The call sites all go through
/// `DockPresence.apply(showingWindow:)`, and again when that window becomes
/// key while another app is still frontmost: Settings (the usage card's grid
/// symbol, the panel menu's Settings…, the menu bar item, ⌘,, a reopen,
/// `pulse://settings`, and a clicked notification), the recap, and the
/// service chooser. An update offer uses `apply()` with no window; a policy
/// change still waits a turn.
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

    @Test("The follow-up claim waits past the turn a menu uses to restore the previous app")
    func claimsFrontmost() {
        #expect(MainWindowActivation.claims(for: .skip).isEmpty)
        #expect(MainWindowActivation.claims(for: .now) == [
            .claimFrontmost(turn: 0),
            .claimFrontmost(turn: 2),
        ])
        let deferred = [
            MainWindowActivation.Claim.orderFront,
            .claimFrontmost(turn: 1),
            .claimFrontmost(turn: 2),
        ]
        #expect(MainWindowActivation.claims(for: .nextTurn) == deferred)
        #expect(MainWindowActivation.claims(for: .orderOnly) == deferred)
        for timing: MainWindowActivation.Timing in [.now, .nextTurn, .orderOnly] {
            let turns = MainWindowActivation.claims(for: timing).compactMap { claim -> Int? in
                if case .claimFrontmost(let turn) = claim { return turn }
                return nil
            }
            #expect(turns.count == 2)
            if turns.count == 2 {
                #expect(turns[0] < turns[1])
                #expect(turns[1] >= 2)
            }
        }
    }

    @Test("Another frontmost app is named in the activation request")
    func activationNamesTheFrontmostApp() {
        #expect(MainWindowActivation.activationSource(frontmostPID: nil, currentPID: 10) == .thisApp)
        #expect(MainWindowActivation.activationSource(frontmostPID: 10, currentPID: 10) == .thisApp)
        #expect(MainWindowActivation.activationSource(frontmostPID: 20, currentPID: 10) == .frontmostApp)
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
