// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController {
    /// The panel's frame, derived from the SwiftUI layer's own layout
    /// constants (`DockLayout` in UsageDockView.swift, `DetailCardLayout` in
    /// UsageDetailCard.swift) so it can never drift out of sync with what
    /// SwiftUI actually draws. Not `private` because
    /// `FloatingUsagePanelView`'s `#Preview` sizes itself from these too.
    ///
    /// **The panel is this size always — it does not grow when the details
    /// card opens.** It used to, and that was the source of a stubborn
    /// glitch: widening the panel moves its left edge, which moves the
    /// coordinate space the SwiftUI content is laid out in. The dock rail's
    /// position *within that space* therefore jumps by the width of the card,
    /// even though its position on screen never changes — and since this all
    /// happens inside the animation that opens the card, SwiftUI dutifully
    /// animates the jump, flinging the rail sideways and sliding it back.
    /// A panel that never resizes cannot do that. The extra width costs
    /// nothing: it is transparent, and macOS routes clicks through the
    /// transparent parts of a non-opaque window.
    enum Layout {
        /// The panel's size for a given dock and display housing. It changes
        /// when the axis or screen geometry changes, never while a card opens
        /// or the notch surface expands. That distinction is
        /// the whole point: growing the window mid-animation moves the
        /// coordinate space the rail is laid out in, so the rail lurches
        /// sideways and slides back every time a card appears. Re-docking
        /// happens under the pointer, with no card open, and has to resize.
        ///
        /// **Whole points, always.** AppKit rounds a window's frame, and
        /// SwiftUI lays the rail out against the frame it actually got, while
        /// every hit test measures against this. At 280.44 wide the window
        /// came out 281: the rail was drawn flush with the screen edge, the
        /// hit rect stopped 0.56pt short of it, and a pointer pushed against
        /// the edge — exactly where anyone reaching for a docked rail puts it
        /// — was "off the panel". The sliver opened on entry and the sampler
        /// shut it again, over and over. Rounded here, the two cannot differ.
        /// `capacity` is the ring budget, which the running app sets from what
        /// is switched on. A test passes its own rather than read a global
        /// another test may be moving.
        static func size(
            for edge: PanelEdge,
            notchSize: CGSize? = nil,
            capacity: Int = PanelMetrics.railCapacity,
            docked: Bool = true
        ) -> CGSize {
            let size = unrounded(for: edge, notchSize: notchSize, capacity: capacity, docked: docked)
            return CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
        }

        /// `docked` only moves the lying rail's thickness: free across with
        /// its figures under the rings it is thicker than the top dock, and
        /// the top dock keeps exactly its own budget.
        private static func unrounded(for edge: PanelEdge, notchSize: CGSize?, capacity: Int, docked: Bool) -> CGSize {
            // Card + its pointer + the gap after it, which is the room the
            // card unfolds into whichever way it unfolds.
            let reach = DetailCardLayout.width
                + DetailCardLayout.pointerWidth
                + DetailCardLayout.horizontalGap

            switch edge.axis {
            case .vertical:
                return CGSize(
                    width: reach + DockLayout.thickness(on: .vertical),
                    // Tall enough for whichever is bigger: the rail with every
                    // provider on, or the tallest card that might be shown
                    // beside it. A card taller than the window gets sliced off
                    // flat against its edge, which reads as a drawing bug
                    // rather than as a card that didn't fit.
                    height: max(DockLayout.maximumLength(on: .vertical, capacity: capacity), DetailCardLayout.maximumHeight)
                )
            case .horizontal:
                return CGSize(
                    // Wide enough for whichever is wider, for the same reason.
                    width: max(DockLayout.maximumLength(on: .horizontal, capacity: capacity), DetailCardLayout.width, notchSize?.width ?? 0),
                    height: DockLayout.thickness(on: .horizontal, docked: docked)
                        + (notchSize?.height ?? 0)
                        + DetailCardLayout.horizontalGap
                        + DetailCardLayout.pointerWidth
                        + DetailCardLayout.maximumHeight
                )
            }
        }

        /// The vertical dock's size, which is what the previews and anything
        /// written before there was a second axis mean.
        static var width: CGFloat { size(for: .right).width }
        static var height: CGFloat { size(for: .right).height }
    }

    private let panel: FloatingPanel
    private var hostingView: NSHostingView<FloatingUsagePanelView>?
    /// Written once in `init` and read once in `deinit`, which is nonisolated
    /// and so cannot reach a main-actor property. Nothing else touches it.
    nonisolated(unsafe) private var screenObserver: (any NSObjectProtocol)?
    private let store: UsageStore
    private let settings: AppSettings
    /// Where the panel is parked. The drag handle writes to this and moves the
    /// window itself; this class reads it when first placing the panel.
    private let placement: PanelPlacement
    /// Watches which display the pointer is on, while that is switched on.
    private let displayFollower = ActiveDisplayFollower()

    /// Opens the main window from the rail's context menu and the card's grid symbol.
    /// The panel never becomes key, so the menu-bar shortcuts do not reach it.
    private let openSettings: () -> Void
    /// Opens the Token spend summary from the card header.
    private let openTokenSpend: () -> Void
    private let onTokenSpendFrame: (CGRect) -> Void

    init(
        store: UsageStore,
        settings: AppSettings,
        placement: PanelPlacement,
        openSettings: @escaping () -> Void,
        openTokenSpend: @escaping () -> Void = {},
        onTokenSpendFrame: @escaping (CGRect) -> Void = { _ in }
    ) {
        self.store = store
        self.settings = settings
        self.placement = placement
        self.openSettings = openSettings
        self.openTokenSpend = openTokenSpend
        self.onTokenSpendFrame = onTokenSpendFrame
        placement.snapsToEdges = settings.snapsToEdges

        // The sliver has to be reachable without leaving the rail, or hiding
        // and showing chase each other forever. It is geometry, so it can be
        // asserted rather than watched for — and it is asserted here because
        // this is where the metrics it depends on are finally settled.
        assert(
            PanelHitArea.stripIsContainedInRail(),
            "the collapsed sliver escapes the rail's hit area — see PanelHitArea"
        )

        let initialSize = Layout.size(for: placement.edge, docked: placement.isDocked)
        panel = FloatingPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: initialSize.width,
                height: initialSize.height
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configurePanel()

        panel.onHeaderControl = { control in
            switch control {
            case .openApp: openSettings()
            case .tokenSpend: openTokenSpend()
            case .quit: NSApplication.shared.terminate(nil)
            }
        }
        let headerSink = panel.headerSink
        let hostingView = NSHostingView(
            rootView: FloatingUsagePanelView(
                store: store,
                settings: settings,
                placement: placement,
                openSettings: openSettings,
                openTokenSpend: openTokenSpend,
                onTokenSpendFrame: onTokenSpendFrame,
                onHeaderFrame: { [headerSink] control, rect in
                    headerSink.note(control, rect)
                }
            )
        )
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(x: 0, y: 0, width: initialSize.width, height: initialSize.height)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        self.hostingView = hostingView

        // Choosing an edge in settings only changes the placement; without
        // this the content would mirror while the window stayed where it was,
        // leaving the rail stranded mid-screen.
        placement.onChange = { [weak self] in
            self?.placePanel()
        }

        // Displays come and go: a monitor is unplugged, a laptop is docked,
        // the arrangement is rearranged in System Settings. Any of those can
        // leave the panel parked in a space that no longer exists, with no
        // way to get it back — so it is re-placed whenever the screens change.
        // Not during a drag, which is already moving the window itself and
        // would be fought over the same frame.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.placement.isDragging else { return }
                // The pointer has not moved, but the display under it may not
                // be the one it was on a moment ago — and the panel may have
                // just fallen back onto a screen nobody chose. Ask again.
                self.displayFollower.forgetLastDisplay()
                self.placePanel()
            }
        }

        // Carrying the panel to the display the pointer is on is the whole of
        // the feature: there is one panel, and it moves. Refusing while the
        // panel is held is `move(toDisplay:)`'s own rule, and returning that
        // refusal keeps the display on offer for the next tick instead of
        // being remembered as done.
        displayFollower.onEnter = { [placement] identifier in
            placement.move(toDisplay: identifier)
        }

        // What the panel can be picked up by. Collapsed there is no rail on
        // screen to grab, only the sliver — a press in the sixty points of
        // empty air where the rail *would* be must go to whatever is behind
        // the panel, not move it.
        panel.placement = placement
        // Both capture the two objects they need rather than the controller,
        // which owns the panel they are stored on.
        panel.railFrame = { [settings, store, placement] in
            PanelHitArea.rail(
                edge: placement.edge,
                railSize: DockLayout.size(for: Self.shownSlotCount(settings, usage: { store.usage(for: $0) }), on: placement.edge.axis, docked: placement.isDocked),
                railTop: placement.railTop,
                railLeading: placement.railLeading
            )
        }
        // The rail's size for a dock it is not on yet, which the drag needs:
        // crossing onto the other axis turns the rail as it goes.
        // Takes the dock it is *landing* on, not the one it is leaving: the
        // rail's ends lose the flare's worth of padding the moment it comes off
        // an edge, and measuring the old state throws the placement off by that
        // much on the frame it changes.
        panel.railSize = { [settings, store] axis, docked in
            DockLayout.size(for: Self.shownSlotCount(settings, usage: { store.usage(for: $0) }), on: axis, docked: docked)
        }
        panel.grabArea = { [settings, store, placement] in
            if placement.notch != nil && !placement.isRailExpanded { return .zero }
            let size = DockLayout.size(for: Self.shownSlotCount(settings, usage: { store.usage(for: $0) }), on: placement.edge.axis, docked: placement.isDocked)
            if placement.isRailExpanded {
                let rail = PanelHitArea.rail(edge: placement.edge, railSize: size, railTop: placement.railTop, railLeading: placement.railLeading)
                return placement.notch.map { PanelHitArea.notchSurface(rail: rail, notchSize: $0.size) } ?? rail
            }
            return PanelHitArea.strip(edge: placement.edge, railSize: size, railTop: placement.railTop, railLeading: placement.railLeading)
        }
        panel.onClick = { [settings, placement, store] point in
            guard placement.isRailExpanded else { return }
            // The rail draws them in the user's order, so a click has to be
            // matched against that order — `PanelHitArea.slot` maps a
            // position to an index, and the enum's order is not what is on
            // screen once anything has been moved.
            // Slots, not accounts: a split provider draws two rings from one
            // account, so indexing the rail by account count aims the click at
            // the wrong ring from the split onwards.
            let slots = RailSlot.rail(
                for: settings.shownAccounts,
                isSplit: settings.isSplit,
                groups: { RailSlot.modelGroups(of: store.usage(for: $0)) }
            )
            guard let slot = PanelHitArea.slot(
                at: point,
                edge: placement.edge,
                slots: slots,
                railTop: placement.railTop,
                railLeading: placement.railLeading,
                docked: placement.isDocked
            ) else { return }
            // The refresh is still the account's: both rings of a split
            // provider come from one reading.
            store.refresh(slot.account)
        }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    var isVisible: Bool { panel.isVisible }

    /// The menu a secondary click on the rail puts up.
    ///
    /// Supplied from outside rather than built here: what belongs on it is
    /// settings, updates and quitting, none of which this class knows anything
    /// about. Built fresh on each click so an update that arrived since the
    /// last one is on it.
    var contextMenu: (() -> NSMenu)? {
        get { panel.contextMenu }
        set { panel.contextMenu = newValue }
    }

    /// The rail in screen coordinates, for the Token spend window to sit beside it.
    func glanceAnchor() -> SpendGlanceAnchor? {
        guard let screen = panel.screen ?? NSScreen.main, let railInPanel = panel.railFrame?() else { return nil }
        let rail = CGRect(
            x: panel.frame.minX + railInPanel.minX,
            y: panel.frame.maxY - railInPanel.maxY,
            width: railInPanel.width,
            height: railInPanel.height
        )
        let clearance = placement.edge.isVertical
            ? DetailCardLayout.width + DetailCardLayout.pointerWidth + SpendGlancePlacement.gap
            : SpendGlancePlacement.gap
        return SpendGlanceAnchor(
            rail: rail,
            edge: placement.edge,
            screen: screen.visibleFrame,
            cardClearance: clearance,
            level: panel.level
        )
    }

    func show() {
        // **Placed, shown, then placed again**, and the second one is the one
        // that counts.
        //
        // `placePanel` measures where the rail sits inside the window against
        // the frame the window was *granted* rather than the one it asked for
        // — the panel is taller than a laptop's usable area and AppKit pulls it
        // down. But a window that has never been ordered in is not being
        // constrained yet: `setFrame` stores the request, `frame` reads it
        // back unchanged, and the offset is measured against a position the
        // window is about to lose. Ordering it front applies the constraint,
        // and on this Mac that moved it 76pt — so the rail was drawn 76pt off
        // from the moment the panel first appeared until anything happened to
        // re-place it, at which point it jumped.
        //
        // The first call is not wasted: it puts the window roughly right
        // before it is shown, so it does not appear at the origin and slide
        // into place.
        placePanel()
        panel.orderFrontRegardless()
        placePanel()
        applyDisplayFollowing()
        store.refreshCodexResetForecast()
    }

    func toggle() {
        panel.isVisible ? panel.orderOut(nil) : show()
        applyDisplayFollowing()
    }

    /// Brings the panel in line with settings that were just changed.
    func settingsChanged() {
        if placement.snapsToEdges != settings.snapsToEdges {
            keepFreeRailInPlace(snaps: settings.snapsToEdges)
        }
        placement.snapsToEdges = settings.snapsToEdges
        applyCollectionBehavior()
        applyScreenCapture()
        applyDisplayFollowing()

        if settings.isPanelVisible {
            if !panel.isVisible { show() }
            // Switching a provider off shortens the rail, and where the rail
            // sits inside the panel is worked out from its height — so this
            // has to be redone or the rail drifts from where it was left.
            placePanel()
        } else {
            panel.orderOut(nil)
        }
    }

    private func configurePanel() {
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.applyLevel(for: placement.dock)
        applyCollectionBehavior()
        applyScreenCapture()
    }

    /// Marked not to be captured when the setting asks. The window is sized
    /// for the tallest card and mostly transparent, so a screenshot tool's
    /// window selection finds a frame far larger than the rail.
    ///
    /// **A request, not a guarantee.** Apple says not to rely on `.none` to
    /// keep a window out of capture: since macOS 15.4, ScreenCaptureKit can
    /// still include it. Tools that read the sharing state skip it, which is
    /// what the setting is for; it does not promise a recording or a shared
    /// screen leaves the panel out, and its wording says so.
    /// `.readOnly` is AppKit's default, which lets anything capture it.
    private func applyScreenCapture() {
        panel.sharingType = settings.hidesFromScreenCapture ? .none : .readOnly
    }

    /// Keeps the rail on every ordinary desktop Space while deciding separately
    /// whether it may accompany another app into a full-screen Space.
    ///
    /// `.fullScreenAuxiliary` is the explicit opt-in that made the panel appear
    /// over full-screen apps before this setting existed. `.fullScreenNone` is
    /// the matching public opt-out, so no app inspection, Space polling, or
    /// Accessibility permission is needed.
    private func applyCollectionBehavior() {
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            settings.hidesInFullScreen ? .fullScreenNone : .fullScreenAuxiliary,
            .stationary
        ]
    }

    /// Starts or stops watching the pointer's display.
    ///
    /// Nothing is sampled unless the panel is on screen and the setting is on,
    /// so someone with one display — or with this switched off — pays for no
    /// timer at all.
    private func applyDisplayFollowing() {
        guard settings.isPanelVisible, settings.followsActiveDisplay, panel.isVisible else {
            displayFollower.stop()
            return
        }
        // The stored display may be one the pointer left long ago, so the
        // first tick has to be allowed to report where it actually is.
        displayFollower.forgetLastDisplay()
        displayFollower.start()
    }

    /// How many rings the rail is actually drawing.
    ///
    /// **Not `shownAccounts.count`.** A split provider draws two rings from
    /// one account, so counting accounts sizes every rect below one item short
    /// of what is on screen — and the shortfall is at the far end, where it
    /// takes the last ring out of the grab area entirely. The panel window and
    /// the view have to agree on this number; the view gets it from
    /// `entries.count`, which is the same list.
    ///
    /// Static so the closures storing it on the panel capture the objects they
    /// need rather than the controller that owns the panel — and it takes the
    /// readings as a function rather than the store so a test can hand it a
    /// split account without a store to seed.
    static func shownSlotCount(
        _ settings: AppSettings,
        usage: (AccountKey) -> ProviderUsage
    ) -> Int {
        RailSlot.rail(
            for: settings.shownAccounts,
            isSplit: settings.isSplit,
            groups: { RailSlot.modelGroups(of: usage($0)) }
        ).count
    }

    /// Parks the panel where it was last left.
    ///
    /// The rail's size is passed in because it changes under the placement —
    /// a provider switched off shortens it, and a split account's first
    /// reading lengthens it — and the placement works in terms of the rail
    /// rather than the window, which is mostly the empty space the card
    /// unfolds into and which the user has never positioned.
    ///
    /// **Everything that can change the rail's length has to reach here.**
    /// Settings go through `settingsChanged()`; a reading that splits an
    /// account into two rings has no setting behind it and arrives through
    /// `PanelPlacement.railLengthChanged()`. Miss one and the window's rects
    /// stay measured against a rail that is no longer that long.
    /// The display the panel was left on, if that display is still here. A
    /// monitor that has been unplugged falls back to one that exists rather
    /// than parking the panel in a space nobody can see.
    private var placementScreen: NSScreen? {
        PanelScreen.screen(withIdentifier: placement.display)
            ?? panel.screen ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Switching snapping changes the room a free rail's ratios are
    /// fractions of (`PanelPlacement.room`), so the same ratios would put it
    /// somewhere else — down onto the Dock, say, from just above it. They
    /// are measured again from where the rail is now, kept inside the new
    /// room, so it stays put or moves only as far as it has to.
    private func keepFreeRailInPlace(snaps: Bool) {
        guard
            !placement.isDocked,
            panel.isVisible,
            let screen = placementScreen,
            let rail = panel.railFrame?()
        else { return }

        let room = PanelPlacement.room(
            snaps: snaps, dock: placement.dock, visible: screen.visibleFrame, screen: screen.frame
        )
        // Bottom-left, as the drag measures it.
        let origin = CGPoint(
            x: min(max(panel.frame.minX + rail.minX, room.minX), room.maxX - rail.width),
            y: min(max(panel.frame.maxY - rail.maxY, room.minY), room.maxY - rail.height)
        )
        let ratios = PanelPlacement.ratios(forRailAt: origin, in: room, rail: rail.size)
        placement.record(
            dock: placement.dock,
            horizontalRatio: ratios.h,
            verticalRatio: ratios.v,
            display: placement.display
        )
    }

    private func placePanel() {
        guard let screen = placementScreen else { return }

        let edge = placement.edge
        // The dock, not the edge: a rail standing free in the top half of the
        // screen opens its card downwards too, and has no notch to sit in.
        placement.notch = placement.dock == .edge(.top) ? PanelScreen.notch(of: screen) : nil
        let railSize = DockLayout.size(
            for: Self.shownSlotCount(settings, usage: { store.usage(for: $0) }),
            on: edge.axis,
            docked: placement.isDocked
        )
        let layout = placement.layout(
            in: placement.room(visible: screen.visibleFrame, screen: screen.frame),
            topEdge: FloatingPanel.topEdge(of: screen),
            bottomEdge: screen.frame.minY,
            panel: Layout.size(for: edge, notchSize: placement.notch?.size, docked: placement.isDocked),
            rail: railSize
        )

        placement.cardRoom = PanelPlacement.cardRoom(
            edge: edge, railOrigin: layout.railOrigin, rail: railSize, in: screen.visibleFrame
        )
        panel.applyLevel(
            for: placement.dock,
            beyond: PanelPlacement.isBeyond(screen.visibleFrame, railOrigin: layout.railOrigin, rail: railSize)
        )
        panel.setFrame(layout.frame, display: true)
        // **Measured against the frame the window actually got**, not the one
        // it was asked for. The panel is as tall as a rail with every account
        // on, which is taller than a laptop's usable screen, and AppKit will
        // not hand out a frame that does not fit — so the two halves of the
        // placement disagreed by however much it refused, and the rail was
        // drawn that far off.
        let offsets = PanelPlacement.offsets(
            forRailTopLeft: layout.railOrigin,
            in: panel.frame,
            rail: railSize
        )
        placement.setRailOffset(top: offsets.top, leading: offsets.leading)
    }
}

