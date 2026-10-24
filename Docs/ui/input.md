# Pointer, drag, clicks

SwiftUI `.onHover` **does not work here**. It tracks only while the app is active. Pulse is `.accessory` behind a non-activating panel that never becomes key, so it is essentially never active.

SwiftUI `.help` does not show on a control this panel draws with `PointerHand`. The window can never become key, and that `NSView` is the one under the pointer, so the tooltip is never the view the pointer is on. Help copy that has to be read from such a control is drawn in the card from that tracking area — hover and click — and must not change the card's height. A callout that grows the card moves the mark, the tracking area exits, and the callout closes.

Do not treat `hitTest` or synthesised `NSEvent`s as proof that a real click arrives. They have reported handles as reachable at widths the rail did not have, and they bypass whatever a material installs. Geometry probes are useful (“is this point in `grabArea`?”). Whether a person can drag the panel is **real input**: last verified by hand on the docked glass rail after #68.

Why enter/leave are split, why the window owns the drag, and the Liquid Glass episode: [../decisions/hover-and-drag.md](../decisions/hover-and-drag.md), [../decisions/liquid-glass.md](../decisions/liquid-glass.md).

## Hover (open / close the card)

`FloatingUsagePanelView` builds rail readings from observed store/settings inputs; `FloatingUsagePanelContent` owns pointer, hover and card state below it. Layout and pointer hit tests share the same entry array, so pointer samples do not reconstruct account slots, labels and quota readings.

Two `NSViewRepresentable` backgrounds:

- `PointerEntryReporter` — `.activeAlways` `NSTrackingArea`, reports **only entering** a ring.
- `PanelPointerWatcher` — samples `NSEvent.mouseLocation` on a timer. `FloatingUsagePanelContent.isOverContent` tests against the **rail and the card**, not the window frame (the panel is full-size and mostly transparent).

For a top-docked notch rail, an unpainted `PointerEntryReporter` covers exactly the physical housing rectangle (`PanelIntent.notchHousing`). **Arriving there does not open the rail; staying does.** Entry — from the tracking area, or from a sample that finds the pointer there, for a pointer that was already inside when the area was installed — arms `armNotch`, which waits `PanelIntent.notchDwell` (250ms) and then opens only if the pointer is still in the housing *at that moment*, read through `PointerProbe` rather than the last sample (which can be 150ms old, most of the wait). A sample outside the housing calls the wait off. The housing sits on the way between the two halves of the menu bar, so opening on entry put the rail over whatever the pointer was heading for. Nothing in the wait closes anything, so the enter-only rule below still holds. The housing counts in `isOverContent` only once the rail is out, where it holds the rail open like the rest of its surface. The hidden rail has no sliver or grab target. Once expanded, the full surface from the screen top through the added bottom padding counts as content. One derived `isNotchHeld` state covers a press, drag, or open menu; releasing the last of these re-evaluates the pointer so a stationary pointer cannot leave it stuck open.

**A ring click needs the rail to have been out for `PanelIntent.ringClickGuard` (300ms)**, measured from mouse-down against `placement.railOpenedAt`. A press sooner than that was started at whatever was under the pointer before the rings appeared. It still picks up the panel; only the refresh is dropped. Every dock, not just the notch.

**Do not close on exit events.** Views appearing, moving, or animating under a stationary pointer fire spurious exits; closing reopens; it loops. Enter from tracking areas, leave from sampling the real pointer. That loop is then structurally impossible.

**Samples are deduplicated, so whatever opens the panel by another path asks for a fresh one** (`PointerProbe.reportAgain`). A ring's enter can arrive late — queued behind a busy main thread, or for a ring crossed between two samples — after the sampler has already reported the pointer gone; every later sample was that same "gone", so the card stayed open until the pointer came back and left again. Now `select` opens nothing unless the pointer is on the content **now** (`pointerProbe`; refusing closes nothing, so no loop), and `select`, `show`, the end of a drag and the menu closing each have the next sample report the pointer even if it has not moved.

The sliver’s tracking area cannot be the only way `isHovered` gets set: a floating panel dragged onto an edge docks with `isHovered` still false and snaps shut in the hand. `pointerMoved` sets it from the same test that decides when to hide.

`PanelHitArea.stripIsContainedInRail()` asserts the sliver never pokes outside the rail’s hit area (or leave-rail lands on the sliver, which shows the rail, which hides it). Bound is rail capacity / slots, not `Provider.allCases.count`. Run from `FloatingPanelController.init` once metrics are settled.

## Drag belongs to the window

Two things, different files:

1. Something in the panel must **claim** the point or the window is never handed the press — `PanelSurface`, hit-testable, `contentShape` of the capsule. `allowsHitTesting(false)` killed dragging in the empty black between rings (rings still worked via tracking areas).
   On glass that is not enough: the window server only hands a transparent window a press on a pixel it has drawn, and glass is composited outside the window. `PanelGlass.claim` puts a near-invisible fill under it. [rings-and-surface.md](rings-and-surface.md)
2. The press must be **taken** — `FloatingPanel.sendEvent`. A SwiftUI-hosted handle only sees a press if SwiftUI claims the point first. Laying a shape *over* the handle swallows the press. `sendEvent` sees events before SwiftUI hit testing and before anything Liquid Glass installs.

