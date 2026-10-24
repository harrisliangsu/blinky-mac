// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import Foundation
import Testing
@testable import Pulse

/// Real event delivery through the Token spend window.
///
/// Earlier tests called `SpendGlanceDismissal` with rectangles and key codes.
/// The window on a Mac still dropped the click: a utility panel never became
/// key, `sendEvent` returned before the content view, and the content covered
/// the close button. These tests build that window and send the events.
@MainActor
@Suite("Token spend glance window", .serialized)
struct SpendGlanceWindowTests {
    @Test("The window sits above the rail and under a menu")
    func level() {
        let aboveRail = SpendGlanceWindowLevel.above(.statusBar)
        #expect(aboveRail.rawValue > NSWindow.Level.floating.rawValue)
        #expect(aboveRail.rawValue < NSWindow.Level.popUpMenu.rawValue)
        #expect(SpendGlanceWindowLevel.above(.popUpMenu).rawValue < NSWindow.Level.popUpMenu.rawValue)
        #expect(SpendGlanceWindowLevel.above(.floating).rawValue == NSWindow.Level.floating.rawValue + 1)

        #expect(SpendGlanceWindowLevel.isAuxiliary(level: .popUpMenu, className: "NSWindow"))
        #expect(SpendGlanceWindowLevel.isAuxiliary(level: .normal, className: "NSMenuWindow"))
        #expect(SpendGlanceWindowLevel.isAuxiliary(level: .normal, className: "DatePickerPanel"))
        #expect(!SpendGlanceWindowLevel.isAuxiliary(level: .floating, className: "SpendGlancePanel"))
        #expect(!SpendGlanceWindowLevel.dismisses(inside: true, auxiliary: false))
        #expect(!SpendGlanceWindowLevel.dismisses(inside: false, auxiliary: true))
        #expect(SpendGlanceWindowLevel.dismisses(inside: false, auxiliary: false))
    }