/// The panel, which also owns dragging itself around.
///
/// The drag used to be an `NSViewRepresentable` inside the SwiftUI tree, and
/// that turned out to be a bad place for it. A press only reaches a view inside
/// `NSHostingView` if SwiftUI claims the point first, and once the berth became
/// a `PanelSurface` — added for the Liquid Glass option, and marked as not
/// hit-testable so it could never take a press away from the handle — nothing
/// claimed the empty black between the rings. The panel could be dragged by its
/// rings, which carry a `contentShape` for their tracking areas, and nowhere
/// else. Putting a shape over the handle to claim those points was worse: it
/// swallowed the press rather than passing it down, and then nothing worked at
/// all.
///
/// `sendEvent` sees every event the window server hands this window, before any
/// of SwiftUI's hit testing and before whatever Liquid Glass installs for its
/// own interactivity. Neither can take the drag away from here.
///
/// What is dragged is the **rail**, not the window. The window is far wider than
/// the rail (it carries the space the card unfolds into) and which side of it
/// the rail sits on flips at the middle of the screen; moving the window with
/// the pointer would throw the rail sideways at that moment.
/// Internal so a test can send a click through `sendEvent` the way the window
/// receives one. The controller is what the app holds.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// **What makes the glass Liquid Glass rather than a frosted blur.** A
    /// private AppKit question, answered here so the panel's glass always
    /// renders active.
    ///
    /// macOS 26 draws glass in an inactive window as a flat blur with no
    /// lensing. This panel is inactive almost always: it cannot become key,
    /// and once Pulse has been active even once (Settings opened, a menu
    /// used) every window it owns is drawn inactive from the moment another
    /// app takes over. Measured on 26.7 over busy text: SwiftUI or AppKit
    /// glass, `.clear` or `.regular`, any size, with `appearsActive` /
    /// `controlActiveState` forced in the environment, re-ordered or rebuilt
    /// after deactivation — all frosted. Returning `true` here was refracted,
    /// readable glass in every case, with `canBecomeKey` still `false`.
    ///
    /// Chosen over making the panel key-eligible, which also works until the
    /// app is first deactivated and would put focus at risk. Private, so it
    /// may stop being asked: then the glass is frosted again and nothing else
    /// breaks — the panel has no controls whose look depends on this.
    @objc(_hasActiveAppearanceIgnoringKeyFocus)
    private func hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }

    /// What can be taken hold of, in the panel's own top-left coordinates:
    /// the rail when it is drawn out, its sliver when it is not. Supplied by
    /// the controller, which is what knows how many providers are switched on.
    var grabArea: (() -> CGRect)?
    /// The rail's own rect, whatever is currently on screen.
    ///
    /// Separate from `grabArea` on purpose: collapsed, what is grabbed is the
    /// sliver, but what is *placed* is still the rail — the stored position is
    /// the rail's, and handing the placement a 20pt sliver where it expects a
    /// 64pt rail would throw the panel across the screen on the first drag.
    var railFrame: (() -> CGRect)?
    /// The rail's size on a given axis, docked or not, which the drag needs
    /// for a dock the panel has not reached yet.
    var railSize: ((PanelEdge.Axis, Bool) -> CGSize)?

    /// Where a top-docked rail's top edge belongs: the display's physical top,
    /// less whatever a notch takes out of it.
    ///
    /// Not `visibleFrame.maxY`, which is under the menu bar — a rail parked a
    /// menu bar's height below the edge of the screen is not against the edge
    /// of the screen, and looks it.
    static func topEdge(of screen: NSScreen) -> CGFloat {
        let notch = screen.safeAreaInsets.top
        guard notch > 0 else { return screen.frame.maxY }

        // With a notch there is a row of screen either side of it, but the
        // rail is wider than either — centred, most of it would be behind the
        // notch, where nothing is drawn at all. So it stops at the notch's own
        // line, which is also where the menu bar ends. Taking the lower of the
        // two rather than trusting them to be equal: the rail must never be
        // asked to draw itself into a row it cannot be seen in, and only one
        // of these two numbers is the notch's.
        return min(screen.frame.maxY - notch, screen.visibleFrame.maxY)
    }

    /// Above the menu bar while docked to the top, and only then.
    ///
    /// `.floating` sits *below* the menu bar's own level, so a panel placed at
    /// the display's edge would simply be drawn over by it. `.statusBar` is
    /// one step above the menu bar and the same level the menu bar's own extras
    /// use — high enough to reach the edge, not so high that it covers system
    /// alerts. Nothing else about the panel changes, and off the top edge it
    /// goes back to floating so it never sits over the menu bar for nothing.
    ///
    /// `beyond`: a free rail that reaches over the menu bar or the Dock
    /// (snapping off, `PanelPlacement.isBeyond`) is raised the same way, or
    /// it would be put there and drawn underneath.
    func applyLevel(for dock: PanelDock, beyond: Bool = false) {
        // Docked to the bottom it sits level with the Dock, beside it, and
        // must not slip under it where the two meet.
        level = dock.edge == .top || dock.edge == .bottom || beyond ? .statusBar : .floating
    }
    /// A short press that ended without moving the panel. The controller maps
    /// it to a provider ring; empty rail space remains drag-only.
    var onClick: ((CGPoint) -> Void)?
    /// The menu a secondary click on the rail puts up, built fresh each time
    /// so it can carry whatever is true now — an available update, say.
    var contextMenu: (() -> NSMenu)?
    var placement: PanelPlacement?

    /// Where on the rail the pointer took hold, so the panel doesn't jump to
    /// centre itself under the pointer when the drag starts. Nil when no drag
    /// is in progress.
    private var grab: CGSize?
    private var pressedAt: CGPoint?
    /// When that press began, for `PanelIntent.ringClickGuard`.
    private var pressBegan: Date?
    private var didDrag = false

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        // Before the drag: a control-click *is* a right click on macOS, and
        // taking it as a press would start carrying the panel instead.
        case .rightMouseDown where showMenu(event): return
        case .leftMouseDown where event.modifierFlags.contains(.control) && showMenu(event): return
        // Header controls, before the rail. Their layout frames are the
        // target: a view under the symbol was taking the point and dropping it.
        case .leftMouseDown where routeHeader(event): return
        case .leftMouseDown where begin(event): return
        case .leftMouseDragged where routeHeader(event): return
        case .leftMouseDragged where carry(): return
        case .leftMouseUp where routeHeader(event): return
        case .leftMouseUp where finish(): return
        default: super.sendEvent(event)
        }
    }

    /// Header frames in window coordinates, written while the buttons lay out.
    let headerSink = HeaderFrameSink()
    /// Open, Token spend, and Quit. Called on mouse-up inside the pressed control.
    var onHeaderControl: ((CardHeaderControl) -> Void)?
    private var pressedHeader: CardHeaderControl?

    /// True when this event belongs to a header control and must not start a drag.
    private func routeHeader(_ event: NSEvent) -> Bool {
        var pressed = pressedHeader
        let outcome = HeaderClickDispatch.outcome(
            type: event.type,
            point: event.locationInWindow,
            frames: headerSink.frames,
            pressed: &pressed
        )
        pressedHeader = pressed
        switch outcome {
        case .pass:
            return false
        case .taken:
            return true
        case .activate(let control):
            // The next turn, not this one. The press is still the non-activating
            // panel's, and ordering the main window front from inside it leaves
            // the window behind the app that was key. A main-queue block queued
            // from this call does not run until AppKit gets the thread back;
            // a main-actor task is the same turn, and a test can yield to it.
            Task { @MainActor [weak self] in
                self?.onHeaderControl?(control)
            }
            return true
        }
    }

    /// Puts the panel's menu up, if the click landed on something to grab.
    ///
    /// The same geometry the drag uses, so what can be picked up is what can be
    /// right-clicked — including the sliver, which is the whole point: the rail
    /// is wound down to six points most of the time, and a menu you can only
    /// reach by hovering first is one more thing to know.
    ///
    /// Taken here rather than through SwiftUI's `.contextMenu` for the reason
    /// every other press is: this window is a non-key accessory panel, and
    /// SwiftUI's own input handling is not reliable on it. See Docs/ui/input.md.
    private func showMenu(_ event: NSEvent) -> Bool {
        guard
            let area = grabArea?(),
            let menu = contextMenu?(),
            let view = contentView,
            area.contains(local(event))
        else { return false }

        // `popUp` runs its own tracking loop, so the flag is cleared only once
        // the menu has closed — which is exactly the span the rail must stay
        // drawn out for.
        placement?.isMenuOpen = true
        menu.popUp(positioning: nil, at: view.convert(event.locationInWindow, from: nil), in: view)
        placement?.isMenuOpen = false
        return true
    }

    private func begin(_ event: NSEvent) -> Bool {
        let location = local(event)
        guard
            let area = grabArea?(),
            let rail = railFrame?(),
            area.contains(location)
        else { return false }

        // Measured against the rail even when the sliver is what was grabbed,
        // so the pointer keeps its hold on the rail rather than on whichever
        // stand-in was on screen at the time.
        //
        // Screen coordinates run bottom-up, so the rail's bottom edge is its
        // distance from the window's top subtracted from the window's top.
        let origin = CGPoint(x: frame.minX + rail.minX, y: frame.maxY - rail.maxY)
        let pointer = NSEvent.mouseLocation
        grab = CGSize(width: pointer.x - origin.x, height: pointer.y - origin.y)
        pressedAt = location
        pressBegan = Date()
        didDrag = false
        // From here the grab offset is fixed, so nothing may move the panel
        // until the button comes up — a re-place now is a jump on the first
        // frame the pointer travels.
        placement?.isPressed = true
        return true
    }

    private func carry() -> Bool {
        guard
            let grab,
            let placement,
            let railFrame = railFrame?()
        else { return false }

        let pointer = NSEvent.mouseLocation

        // **The screen the pointer is on, not the one the window is on.** The
        // rail is clamped to the usable area every frame, so measuring that
        // against the window's own screen is what pinned the panel to one
        // display: a drag towards a second monitor was put back where it came
        // from on every frame, and nothing ever crossed.
        guard let screen = PanelScreen.containing(pointer) ?? self.screen ?? NSScreen.main
        else { return false }

        let visible = screen.visibleFrame
        // Where the rail may go: the usable area, or the whole screen with
        // snapping off (`PanelPlacement.room`). Not asked of the placement,
        // whose dock is still the one being left: a docked rail picked up
        // with snapping off is free from the first frame.
        let room = placement.snapsToEdges ? visible : screen.frame
        let rail = railFrame.size

        if !didDrag {
            didDrag = true
            placement.isDragging = true
        }

        // Where the rail would like to be, kept wholly in its room.
        let wanted = CGPoint(
            x: min(max(pointer.x - grab.width, room.minX), room.maxX - rail.width),
            y: min(max(pointer.y - grab.height, room.minY), room.maxY - rail.height)
        )

        // Where it lands is `PanelPlacement.dragDock`'s to say. The rail's
        // bottom is the pointer's, not `wanted`'s: kept on screen, `wanted`
        // never goes below the Dock, and a rail docked beside it is.
        let dock = PanelPlacement.dragDock(
            pointer: pointer,
            rail: CGRect(origin: CGPoint(x: wanted.x, y: pointer.y - grab.height), size: rail),
            screen: screen.frame,
            visible: visible,
            current: placement.dock,
            axis: placement.edge.axis,
            snaps: placement.snapsToEdges
        )

        // The rail turns as it crosses onto the other axis, so everything from
        // here is measured in the orientation it is about to be in — not the
        // one it is leaving. Measuring in the old one throws the panel across
        // the screen on the frame the axis changes.
        //
        // `placement.edge` is a frame behind until `record` below, so it is
        // not asked which way the rail runs: sizing the window for the axis
        // being left while the content has already redrawn on the new one
        // slices 52pt off the rail and puts the hit rect a hundred points from
        // where the rail is. The axis comes from the dock being landed on, and
        // the edge — which only decides where the card opens — from the
        // placement once it has been recorded.
        let landingAxis: PanelEdge.Axis = switch dock {
        case .edge(let edge): edge.axis
        case .floating(let axis): axis
        }
        let landingRail = railSize?(landingAxis, dock.isDocked) ?? rail
        let landingNotch = dock == .edge(.top) ? PanelScreen.notch(of: screen) : nil

        // Under the pointer, in the new orientation. Carrying the old grab
        // offset across a quarter turn would put the rail somewhere the hand
        // holding it never asked for.
        //
        // A turn is a change of **axis**, and must not be inferred from the
        // rail's size: the ends lose the flare's padding when the rail floats,
        // so the same rail is 48pt shorter off an edge — which made every
        // dock↔float transition re-centre itself under the pointer for one
        // frame and snap back on the next. The grab is re-measured whenever
        // that does happen, or the frame after a turn would undo it.
        let turned = landingAxis != placement.edge.axis

        let origin: CGPoint
        if turned {
            origin = CGPoint(x: pointer.x - landingRail.width / 2, y: pointer.y - landingRail.height / 2)
            self.grab = CGSize(width: landingRail.width / 2, height: landingRail.height / 2)
        } else if landingRail != rail {
            // Same axis, different length: the ends lose the flare's padding
            // as the rail comes off an edge, so it is 48pt shorter floating.
            // Half of that goes from each end, which means the **rings do not
            // move** — as long as the rail's centre is what stays put. Holding
            // the grab offset instead pins the far end and slides all of them
            // 48pt through the hand that is carrying them.
            let shrink = CGSize(
                width: (rail.width - landingRail.width) / 2,
                height: (rail.height - landingRail.height) / 2
            )
            let recentred = CGSize(width: grab.width - shrink.width, height: grab.height - shrink.height)
            self.grab = recentred
            origin = CGPoint(
                x: min(max(pointer.x - recentred.width, room.minX), room.maxX - landingRail.width),
                y: min(max(pointer.y - recentred.height, room.minY), room.maxY - landingRail.height)
            )
        } else {
            origin = wanted
        }

        let ratios = PanelPlacement.ratios(forRailAt: origin, in: room, rail: landingRail)
        placement.record(
            dock: dock,
            horizontalRatio: ratios.h,
            verticalRatio: ratios.v,
            display: PanelScreen.identifier(of: screen)
        )

        placement.notch = landingNotch
        let landingPanel = FloatingPanelController.Layout.size(
            for: placement.edge, notchSize: landingNotch?.size, docked: dock.isDocked
        )

        // One source of truth for the geometry: ask the placement where that
        // puts things rather than working it out a second way here.
        let layout = placement.layout(
            in: room,
            topEdge: Self.topEdge(of: screen),
            bottomEdge: screen.frame.minY,
            panel: landingPanel,
            rail: landingRail
        )
        placement.cardRoom = PanelPlacement.cardRoom(
            edge: placement.edge, railOrigin: layout.railOrigin, rail: landingRail, in: visible
        )
        applyLevel(
            for: dock,
            beyond: PanelPlacement.isBeyond(visible, railOrigin: layout.railOrigin, rail: landingRail)
        )
        setFrame(layout.frame, display: true)
        // Same rule as `placePanel`: the frame is a request, and on a screen
        // the panel does not fit the rail has to be measured against what the
        // window was actually given, or it slides out from under the pointer
        // by exactly the difference.
        let offsets = PanelPlacement.offsets(
            forRailTopLeft: layout.railOrigin,
            in: frame,
            rail: landingRail
        )
        placement.setRailOffset(top: offsets.top, leading: offsets.leading)
        return true
    }

    private func finish() -> Bool {
        guard grab != nil else { return false }
        // A press that began before the rings had been out for
        // `ringClickGuard` was aimed at whatever was under the pointer
        // before they appeared: it can still carry the panel, but it is not
        // a click on a ring.
        let aimed = pressBegan.map {
            PanelIntent.acceptsRingClick(pressedAt: $0, railOpenedAt: placement?.railOpenedAt)
        } ?? false
        let click = didDrag || !aimed ? nil : pressedAt
        grab = nil
        pressedAt = nil
        pressBegan = nil
        didDrag = false
        placement?.isDragging = false
        placement?.isPressed = false
        if let click { onClick?(click) }
        return true
    }

    /// The event's location in the panel's own coordinates, with the origin at
    /// the top-left corner to match SwiftUI — which is the space the grab area
    /// is given in.
    private func local(_ event: NSEvent) -> CGPoint {
        CGPoint(x: event.locationInWindow.x, y: frame.height - event.locationInWindow.y)
    }
}
