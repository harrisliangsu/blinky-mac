# Rings and surface

The panel's surface (solid, light, Liquid Glass), what ring colour means, the arcs a ring can carry, and the robot a ring can draw in place of the provider's mark. Input and hit testing: [input.md](input.md).

## Light panel

Light is a case of `AppSettings.panelAppearance` (and of Auto when the Mac is light), not a second switch (#74). The solid surface is drawn light (`PanelLight.fill`, grey 0.97 with a 0.12 black hairline so it keeps an edge on a white page) with dark content. The hairline is drawn **inside** the outline: the window is exactly card + rail wide, so the free rail's far side and the card's far side lie on the window's edge, and a line drawn outside was cut off there. It strokes the *normalized* path (the card's tail is a separate, overlapping subpath) and leaves out `PanelSurface.screenEdge` — the docked side, or the notch berth's top — where it would be a grey line along the display's own edge. It is a colour scheme, not a second set of views: `FloatingUsagePanelContent.panelScheme` pins `.light`, `PanelSurface` picks its fill off `\.colorScheme`, and content already drawn in `.primary` follows.

- **Solid surface only, notch included.** Glass stays dark until the Transparency slider passes three quarters, for the reason below. At a notch the berth is light too — the reader chose light, and a surface that silently turns black when docked there read as a bug. The notch fillet is the housing's own radius, and the berth is the free rail's width, not a second size.
- **The usage colours have light twins.** `pulseGood` / `pulseCaution` are about 1.5:1 on a light surface — no reading. Each `Color.pulse*` — including Gradient's peak and Quiet's greys — is a dynamic `NSColor` that resolves a deeper twin under an aqua appearance, ≥ 3:1 on `PanelLight.fill` (`UsageTintTests` pins both the switch and the ratio). The same twins appear in the menu where macOS draws it light. A colour chosen per account (`RingTint`) is the reader's and is not adjusted.

## Liquid Glass

Optional, **off by default** (`AppSettings.panelAppearance == .glass`, `PanelSurface`). Dark (flat black) stays the default because a solid rail is legible over anything.

`AppSettings.panelAppearance` is **dark / light / system / glass** — one setting. Glass used to be a separate toggle that silently overrode Light. Light exists because a black bar parked on a page of work all day is a hole in the page — not pure white (that vanishes on a white page, and the panel has no window shadow), a hairline on the light fill is the edge. Auto follows the Mac.

- **When glass is on, dim it, and let the text follow the slider.** With the active-appearance gate open (below) `.clear` glass is nearly transparent: white over a white page, black over a terminal. So the glass carries `PanelGlass.dim` — black up to 0.6, set by the reader's **Transparency** slider (`AppSettings.glassTransparency`, default 0.5 → 0.3), handed down as `\.glassTransparency`. Up to `PanelGlass.inkTurns` (0.5) the panel stays dark. Past that, `panelInk` turns the text from white toward black, and past `PanelGlass.schemeTurns` (0.75) `panelScheme` follows into light so hairlines, tracks and the usage colours stay readable. The slider's caption says black text is hard to read over dark windows. Dark, light, and auto still apply when glass is off, through `panelAppearance`. The scheme is `.environment(\.colorScheme, …)`, not `preferredColorScheme` (window-wide).
- Do **not** take the surface out of hit testing. `allowsHitTesting(false)` is what stopped gap-dragging. The window takes the drag in `sendEvent` before any view sees the event. [input.md](input.md)
- **Liquid, not frosted, depends on `FloatingPanel` overriding the private `_hasActiveAppearanceIgnoringKeyFocus` to return `true`.** Glass in an inactive window is drawn as a flat blur with no lensing, and this panel is always inactive (not key-eligible; and once Pulse has been active even once, all its windows go inactive when another app takes over). Do not "fix" it by making the panel key-eligible instead: that only holds until the first deactivation and puts focus at risk. If macOS stops asking the selector, the glass goes back to frosted and nothing else breaks. [../decisions/liquid-glass.md](../decisions/liquid-glass.md)
- Use `Glass.clear`, not `.regular`. `.regular` was measured (historical) as opaque milky white in a transparent panel. Needs macOS 26; `#available` with a vibrant blur behind it.

- **Glass needs a pixel under it** (`PanelGlass.claim`, black 0.01). The glass and its tint are composited by the system, not drawn into the window, so where only glass lies the window's own pixels are empty and the window server hands the press to whatever is behind — `sendEvent` never sees it. Reported on the docked rail (#68): rings draggable, glass between them not. Verified by real input on the docked rail after the fill went in. Do not remove it, and do not take it to zero.

[../decisions/liquid-glass.md](../decisions/liquid-glass.md)

## Colour and spent

Colour means **usage**, not identity. One setting owns the whole colour language: `AppSettings.ringColourScheme` (`RingColourScheme`, default Red alert). 1.2.1's spent-only picker (Emphasize / Follow usage / Quiet) only overrode the spent hue, so Quiet still went red at 98% used through the green→amber→red ladder. The scheme is the vocabulary; a global threshold plus a spent-only tweak is not. `Provider` carries no accent; the icon is the brand. Brand-coloured rings read as a warning (Claude’s orange at 3% used).

Three schemes, one value on the environment (`ringColourScheme`) so every ring, bar and figure agrees. `UsageTint.color(for:isExhausted:warningAt:scheme:)` and `UsageWindow.tint(warningAt:scheme:)` take both with **no default** — a default is how one ring comes to disagree with the one beside it. The environment is set once in `FloatingUsagePanelContent`.

- **Red alert** — the default, and the **only** scheme that may draw red. Green below `warningThreshold`, red at or above it, spent deep red (`pulseExhausted`). No amber step. `Turn red at` (`WarningThreshold`, 60–90%, default 75) is nested under Red alert and Quiet. It reaches the panel through `EnvironmentValues.usageWarningThreshold`, set once in `FloatingUsagePanelContent`.
- **Gradient** — green → yellow/amber → deeper amber/orange by usage. `warningThreshold` is the yellow→orange step internally and is never shown as a red control. **Never red**, including when spent, exhausted, or locked.
- **Quiet** — the same green band Red alert uses below the threshold; muted grey at or above it, and when spent. **Never red, never amber.** Not a grey wash of the whole rail — 93% remaining stays green; 2% remaining and a spent limit go grey. The 1.2.2 full-greyscale reading was a misread; [quiet-is-not-greyscale.md](../decisions/quiet-is-not-greyscale.md).

`warningThreshold` is not a layout input, so it does not belong in `PanelMetrics`. Every offered figure sits above `UsageTint.cautionThreshold` (0.5), which is Gradient's green→yellow step.

Per-account `RingTint` is opt-in. Under Red alert, spent red still wins over a chosen tint (`UsageRingView.isSpent` from the **provider**, not from the fraction — a lock can happen well short of 100%). Under Gradient and Quiet the scheme wins over alarm red; a chosen tint is kept, including when spent. System colour well, stored as hex, converted through **sRGB**. No opacity (translucent reads as “no reading”).

**Collapsed alert colour.** `FloatingUsagePanelContent.alertTint` finds the worst headline window across the rail and, past `warningThreshold` or exhausted, hands its `UsageTint` colour to `UsageDockView.alert`. An ordinary `PanelSurface` applies it only while collapsed (`isExpanded ? nil : alert`; expanded, the rings already say it). A physical notch has no collapsed surface, so `NotchAlertShape` draws the colour as a 2pt edge directly below the housing. `AppSettings.dockShowsAlertColor` (on by default) gates both inside `alertTint`, so off is the same `nil` an all-green rail produces. It exists because several accounts past the threshold otherwise leave a line coloured for as long as it is watched, which reads as a stuck pixel rather than a warning. [settings.md](settings.md)

**Countdown** (`showsRemaining`): the arc follows the figure; colour still means closeness to the limit. No reading → empty track either way; spent fills the ring. Do not invert `nil` into a full "100% left" circle. [../refresh-and-data.md](../refresh-and-data.md)

## Hover halo

The pointed-at halo hangs on the **progress arc**, not the ring view, and its inward half is **masked**. Not a `.shadow` on the composed view (it draws behind the icon and antialiased edges leak tint), not an opaque disc (invisible on black, a white coin on glass); a mask has no colour to get wrong. Measurements: [../decisions/liquid-glass.md](../decisions/liquid-glass.md).

## Window-clock arc

`showsWindowClock`, default off. Drawn **outside** the usage ring (inside belongs to the activity mark), neutral and low opacity, not a second hue. `windowClockDirection` chooses filling with elapsed time (the default, so existing installs do not reverse) or emptying with time remaining. Either direction needs both the provider-reported reset and duration (`reportsLength` must be true); with either missing it is nil. Applied as an overlay **after** `.frame(width: diameter…)`, never as a ZStack child (a wider child grew the usage ring). Own 60s ticker, not the usage loop.

## Second ring

`showsSecondRing`, default off. `ProviderUsage.secondWindow(preferring:)` returns **the fullest limit in the ring's own model group**, else the fullest of everything else. Nil where the provider reports one limit: an empty second ring reads as a limit at zero, or as a fault.

- **The group comes first because a provider can report independent budgets.** Antigravity reports a five-hour and a weekly for `Gemini` and the same pair for `Claude and GPT`; pairing a Gemini weekly with a Claude five-hour would put two unrelated pools on one mark. Claude Code's five-hour and weekly are unscoped, so they pair with each other and the model-scoped weekly stays on the card. "Fullest" rather than "the weekly one" needs no per-provider table and still works when the ring is pinned. `max(by:)` keeps the first of equals, so untouched windows stay in the provider's order between passes.
- **Inside, not outside.** Outside is the clock arc's, and the limit that matters most stays the outer, bigger, thicker ring, so nothing moves for anyone who leaves this off. Same colour language as the first ring; size and weight tell them apart. Spent fills it, whichever way it counts.
- **Geometry lives in `DockLayout.secondRing…`, not in `PanelMetrics`**: nothing outside the ring changes size. At standard scale the band between the icon disc and the ring's inner edge is 6pt and the activity mark rides its middle; with the second ring on, the mark moves in against the disc and the disc gives up 2pt a side. The ring, the rail's width and the ring centres are unchanged.
- **The percent label follows the outer limit only.** Two figures there would change `DockLayout.percentTextWidth`, a budget the whole rail is measured from.

## One ring per model group

`AppSettings.splitAccounts`, per account, default off, offered only where `Provider.splitsByModelGroup` is true — Antigravity alone, whose plan reports a Gemini allowance and a Claude-and-GPT one as two `scope`s of one login. One ring could only show the busier. Off by default because a second ring costs a slot, and docked, the rail is the whole panel.

- **The rail is slots, not accounts.** `RailSlot.rail(for:isSplit:groups:)` is the one place the order is decided; the panel's `entries` and `PanelHitArea.slot(at:)` both go through it, so a ring is never drawn at one position and refreshed from another. A slot is an account plus an optional group; `id` is `account@group`.
- **A limit never disappears into the split.** `modelGroups(of:)` is all-or-nothing: a reading that mixes scoped and unscoped windows yields no groups. More groups than `modelGroupCount` leaves the account whole rather than dropping the extra group — one ring showing the busiest of three is better than a limit nobody can see.
- **One slot until a reading carries more than one group**: one ring that becomes two beats two empty ones that may never fill. Groups keep the provider's reported order (what Antigravity's own screen shows).
- **Both rings are the same account**: icon, tint, key, refresh. Clicking either refreshes the login. They differ in windows (`windows.filter { $0.scope == group }`) and title, which appends the group so VoiceOver and the card do not repeat themselves.
- **The budget moves with it.** `AppSettings.railSlotCount` counts a split account as `provider.modelGroupCount` (a fixed 2, so the rail does not resize when a reading is one group short) and feeds `PanelMetrics.makeRoom(for:)`.