    @Test("Span, breakdown, Refresh, Share, the close button, and Escape all reach the window")
    func controlsReceiveEvents() throws {
        LocalizationSource.use(.english)
        defer { LocalizationSource.use(.system) }

        let (defaults, cleanup) = AppSettingsPersistenceTests.isolatedDefaults()
        defer { cleanup() }
        let settings = AppSettings(defaults: defaults)
        settings.readsTokenSpend = true
        settings.spendSpan = .month

        let controller = SpendGlanceController(settings: settings)
        controller.model.presentReadySummary()
        controller.anchor = {
            SpendGlanceAnchor(
                rail: CGRect(x: 800, y: 700, width: 280, height: 36),
                edge: .right,
                screen: CGRect(x: 0, y: 0, width: 1440, height: 900),
                cardClearance: 12,
                level: .statusBar
            )
        }
        controller.show()
        defer {
            settings.readsTokenSpend = false
            controller.close()
        }

        let window = try #require(NSApp.windows.first { $0 is SpendGlancePanel } as? SpendGlancePanel)
        #expect(!window.isKind(of: NSPanel.self))
        #expect(window.canBecomeKey)
        #expect(window.canBecomeMain)
        #expect(window.styleMask.contains(.titled))
        #expect(window.styleMask.contains(.closable))
        #expect(!window.styleMask.contains(.fullSizeContentView))
        #expect(!window.styleMask.contains(.utilityWindow))
        #expect(window.level == SpendGlanceWindowLevel.above(.statusBar))
        #expect(window.contentView?.acceptsFirstMouse(for: nil) == true)
        #expect(window.title == "Token spend")

        window.makeKey()
        window.displayIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        pump()
        window.contentView?.layoutSubtreeIfNeeded()
        let content = try #require(window.contentView)
        let views = Self.flatten(content)
        // SwiftUI's menu picker is a popup view, not an NSPopUpButton. The
        // hosting view that wraps it also has "PopUpButton" in its class name;
        // hit-testing that wrapper lands on the popup, which is not inside it.
        let menus = views.filter {
            String(describing: Swift.type(of: $0)).contains("SwiftUIPopupButton")
        }
        #expect(menus.count >= 1)
        for menu in menus {
            let hit = Self.hit(menu, in: content)
            let name = hit.map { String(describing: Swift.type(of: $0)) } ?? ""
            #expect(Self.contains(hit, menu) || name.contains("PopupButton") || name.contains("PopUpButton"))
        }

        // Refresh and Share have no NSButton. Their layout frames are in
        // window coordinates, and the click is a real event at that point.
        let shareFrame = try #require(
            controller.model.controlFrames["spend-glance-share"],
            "Share has no layout frame. Recorded: \(controller.model.controlFrames)"
        )
        let refreshFrame = try #require(
            controller.model.controlFrames["spend-glance-refresh"],
            "Refresh has no layout frame. Recorded: \(controller.model.controlFrames)"
        )
        #expect(Self.hit(shareFrame, in: content) != nil)
        #expect(Self.hit(refreshFrame, in: content) != nil)

        // Share before Refresh. Refresh starts a read, and that read must not
        // be what this click is proving.
        try Self.click(shareFrame, in: window)
        pump()
        #expect(controller.model.didCopy || controller.model.copyFailed)

        // A menu's click is outside this window's frame and must not dismiss it.
        let menu = NSWindow(
            contentRect: NSRect(x: 20, y: 20, width: 120, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        menu.level = .popUpMenu
        menu.orderFront(nil)
        defer { menu.orderOut(nil) }
        let menuClick = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: menu.windowNumber,
            context: nil,
            eventNumber: 7,
            clickCount: 1,
            pressure: 1
        ))
        NSApp.sendEvent(menuClick)
        #expect(controller.isOpen)
        menu.orderOut(nil)

        // A click in the content must reach the control. The old sendEvent
        // returned before super, so this click changed nothing.
        let rescanBefore = controller.model.rescan
        try Self.click(refreshFrame, in: window)
        #expect(controller.model.rescan == rescanBefore + 1)
        #expect(controller.isOpen)

        let close = try #require(window.standardWindowButton(.closeButton))
        #expect(close.isEnabled)
        if let frame = window.contentView?.superview {
            let hit = Self.hit(close, in: frame)
            #expect(Self.contains(hit, close))
        }
        close.performClick(nil)
        #expect(!controller.isOpen)
        #expect(!window.isVisible)

        controller.show()
        pump()
        let again = try #require(NSApp.windows.first { $0 is SpendGlancePanel })
        again.makeKey()
        pump()
        let escape = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: again.windowNumber,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: SpendGlanceDismissal.escapeKeyCode
        ))
        if again.isKeyWindow {
            again.sendEvent(escape)
        } else {
            NSApp.sendEvent(escape)
        }
        #expect(!controller.isOpen)
    }

    @Test("A click on another window closes the Token window")
    func clickOutsideCloses() throws {
        LocalizationSource.use(.english)
        defer { LocalizationSource.use(.system) }
        let (defaults, cleanup) = AppSettingsPersistenceTests.isolatedDefaults()
        defer { cleanup() }
        let settings = AppSettings(defaults: defaults)
        settings.readsTokenSpend = true
        let controller = SpendGlanceController(settings: settings)
        controller.model.presentReadySummary()
        controller.anchor = {
            SpendGlanceAnchor(
                rail: CGRect(x: 800, y: 700, width: 280, height: 36),
                edge: .right,
                screen: CGRect(x: 0, y: 0, width: 1440, height: 900),
                cardClearance: 12,
                level: .statusBar
            )
        }
        controller.show()
        defer {
            settings.readsTokenSpend = false
            controller.close()
        }
        pump()
        #expect(controller.isOpen)
        let other = NSWindow(
            contentRect: NSRect(x: 40, y: 40, width: 80, height: 40),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        other.level = .normal
        other.orderFront(nil)
        defer { other.orderOut(nil) }
        let click = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: other.windowNumber,
            context: nil,
            eventNumber: 11,
            clickCount: 1,
            pressure: 1
        ))
        NSApp.sendEvent(click)
        #expect(!controller.isOpen)
    }

    @Test("Escape closes the window when it is not key, and a menu keeps Escape")
    func escapeWithoutKey() throws {
        let fixture = openGlance()
        defer { fixture.finish() }
        let controller = fixture.controller
        let window = try glanceWindow()
        let installed = controller.monitorInstallation
        #expect(installed.local)
        #expect(installed.global)
        #expect(installed.resignActive)
        #expect(installed.becomeActive)

        window.resignKey()
        let menu = NSWindow(
            contentRect: NSRect(x: 20, y: 20, width: 120, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        menu.level = .popUpMenu
        menu.orderFront(nil)
        defer { menu.orderOut(nil) }
        NSApp.sendEvent(try Self.keyDown(code: SpendGlanceDismissal.escapeKeyCode, windowNumber: 0))
        #expect(controller.isOpen)
        menu.orderOut(nil)

        window.resignKey()
        NSApp.sendEvent(try Self.keyDown(code: SpendGlanceDismissal.escapeKeyCode, windowNumber: 0))
        #expect(!controller.isOpen)
        #expect(!window.isVisible)
    }

    @Test("A click outside the app, and leaving the app, close the window")
    func outsideTheAppCloses() throws {
        let fixture = openGlance()
        defer { fixture.finish() }
        let controller = fixture.controller

        // The Token button is not a click outside. The same local monitor
        // that closes on another Blinky window has to leave this one alone.
        let entry = NSWindow(
            contentRect: NSRect(x: 40, y: 40, width: 80, height: 40),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        entry.level = .normal
        entry.orderFront(nil)
        defer { entry.orderOut(nil) }
        controller.entryRect = entry.frame
        NSApp.sendEvent(try Self.mouseDown(in: entry, eventNumber: 21))
        #expect(controller.isOpen)
        controller.entryRect = .null
        NSApp.sendEvent(try Self.mouseDown(in: entry, eventNumber: 22))
        #expect(!controller.isOpen)

        controller.show()
        pump()
        #expect(controller.monitorInstallation.global)
        // The handler the global monitor calls. A synthesized `NSApp.sendEvent`
        // never takes that path: it is a local event.
        controller.noteClickOutsideTheApp()
        pump()
        #expect(!controller.isOpen)

        controller.show()
        pump()
        let again = try glanceWindow()
        again.resignKey()
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        pump()
        #expect(controller.monitorInstallation.closesWhenAppResigns)
        if NSApp.isActive {
            #expect(again.isKeyWindow)
        }
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        #expect(!controller.isOpen)

        controller.show()
        pump()
        #expect(controller.monitorInstallation.local)
        controller.close()
        pump()
        let gone = controller.monitorInstallation
        #expect(!gone.local)
        #expect(!gone.global)
        #expect(!gone.resignActive)
        #expect(!gone.becomeActive)
        #expect(!gone.closesWhenAppResigns)
    }

    private struct GlanceFixture {
        let controller: SpendGlanceController
        let finish: () -> Void
    }

    private func openGlance() -> GlanceFixture {
        LocalizationSource.use(.english)
        let (defaults, cleanup) = AppSettingsPersistenceTests.isolatedDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.readsTokenSpend = true
        let controller = SpendGlanceController(settings: settings)
        controller.model.presentReadySummary()
        controller.anchor = {
            SpendGlanceAnchor(
                rail: CGRect(x: 800, y: 700, width: 280, height: 36),
                edge: .right,
                screen: CGRect(x: 0, y: 0, width: 1440, height: 900),
                cardClearance: 12,
                level: .statusBar
            )
        }
        controller.show()
        pump()
        return GlanceFixture(controller: controller, finish: {
            settings.readsTokenSpend = false
            controller.close()
            cleanup()
            LocalizationSource.use(.system)
        })
    }

    private func glanceWindow() throws -> SpendGlancePanel {
        try #require(NSApp.windows.first { $0 is SpendGlancePanel && $0.isVisible } as? SpendGlancePanel)
    }

    private static func keyDown(code: UInt16, windowNumber: Int) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: windowNumber,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: code
        ))
    }

    private static func mouseDown(in window: NSWindow, eventNumber: Int) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: eventNumber,
            clickCount: 1,
            pressure: 1
        ))
    }

    private func pump() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }

    private static func flatten(_ view: NSView?) -> [NSView] {
        guard let view else { return [] }
        return [view] + view.subviews.flatMap { flatten($0) }
    }

    private static func hit(_ control: NSView, in root: NSView) -> NSView? {
        let inWindow = control.convert(NSPoint(x: control.bounds.midX, y: control.bounds.midY), to: nil)
        guard let superview = root.superview else { return root.hitTest(inWindow) }
        return root.hitTest(superview.convert(inWindow, from: nil))
    }

    private static func hit(_ frame: CGRect, in root: NSView) -> NSView? {
        let point = NSPoint(x: frame.midX, y: frame.midY)
        guard let superview = root.superview else { return root.hitTest(point) }
        return root.hitTest(superview.convert(point, from: nil))
    }

    private static func contains(_ hit: NSView?, _ control: NSView) -> Bool {
        var view = hit
        while let current = view {
            if current === control { return true }
            view = current.superview
        }
        return false
    }

    /// `frame` is in the window's base coordinates, which is where `sendEvent` looks.
    private static func click(_ frame: CGRect, in window: NSWindow) throws {
        try #require(!frame.isEmpty)
        let point = NSPoint(x: frame.midX, y: frame.midY)
        let down = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
        let up = try #require(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 1
        ))
        window.sendEvent(down)
        window.sendEvent(up)
    }
}