The window is handed **two** rects: `grabArea` (rail, or sliver when collapsed) decides whether a press is taken; `railFrame` (always the rail) is what placement arithmetic runs on. Collapsed, grabbing a 20pt sliver and placing it as a 64pt rail throws the panel across the screen. Both sized to what is drawn, or a press in the transparent band moves the panel instead of passing through.

## Ring click vs ring drag

Same window-level path. `FloatingPanel` records the press, marks a drag only after a real `leftMouseDragged`, reports a click on mouse-up otherwise. The press also sets `placement.isPressed`, and **nothing may move the panel while that is set** — not merely while `isDragging` is. The grab offset is measured at mouse-down, so a re-place in the gap before the first movement does not slide the panel, it makes it jump by that much on the frame the pointer first travels. `PanelHoldTests` pins it. `PanelHitArea.slot(at:)` accepts only the visible circle; labels and berth gaps stay drag-only. It indexes **slots**, not accounts — a split provider draws two rings from one login, so counting accounts aims every click after the split at the wrong ring. The controller builds the same list the panel draws from, through `RailSlot.rail(for:isSplit:groups:)`.

Click starts an account-scoped refresh. `UsageStore.isRefreshing` : the usage arc **dims but does not move**; a short bright segment travels around. Do not rotate the usage arc (at 0% there is no arc; at 95% a rotated arc looks still; it also takes the gauge away). Travelling mark is usage colour, not white (white is the CLI-activity mark). Hold at least 650ms so a local read still registers. Keep the physical click here; `sendEvent` takes the press before SwiftUI. Default accessibility action can still live on the ring.

A click is matched against the **displayed slots** the controller builds through `RailSlot.rail(for:isSplit:groups:)`, not `Provider.allCases`.

## Secondary click opens the panel's menu

`FloatingPanel.sendEvent` also takes `.rightMouseDown`, and `.leftMouseDown` **with control held** — a control-click is a right click on macOS, and letting it fall through to `begin(_:)` starts carrying the panel instead. Same geometry as the drag (`grabArea`), so what can be picked up can be right-clicked, **the sliver included** — the rail is wound down most of the time, and a menu reachable only after hovering is one more thing to know.

Taken in `sendEvent` rather than with SwiftUI's `.contextMenu`, for the reason every other press is: this is a non-key accessory panel and SwiftUI's own input handling is not reliable on it.

`AppDelegate.panelMenu()` builds it — the menu bar menu's plain items: Show floating panel, Settings…, Quit, and an available update — and builds it **fresh on every click**, so an update found since the last one is on it. The menu exists because a full menu bar is where Pulse's icon stops being reachable ([issue #24](https://github.com/qunqin24/Pulse/issues/24)).

`placement.isMenuOpen` is set for the span of `popUp`, which runs its own tracking loop. Without it the pointer is on the menu — off the panel by every test `pointerMoved` makes — and the rail winds down to its sliver the moment the menu appears beside it. `scheduleHide` guards on it exactly as it guards on `isDragging`, and re-arms the same way.

## The card header

Token spend, Open, and Quit sit on the usage card's header. Token spend is there only while that reading is on. Open is the SF Symbol `square.grid.2x2.fill`, labelled Open Blinky. It opens the main window on the pane last shown (`settings.lastPane`). Quit is `power`. Blinky's own icon is not a control. Hovering a ring still opens that provider's card.

The press is taken in `FloatingPanel.sendEvent`, before the rail's drag, from the window rectangle `ControlFrameProbe` reported (`HeaderClickDispatch`). Mouse-up has to land in the same control. The action runs on the next turn, so the main window is not ordered front inside the panel's mouse-up. `PointerHand` still tracks the pointer and remains the fallback when that rectangle is not in yet; VoiceOver uses the button's action. `ScreenRectReporter`, which publishes Token spend's screen rectangle for the summary's outside click, returns nil from `hitTest` so it cannot swallow the press.

The summary is a separate window that can become key, so Escape, the close button, and a click outside dismiss it. The close button is the window's own, not a click the content view takes in `sendEvent`. The click-outside monitor ignores the button's screen rectangle, and it ignores a menu, so that same click toggles the window closed and choosing a span does not. A press on the rail is still the rail's drag and is not one of these buttons. [../token-spend.md](../token-spend.md#the-glance-window)

## Global shortcuts

`GlobalShortcut` / `GlobalShortcutMonitor` (App/). `RegisterEventHotKey`, **not** an event tap: a tap that sees other apps' keystrokes needs Accessibility permission, and that is not a trade worth offering to open a settings window. Two actions, both **unset until somebody sets one** — a default combination is a key taken out of every other app's hands on behalf of someone who never asked.

A combination needs ⌘, ⌥ or ⌃ in it; ⇧ alone is refused, and so is a bare key, function keys included. `⇧P` would take the letter P away from every text field on the Mac. A registration the window server refuses (another app holds the keys — or Pulse's own other shortcut does) lands in `unavailable`, and settings says so: a shortcut that quietly does nothing is worse than none, because the reader blames the feature. Recording is a **local event monitor**, installed only while recording and swallowing what it sees, which is what lets ⌘Q be recorded rather than quitting the app. [settings.md](settings.md)

## Settings fields

Click-away ending editing is `SettingsWindow.sendEvent`, geometry vs the field, never `hitTest`. [settings.md](settings.md).