## What may not be animated

The rail's `railTop` / `railLeading` offsets track the pointer, so they sit **outside** `.animation(_:value:)`, applied after the card's reveal. Inside the card's `value: selectedSlot` spring, the first frame of a drag closed the card and sprang the rail's position too, so the panel slid away from the hand dragging it.

## Activity mark

White arc on the band between the icon disc and the usage stroke — **or just outside the disc while the second ring is on**. Core Animation, not `TimelineView`. Reset `spinning` on disappear. **Not drawn on a ring with the robot**, which shows the CLI working itself: one fact, drawn once. [../refresh-and-data.md](../refresh-and-data.md)

**`AppSettings.animatesRingActivity`** (on by default) is the one switch over this arc and the refresh mark drawn over the usage arc during a fetch. `UsageRingView.isBusy` / `isRefreshing` track the facts either way; off only withholds the cue — no travelling arc, no refresh sweep, no dimming of the usage arc while it fetches. [settings.md](settings.md)

## Robot

`AppSettings.robotAccounts`, per account, **off by default** (key `settings.robotAccounts`; the removed mark's `settings.botMarks` and its siblings are not read). On, the ring draws a robot in place of the provider's mark. The robot is **CX ArtLab's [Agent Robot Avatar](https://github.com/CX-ArtLab/agent-robot-avatar)** (MIT, v0.7.1), ported to Swift in `Sources/Pulse/Panel/Robot` — not Pulse's character, and never described as one. Licence: `THIRD_PARTY_NOTICES.md`; credit: Settings › About › Credits and the switch's own subtitle. Why the earlier mark went: [../decisions/bot-mark-removed.md](../decisions/bot-mark-removed.md).

**Each mood is one of the original's own actions, chosen from facts Pulse has seen** (`RobotMood.resolve`, in this order):

| Fact | Mood | Original action |
|---|---|---|
| A refresh from this ring (`UsageStore.isRefreshing`) | refreshing | `waiting-wave`: the eyes bob in turn |
| The provider's CLI is working (`UsageStore.isRunning`) | working | `waiting-spin`: the eyes circle each other |
| No reading | asleep | `sleep`: drowsy, then the lids meet as the head sinks; `wake` when a reading arrives |
| The provider says the limit is spent (`UsageTint.isSpent`) | spent | `failure`, held: sad lids, head and eyes lowered |
| None of these | idle | `idle`: blinks and glances around |

Two one-off gestures play over the mood when their fact becomes true (`RobotCue`): **a reset** (`UsageStore.justReset`, `ResetWatch`) plays `success`, **a finished turn** (`UsageStore.justFinishedWorking`) plays `affirm`, a nod; a reset wins if both are true. They play on the change, not on every frame the span is true, and not again when the panel reopens after the span.

- **Refresh first** because it answers a click on the ring; **working before the reading**, because the CLI runs whatever the last reading said and the white arc this replaces has nowhere else to go; **no reading before spent**, because without a reading "spent" is a memory. Nothing near a limit gets a face of its own: the ring's colour already says it.
- **`animatesRingActivity` off withholds working and refreshing** here as it withholds the arcs; the robot then shows only the reading's state. The refresh sweep on the usage arc is unchanged: it is on the ring, not in the disc.
- **Size:** `centreDiameter × UsageRingView.robotScale` — 1.1, against the mark's 1.0, so the head reads as large as the logo beside it (its drawing carries the antenna and room to move). It spreads into the band between the disc and the usage ring, which a ring with a robot leaves empty (no activity arc); with a second ring that band is taken and it is drawn at 0.8, since its taller outline would touch the inner ring at 1.0. Nothing around it is measured differently, so it is not a `PanelMetrics` entry. Dimmed with no reading, like the mark.
- **Colour:** one colour with the eyes cut out (`.destinationOut`), not the original's black and white, so the surface (glass included) shows through the eyes; the original's `color` attribute sets the same thing. **The robot's colour says which product it is, and nothing else** — kept apart from the ring's colour (`AppSettings.robotColours`, not `ringTints`), which says how much is used. Under Red alert a spent limit still turns the ring red whatever the robot wears; Gradient and Quiet do not. All robots on the rail are coloured at once (`RobotAutomatic.inks`, applied in `FloatingUsagePanelView.spreadingRobots`):
  1. **A chosen colour** (Custom, a colour well stored as hex like the ring colour) is fixed, and drawn exactly as chosen.
  2. **The product's own colour** (`Provider.brandColour`: an exhaustive switch over the hand-written providers, `ProviderProfile.brandColour` for profiled ones) is fixed too. Claude Code `D97757`, DeepSeek `4D6BFE`, Volcengine `1664FF`, MiniMax `E8483F`, Antigravity `4285F4`, GLM Coding `3A7BF7`, Kimi Code `7AA5FF`, Xiaomi MiMo `FF6900` (Xiaomi's), sub2api `3875F6` (the blue end of its gradient), Qoder `2ADB5C`, StepFun `0160FF`; Alibaba Coding Plan and Token Plan `FF6A00`, Perplexity `20808D`, Hugging Face `FFD21E`, ZoomMate `0B5CFF`. MiniMax's and Antigravity's are the right family, exact value unconfirmed. Products with a black-and-white mark have none (Codex, Kiro, Cursor, OpenCode Go, Ollama Cloud, Z.ai, Copilot, Grok, Grok Bot, Command Code, Devin, New API — neither end of its gradient is its colour — V2EX, extensions, and every profile that does not set one).
  3. **Everything else takes a colour from Pulse's wheel** (`RobotAutomatic.wheel`): twenty-four hues **less those near green, amber and red** (`usageClearances`: 66° from green, 50° from amber, 35° from the reds), which leaves blue to magenta. A robot Pulse coloured green inside a green ring read as part of the gauge in the rendered rail; a product's own colour is its own and is not held to this. Each robot, in rail order, takes the unused wheel hue farthest from its neighbours and from every colour on the panel, a neighbour counting double.

  An automatic colour (2 or 3) is adjusted to stand **3:1** off the panel — towards white on the dark panel, towards black on the light one (`RobotInk.legible(onDark:)`), so Hugging Face's yellow is darkened on the light panel; a chosen colour is never adjusted, as with `RingTint`. Two accounts of one product share its colour: it says which product, and a split account's two rings are one login.
