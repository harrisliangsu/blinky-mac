// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import SwiftUI
import Testing
@testable import Pulse

/// Header presses on the usage card.
///
/// The panel never becomes key, and a view under the symbol was dropping the
/// click. `FloatingPanel.sendEvent` takes the press from the rectangle the
/// button laid out. These events are the window's own routing. They are not
/// a real pointer on glass.
@MainActor
@Suite("Card header")
struct CardHeaderTests {
    @Test("Open is a filled grid, beside Token spend and Quit")
    func symbols() {
        #expect(CardHeaderControl.allCases.map(\.symbolName) == [
            "chart.bar",
            "square.grid.2x2.fill",
            "power",
        ])
        #expect(CardHeaderControl.openApp.symbolName == "square.grid.2x2.fill")
        #expect(CardHeaderControl.tokenSpend.symbolName == "chart.bar")
        #expect(CardHeaderControl.quit.symbolName == "power")
        for control in CardHeaderControl.allCases {
            let name = control.symbolName
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil)
        }
        #expect(HeaderIconButton.label(for: .openApp) == String.localized("Open Blinky"))
        #expect(HeaderIconButton.label(for: .tokenSpend) == String.localized("Token spend"))
        #expect(HeaderIconButton.label(for: .quit) == String.localized("Quit Blinky"))
        #expect(HeaderIconButton.tip(for: .tokenSpend) == String.localized("Open the Token spend window"))
        #expect(HeaderIconButton.tip(for: .openApp) == String.localized("Open the Blinky window"))
        #expect(HeaderIconButton.tip(for: .quit) == String.localized("Quit Blinky"))
        #expect(CardHeaderMetrics.hitOutset <= 4)
        #expect(CardHeaderMetrics.clusterSpacing <= 2)
        #expect(HeaderTitleFit.minimumScale < 1)
        #expect(!HeaderTitleFit.needsTooltip(idealWidth: 40, availableWidth: 120))
        #expect(!HeaderTitleFit.needsTooltip(idealWidth: 100, availableWidth: 80))
        #expect(HeaderTitleFit.needsTooltip(idealWidth: 200, availableWidth: 80))
        #expect(!HeaderTitleFit.needsTooltip(idealWidth: 0, availableWidth: 80))
        let chinese = LocalizationSource.bundle(for: .chineseSimplified)
        #expect(chinese.localizedString(forKey: "Open the Token spend window", value: nil, table: nil) == "打开 Token 消耗窗口")
        #expect(chinese.localizedString(forKey: "Open the Blinky window", value: nil, table: nil) == "打开 Blinky 主窗口")
        #expect(chinese.localizedString(forKey: "Quit Blinky", value: nil, table: nil) == "退出 Blinky")
        let english = LocalizationSource.bundle(for: .english)
        #expect(english.localizedString(forKey: "Open Blinky", value: nil, table: nil) == "Open Blinky")
        #expect(english.localizedString(forKey: "Token spend", value: nil, table: nil) == "Token spend")
        #expect(english.localizedString(forKey: "Quit Blinky", value: nil, table: nil) == "Quit Blinky")
    }

    @Test("Mouse-up inside the pressed control activates it, and leaving it does not")
    func dispatch() {
        let open = CGRect(x: 10, y: 10, width: 20, height: 20)
        let quit = CGRect(x: 40, y: 10, width: 20, height: 20)
        var frames: [CardHeaderControl: CGRect] = [
            .openApp: open,
            .quit: quit,
            .tokenSpend: CGRect(x: 70, y: 10, width: 40, height: 40),
        ]
        var pressed: CardHeaderControl?

        #expect(HeaderClickDispatch.outcome(
            type: .leftMouseDown, point: CGPoint(x: 15, y: 15), frames: frames, pressed: &pressed
        ) == .taken)
        #expect(pressed == .openApp)
        #expect(HeaderClickDispatch.outcome(
            type: .leftMouseDragged, point: CGPoint(x: 16, y: 16), frames: frames, pressed: &pressed
        ) == .taken)
        #expect(HeaderClickDispatch.outcome(
            type: .leftMouseUp, point: CGPoint(x: 18, y: 18), frames: frames, pressed: &pressed
        ) == .activate(.openApp))
        #expect(pressed == nil)

        #expect(HeaderClickDispatch.outcome(
            type: .leftMouseDown, point: CGPoint(x: 45, y: 15), frames: frames, pressed: &pressed
        ) == .taken)
        #expect(HeaderClickDispatch.outcome(
            type: .leftMouseUp, point: CGPoint(x: 1, y: 1), frames: frames, pressed: &pressed
        ) == .taken)
        #expect(pressed == nil)

        #expect(HeaderClickDispatch.outcome(
            type: .leftMouseDown, point: CGPoint(x: 1, y: 1), frames: frames, pressed: &pressed
        ) == .pass)
        #expect(HeaderClickDispatch.outcome(
            type: .leftMouseDragged, point: CGPoint(x: 15, y: 15), frames: frames, pressed: &pressed
        ) == .pass)
        #expect(HeaderClickDispatch.outcome(
            type: .leftMouseUp, point: CGPoint(x: 15, y: 15), frames: frames, pressed: &pressed
        ) == .pass)
        #expect(pressed == nil)

        frames[.openApp] = .null
        frames[.quit] = CGRect.infinite
        frames[.tokenSpend] = CGRect(x: 0, y: 0, width: 1, height: 20)
        #expect(CardHeaderHit.control(at: CGPoint(x: 0, y: 5), frames: frames) == nil)

        frames = [
            .tokenSpend: CGRect(x: 0, y: 0, width: 100, height: 100),
            .openApp: CGRect(x: 10, y: 10, width: 10, height: 10),
        ]
        #expect(CardHeaderHit.control(at: CGPoint(x: 12, y: 12), frames: frames) == .openApp)
        #expect(CardHeaderHit.control(at: CGPoint(x: 50, y: 50), frames: frames) == .tokenSpend)

        let sink = HeaderFrameSink()
        sink.note(.openApp, CGRect(x: 10, y: 10, width: 20, height: 20))
        #expect(sink.frames[.openApp] != nil)
        sink.note(.openApp, .null)
        #expect(sink.frames[.openApp] == nil)
        sink.note(.quit, CGRect(x: 0, y: 0, width: 0.5, height: 10))
        #expect(sink.frames[.quit] == nil)

        sink.note(.tokenSpend, CGRect(x: 0, y: 0, width: 20, height: 20))
        sink.note(.openApp, CGRect(x: 30, y: 0, width: 20, height: 20))
        sink.replace(with: [.openApp: CGRect(x: 30, y: 0, width: 20, height: 20)])
        #expect(sink.frames[.tokenSpend] == nil)
        #expect(sink.frames[.openApp] != nil)
    }

    @Test("The panel takes a click on each header control and ignores one that leaves it")
    func panelRoutesHeaderClicks() async throws {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.setFrame(NSRect(x: 0, y: 0, width: 420, height: 240), display: false)
        panel.orderFrontRegardless()
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)

        let open = CGRect(x: 180, y: 40, width: 28, height: 28)
        let quit = CGRect(x: 220, y: 40, width: 28, height: 28)
        let spend = CGRect(x: 140, y: 40, width: 28, height: 28)
        panel.headerSink.note(.openApp, open)
        panel.headerSink.note(.quit, quit)
        panel.headerSink.note(.tokenSpend, spend)

        let activated = Activations()
        panel.onHeaderControl = { activated.controls.append($0) }

        try Self.click(open, in: panel)
        #expect(activated.controls.isEmpty)
        await Self.until { activated.controls.count == 1 }
        #expect(activated.controls == [.openApp])

        try Self.click(quit, in: panel)
        await Self.until { activated.controls.count == 2 }
        #expect(activated.controls == [.openApp, .quit])

        try Self.click(spend, in: panel)
        await Self.until { activated.controls.count == 3 }
        #expect(activated.controls == [.openApp, .quit, .tokenSpend])

        try Self.press(
            down: CGPoint(x: quit.midX, y: quit.midY),
            up: CGPoint(x: 8, y: 8),
            in: panel
        )
        await Self.settle()
        #expect(activated.controls == [.openApp, .quit, .tokenSpend])

        try Self.click(CGRect(x: 8, y: 8, width: 4, height: 4), in: panel)
        await Self.settle()
        #expect(activated.controls == [.openApp, .quit, .tokenSpend])
        panel.orderOut(nil)
    }

    private final class Activations {
        var controls: [CardHeaderControl] = []
    }

    @Test("A laid-out header button is hit from its window rectangle, and the view does not also fire")
    func laidOutButtonReceivesTheWindowClick() async throws {
        let fromWindow = Activations()
        let fromView = Activations()
        let panel = FloatingPanel(
            contentRect: NSRect(x: 80, y: 80, width: 80, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let host = NSHostingView(rootView: HeaderIconButton(
            control: .openApp,
            onFrame: { panel.headerSink.note($0, $1) },
            action: { fromView.controls.append(.openApp) }
        ))
        host.frame = NSRect(x: 0, y: 0, width: 80, height: 44)
        panel.contentView = host
        panel.onHeaderControl = { fromWindow.controls.append($0) }
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        host.layoutSubtreeIfNeeded()
        Self.pump()
        host.layoutSubtreeIfNeeded()

        let frame = try #require(panel.headerSink.frames[.openApp])
        #expect(frame.width > 1)
        #expect(frame.height > 1)
        try Self.click(frame, in: panel)
        #expect(fromView.controls.isEmpty)
        #expect(fromWindow.controls.isEmpty)
        await Self.until { fromWindow.controls.count == 1 }
        #expect(fromWindow.controls == [.openApp])
        #expect(fromView.controls.isEmpty)
        panel.orderOut(nil)
    }

    @Test("The first click reaches Token spend when no frame has been stored yet")
    func firstClickBeforeTheFrameIsStored() async throws {
        let fromWindow = Activations()
        let panel = FloatingPanel(
            contentRect: NSRect(x: 80, y: 80, width: 80, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let host = PanelHostingView(rootView: HeaderIconButton(
            control: .tokenSpend,
            onFrame: { panel.headerSink.note($0, $1) },
            action: {}
        ))
        host.frame = NSRect(x: 0, y: 0, width: 80, height: 44)
        panel.contentView = host
        panel.onHeaderControl = { fromWindow.controls.append($0) }
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        host.layoutSubtreeIfNeeded()
        Self.pump()
        host.layoutSubtreeIfNeeded()

        panel.headerSink.replace(with: [:])
        #expect(panel.headerSink.frames[.tokenSpend] == nil)
        let frame = try #require(HeaderControlFrames.collect(in: host)[.tokenSpend])
        #expect(HeaderControlFrames.control(at: CGPoint(x: frame.midX, y: frame.midY), in: host) == .tokenSpend)

        try Self.click(frame, in: panel)
        #expect(fromWindow.controls.isEmpty)
        await Self.until { fromWindow.controls.count == 1 }
        #expect(fromWindow.controls == [.tokenSpend])
        panel.orderOut(nil)
    }

    /// Lets the main-queue block queued by a header click run. The action
    /// waits until AppKit has finished the mouse-up; yielding the main actor
    /// does not drain that queue.
    private static func until(_ ready: () -> Bool) async {
        for _ in 0..<50 {
            if ready() { return }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    private static func settle() async {
        for _ in 0..<5 {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    private static func pump() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    private static func click(_ frame: CGRect, in window: NSWindow) throws {
        try press(
            down: CGPoint(x: frame.midX, y: frame.midY),
            up: CGPoint(x: frame.midX, y: frame.midY),
            in: window
        )
    }

    /// `point` is in the window's base coordinates, which is where `sendEvent` looks.
    private static func press(down: CGPoint, up: CGPoint, in window: NSWindow) throws {
        let downEvent = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: down,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
        let upEvent = try #require(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: up,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 1
        ))
        window.sendEvent(downEvent)
        window.sendEvent(upEvent)
    }
}
