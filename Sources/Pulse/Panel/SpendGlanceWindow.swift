// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import SwiftUI

/// The summary window beside the floating panel.
///
/// A normal window, so Escape, the close button, and a click outside can
/// dismiss it. The usage panel cannot become key, which is why this is not
/// drawn inside that panel.
@MainActor
final class SpendGlanceController {
    private let settings: AppSettings
    let model: SpendGlanceModel
    private let dock: DockPresence?
    private var window: SpendGlancePanel?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    /// The entry button, in screen coordinates. A click there toggles; it is
    /// not a click outside.
    var entryRect = CGRect.null
    /// The rail's screen rect, the edge, and the visible frame. Supplied by
    /// the panel controller, which is created beside this one.
    var anchor: () -> SpendGlanceAnchor? = { nil }

    init(settings: AppSettings, dock: DockPresence? = nil) {
        self.settings = settings
        self.dock = dock
        model = SpendGlanceModel(settings: settings)
    }

    /// Whether the summary is open. False while reading is off: `show` and
    /// `toggle` both leave it closed, and neither makes a window.
    var isOpen: Bool { model.isOpen }

    func toggle() {
        guard settings.readsTokenSpend else {
            close()
            return
        }
        if window?.isVisible == true {
            close()
        } else {
            show()
        }
    }

    func show() {
        guard settings.readsTokenSpend else { return }
        let window = window ?? makeWindow()
        self.window = window
        model.isOpen = true
        if let anchor = anchor(), !window.isVisible {
            window.level = SpendGlanceWindowLevel.above(anchor.level)
            let frame = SpendGlancePlacement.frame(
                rail: anchor.rail,
                edge: anchor.edge,
                screen: anchor.screen,
                cardClearance: anchor.cardClearance
            )
            window.setFrame(frame, display: false)
        }
        window.title = String.localized("Token spend")
        window.standardWindowButton(.closeButton)?.isEnabled = true
        installMonitors()
        dock?.track(window)
        // Same path as the main window: policy first, then in front of other
        // apps. Ordering before the policy change left the window behind.
        if let dock {
            dock.apply(showingWindow: window)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            MainWindowActivation.orderFront(window)
        }
    }

    func close() {
        model.isOpen = false
        let closing = window
        window?.orderOut(nil)
        if let closing { dock?.apply(closing: closing) }
        // `NSEvent.removeMonitor` must not run inside the monitor's own
        // handler. Escape and a click outside both come through that handler,
        // so the removal waits until this call has returned.
        let local = localMonitor
        let global = globalMonitor
        guard local != nil || global != nil else { return }
        localMonitor = nil
        globalMonitor = nil
        DispatchQueue.main.async {
            if let local { NSEvent.removeMonitor(local) }
            if let global { NSEvent.removeMonitor(global) }
        }
    }

    private func share() {
        // Before the toast. The image is the summary on screen, and the
        // confirmation must not be part of it or of the layout under it.
        guard let view = window?.contentView, SpendGlanceExport.copyVisible(view) else {
            model.noteCopyFailed()
            return
        }
        model.noteCopied()
    }