- **Personality** (`AppSettings.robotPersonalities`, `RobotPersonality`): how the robot passes **idle time only** — how often and how fast it glances (`glanceGap`, `glanceSpeed`; the original's idle is Curious's), how often it blinks, and which of the original's idle actions it reaches for every half-minute or so (`pastime`). **Calm** looks slowly and now and then plays `bored`; **Curious** keeps the original's timing and plays `inspect`; **Lively** glances quickly and plays `surprise`. Pastimes are only actions that **claim nothing**: `success` and `affirm` are kept for a reset and a finished turn, so idle time never fakes one. Every mood that reports a fact looks the same whatever the personality. Never with Reduced Motion. **Automatic** spreads them like the colours.
- **Shape** (`AppSettings.robotShapes`, `RobotShape`): the original's `setHeadRoundness` — **Original** (50, the default), **Squarer** (0) and **Rounder** (100), each the outline eased towards a superellipse of the same box. The only appearance variant the original has besides colour and its skins, which are not ported.
- **Timing:** `TimelineView(.animation(minimumInterval: 1/30))` over a `Canvas`, the original's thirty frames a second; `RobotMotion` holds the state and has no clock of its own (`RobotMarkTests` drive it). **Paused while the rail is collapsed** (`UsageDockItem.isInteractive`) and once asleep and settled, as the original stops its frame loop asleep. Reduced Motion snaps between poses and holds still, as the original does.
- **Not ported:** pointer following, dragging, squeezing and the antenna drag (the panel's input belongs to the window, and a ring is too small to grab), the skins, and the actions with neither a Pulse fact nor a personality behind them (`wary`, `angry`, `refuse`, `love`, `random`, `input`).


## Icons

`LobeIconView` is a template image with **no colour of its own**. Do not hardcode white there: the settings sidebar needs the ordinary label colour.