    private func makeWindow() -> SpendGlancePanel {
        // A normal window, not a utility panel. A utility panel at the rail's
        // level does not become key, and SwiftUI menus and buttons in it
        // never see the click. The title bar is the system's, so the close
        // button is not covered by the content view.
        let window = SpendGlancePanel(
            contentRect: NSRect(origin: .zero, size: SpendGlancePlacement.size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = true
        window.backgroundColor = .windowBackgroundColor
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.onDismiss = { [weak self] in self?.close() }
        window.contentView = SpendGlanceHostingView(rootView: SpendGlanceView(
            model: model,
            settings: settings,
            onShare: { [weak self] in self?.share() },
            onDismiss: { [weak self] in self?.close() }
        ))
        return window
    }

    private func installMonitors() {
        guard localMonitor == nil else { return }
        // Monitors run on the main thread. The handler is not annotated with
        // the main actor, and an `NSEvent` cannot cross into that body — a
        // key code, whether a modifier is held, and a window identity can.
        // Same split as the shortcut recorder.
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            let eventType = event.type
            // A mouse event has no key code. Asking for one throws
            // NSInternalInconsistencyException on macOS 26, which is a click
            // that quits the app instead of reaching the button.
            let keyCode: UInt16 = eventType == .keyDown ? event.keyCode : 0
            let hasModifiers = eventType == .keyDown
                && !event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            let eventWindow = event.window.map { ObjectIdentifier($0) }
            // The click's own window and point. The cursor is a fallback for an
            // event that names no window; a real click and a synthesized one
            // then name the same place. The window number crosses into the
            // actor; the window does not.
            let windowNumber = event.windowNumber
            let locationInWindow = event.locationInWindow
            let swallowEscape = MainActor.assumeIsolated { () -> Bool in
                guard let self, let window = self.window, window.isVisible else { return false }
                if eventType == .keyDown {
                    // A menu or a date popover owns Escape. Closing the summary
                    // here used to throw the picker away as it opened.
                    let menuOpen = NSApp.windows.contains {
                        $0 !== window && $0.isVisible && SpendGlanceWindowLevel.isAuxiliary($0)
                    }
                    guard !menuOpen else { return false }
                    guard SpendGlanceDismissal.shouldCloseOnEscape(
                        keyCode: keyCode,
                        hasModifiers: hasModifiers,
                        eventWindow: eventWindow,
                        glanceWindow: ObjectIdentifier(window)
                    ) else { return false }
                    window.close()
                    return true
                }
                let source = NSApp.window(withWindowNumber: windowNumber)
                let auxiliary = source.map { window in
                    SpendGlanceWindowLevel.isAuxiliary(
                        level: window.level,
                        className: String(describing: Swift.type(of: window))
                    )
                } ?? false
                let point = source?.convertPoint(toScreen: locationInWindow) ?? NSEvent.mouseLocation
                if SpendGlanceOutsideClick.shouldClose(
                    point: point,
                    windowFrame: window.frame,
                    entryRect: self.entryRect,
                    auxiliary: auxiliary
                ) {
                    self.close()
                }
                return false
            }
            return swallowEscape ? nil : event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }
}

struct SpendGlanceAnchor {
    var rail: CGRect
    var edge: PanelEdge
    var screen: CGRect
    var cardClearance: CGFloat
    var level: NSWindow.Level
}

/// Where the summary sits relative to the rail and to menus.
///
/// The rail can be at `.statusBar`. A window at that same level, or a utility
/// panel, does not keep a menu in front of it, so a picker looks dead. Stay
/// one level above the rail and strictly under `.popUpMenu`.
enum SpendGlanceWindowLevel {
    static func above(_ rail: NSWindow.Level) -> NSWindow.Level {
        let menu = NSWindow.Level.popUpMenu.rawValue
        let next = max(rail.rawValue, NSWindow.Level.floating.rawValue) + 1
        if next >= menu { return NSWindow.Level(rawValue: menu - 1) }
        return NSWindow.Level(rawValue: next)
    }

    static func isAuxiliary(_ window: NSWindow) -> Bool {
        // The monitor that calls this runs on the main thread, and a window's
        // level is isolated to that actor. The call is not in a main-actor
        // function: the event itself cannot cross into one.
        let level = MainActor.assumeIsolated { window.level }
        return isAuxiliary(level: level, className: String(describing: type(of: window)))
    }

    /// A menu, a popover, or a date picker. A click there is part of a control
    /// in this window, not a click outside it.
    static func isAuxiliary(level: NSWindow.Level, className: String) -> Bool {
        if level.rawValue >= NSWindow.Level.popUpMenu.rawValue { return true }
        return className.contains("Menu")
            || className.contains("Popover")
            || className.contains("Picker")
            || className.contains("Date")
    }

    static func dismisses(inside: Bool, auxiliary: Bool) -> Bool {
        !inside && !auxiliary
    }
}

/// A click outside the Token window closes it. A click on the window, on the
/// button that opened it, or on a menu or date picker does not.
enum SpendGlanceOutsideClick {
    static func shouldClose(
        point: CGPoint,
        windowFrame: CGRect,
        entryRect: CGRect,
        auxiliary: Bool
    ) -> Bool {
        if auxiliary { return false }
        if windowFrame.contains(point) { return false }
        if !entryRect.isNull, !entryRect.isInfinite, entryRect.contains(point) { return false }
        return true
    }
}

/// What closes the glance window, without a window server: plain Escape, and
/// a click that lands inside the close button. A modified Escape is a
/// different shortcut. An empty button is one that has not been laid out.
enum SpendGlanceDismissal {
    static let escapeKeyCode: UInt16 = 53

    static func shouldCloseOnEscape(keyCode: UInt16, hasModifiers: Bool) -> Bool {
        keyCode == escapeKeyCode && !hasModifiers
    }

    /// Escape dismisses this window unless the event is already aimed at a
    /// different one. A key event that has not been given a window yet still
    /// belongs here.
    static func shouldCloseOnEscape(
        keyCode: UInt16,
        hasModifiers: Bool,
        eventWindow: ObjectIdentifier?,
        glanceWindow: ObjectIdentifier
    ) -> Bool {
        guard shouldCloseOnEscape(keyCode: keyCode, hasModifiers: hasModifiers) else { return false }
        if let eventWindow, eventWindow != glanceWindow { return false }
        return true
    }

    static func claimsCloseClick(buttonBounds: CGRect, pointInButton: CGPoint) -> Bool {
        !buttonBounds.isEmpty && buttonBounds.contains(pointInButton)
    }
}

/// Escape and the close button both dismiss. Clicks outside are the controller's monitors.
///
/// This is an `NSWindow`, not a panel. A utility panel never became key while
/// Blinky was an accessory app, and every SwiftUI control in it — the time
/// range, the dimension, Share — then ignored the click. The title bar is
/// the system's, so the close button is not under the content view.
/// `performClose` still closes directly: ⌘W and the button share one path.
/// Escape is taken here while this window is key. A menu that is key keeps it.
final class SpendGlancePanel: NSWindow {
    var onDismiss: (() -> Void)?
    private var closing = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func close() {
        // `onDismiss` orders the window out, which can re-enter `close` while
        // a click or Escape is still being delivered.
        guard !closing else { return }
        closing = true
        defer { closing = false }
        onDismiss?()
        super.close()
    }

    /// The button's action, and ⌘W.
    override func performClose(_ sender: Any?) {
        close()
    }

    override func sendEvent(_ event: NSEvent) {
        // Mouse events are not taken here. The previous override closed on a
        // geometry test and returned before the content view, which is how a
        // picker and Share could be clicked and still do nothing.
        if event.type == .keyDown, isKeyWindow,
           SpendGlanceDismissal.shouldCloseOnEscape(
               keyCode: event.keyCode,
               hasModifiers: !event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
           ) {
            close()
            return
        }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func keyDown(with event: NSEvent) {
        if SpendGlanceDismissal.shouldCloseOnEscape(
            keyCode: event.keyCode,
            hasModifiers: !event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        ) {
            close()
            return
        }
        super.keyDown(with: event)
    }
}

/// The hosted summary. The first click has to reach the control even when
/// the window was not yet key: an accessory app's window otherwise eats it
/// as an activation click and the picker looks dead.
final class SpendGlanceHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Records a control's window rectangle without taking the click.
///
/// Refresh and Share are SwiftUI buttons. macOS 26 does not put an `NSButton`
/// under them, and asking the hosting view for its accessibility children
/// returns the view itself. The test needs the rectangle the button laid out
/// so it can send the click there. `hitTest` returns nil, so the press falls
/// through to the button.
struct ControlFrameProbe: NSViewRepresentable {
    var id: String
    var onFrame: (String, CGRect) -> Void

    func makeNSView(context: Context) -> ProbeView {
        ProbeView()
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.marker = id
        nsView.onFrame = { [onFrame, id] frame in onFrame(id, frame) }
        nsView.report()
        // The first layout can run before the view has a window. Report again
        // once AppKit has placed it, so a click in that gap still has a rect.
        DispatchQueue.main.async { [weak nsView] in nsView?.report() }
    }

    final class ProbeView: NSView {
        /// `CardHeaderControl.rawValue` when this probe marks a header button.
        var marker = ""
        var onFrame: ((CGRect) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            report()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            report()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            report()
        }

        func report() {
            guard window != nil, bounds.width > 1, bounds.height > 1 else { return }
            onFrame?(convert(bounds, to: nil))
        }
    }
}

/// Copies the visible summary. The image is what the window is showing —
/// the headline and the lists on screen — not a separate poster. Nothing
/// is written to disk. PNG and TIFF, the same two types as the recap.
@MainActor
enum SpendGlanceExport {
    static func copyVisible(_ view: NSView, pasteboard: NSPasteboard = .general) -> Bool {
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1 else { return false }
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: bounds) else { return false }
        view.cacheDisplay(in: bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        if let tiff = bitmap.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
        return true
    }
}

/// The window's contents. Share copies this view as it is on screen.
/// The copy confirmation is an overlay (`SpendGlanceCopy.shiftsLayout`): a
/// line in the column would move the lists.
struct SpendGlanceView: View {
    @Bindable var model: SpendGlanceModel
    let settings: AppSettings
    let onShare: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        let _ = settings.language
        VStack(alignment: .leading, spacing: 12) {
            shareRow
            if model.showsHeadline {
                headline
            }
            ScrollView {
                TokenSpendView(
                        summary: model.summary,
                        focus: $model.focus,
                        focused: model.focused,
                        modelFocus: $model.selectedModel,
                        modelSummary: model.modelSpend,
                        noRecords: model.noRecords,
                        hasReadLimitations: model.hasReadLimitations,
                        span: Binding(
                            get: { settings.spendSpan },
                            set: { settings.spendSpan = $0 }
                        ),
                        customDays: Binding(
                            get: { settings.spendCustomDays },
                            set: { settings.spendCustomDays = $0 }
                        ),
                        activity: model.tokenActivity,
                        activityView: Binding(
                            get: { settings.spendActivityView },
                            set: { settings.spendActivityView = $0 }
                        ),
                        dimension: Binding(
                            get: { settings.spendGlanceDimension },
                            set: { settings.spendGlanceDimension = $0 }
                        ),
                        isLoading: model.isScanning,
                        isSummarizing: model.summaryIsPending,
                        hidesSpanHeadline: true,
                        onControlFrame: model.noteControlFrame,
                        refresh: { model.rescan += 1 }
                    )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) { copyNotice }
        .task(id: model.loadKey) { await model.load() }
        .task(id: model.summaryRequest) { await model.recompute() }
        .onChange(of: settings.readsTokenSpend) { _, enabled in
            if !enabled { onDismiss() }
        }
        .onChange(of: model.focus) { _, _ in model.selectedModel = nil }
    }

    private var shareRow: some View {
        HStack {
            Spacer(minLength: 8)
            Button(String.localized("Share this summary"), action: onShare)
                .disabled(!model.figuresReady || model.isScanning)
                .accessibilityIdentifier("spend-glance-share")
                .background(ControlFrameProbe(id: "spend-glance-share", onFrame: model.noteControlFrame))
        }
        .controlSize(.small)
    }

    /// Tokens large, the estimate under them. Both follow the selected span,
    /// and both are centered on the row.
    private var headline: some View {
        let picture = model.picture
        let centered = SpendGlanceHeadline.centersFigures
        return VStack(alignment: centered ? .center : .leading, spacing: 4) {
            Text(verbatim: picture.tokens)
                .font(.system(size: SpendGlanceHeadline.tokenPointSize, weight: .semibold))
                .monospacedDigit()
                .multilineTextAlignment(centered ? .center : .leading)
                .frame(maxWidth: centered ? .infinity : nil, alignment: centered ? .center : .leading)
            if let cost = picture.cost {
                Text(verbatim: cost)
                    .font(.system(size: SpendGlanceHeadline.moneyPointSize, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(centered ? .center : .leading)
                    .frame(maxWidth: centered ? .infinity : nil, alignment: centered ? .center : .leading)
            }
            if let note = picture.costNote {
                Text(verbatim: note)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(centered ? .center : .leading)
                    .frame(maxWidth: centered ? .infinity : nil, alignment: centered ? .center : .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .accessibilityIdentifier("spend-glance-headline")
    }

    /// Over the lists. It does not take a row, so the lists do not move.
    @ViewBuilder
    private var copyNotice: some View {
        if model.didCopy || model.copyFailed {
            Text(verbatim: copyNoticeText)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 16)
                .allowsHitTesting(false)
                .accessibilityIdentifier("spend-glance-copy-note")
        }
    }

    private var copyNoticeText: String {
        if model.didCopy { return String.localized("Copied to the clipboard.") }
        return String.localized("Could not copy.")
    }

}
