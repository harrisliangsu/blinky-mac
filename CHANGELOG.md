# Changelog

What each release changed, written for somebody deciding whether to install it.

This file is the **English** source for Sparkle's update window (via
[Scripts/changelog.py](Scripts/changelog.py) / appcast) and for the English half
of the GitHub Release page. The Chinese half lives in
[CHANGELOG.zh-CN.md](CHANGELOG.zh-CN.md); both are assembled by
[Scripts/release-notes.py](Scripts/release-notes.py) (Chinese first).
Add the entry **before** tagging, in the small grammar the converter knows:
bullets, `**bold**`, `` `code` `` and `[links](https://example.com)`.

## 1.5.13

- **The usage card opens Blinky from a grid icon.** The control beside Token spend in the card header is a filled four-square grid, and clicking it opens the main window on the pane last shown. [#74](https://github.com/harrisliangsu/blinky-mac/pull/74)

## 1.5.12

- **The exhaustion estimate appears on every shown account.** With Show the estimate on, under Settings → Usage, a weekly limit that is unused or only lightly used says it is expected to last the window, including when the service does not state that window's length. [#73](https://github.com/harrisliangsu/blinky-mac/pull/73)
- **An estimate that should last is green, and one that may not is amber.** The line under the limit uses those two colours, both held back so they stay quieter than the percentage. [#73](https://github.com/harrisliangsu/blinky-mac/pull/73)
- **The usage card opens Blinky from a window icon.** The control beside Token spend in the card header is a window symbol, and clicking it opens the main window on the pane last shown. [#73](https://github.com/harrisliangsu/blinky-mac/pull/73)

## 1.5.11

- **Notifications gathers every notice.** Settings → Notifications holds Limit reminders, Running out, Service status, and Monthly recap, and Usage under Panel holds the figures and the exhaustion estimate. [#72](https://github.com/harrisliangsu/blinky-mac/pull/72)
- **Providers is one row in Application.** Opening an account keeps Providers selected, with the account's title and Back inside the page, while the toolbar's back and forward still move between panes. [#72](https://github.com/harrisliangsu/blinky-mac/pull/72)
- **The exhaustion estimate follows the weekly limit.** The card line and the remaining-hours and will-not-last notices use the weekly limit, or the longest other limit when there is none, and a five-hour limit is left out. [#72](https://github.com/harrisliangsu/blinky-mac/pull/72)
- **The Token spend window's controls respond.** The time range, the breakdown, Refresh, Share, the close button, and Escape all do what they say, and Share says when the image was copied. [#72](https://github.com/harrisliangsu/blinky-mac/pull/72)
- **The usage card opens Blinky from its own icon.** The icon in the card's header opens the main window on the pane last shown. [#72](https://github.com/harrisliangsu/blinky-mac/pull/72)

## 1.5.10

- **Settings splits the usage card from the rings' colours.** Usage card, under Panel, holds the figures, the second ring, the reset clock, the exhaustion forecast on the card, and which accounts that forecast shares with the exhaustion notifications. Appearance gains Colour: the ring scheme, Turn red at, and the alert colour when docked. Rings and figures is no longer a pane. Notifications is now Exhaustion and reminders, and it keeps limits and outages, the exhaustion notifications, reset reminders, and celebrations. [#71](https://github.com/harrisliangsu/blinky-mac/pull/71)
- **A scheduled update can install the next time Blinky quits.** Settings → About → When an update is found adds Install silently. A scheduled check downloads the update and installs it on quit, with no notification and no update window. Notify first stays the default. Check now still opens the window. [#71](https://github.com/harrisliangsu/blinky-mac/pull/71)
- **The Token spend panel leads with tokens.** The window beside the usage card uses the same time range as Settings, including a custom range, and switches among model, agent, project, and session. Tokens are the large figure and the estimate is smaller. The chart follows that range, and Share says when the image is on the clipboard. [#71](https://github.com/harrisliangsu/blinky-mac/pull/71)
- **Opening Settings names Blinky in the menu bar.** The gear, Settings…, ⌘,, a reopen, and a settings link activate Blinky after the window's Dock policy is applied, so the menu bar shows Blinky. [#71](https://github.com/harrisliangsu/blinky-mac/pull/71)
- **The Token spend window closes from its close button and from Escape.** The red close button and Escape hide the summary opened from the usage card. [#71](https://github.com/harrisliangsu/blinky-mac/pull/71)

## 1.5.9

- **Opening Blinky shows its main window.** Finder, Spotlight, Launchpad, and the Dock open the window titled Blinky on the Appearance pane, and a launch at login stays in the menu bar unless Show main window when opened at login is on under Settings → General → Startup and windows. [Docs/architecture.md](https://github.com/harrisliangsu/blinky-mac/blob/main/Docs/architecture.md#login-item) [#70](https://github.com/harrisliangsu/blinky-mac/pull/70)
- **The Dock icon can stay on.** Always show Dock icon, in that same section, keeps Blinky in the Dock and in ⌘-Tab, and Show Dock icon while a window is open still covers the main window, a recap, and the service chooser while that switch is off. [#70](https://github.com/harrisliangsu/blinky-mac/pull/70)
- **A login launch waits to ask.** The service chooser and the first-run questions stay back until Blinky is opened by hand, and General explains it when the menu bar icon had to be turned back on. [#70](https://github.com/harrisliangsu/blinky-mac/pull/70)

## 1.5.8

- **A scheduled check notifies you before opening the update window.** Settings → About, under Check automatically: When an update is found defaults to Notify first, and the window opens when that notification is clicked. Show the window opens it immediately. Check for Updates… and Check now still open the window. If notification permission is refused, the window opens so the update is not missed. [#65](https://github.com/harrisliangsu/blinky-mac/pull/65)

## 1.5.7

- **Token spend can open beside the floating panel.** With Token spend on, the button on the usage card's header opens a summary for the same span as Settings, and Share copies that summary as an image. The full Token spend page stays in Settings. [Docs/token-spend.md](https://github.com/harrisliangsu/blinky-mac/blob/main/Docs/token-spend.md) [#62](https://github.com/harrisliangsu/blinky-mac/pull/62)

## 1.5.6

- **Settings groups a control with the choices that belong to it.** In Settings, a child row hides while its switch is off, and Notifications shows the countdown hours, starting at 6. A separate notice before the reset stays off until it is turned on. [#66](https://github.com/harrisliangsu/blinky-mac/pull/66)

## 1.5.5

- **The card says when a limit may run out.** Settings → Notifications → Exhaustion forecast. Within six hours it names the window and a rough time, for example “Weekly · may run out in about 4 hours”; further out it can say the pace may not last until the reset. Notifications start with one warning at 24 hours left, and more stages can be added. Codex’s 5-hour and weekly windows are included when the reply states a length and a reset. [#61](https://github.com/harrisliangsu/blinky-mac/pull/61)

## 1.5.4

- **Settings lists every provider under Providers.** Open Settings and choose Providers; search still finds an account by its name or the name you gave it. [#60](https://github.com/harrisliangsu/blinky-mac/pull/60)
- **The Blinky menu checks for updates.** Check for Updates… is under About and opens the same update window as the button in Settings → About. [#60](https://github.com/harrisliangsu/blinky-mac/pull/60)
- **Manage extensions, Developer integrations and About share one section.** They sit under Other at the bottom of the Settings sidebar. [#60](https://github.com/harrisliangsu/blinky-mac/pull/60)
- **Open at login is the first row under General.** The switch registers the copy that is running, including Blinky.app after a rename from Pulse.app, and simplified Chinese labels the row 开机启动. [#60](https://github.com/harrisliangsu/blinky-mac/pull/60)
- **Sparkle's update window comes forward.** A check that finds a newer version, on the schedule or from Check for Updates…, brings that window to the front and asks before installing. [#60](https://github.com/harrisliangsu/blinky-mac/pull/60)
- **The update window shows only the version being offered.** Its notes are that version's changelog entry, and earlier releases are not stacked in the same window. [#60](https://github.com/harrisliangsu/blinky-mac/pull/60)

## 1.5.3

- **An installed update shows up in Finder as Blinky.** The next time a copy still named `Pulse.app` opens, including the relaunch after an in-app update, it renames itself to `Blinky.app` when that folder has no `Blinky.app` yet, and Open at login is registered again for the new file when it was already on (Settings → General). [#58](https://github.com/harrisliangsu/blinky-mac/pull/58)
- **The predicted-reset countdown shares its title row.** On the Codex card, the time remaining sits beside Predicted reset, and the local date and time are on the line below. [Docs/providers/codex.md](https://github.com/harrisliangsu/blinky-mac/blob/main/Docs/providers/codex.md) [#59](https://github.com/harrisliangsu/blinky-mac/pull/59)

## 1.5.2

- **A new download is Blinky.app.** Finder and the disk image show that name, and the icon is the Blinky mascot. [Docs/releasing.md](https://github.com/harrisliangsu/blinky-mac/blob/main/Docs/releasing.md) [#56](https://github.com/harrisliangsu/blinky-mac/pull/56)

## 1.5.1

- **The download is named Blinky.** This release attaches `Blinky-1.5.1.dmg` and `Blinky-1.5.1.zip`, the app on disk stays `Pulse.app` with the same bundle identifier, and 1.5.0 keeps the `Pulse-1.5.0` files already published. [#54](https://github.com/harrisliangsu/blinky-mac/pull/54)

## 1.5.0

- **The name on screen is Blinky.** The menu bar, Settings, About, and update notes show Blinky, the same name as the iOS app, and this remains a fork of [Pulse](https://github.com/qunqin24/Pulse).

## 1.4.29

- **Antigravity prices its Gemini 3.8 Flash variants.** Names ending in `-n`, `-control` and `-xpe` use the published rate for `gemini-3.8-flash`, where those rows had no public price. Thanks to [@1206-skittle](https://github.com/qunqin24/Pulse/issues/90) for the report.
- **Synced from upstream qunqin24/Pulse** (4 commits, through their 1.12.3, `8410d08`, since 1.4.28). This repository is the update source, and this fork's version is **1.4.29**. Their Sparkle offer for 1.12.3 was not copied. `appcast.xml` is unchanged until this version is tagged. This sync also cuts a provider command's output at its limit, keeping only the bytes that fit.
- **Fork-only pieces kept:** Codex reset forecast, the latest-reset row (including on a card that is already open), hover copy on the reset type, and advance reminders; ring colour schemes (Red alert / Gradient / Quiet, and Quiet keeps green); ResetCelebration ribbons, including the optional five-hour / hourly one; Kimi device-code sign-in and multi-account; Qoder (including a personal token and discovery of Qoder IDE and `~/.qoder`); Zen's cookie store; bilingual release notes; and this repo's Sparkle feed and signing key.

## 1.4.28

- **Cursor shows the weekly usage limit on weekly plans.** On Premium and other plans with weekly included usage, Cursor's ring shows the week's usage and reset in place of the two monthly pools that always read 0%. Thanks to [@HesionBlack](https://github.com/qunqin24/Pulse/issues/87) for the report.
- **A ring pinned to Qoder's total stays pinned across launches.** Turning on the credit breakdown and starting Pulse again no longer returns a ring pinned to Credit allowance to automatic. Thanks to [@momusticks](https://github.com/qunqin24/Pulse/issues/89) for the report.
- **Grok's cached and reasoning tokens are counted once.** The cache hit rate, token totals and estimated cost match Grok Build's own records. Thanks to [@Edfghdrtxxx](https://github.com/qunqin24/Pulse/issues/91) for the report.
- **Antigravity prices its Pro rows and Flash (Low).** Gemini 3.1 Pro and Gemini 3.5 Flash (Low) use their published rates, and the * appears only beside a money line when a model still has no published price. Thanks to [@1206-skittle](https://github.com/qunqin24/Pulse/issues/90) for the report.
- **Choices in settings rows are menus, and sidebar icons use the text's colour.** Position, appearance, ring colour and the other row choices are pop-up menus. The icons are black in light mode and white in dark mode.
- **The Russian Token activity labels are shorter.** The switcher no longer cuts them off. Thanks to [@winstik13](https://github.com/qunqin24/Pulse/pull/92) for the contribution.
- **Qoder's card can show credit amounts.** Turn on Show credit amounts under Panel in Qoder's settings and each row shows its credits, such as 5,843 / 6,000. Thanks to [@momusticks](https://github.com/qunqin24/Pulse/issues/88) for the suggestion.
- **Qoder's credit history comes from the account's records.** The detailed card and Qoder's settings show the whole account's credits used and charged today, over 7 and 31 days, and day by day; the last seven days are taken from those records. Thanks to [@momusticks](https://github.com/qunqin24/Pulse/issues/88) for the suggestion.
- **Token spend can follow a calendar period.** Under Settings → Token spend, counting adds this month, last month, this year, and a custom range with its own first and last day.
- **Usage recaps add a day and a week.** Open them under Settings → Token spend → Usage recaps, and switch day, week, month and year at the top of the window. The four periods share one row and one Open button.
- **In Chinese, Qoder's deducted credits are named 消耗.** The larger figure, before discounts, is named 折前, so the two no longer share a word.
- **Synced from upstream qunqin24/Pulse** (24 commits, through the Qoder Chinese wording after their 1.12.2, `b035a7a`, since 1.4.27). This repository is the update source, and this fork's version is **1.4.28**. Their Sparkle offers for 1.12.1 and 1.12.2 were not copied. `appcast.xml` is unchanged until this version is tagged. This sync also times a killed subprocess from the child's side, so a busy runner does not record a finished process as still running.
- **Kept in this sync for this repository:** A Qoder personal token is still sent as a bearer token, for the quota and for credit history. Appearance stays one control: dark, light, match the Mac, or glass. Update checks still point at this repository.
- **Fork-only pieces kept:** Codex reset forecast, the latest-reset row (including on a card that is already open), hover copy on the reset type, and advance reminders; ring colour schemes (Red alert / Gradient / Quiet, and Quiet keeps green); ResetCelebration ribbons, including the optional five-hour / hourly one; Kimi device-code sign-in and multi-account; Qoder (including a personal token and discovery of Qoder IDE and `~/.qoder`); Zen's cookie store; bilingual release notes; and this repo's Sparkle feed and signing key.

## 1.4.27

- **Snap to screen edges can be turned off.** Turn it off under Settings → Position and behavior and a drag only moves the panel, flush to any edge, including over the menu bar and the Dock. Thanks to [@GinWU05](https://github.com/qunqin24/Pulse/issues/85) for the suggestion.
- **Antigravity can be read through the agy CLI.** With the editor closed, Pulse reads the quota through `agy`. Under Read usage from in Antigravity's settings, choose Automatic, CLI, or Desktop app.
- **MiniMax and MiniMax CN are one provider.** Choose the international or mainland site in MiniMax's settings. Each site keeps its own key, and a MiniMax CN key and ring settings move over at launch.
- **MiniMax Code is included in Token spend.** With Token spend on, MiniMax's card and settings show this Mac's MiniMax Code session log. Thanks to [@Eileenes](https://github.com/qunqin24/Pulse/issues/86) for the suggestion.
- **Progress bars can be segmented.** Choose Continuous or Segmented under Settings → Appearance → Progress bars. The card and the menu both follow it.
- **Estimates can use your currency.** Choose the US dollar, yuan, Hong Kong dollar, New Taiwan dollar, yen, won, or rouble under Settings → General → Currency, at the day's rate or one you type. Balances and charges a service reports stay in its own currency.
- **About 44 providers show service status.** Each provider's settings show its status page and history, with Refresh. Cursor is read from status.cursor.com. OpenCode's bars follow its own page. Turn on outage alerts under Settings → Notifications → When a service is down.
- **Connection diagnostics show the servers' replies.** Expand Server replies under Connection diagnostics in a provider's settings to see each request's status and body. Credentials are hidden.
- **Quit in the Dock icon's menu closes the windows only.** Pulse stays in the menu bar. Command-Q and Quit Pulse in the menu bar icon still quit the app.
- **Settings looks like System Settings.** The sidebar runs to the top of the window, and the title bar shows the current pane with back and forward.
- **Text stays readable on clearer Liquid Glass.** Past the default on the Transparency slider, the text turns from white to black.
- **An expired OpenCode Go subscription says there is no plan.** It is no longer reported as a refused key.
- **The panel at the notch waits before it opens.** The pointer has to rest on the housing, and a click in the moment after it opens does not refresh a ring.
- **Synced from upstream qunqin24/Pulse** (41 commits, through their 1.12.0, `572a931`, since 1.4.26). This repository is the update source, and this fork's version is **1.4.27**. Their Sparkle offer for 1.12.0 was not copied. `appcast.xml` is unchanged until this version is tagged. This sync also hides credentials a reply repeats, keeps the two MiniMax sites from sharing a cached reading, and reads a typed exchange rate whole. The READMEs are shorter, and screenshots live in `Docs/images`.
- **Fork-only pieces kept:** Codex reset forecast, the latest-reset row (including on a card that is already open), hover copy on the reset type, and advance reminders; ring colour schemes (Red alert / Gradient / Quiet, and Quiet keeps green); ResetCelebration ribbons, including the optional five-hour / hourly one; Kimi device-code sign-in and multi-account; Qoder (including a personal token and discovery of Qoder IDE and `~/.qoder`); Zen's cookie store; bilingual release notes; and this repo's Sparkle feed and signing key.

## 1.4.26

- **Codex’s predicted reset does not stay after the reset has happened.** Once the weekly limit has refilled, or the predicted time has passed, the Codex card no longer shows that countdown as still coming; opening the card or a usage refresh reads Codex Resets again. [#47](https://github.com/harrisliangsu/blinky-mac/pull/47)

## 1.4.25

- **The reasoning lattice is shown as a figure.** On the Codex account in Settings, under Signs of a weaker model, each model's share of long replies that stopped at a fixed point is listed on its own, with Too few to tell under 20 long replies, and without a Possibly weakened or Normal label. [#84](https://github.com/qunqin24/Pulse/pull/84)
- **The group is named Reasoning stopped at fixed points.** Under Signs of a weaker model on the Codex account in Settings, the former Reasoning cut off group uses this name, and the footnote says the cause has not been published and that the share alone does not show a model was weakened. [#84](https://github.com/qunqin24/Pulse/pull/84)
- **Synced from upstream qunqin24/Pulse** (1 commit, `b3bf083`, through [#84](https://github.com/qunqin24/Pulse/pull/84), since 1.4.24). This repository is the update source, and this fork's version is **1.4.25**. `appcast.xml` is unchanged until this version is tagged.
- **Fork-only pieces kept:** Codex reset forecast, the latest-reset row (including on a card that is already open), hover copy on the reset type, and advance reminders; ring colour schemes (Red alert / Gradient / Quiet, and Quiet keeps green); ResetCelebration ribbons, including the optional five-hour / hourly one; Kimi device-code sign-in and multi-account; Qoder (including a personal token and discovery of Qoder IDE and `~/.qoder`); Zen's cookie store; bilingual release notes; and this repo's Sparkle feed and signing key.

## 1.4.24

- **Codex’s effort ranking includes max and ultra.** On the Codex account in Settings, Signs of a weaker model now records a turn lowered from max or ultra, the levels above xhigh. [#83](https://github.com/qunqin24/Pulse/pull/83)
- **A smaller context window is no longer listed as a cut.** Editing the context window in Codex’s `config.toml` is your own change, and Settings quietly lowered no longer lists it. [#83](https://github.com/qunqin24/Pulse/pull/83)
- **Synced from upstream qunqin24/Pulse** (1 commit, `7579dcd`, through [#83](https://github.com/qunqin24/Pulse/pull/83), since 1.4.23). This repository is the update source, and this fork's version is **1.4.24**. `appcast.xml` is unchanged until this version is tagged.
- **Fork-only pieces kept:** Codex reset forecast, the latest-reset row (including on a card that is already open), hover copy on the reset type, and advance reminders; ring colour schemes (Red alert / Gradient / Quiet, and Quiet keeps green); ResetCelebration ribbons, including the optional five-hour / hourly one; Kimi device-code sign-in and multi-account; Qoder (including a personal token and discovery of Qoder IDE and `~/.qoder`); Zen's cookie store; bilingual release notes; and this repo's Sparkle feed and signing key.

## 1.4.23

- **Codex’s predicted reset follows an announced reset.** After Codex Resets publishes a reset, Predicted reset and Last reset on the Codex card show that announcement. [#43](https://github.com/harrisliangsu/blinky-mac/pull/43)

## 1.4.22

- **Extensions can report metrics of their own.** Figures such as time to first token and output rate appear on the card with a trend line. [How to report them](https://github.com/harrisliangsu/blinky-mac/blob/main/Docs/extensions.md#metrics). Thanks to [@xkaaaaaa](https://github.com/qunqin24/Pulse/issues/80) for the suggestion.
- **No Proxy and System Proxy Only.** Choose them under Settings → Network and refresh → Proxy; System Proxy Only connects nowhere while macOS has no proxy switched on, and Follow System stays the default.
- **Hide the floating panel from screenshots.** Turn on Hide from screenshots under Settings → Position and behavior, and screenshot tools that support it leave the panel out; recordings and screen sharing may still show it.
- **Old figures are no longer shown once a provider confirms there is no plan.** This covers z.ai, Xiaomi Coding Plan, Grok Bot and others.
- **Clearing Xiaomi Coding Plan's sign-in asks you to sign in again.** The card no longer shows the old figures.
- **An account signed in to again is no longer replaced by the old login's renewal.** This covers Claude Code and Grok accounts added in Pulse.
- **Qoder's expiry lines no longer repeat when its credits are shown part by part.** The total no longer shows one, and a row whose credits all lapse together reads "All expire Nov 7". Thanks to [@momusticks](https://github.com/qunqin24/Pulse/issues/76) for the report.
- **Qoder credits lapsing over several days are described in full.** For example, "All expire from Nov 8, in 4 lots". [#76](https://github.com/qunqin24/Pulse/issues/76)
- **Turning on Show each part of the credits lets the ring follow the part closest to spent.** A ring pinned to the total returns to automatic. [#76](https://github.com/qunqin24/Pulse/issues/76)
- **Synced from upstream qunqin24/Pulse** (21 commits, through their 1.11.0, since 1.4.21). This repository is the update source, and this fork's version is **1.4.22**. Their Sparkle offer for 1.11.0 was not copied. `appcast.xml` is unchanged until this version is tagged.
- **Fork fixes in this sync:** Qoder's personal token (`pt-` / `jt-`) and discovery of Qoder IDE and `~/.qoder` stay. The figure on a limit row keeps the ring colour scheme. The light surface stays on the existing Appearance choice (dark, light, auto, or glass). The extensions guide in Settings opens this repository. Update checks stay on this repository.
- **Fork-only pieces kept:** Codex reset forecast, the latest-reset row (including on a card that is already open), hover copy on the reset type, and advance reminders; ring colour schemes (Red alert / Gradient / Quiet, and Quiet keeps green); ResetCelebration ribbons, including the optional five-hour / hourly one; Kimi device-code sign-in and multi-account; Qoder (including a personal token and discovery of Qoder IDE and `~/.qoder`); Zen's cookie store; bilingual release notes; and this repo's Sparkle feed and signing key.

## 1.4.21

- **Qoder's credits can be shown part by part.** The allowance adds up plan credits, a top-up pack and dedicated credits, and each is spent on its own, so the total can look ample while one part is nearly gone. In Qoder's settings, under Panel, turn on Show each part of the credits. The three parts follow the total, and the ring follows whichever is closest to spent. A single part with an allowance is not shown twice. Off by default. A personal token (`pt-` / `jt-`) still signs in. Thanks to [@momusticks](https://github.com/qunqin24/Pulse/issues/76) for the suggestion.
- **With the time arc on, the rings no longer sit against the panel's bottom edge.** Docked at the top of the screen, with figures above the rings, the arc almost touched the bottom edge, most noticeably under the camera notch. The ring's side now keeps 10pt more room while the arc is on. Thanks to [@cybershape](https://github.com/qunqin24/Pulse/issues/78) for the report.
- **Expiring credits are no longer read as everything that is left.** In Chinese, Japanese and Korean, the line names them as part of the total. Russian puts the verb before the amount, so the singular reads correctly for every number.
- **Russian is a sixth interface language.** Settings can follow the system or choose Русский. Dates and large-number units follow that language. Japanese, Korean and Russian still read the English update notes.
- **Past usage stays after a tool deletes its old records.** Claude Code and other tools prune old transcripts. Pulse keeps the days, money, hours, sessions and recaps it has already read. Records deleted before this version cannot be recovered.
- **The notch surface follows the rings.** Docked at the camera housing, the surface is as wide as the rings it carries.
- **Recap cards say what they count.** Rhythm of the day names the reader's own busiest four hours. A fixed span from 9 PM to 5 AM is no longer used. The payback card stays when some work has no published price, and says the money is a floor. A recap counts from this Mac's first record; earlier days are dashed, and are not counted as zero. A day with no published price no longer removes the money chart. Cache figures are described as reductions in the API price. Weekdays are compared by their average. A month that is still running is not described as finished. Every card can carry a note.
- **Synced from upstream qunqin24/Pulse** (24 commits, through the Russian expiry-line follow-up after their 1.10.0, since 1.4.20). This fork's version is **1.4.21**. Their Sparkle offers for 1.9.0 and 1.10.0 were not copied. `appcast.xml` is unchanged until this version is tagged. The Mistral and Kilo Code balance tests compare figures with the reader's own number format ([#79](https://github.com/qunqin24/Pulse/issues/79)). The extension time-limit test allows for a loaded runner's wait for a thread.
- **Fork fixes in this sync:** Qoder's part rows stay on the same account as the personal token and discovery of Qoder IDE and `~/.qoder`. Russian includes this fork's own strings. The light surface stays on the existing Appearance choice (dark, light, auto, or glass). Update checks stay on this repository.
- **Fork-only pieces kept:** Codex reset forecast, the latest-reset row (including on a card that is already open), hover copy on the reset type, and advance reminders; ring colour schemes (Red alert / Gradient / Quiet, and Quiet keeps green); ResetCelebration ribbons, including the optional five-hour / hourly one; Kimi device-code sign-in and multi-account; Qoder (including a personal token and discovery of Qoder IDE and `~/.qoder`); Zen's cookie store; bilingual release notes; and this repo's Sparkle feed and signing key.

## 1.4.20

- **Codex reset cards show again while any remain.** The Reset cards line counts a card whose status is available, unknown, or omitted, until its expiry. A shorter list keeps the reported count. An empty list, or a list whose rows are all redeemed or expired, still removes the line when an older count is attached. The count on the usage reply is shown with the weekly window; a later list that proves none are left replaces it, and a count-only reply does not bring that line back. The Banked reset credit row under Last reset is the public announcement, not this inventory.

## 1.4.19

- **Codex's credit balance is a number.** The Credit balance row in Settings showed the raw value with ten decimal places, such as "2500.0000000000". It now uses the number format of the current language, with at most two decimal places.
- **A short history no longer draws a disc over the card.** When this Mac's records covered only one day, the daily chart on the detail card was a circle over the rows below it. Bars are always sized for 31 days, and a short history starts at the left. The daily charts in Settings and the menu bar follow the same rule and no longer draw wide blocks.
- **The light panel keeps its edge, and its colours stay readable.** Light, and Auto when the Mac is light, draws a light surface, including in the notch. The hairline sits inside the outline, and is left off the side that lies on the screen. Green, amber, red, and the Gradient and Quiet colours are deeper on that surface. Where the panel meets the notch, the curve matches the housing instead of the rail's larger flare. Glass stays dark.
- **Synced from upstream qunqin24/Pulse** (8 commits, through the light-panel edge follow-up after their 1.8.3 line, since 1.4.16). This fork's version is **1.4.19**. Their Sparkle offer for 1.8.3 was not copied. `appcast.xml` already offers 1.4.18 and is otherwise unchanged until this version is tagged.
- **Fork fixes in this sync:** the light surface stays on the existing Appearance choice (dark, light, auto, or glass), rather than a second Panel colour switch. Ring colour schemes, the Codex reset forecast, and reset ribbons still draw on that surface.
- **Fork-only pieces kept:** Codex reset forecast, the latest-reset row (including on a card that is already open), hover copy on the reset type, and advance reminders; ring colour schemes (Red alert / Gradient / Quiet, and Quiet keeps green); ResetCelebration ribbons, including the optional five-hour / hourly one; Kimi device-code sign-in and multi-account; Qoder (including a personal token and discovery of Qoder IDE and `~/.qoder`); Zen's cookie store; bilingual release notes; and this repo's Sparkle feed and signing key.

## 1.4.18

- **The Codex card drops reset cards that are already gone.** The line counts credits that are still available and have not expired. When the reply lists none left, the line is removed, even if an older count is still attached. Opening the Codex card asks again, and so does each later refresh while a card is showing, so the line moves with the rest of the card. A failed read keeps the previous figure; a successful read with no reset-card data removes the line.

## 1.4.16

- **About credits the panel design as inspiration.** The Credits row for Vinz says the panel design is inspired by work he shared on X. English, Simplified Chinese, Traditional Chinese, Japanese, and Korean all say that.
- **Interface copy is revised in Simplified Chinese, Traditional Chinese, Japanese, and Korean.** Each concept keeps one term, and wording and line breaks are corrected. In Simplified Chinese, keychain lines now say that no Keychain prompt is needed, and notices such as an expired login or an unreachable update feed are full sentences.
- **Synced from upstream qunqin24/Pulse** (6 commits, through their 1.8.2 line, since 1.4.15). This fork's version is **1.4.16**. Their Sparkle offer for 1.8.2 was not copied; `appcast.xml` is unchanged until this version is tagged. Upstream rewrote the Chinese notes for its own versions; this fork's existing entries are unchanged.
- **Fork-only pieces kept:** Codex reset forecast, the latest-reset row (including on a card that is already open), hover copy on the reset type, and advance reminders; ring colour schemes (Red alert / Gradient / Quiet, and Quiet keeps green); ResetCelebration ribbons, including the optional five-hour / hourly one; Kimi device-code sign-in and multi-account; Qoder (including a personal token and discovery of Qoder IDE and `~/.qoder`); Zen's cookie store; bilingual release notes; and this repo's Sparkle feed and signing key.

## 1.4.15

- **A Keychain prompt no longer holds up every refresh.** Reading Claude Code's sign-in waits at most 60 seconds, then uses the other routes. Saving a key while a console session is being renewed no longer drops one of them, and a renewal cannot write back a login you just removed.
- **Changing how the panel looks no longer asks every provider again.** Size, spacing, appearance and the other look settings only lay the panel out again.
- **The Position row wraps.** When the window is too narrow for the label and the choices side by side, the choices move under the label.
- **The recap's big numbers are no longer clipped.** A 9 or a 5 keeps its right edge, and the month and year leave room for the mark beside them. The price field is the width of a price.
- **Token kinds name what was not classified.** The breakdown shows an Unclassified row, and Fresh is now Input. Work that is only unclassified reads as not reported.
- **Synced from upstream qunqin24/Pulse** (17 commits, through the Support section after their 1.8.1 line, since 1.4.14). This fork's version is **1.4.15**. Their Sparkle offer for 1.8.1 was not copied; `appcast.xml` is unchanged until this version is tagged. The README's Support section, with its Afdian badge, is included; this repository's badges and links stay on harrisliangsu/blinky-mac.
- **Fork fixes in this sync:** update checks stay on this repository's GitHub feeds and are not retried against update.qunqin.org. Ring colour schemes, reset reminders (predicted and regular, 12 / 24 / 48 hours), celebrations including the hourly one, the appearance picker, Kimi's extra accounts, Qoder and Zen are carried into the split settings files. The shared usage fetch still asks Qoder, Kimi's extra accounts, and the Codex reset forecast.
- **Fork-only pieces kept:** Codex reset forecast, the latest-reset row (including on a card that is already open), hover copy on the reset type, and advance reminders; ring colour schemes (Red alert / Gradient / Quiet, and Quiet keeps green); ResetCelebration ribbons, including the optional five-hour / hourly one; Kimi device-code sign-in and multi-account; Qoder (including a personal token and discovery of Qoder IDE and `~/.qoder`); Zen's cookie store; bilingual release notes; and this repo's Sparkle feed and signing key.

## 1.4.14

- **Monthly and yearly recaps.** A month or a year of AI coding becomes a set of cards to share: an overview poster, the tools that worked with you, the calendar, your hours, whether your plan paid for itself, and a closing scorecard. The yearly recap adds twelve small calendars and a month-by-month comparison. Open it from Settings › Token spend, then save, copy or share the images. Everything comes from this Mac's own records; what is missing is left out, never drawn as zero. Type a monthly plan price in the recap window to see how many times over you used it; leave it empty and that card is left out. Project names are shown and can be hidden in one click. The recap's Chinese persona names are written plainly.
- **A note when the recap is ready.** Once a month, early in the month, for the month that ended; clicking it opens that recap. In Settings › Notifications, off by default. The Dock icon also shows while the recap window is open.
- **Token activity.** The Token spend pane charts the last twelve months by day (a square per day), by week, or as a running total, with the day's or week's figure under the pointer. Month labels sit on each month's first day, columns grow with the pane, and faint squares fill the days before the first record.
- **Cleaner sessions and project names.** Claude Code's subagent transcripts join the session they belong to, so one session no longer appears several times. Codex sessions are titled from the first thing you actually said; automatic reviews are marked Codex review. Titles no longer show links or fall back to a file name. Work in a repository's worktree counts under that repository. Codex Desktop's and DeepSeek's scratch folders are no longer taken for projects.
- **A blank cache cell where none was recorded.** The day table leaves the cache cell empty when the records have no cache.
- **Bundled marks draw their arcs.** Arc flags are spelled out in the bundled marks, so icons macOS was drawing incomplete — Gemini CLI among them — draw whole.
- **Update notes in the language you set.** A new Sparkle item can carry one description per language, and a Pulse set to Chinese or English reads that language's feed (`appcast-zh.xml`, `appcast-en.xml`) beside the main one. Every URL is this repository on GitHub. The update.qunqin.org mirror is not used, and this fork does not read qunqin24's feed.
- **Docs, notices, and recap fixes.** Third-party notices list every bundled mark and the bot data. Docs drop claims the code no longer makes. Recap review fixes cover daylight-saving midnights, same-period chips, months still to come, singular counts, stale recap reads, and translations.
- **Synced from upstream qunqin24/Pulse** (35 commits, through their 1.8.0 line, since the 2026-10-05 sync). This fork's version is **1.4.14**. Their Sparkle offers for 1.7.3 and 1.8.0 were not copied; `appcast.xml` is unchanged until this version is tagged.
- **Fork fixes in this sync:** update checks stay on this repository's GitHub feeds, including the per-language copies the release workflow writes with this fork's signing key; a failed check is not retried against the mirror. The floating panel still opens Settings from a card while the recap notice opens the recap. The recap scorecard names this repository. Qoder's personal token, Kimi's extra accounts, reset reminders, and the hourly celebration stay in the docs and in Settings search.
- **Fork-only pieces kept:** Codex reset forecast, the latest-reset row (including on a card that is already open), hover copy on the reset type, and advance reminders; ring colour schemes (Red alert / Gradient / Quiet, and Quiet keeps green); ResetCelebration ribbons, including the optional five-hour / hourly one; Kimi device-code sign-in and multi-account; Qoder (including a personal token and discovery of Qoder IDE and `~/.qoder`); Zen's cookie store; bilingual release notes; and this repo's Sparkle feed and signing key.

## 1.4.13

- **The panel can lie across, or sit on the bottom edge.** Position is Left, Top, Bottom, Free across, Free upright, Right. Free across is the top dock’s shape placed anywhere; Bottom sits on the screen’s own edge, in the empty space either side of the Dock. A rail lying across can put the percentage to the right of each ring. With the time arc on, figures stand clear of it. A card taller than the room on that side of the screen scrolls instead of being cut off. Thanks to [@GinWU05](https://github.com/qunqin24/Pulse/issues/70) and [@tyrival](https://github.com/qunqin24/Pulse/issues/73).
- **Usage history by model, and speeds.** Claude Code and Codex settings add a Models card: each model’s share, cache hit rate, and output tokens per second over the last 24 hours. Codex also shows the wait for the first token. Conversations that still hold a prompt cache are listed with how long it has left.
- **OpenCode Go can read its console.** With the browser sign-in, limits and the request log come from the console — every device, at what was actually charged. OpenCode 2’s new tables are read, and a message counts once.
- **DeepSeek’s console.** Read the browser sign-in and Pulse shows the last 30 days — spend and tokens by day and by model, in the account’s currency — and the balance when no API key is set.
- **Signs of a weaker Codex model.** Codex settings read this Mac’s sessions and send nothing: long replies whose reasoning stopped on 516, 1,034, 1,552 and so on, and turns that ran on a different model, lower reasoning, or a smaller context than you set. These are signs, not proof.
- **Service status.** Codex, Claude Code, and DeepSeek settings show each provider’s own status page: the state now, a bar a day for about 90 days, and the page’s uptime. Notifications gain When a service is down, off by default. It checks every five minutes and says once when a part the tool runs on goes down, gets worse, or comes back.
- **Opening About checks for an update now.** The version row is this check, not the last scheduled one.
- **A Dock icon while Settings is open**, on by default, so a covered settings window can be found with Cmd-Tab. It goes away when the window closes.
- **Token spend counts and prices more carefully.** A resumed or forked Claude Code session’s copied replies count once. Codex sub-agents no longer inherit the parent’s running total, and archived sessions are read. Claude Code’s output is no longer taken from only the first line of a reply. Cache writes, long-context tiers, and several agents that counted twice are corrected. A cache nobody records says Not reported.
- **A missing sign-in is no longer hidden behind yesterday’s percentage.** A missing session, saved login, or app asks you to sign in. Renewing a login no longer writes back an account you already removed.
- **Lighter on the Mac.** Usage scans, token-spend totals, and the panel following the pointer do less repeated work.
- **Contributions no longer need an accepted issue first.** Review and evidence rules stay.
- **Simplified and Traditional Chinese copy is plainer**, including 服务商 and 账号 where the text used to say 供应商 and 账户.
- **Synced from upstream qunqin24/Pulse** (26 commits, through their 1.7.2 line, including copyright headers). This fork’s version is **1.4.13**. Their Sparkle offers were not copied; `appcast.xml` is unchanged until this version is tagged.
- **Fork fixes in this sync:** service-outage alerts sit beside reset ribbons and advance reminders, each with its own file; ring colour schemes still paint every ring, bar, and figure on the split panel view; the Codex reset forecast, the latest-reset row, and reminders still draw on a card that is already open; Kimi’s device-code login and extra accounts stay.
- **Fork-only pieces kept:** Codex reset forecast, the latest-reset row (including on a card that is already open), hover copy on the reset type, and advance reminders; ring colour schemes (Red alert / Gradient / Quiet, and Quiet keeps green); ResetCelebration ribbons, including the optional five-hour / hourly one; Kimi device-code sign-in and multi-account; Qoder (including a personal token and discovery of Qoder IDE and `~/.qoder`); Zen’s cookie store; bilingual release notes; and this repo’s Sparkle feed and signing key.

## 1.4.12

- **Codex’s prompt cache is timed by OpenAI’s stated floor.** On GPT-5.6 and later, the detailed card and Settings show how long that cache is still guaranteed, worded “at least”, counted from the request that last touched it. When the floor has passed, the line says “May have lapsed”. Earlier models have no stated lifetime and are not timed.
- **Synced from upstream qunqin24/Pulse** (the one commit this fork had not yet taken). This fork’s version is **1.4.12**. `appcast.xml` is unchanged until this version is tagged.
- **Fork-only pieces kept:** Codex reset forecast, the latest-reset row (including on a card that is already open), hover copy on the reset type, and advance reminders; ring colour schemes (Red alert / Gradient / Quiet, and Quiet keeps green); ResetCelebration ribbons, including the optional five-hour / hourly one; Kimi device-code sign-in and multi-account; Qoder (including a personal token and discovery of Qoder IDE and `~/.qoder`); Zen’s cookie store; bilingual release notes; and this repo’s Sparkle feed and signing key.

## 1.4.11

- **Small fixes no longer need an accepted issue first.** A bug fix, a documentation change, or a translation can be a pull request on its own. A new feature or a large refactor still needs an issue a maintainer has labelled `accepted`. When one person already has two pull requests open, the check posts a reminder and leaves the pull request open.
- **The README leads with what Pulse saves you.** Each language opens with a download button, the hover card, and four reasons. The badges still point at this repository.
- **Each account can open a detailed card.** Switch it on in that account’s settings. The card adds the plan and when the figures were read. Where Pulse has a history it also shows today, the last 7 days and the last 31 days of tokens, a month’s chart, and the model doing most of the work. z.ai and Zhipu use their own account statistics. Claude Code, Codex, and every Token spend agent that borrows a provider’s mark use this Mac’s records, and those need Token spend on.
- **The detailed card adds an estimated value, the cache hit rate, and how long Claude Code’s prompt cache has left.** Each limit gets the estimated-value line the account’s settings pane already had. The usage section shows the cache hit rate, and the settings pane lists it by model. For Claude Code the time left is read from the tier each reply records and counted from the request. With several conversations open, the card names the one about to lapse and Settings lists every conversation. Subagent caches are left out: they are their own and do not make the next message cheaper.
- **Synced from upstream qunqin24/Pulse** (the four commits this fork had not yet taken). This fork’s version is **1.4.11**. `appcast.xml` is unchanged until this version is tagged.
- **Fork-only pieces kept:** Codex reset forecast, the latest-reset row (including on a card that is already open), hover copy on the reset type, and advance reminders; ring colour schemes (Red alert / Gradient / Quiet, and Quiet keeps green); ResetCelebration ribbons, including the optional five-hour / hourly one; Kimi device-code sign-in and multi-account; Qoder (including a personal token and discovery of Qoder IDE and `~/.qoder`); Zen’s cookie store; bilingual release notes; and this repo’s Sparkle feed and signing key.

## 1.4.10

- **An issue titled with only the template prefix is closed.** New issues start with `[Bug]`, `[Feature]`, `[Provider]`, or `[Question]` already filled in, and the form cannot require any text after that prefix. If nothing is left once those prefixes are removed, the issue is closed, with a short note in both languages asking for a new one whose title says what it is about. Each of the four templates says so. Maintainers are exempt.
- **Synced from upstream qunqin24/Pulse** (the one commit this fork had not yet taken). This fork’s version is **1.4.10**. `appcast.xml` is unchanged until this version is tagged.
- **Fork-only pieces kept:** ring colour schemes (Red alert / Gradient / Quiet, and Quiet keeps green); ResetCelebration ribbons, including the optional five-hour / hourly one; Kimi device-code sign-in and multi-account; Qoder (including a personal token and discovery of Qoder IDE and `~/.qoder`); Zen’s cookie store; bilingual release notes; and this repo’s Sparkle feed and signing key.

## 1.4.9

- **The Codex countdown and its note both show.** After 1.4.8 the card could still stop at 「预测重置」 and the confidence, with no countdown and no 「预计在 … 前」. A status saved before the window end was stored has no `expires_at`, and a 304 keeps that copy. Pulse now fetches it again at once. The event note still lives on the ?, and hovering or clicking draws it on the card — this panel never becomes key, so a system tooltip there does not appear. Confidence stays at the end of the title. A reminder still counts down only to an announced time.
- **Fork-only pieces kept:** ring colour schemes (Red alert / Gradient / Quiet, and Quiet keeps green); ResetCelebration ribbons, including the optional five-hour / hourly one; Kimi device-code sign-in and multi-account; Qoder (including a personal token and discovery of Qoder IDE and `~/.qoder`); Zen’s cookie store; bilingual release notes; and this repo’s Sparkle feed and signing key.

## 1.4.8

- **Codex’s predicted reset shows the time.** On the Codex card, 「预测重置」 counts down and gives the local date, the way [codex-resets.com](https://codex-resets.com) does: how long until a reset may happen, and the moment it is expected before. The event note (DevDay and the like) sits behind a ? on that row. Confidence stays at the end of the title. An announced time is still what a reminder counts down to; a watch’s window end is not.
- **Fork-only pieces kept:** ring colour schemes (Red alert / Gradient / Quiet, and Quiet keeps green); ResetCelebration ribbons, including the optional five-hour / hourly one; Kimi device-code sign-in and multi-account; Qoder (including a personal token and discovery of Qoder IDE and `~/.qoder`); Zen’s cookie store; bilingual release notes; and this repo’s Sparkle feed and signing key.

## 1.4.7

- **This repository ([harrisliangsu/blinky-mac](https://github.com/harrisliangsu/blinky-mac)) is the update source.** Sparkle’s appcast and GitHub Releases point here, not upstream qunqin24/Pulse.
- **Synced from upstream qunqin24/Pulse** (seven commits this fork had not yet taken, through their 1.6.1 line). This fork stays on its own version: **1.4.7**. Their Sparkle offer was not copied; `appcast.xml` is unchanged until this version is tagged.
- **A new icon.** A P drawn in one stroke: the stem is the screen edge the panel docks to, the lime bowl a usage ring left open. It is built from an Icon Composer document, as macOS 26 expects, so Liquid Glass follows the dark, clear, and tinted icon styles. Older systems still get the flattened icon.
- **With Liquid Glass on and the panel docked, the rail can be dragged from between its rings**, not only by a ring. A near-invisible fill under the glass gives the window those pixels. The settings caption that said to drag by a ring is gone. Thanks to [@annsyun](https://github.com/qunqin24/Pulse/issues/68) for reporting it upstream.
- **The window starter is listed among the features** in the README. Starting Claude Code’s and Codex’s usage windows after a reset already shipped in 1.4.6, still off by default.
- **LiteLLM’s duration cases are written out** so that test file type-checks.
- **Fork-only pieces kept:** Codex reset forecast, the latest-reset row (including on a card that is already open), hover copy on the reset type, and advance reminders; ring colour schemes (Red alert / Gradient / Quiet, and Quiet keeps green); ResetCelebration ribbons, including the optional five-hour / hourly one; Kimi device-code sign-in and multi-account; Qoder (including a personal token and discovery of Qoder IDE and `~/.qoder`); Zen’s cookie store; bilingual release notes; and this repo’s Sparkle feed and signing key.

## 1.4.6

- **This repository ([harrisliangsu/blinky-mac](https://github.com/harrisliangsu/blinky-mac)) is the update source.** Sparkle’s appcast and GitHub Releases point here, not upstream qunqin24/Pulse.
- **Synced from upstream qunqin24/Pulse** (one hundred and thirteen commits this fork had not yet taken, through the opt-in that starts Claude Code’s and Codex’s usage windows after they reset).
- **Extensions.** A program in the extensions folder can report one account’s usage — an internal quota, or a prepaid balance — and Pulse draws it as a ring. Nothing runs until it is switched on, and Pulse hands it no credentials. How to write one: [Docs/extensions.md](Docs/extensions.md).
- **Fifty-two more providers, 77 built in.** They are described by a profile rather than a new case in every switch: ClinePass, Alibaba Cloud Model Studio’s Coding Plan and Token Plan, Qwen Cloud, LongCat, Gemini, Kilo Code, Factory, Augment Code, Windsurf, Amp, Mistral, Moonshot, OpenAI API, xAI API, and the rest named in the README. Those fifty-two were ported by reading [CodexBar](https://github.com/steipete/CodexBar) and have not all been checked against a live account.
- **Subscriptions and API accounts are listed apart.** Enabled accounts sit at the top. Every account that reports a balance can choose what its ring measures — since the last top-up, the balance alone, or a budget you type — the three choices DeepSeek already had.
- **Usage in the menu bar**, off by default. The icon can show the fullest ring, or one account, as a figure, a small ring, or the five-hour and weekly limits side by side. The menu is a dashboard: an overview, a tab per account, Codex’s reset credits and credits left, and estimated spend when Token spend is on. **Show floating panel** is in that menu. Opening Pulse again while it is already running opens Settings.
- **The panel is sized for the rings that are switched on**, not for every provider. Order lists only those accounts. The Settings sidebar is wider. A key field can show what was typed.
- **Codex’s card can show limit reset credits**, behind a switch. Pulse looks for the `codex` the ChatGPT and Codex apps ship, including where ChatGPT 26.924 moved it, and says when none can be found. The card can show when the next credit expires.
- **With Liquid Glass, the card’s tail is part of the card.**
- **After a reset, Pulse can start Claude Code’s and Codex’s usage windows**, off by default. Turning it on asks for a confirmation: this is not a feature of those products, and it sends one short message through the tool already signed in on this Mac.
- **Grok’s pool counts as spent at 100%.** Removing an added account clears that account’s settings, including its animated mark.
- **Fork-only pieces kept:** Codex reset forecast, the latest-reset row (including on a card that is already open), hover copy on the reset type, and advance reminders; ring colour schemes (Red alert / Gradient / Quiet, and Quiet keeps green); ResetCelebration ribbons, including the optional five-hour / hourly one; Kimi device-code sign-in and multi-account; Qoder (including a personal token and discovery of Qoder IDE and `~/.qoder`); Zen’s cookie store; bilingual release notes; and this repo’s Sparkle feed and signing key.

## 1.4.5

- **This repository ([harrisliangsu/blinky-mac](https://github.com/harrisliangsu/blinky-mac)) is the update source.** Sparkle’s appcast and GitHub Releases point here, not upstream qunqin24/Pulse.
- **Synced from upstream qunqin24/Pulse** (twelve commits this fork had not yet taken, on top of their 1.4.0 line).
- **StepFun’s Step Plan is the twenty-fifth provider.** A signed-in browser session for `platform.stepfun.com` or `platform.stepfun.ai` (or a pasted `Cookie:` header) reads a Token Plan’s monthly credits and top-up packs as one ring, with the date the soonest of them lapse, or a Coding Plan’s five-hour and weekly windows. An account with no plan says so.
- **Qoder shows when bonus packs lapse.** Each pack has its own end date; the card shows the soonest, such as “Oct 18: 86 credits expire”, with packs ending the same day added together. `--json` gains `expiresAt` and `expiringAmount`.
- **A stale Qoder reset date no longer drops the reading.** A mainland trial can reply with a reset long past; Pulse used to discard the whole reading as expired. The date is ignored and the remaining credits are shown. Buying a pack is still not a reset — only the reset date moving forward counts.
- **Qoder reporting no credits clears the cached percentage.** A confirmed empty allowance removes the banked reading, so an old figure no longer stands in on the panel, after relaunch, or in `--json`.
- **Model prices refresh without restarting Pulse.** An expired price table is downloaded again on the next read; a failed download keeps the old one and may retry after five minutes.
- **The bot mark follows the original animation.** Glances, gestures and larger moves play at full size, so an eye may touch the edge and the top of the head may briefly leave the ring. An arriving pointer is noticed one mark after another, each turning over about 0.4 seconds, rather than every ring snapping in the same frame.
- **Fork-only pieces kept:** Codex reset forecast, the latest-reset row (including on a card that is already open), hover copy on the reset type, and advance reminders; ring colour schemes (Red alert / Gradient / Quiet, and Quiet keeps green); ResetCelebration ribbons, including the optional five-hour / hourly one; Kimi device-code sign-in and multi-account; Qoder (including a personal token and discovery of Qoder IDE and `~/.qoder`); Zen’s cookie store; bilingual release notes; and this repo’s Sparkle feed and signing key.

## 1.4.4

- **Weekday upstream syncs fail less often on the first CI run.** `Scripts/fork-compat-check.sh` runs in CI before the build. The sync agent should run it after merging upstream, before pushing. It rejects conflict markers, unbalanced braces in the files a merge rewrites, a second `async let` for the same provider (the duplicate Qoder fetch), and a switch that drops a fork case — Qoder, a Kimi session, a credit window — without a `default`.
- **Reset ribbons stay on weeks and months.** Five-hour windows still follow the optional switch. A top-up, credits, a daily or message allowance, a balance, and any window kind added later stay quiet: they do not fail the build, and they do not throw a ribbon.
- **A new provider does not have to edit the bot-mark colour switch.** Brands live in one map. Qoder keeps its green. Anyone else, including a provider upstream just added, is dealt a colour.
- **One place fetches each provider on a pass.** Upstream inserting another `async let qoderUsage` is a second binding the check rejects, rather than two declarations the compiler meets only on the Mac.
- **Tests that had been failing a sync for the wrong reason.** The bot mark's slide budget no longer sits on one tight sample. Glass is pinned dark in the appearance test, which is what this fork draws. Colour dealing counts `Provider.allCases` rather than a hardcoded provider total.
- **Fork-only pieces kept:** Codex reset forecast, the latest-reset row (including on a card that is already open), hover copy on the reset type, and advance reminders; ring colour schemes (Red alert / Gradient / Quiet, and Quiet keeps green); ResetCelebration ribbons, including the optional five-hour / hourly one; Kimi device-code sign-in and multi-account; Qoder; Zen's cookie store; bilingual release notes; and this repo’s Sparkle feed and signing key.

## 1.4.3

- **This repository ([harrisliangsu/blinky-mac](https://github.com/harrisliangsu/blinky-mac)) is the update source.** Sparkle’s appcast and GitHub Releases point here, not upstream qunqin24/Pulse.
- **Synced from upstream qunqin24/Pulse 1.4.0** (the seventeen commits this fork had not yet taken).
- **sub2api, New API, and V2EX.** Two self-hosted gateways read a balance or allowance from a server address and key you enter. V2EX reads its AI Chat allowance with a Personal Access Token.
- **Qoder follows upstream’s account-page read.** Credits and a team plan’s shared pool are two rings. Buying a pack is not treated as a reset. The site (`qoder.com` or `qoder.com.cn`) is a setting, and changing it clears the saved session. A personal token (`pt-` / `jt-`) still works, and discovery still notices Qoder IDE and `~/.qoder`.
- **Real Liquid Glass**, with a Transparency slider. Appearance stays dark, light, match the Mac, or glass; glass pins white content over a dimmed clear material.
- **The window clock can count down.** The outer arc of Time until reset can show time elapsed or time remaining.
- **Kiro and ZCode show activity.** Pulse reads the session records they leave on this Mac. ZCode drives a ring only when its endpoint belongs to Zhipu or z.ai.
- **Settings are split by subject** (Appearance, Rings and figures, Position and behavior, General, Notifications, Network and refresh). Codex reset reminders and reset celebrations moved with the notification rows. Ring colour schemes stayed on Rings and figures.
- **Setup help** opens the user setup pages in this repository.
- **Smoother cards, a panel that stays put at the screen edge, and an animated mark that no longer jumps** when a motion is interrupted. Token spend keeps same-name projects apart, and unpriced use is no longer shown as $0.00.
- **Fork-only pieces kept:** Codex reset forecast, the latest-reset row (including on a card that is already open), hover copy on the reset type, and advance reminders; ring colour schemes (Red alert / Gradient / Quiet, and Quiet keeps green); ResetCelebration ribbons, including the optional five-hour / hourly one; Kimi device-code sign-in and multi-account; bilingual release notes; and this repo’s Sparkle feed and signing key.

## 1.4.2

- **Codex card shows the latest reset while it is open.** 1.4.1 added the row, then left it off when the announcement arrived after the card was already up — the usual case, because 「暂无预测」 / "No prediction yet" does not change when the row should appear under it. The prediction row is unchanged. Reminders still count down only to `scheduled_for`.
- **Hover the reset type.** The info icon is gone. Hovering 「备用重置额度」 / "Banked reset credit" still explains that you apply it yourself and that usage does not refill immediately. Hovering 「常规重置」 / "Regular reset", or a type the feed adds later, shows that announcement's own text. An announcement with no text has no tooltip.
- **The Codex Resets credit line is gone.** The card no longer prints "Data from Codex Resets". An arrow on the prediction row still opens [codex-resets.com](https://codex-resets.com), including when there is no latest announcement.
- **Fork-only pieces kept:** Qoder, Kimi device-code / multi-account, ResetCelebration ribbons (incl. optional hourly), ring colour schemes (Red alert / Gradient / Quiet), bilingual release notes, and this repo’s Sparkle feed / signing key.

## 1.4.1

- **Codex card shows the latest reset.** When [Codex Resets](https://codex-resets.com) has announced one, the Codex card adds how long ago and what kind it was, with the local time — a banked credit explains that you apply it yourself and that it does not refill usage immediately. The prediction row is unchanged, including "No prediction yet" when there is no time and no watch. Reminders still count down only to `scheduled_for`.
- **Fork-only pieces kept:** Qoder, Kimi device-code / multi-account, ResetCelebration ribbons (incl. optional hourly), ring colour schemes (Red alert / Gradient / Quiet), bilingual release notes, and this repo’s Sparkle feed / signing key.

## 1.4.0

- **Codex reset forecast on the card.** The Codex card shows the public [Codex Resets](https://codex-resets.com) status: an explicit `scheduled_for` when there is one, otherwise the watch's level, chance and window — never the watch's expiry as a reset time. No prediction stays an empty line. Banked reset cards from `codex app-server` appear on that card when the read succeeds.
- **Reset reminders, before the reset.** Two switches, both off: predicted (only an explicit Codex Resets time; 12 / 24 / 48 hours ahead) and regular (each account's own reset, skipped when the window is shorter than the lead). These are not the after-the-fact "limit came back" notice and not the celebration ribbons.
- **Fork-only pieces kept:** Qoder, Kimi device-code / multi-account, ResetCelebration ribbons (incl. optional hourly), ring colour schemes (Red alert / Gradient / Quiet), bilingual release notes, and this repo’s Sparkle feed / signing key.

## 1.3.2

- **This repository ([harrisliangsu/blinky-mac](https://github.com/harrisliangsu/blinky-mac)) is the update source.** Sparkle’s appcast and GitHub Releases point here, not upstream qunqin24/Pulse.
- **Synced from upstream qunqin24/Pulse** (five commits on top of their post-1.3.0 line that this fork had not yet taken).
- **Hide the menu bar icon** (off by default). Reach Pulse through the floating panel menu or global shortcuts alone; Settings always keeps at least one working entry point.
- **Agent guidance entry point** — `AGENTS.md` for coding agents working in this repo.
- **Fixed stale RPC timeouts after helper restarts.** Old Codex and Kiro request timers can no longer finish a newer request that reused the same identifier, or report a late failure after a request already completed.
- **Fork-only pieces kept:** Qoder, Kimi device-code / multi-account, ResetCelebration ribbons (incl. optional hourly), ring colour schemes (Red alert / Gradient / Quiet), bilingual release notes, and this repo’s Sparkle feed / signing key.

## 1.3.1

- **This repository ([harrisliangsu/blinky-mac](https://github.com/harrisliangsu/blinky-mac)) is the update source.** Sparkle’s appcast and GitHub Releases point here, not upstream qunqin24/Pulse.
- **Synced from upstream qunqin24/Pulse** (nine commits on top of their 1.3.0 line).
- **Kiro** as a new provider — reads subscription usage over the CLI’s own ACP, without touching its credentials.
- **CLI activity scan only where a provider is being watched**, so idle agents do not wake the rail.
- **Notch rail:** top-docked rail attaches to the notch itself; the notch surface sweeps into the screen edge without padding under it.
- **Marks:** mainland Zhipu row uses the BigModel mark; both GLM rows share one mark instead of naming one after a product; a provider mark that loads but draws nothing fails loudly.
- **Docs:** pull-request contribution guidelines; repository numbers in the READMEs (this fork’s badges and links).
- **Fork-only pieces kept:** Qoder, Kimi device-code / multi-account, ResetCelebration ribbons (incl. optional hourly), ring colour schemes (Red alert / Gradient / Quiet), bilingual release notes, and this repo’s Sparkle feed / signing key.


## 1.3.0

- **This repository ([harrisliangsu/blinky-mac](https://github.com/harrisliangsu/blinky-mac)) is the update source.** Sparkle’s appcast and GitHub Releases point here, not upstream qunqin24/Pulse.
- **Synced from upstream qunqin24/Pulse 1.3.0** (includes their 1.2.1 work that this fork had not yet taken).
- **First-run provider picker.** Pulse reads no credentials and starts no monitoring until you choose what it may watch. Later upgrades only suggest newly detected local services; they never enable one on their own.
- **Proxy settings.** Keep following macOS, or set HTTP / HTTPS / SOCKS5. Provider requests, sign-in flows, and helpers such as Codex and arkcli share the same choice.
- **Token spend is opt-in.** Off on new installs; scans local sessions only while its Settings pane is open. Leaving the pane cancels an unfinished read. Large JSONL logs stream instead of loading whole.
- **Xiaomi Coding Plan** as a new provider (browser session on the MiMo console — not an API key). No plan says so instead of drawing 0%.
- **Updates checked every two hours** (was once a day). Still offered, never auto-installed.
- **Codex no longer spins the CPU** after `codex app-server` exits (closed-pipe read loop).
- **Rail / ring polish from upstream:** optional alert colour when docked, optional CLI-activity / refresh ring animation, rail ends that follow the ring’s own curve (softened by default), bot gaze into the screen with eyes kept inside the face, fuller bot choreography, lighter Kimi bot blue, rewritten Chinese bot settings copy.
- **Fork-only pieces kept:** Qoder, Kimi device-code / multi-account, ResetCelebration ribbons (incl. optional hourly), ring colour schemes (Red alert / Gradient / Quiet), bilingual release notes, and this repo’s Sparkle feed / signing key.

## 1.2.4

- **This repository ([harrisliangsu/blinky-mac](https://github.com/harrisliangsu/blinky-mac)) is the update source.** Sparkle’s appcast and GitHub Releases point here, not upstream qunqin24/Pulse.
- **An opt-in for 5-hour ribbons.** “Celebrate a reset” still means a week or a month by default. A new switch — **Also celebrate hourly quota resets** — covers Zhipu and Kimi’s short window when you want it. Off by default. A clock that only slides a few minutes — Codex’s session — is still not a reset.
- **Fork-only pieces kept:** Qoder, Kimi device-code / multi-account, ResetCelebration ribbons, bilingual release notes, and this repo’s Sparkle feed / signing key.

## 1.2.3

- **This repository ([harrisliangsu/blinky-mac](https://github.com/harrisliangsu/blinky-mac)) is the update source.** Sparkle’s appcast and GitHub Releases point here, not upstream qunqin24/Pulse.
- **Quiet keeps green for healthy usage.** Settings → General → Ring colour scheme → **Quiet** no longer washes the rail grey. Below the Turn-red threshold a ring, percent label and usage bar stay the same green Red alert uses; at or above that line, or when the provider says the limit is spent, they go muted grey — never red. 93% remaining stays green; 2% remaining and a spent limit go grey.
- **Fork-only pieces kept:** Qoder, Kimi device-code / multi-account, ResetCelebration ribbons, bilingual release notes, and this repo’s Sparkle feed / signing key.

## 1.2.2

- **This repository ([harrisliangsu/blinky-mac](https://github.com/harrisliangsu/blinky-mac)) is the update source.** Sparkle’s appcast and GitHub Releases point here, not upstream qunqin24/Pulse.
- **One Ring colour scheme.** Settings → General replaces the spent-only colour picker with **Ring colour scheme**: **Red alert** (green and red only, with the nested **Turn red at** threshold), **Gradient** (never red), or **Quiet** (grey, never red). Quiet no longer reddens past the threshold. Existing Emphasize / Follow usage / Quiet values migrate onto the matching scheme.
- **Fork-only pieces kept:** Qoder, Kimi device-code / multi-account, ResetCelebration ribbons, bilingual release notes, and this repo’s Sparkle feed / signing key.

## 1.2.1

- **This repository ([harrisliangsu/blinky-mac](https://github.com/harrisliangsu/blinky-mac)) is the update source.** Sparkle’s appcast and GitHub Releases point here, not upstream qunqin24/Pulse.
- **Choose how a spent ring is coloured.** Settings → General has a Spent ring colour picker under Turn red at: **Emphasize** (the default, the same deep red as before), **Follow usage** (colour as any other 100% reading), or **Quiet** (a muted grey). Exhausted is no longer forced deep-red if you pick otherwise. The provider still says whether the limit is spent — this only picks the hue.
- **Fork-only pieces kept:** Qoder, Kimi device-code / multi-account, ResetCelebration ribbons, bilingual release notes, and this repo’s Sparkle feed / signing key.

## 1.2.0

- **This repository ([harrisliangsu/blinky-mac](https://github.com/harrisliangsu/blinky-mac)) is the update source.** Sparkle’s appcast and GitHub Releases point here, not upstream qunqin24/Pulse.
- **Animated marks.** A ring’s provider logo can be replaced by a small animated bot. Off by default, switched on per account in that account’s settings pane. It says only what the panel already knows: that provider’s CLI is running, Pulse is fetching a reading, the limit is spent, there is no reading yet, or nothing is happening. A ring drawing a mark no longer draws the white activity arc — a travelling arc and a bot that visibly gets to work are one fact drawn twice.
- **Personality, shape and colour.** Eight personalities decide which motions a mark plays and at what pace, dealt automatically so the ring beside it is a different character. Eighteen body shapes, round by default. Colour is the provider’s brand where it has one, otherwise dealt to stand apart from its neighbours’ hues, or chosen outright. All three are per account.
- **It reacts to what is happening.** The eyes follow the pointer across the panel, and the ring being pointed at stops to listen. Work alternates between working, generating and writing, with anger added out of hours. A machine that has been quiet for twenty minutes gets bored, and sleepy about it at night. A limit that resets is celebrated; a finished turn gets a cheer. The reset is recognised by the same rule the reset notification uses, whether or not notifications are on.
- **Clearer mark messaging.** The mark says what Pulse is doing rather than what it refuses to do; it keeps from claiming what Pulse did not see, and stops re-solving stills.
- **The project’s address in About**, alongside credit for the animated marks’ origin.
- **Fork-only pieces kept:** Qoder, Kimi device-code / multi-account, ResetCelebration ribbons, bilingual release notes, and this repo’s Sparkle feed / signing key.

## 1.1.3

- **This repository ([harrisliangsu/blinky-mac](https://github.com/harrisliangsu/blinky-mac)) is the update source.** Sparkle’s appcast and GitHub Releases point here, not upstream qunqin24/Pulse.
- **More token-spend sources.** Local-record readers for Gemini CLI, Cline, Roo Code, OpenClaw, GitHub Copilot and more, plus exports from Cursor, Trae and others. Some sources need a prior export or capture. [Sources](https://github.com/harrisliangsu/blinky-mac/blob/main/Docs/token-spend-sources.md).
- **Model usage details.** Open a model for input/output/cache, daily and hourly usage, and per-agent contributions; detail tables sort and page. Costs use published API rates — not a subscription bill.
- **Chart hover values.** Point at a history chart to read the token count for that date or hour, including short bars and empty periods.
- **Rail menu and global shortcuts.** Right-click the floating rail to open Settings. Optional shortcuts open Settings or show/hide the rail (unassigned by default).
- **Traditional Chinese, Japanese and Korean.** Three new interface and README translations; large-number abbreviations use each language’s own units.
- **Plan-based model pricing** and corrected Kilo CLI price source; day, model and session amounts agree. Spend catalogue marks missing prices and incomplete counts.
- **Antigravity IDE** reads its own conversation store; Devin records are no longer labelled CLI-only; matched database and Desktop captures count once.
- **Cross-day aggregates** contribute only in-range usage; Command Code rewinds keep consumption that already occurred; default span is the last week and is remembered.
- **Settings sidebar** keeps its width after a language change; agent icons and screenshots updated.
- **Fork-only pieces kept:** Qoder, Kimi device-code / multi-account, ResetCelebration ribbons, bilingual release notes, and this repo’s Sparkle feed / signing key.

## 1.1.2

- **This repository ([harrisliangsu/blinky-mac](https://github.com/harrisliangsu/blinky-mac)) is the update source.** Sparkle’s appcast and GitHub Releases point here, not upstream qunqin24/Pulse.
- **Devin joins as a provider.** Daily and weekly quota come from a Chromium browser session (no keychain prompt). With no credential, Pulse reads the app’s dated saved plan. Account and organization boundaries stay isolated. [Setup](https://github.com/harrisliangsu/blinky-mac/blob/main/Docs/providers/devin.md).
- **Token spend.** Local sessions from Claude Code, Codex, OpenCode, Kilo CLI, Grok Build, Kimi CLI and Devin CLI are grouped by span, agent, model, project, session and token kind. Costs use published API rates — not a subscription bill. [Details](https://github.com/harrisliangsu/blinky-mac/blob/main/Docs/token-spend.md).
- **Detail cards no longer drift** along the rail as they open and close.
- **Model pricing and aliases** match the names agents actually write; snapshots and spending stay inside their proper bounds.
- **Cross-midnight sessions** count only their in-range work; log/database cache updates and custom session titles are corrected.
- **Fork-only pieces kept:** Qoder, Kimi device-code / multi-account, ResetCelebration ribbons, bilingual release notes, and this repo’s Sparkle feed / signing key.

## 1.1.1

- **本仓库（[harrisliangsu/blinky-mac](https://github.com/harrisliangsu/blinky-mac)）为更新源。** Sparkle 的 appcast 与 GitHub Releases 指向本仓库，而不是上游 qunqin24/Pulse。
- **Choose where the ring turns red.** Settings now has a warning threshold for the amber→red boundary; the green boundary stays fixed, and a spent limit still overrides the colour. Exact equality at the threshold counts as red.
- **Claude Code warning severities leave room.** A warning from Claude Code is no longer read as a spent limit; locked reasons and unknown severities still mark the limit spent.
- **Sign-in UI stays on its own provider.** Device-code Cancel, the code row, and sign-in errors only appear on the pane for the provider you started — not on every Accounts group.
- **Issue templates ask for specifics**, and the provider list in them is no longer stale.

## 1.1.0

- **本仓库（[harrisliangsu/blinky-mac](https://github.com/harrisliangsu/blinky-mac)）为更新源。** Sparkle 的 appcast 与 GitHub Releases 指向本仓库，而不是上游 qunqin24/Pulse。 安装自本仓库的副本会从这里收到后续版本。
- **A large balance no longer overflows the ring.** The rail shows ¥5k, ¥123k, $1.2M rather than the full figure, which did not fit and was being cut off — the exact balance is on the card and in Settings. It is always rounded **down**, so the ring never claims you have more than you do.

- **The rail no longer sits slightly too low until you touch something.** On most displays the panel is taller than the space macOS will grant it, and Pulse works out where to draw the rail from the position the window actually got. It was asking that question a moment too early — before the window was on screen, when the answer was still the position it had **requested** — so the rail was drawn about 76pt below where it belonged, and then jumped into place the first time any setting changed.

- **API balances are checked more often.** Pulse paces itself by watching this Mac — an agent writing to its transcripts, a figure that moved, you glancing at the rail — which is why it can be quick when you are working and quiet when you are not. But money spent through an API leaves no trace here, so DeepSeek and Command Code were always being left the full half hour: it waited because nothing had changed, and nothing appeared to change because it waited. Those two are now checked at least every five minutes. Everything else is unaffected, a Mac in low power or with the panel hidden still goes quiet, and a fixed interval you chose yourself still means what it says.

- **The provider list starts in alphabetical order.** It was in the order providers had been added over the months, which meant nothing to anyone reading it. If you have arranged the rail yourself, your arrangement is untouched.

- **Tell me when the credit runs low.** Providers that sell prepaid credit — DeepSeek and Command Code — get a **Warn below** figure in their own settings, and Pulse says so once when the balance falls under it. Money rather than a percentage, because these two report no allowance to take a percentage of; per provider rather than one figure, because ¥20 and $20 are not the same line. Off until you set one, like every other notification here. It is said once and not again until you top up — or until you move the line, which is a new question and gets a new answer.

- **Notifications about a prepaid balance say less, and say it correctly.** Credit that is bought does not reset and cannot be declared spent by arithmetic, so changing what the ring measures against no longer announces a reset, and a balance reaching 100% of a figure **you** set no longer claims the provider says you are out. Only the provider saying so does that.

- **DeepSeek joins as a prepaid-credit provider**, and the first one Pulse carries that reports no allowance at all — `GET /user/balance` says how much prepaid credit is left and nothing else. There is no quota, no window and no spend history to read, so the ring needs a denominator from somewhere and you choose which in DeepSeek's settings. **Since top-up** is the default and needs nothing from you: Pulse remembers the highest balance it has watched, and a balance that goes up can only be a top-up, so the ring starts again from full when you add credit. **Balance only** draws no ring at all and puts the money itself on the rail. **My budget** measures against a figure you type. The first two days on "since top-up" will read low — Pulse can only measure from the moment it started watching, and the card says which date that is.

- **智谱's row is now called "Zhipu".** The rail and the settings list are otherwise all Latin script, and one row in Chinese characters read as a different kind of thing rather than as another shop. The company, the storefront and the key it takes are unchanged — this is the name on the row, nothing else. Its sibling stays **z.ai**, which is that company's own spelling.

## 1.0.9

- **Updates now come from this repository.** Copies installed from GitHub 1.0.8 will be offered this build in the app. The same Codex reset, Cursor Models ring, and celebration sound as 1.0.8.

- **Command Code joins as a prepaid-credit provider.** It bills a credit balance in dollars rather than a token allowance, so the rings are money: the rolling 5-hour and weekly limits, your organisation's spend limits, and how much of this month's plan is gone. That last one is marked **estimated** on the card, and it is the one thing here Pulse has to infer — Command Code reports what is **left** of a plan's monthly credit but never what the plan grants, which is published on its pricing page instead. A plan Pulse cannot size shows no monthly row at all rather than a reassuring zero. Sign in by pasting a key, or let Pulse borrow the one `cmd auth login` already saved.

- **The panel can follow you between displays.** Switch on "Follow the active display" and the rail moves to whichever screen your pointer is on, keeping the same corner and the same distance down it. There is still only one rail — it is carried across, not copied onto every monitor — and it stays where you last dragged it if you leave the setting off, which is how it ships. "Active" means the display the pointer is on and nothing else: it does not chase other apps' windows around, and it asks for no extra permission to work out where you are.

## 1.0.8

- **The floating rail can be tiny, and it can be light.** Size now has a fourth step below Small, for sitting on a page without covering a line of it. Appearance is one control: Dark, Light, Auto, or Glass — glass is not a second switch sitting on top of Light. Light is a pale rail with a hairline, not a white hole and not the black bar that punches through homework.

- **Settings and Quit on the details card enlarge under the pointer**, and the cursor becomes a hand, so they stay hittable at Tiny. A first version of that overlay was a hole in the transparent window — the click landed on the page behind Pulse. The control now claims the point itself.

- **A limit coming back can throw ribbons across the screen.** Off until you turn it on, under Settings › General › Celebrations. The overlay names the provider and plays the system Hero sound. Five-hour sessions do not count — they roll several times a day. Codex pushing `resetsAt` by a few minutes on every poll is not a refill either.

- **Cursor's ring follows Cursor Models**, not the tiny Other Models overflow pool that looks spent as a percentage while Composer still has most of its allowance.

- **Qoder's Add-on Credits now shows when it resets.** That bar is a second JSON document with no date of its own; Team Plan's reset is the one the usage page prints on both, so Pulse copies it across.

- **The interface follows your Mac's language.** Pulse now declares that it speaks Chinese, which it always did — the translations shipped, macOS just was not told they existed, so a Mac set to 简体中文 got an English app. If that was you, this update switches over on its own; if you preferred it in English, Settings › Language still overrides. The Chinese copy has been rewritten throughout while we were in there.

- **Antigravity can show its two allowances as two rings.** The plan carries one budget for Gemini and a separate one for Claude and GPT, and until now a single ring could only follow whichever was busier — the other went unmentioned unless you hovered. Switch on "A ring for each model group" in Antigravity's settings and each gets its own ring, both under the Antigravity icon, both refreshing the one login. Off by default: an extra ring takes room on the rail, and most people want the one number.

- **智谱 and z.ai get a usage history**, read from the same statistics the console draws its own charts from. Unlike the history Pulse builds for Claude Code and Codex — which it works out by reading session files on this Mac — this one comes from the account, so it covers every machine you use it on. It counts tokens only: the figures behind it cannot be turned into money, and the card says so rather than printing a confident zero.

- **A second limit on the ring.** A thinner ring inside the first shows the next-fullest limit *of the same kind* — the 5-hour beside the weekly it belongs with — so both are readable without hovering. Where a provider splits its allowance by model, the two arcs come from the same allowance wherever it has a second limit to show: pairing one model's weekly with another's 5-hour would put two unrelated budgets on one mark. Off by default and switched on in Settings; the ring is the thing you read without stopping, and two arcs is twice as much to take in. Where a provider reports only one limit nothing is added.

- **The panel no longer slides out from under you as you pick it up.** On a display where the panel is taller than the space under the menu bar — which is most laptops — macOS quietly refuses the position Pulse asks for, and Pulse was then drawing the rail relative to a position the window never had. It jumped about one ring's worth on the first frame of a drag. It tracks the pointer exactly now.

- **The two GLM Coding Plan rows are now named for the shops** — **z.ai** and **智谱**. They were "Z.ai" and "GLM Coding Plan", which was a trap: both shops sell the plan under that same name, so anyone on the international plan picked the row named after their product and had their key sent to the mainland service, which of course refused it.
- **A refused key now says the key was refused.** These services answer with an ordinary HTTP 200 and put the verdict inside, and Pulse only recognised the English wording and two of the numbers — so the most common mistake of all, a key from the other one of the two shops, came out as "the service returned an error" and sent people looking for an outage that was not happening.

## 1.0.7

- **Pulse can tell you, instead of waiting to be looked at.** Three switches in Settings, all off until you turn them on. **Warn at** posts a notification when a limit passes 75, 80, 90 or 95% — whichever you pick — and again when the provider says it is spent. **When a limit comes back** says so once the window you were warned about has turned over, which is the moment you can start again. **When a reading stops arriving** is the one that is about Pulse rather than about usage: a failed check falls back to the last good figures, which is the right thing to show and also the reason the fault is invisible — the panel goes on displaying perfectly plausible numbers with only a "last read" time to give it away. It waits for three failures in a row and then says it once, with the same sentence the card would have shown you.
- **It says each thing once.** A limit already past the line when you switch this on is mentioned straight away — silence followed by a wall is not restraint — and then never again until it resets or gets worse. "Spent" is the provider's own word, never a rounding of ours. A reset is announced only on unambiguous evidence, so a rolling weekly allowance sliding down a few points is not mistaken for a window turning over. And a provider you have never set up, or an app that simply is not running, is not a failure to be reminded of on a timer.
- **Antigravity reads from the IDE too**, not only the desktop app. If Antigravity IDE is the one you have open, its ring said “Open Antigravity to see its usage” while the figures were sitting there for the asking. Both report the same thing — the Gemini and the Claude-and-GPT group, weekly and five-hour each.
- **Antigravity could pick the wrong helper and give up.** It runs more than one of these, only one of them answers, and Pulse asked the first it found and stopped.
- **Reorder the rail by dragging.** The arrows are still there — they are the precise way to move one place, and the only way that works from the keyboard — but with fifteen providers, moving the bottom one to the top was fourteen clicks. There is a Reset order button under the list for when a drag goes somewhere you didn't mean.
- **Volcengine**, bringing it to fifteen. The Ark Coding Plan and Agent Plan, personal and team, each with its five-hour, weekly and monthly windows. Two ways in: `arkcli`, using the login it already saved so there is nothing to paste, or a Volcengine access key pair for anyone who has keys but doesn't run the CLI here. With both set up it prefers the keys — the CLI carries a sign-in that can belong to a different account, and quietly showing the wrong account's limits is worse than either answer.
- **`Pulse --json`**, so the figures can go somewhere other than the panel — a tmux status line, sketchybar, Raycast, a shell prompt. It prints what the app last read rather than fetching, so polling it every second costs nothing and asks no provider anything; every account says when its figures were taken and how old they are. Nothing in the output is translated, so a script parsing it does not break when you change the interface language.
- **Settings has a search field**, since the sidebar now lists fifteen providers plus whatever accounts you have added. It matches the provider's name as well as your own label, so a second Claude subscription you called "work" is still found by typing Claude.
- **The Settings window opens bigger.** It was sized when the sidebar held four rows and had got to the point of appearing already scrolled in both columns.
- Notifications come with the standard notification sound. Silence them, or change anything else about how they arrive, in System Settings › Notifications › Pulse — the same place as every other app.

## 1.0.6

- **Grok**, read from the login Grok Build's CLI already stores — nothing to paste. One thing worth knowing before the ring confuses you: since June 2026 a paid Grok plan spends **one weekly pool across every Grok product** — the web chat, Imagine, voice, the API and the CLI alike — so this is what the account has spent this week, not what the CLI has. That is why it is called Grok rather than Grok Build.
- **Grok Bot**, which is a different limit despite the name. It comes with a Cursor plan rather than a SuperGrok one, so it is read with the login the Cursor editor already stores and carries the xAI mark to tell the two apart on the rail. It appears by itself only if the standalone app is installed; otherwise switch it on in Settings.
- **A second account of either.** Grok signs in with a device code, Grok Bot through Cursor's own sign-in page. Both ask for the narrowest access that can read a limit — never for permission to read or write your conversations.
- A card could print a window length the provider never reported. Some limits carry a length that only exists to sort the rows — a rolling week, a billing cycle — and when there was no reset time to show, that length was printed as though it were one.
- A provider with a single route named the wrong one in Settings. Every such provider but Cursor was described as "Antigravity's language server", about an app it had nothing to do with.

## 1.0.5

- **Claude Code read through the Claude desktop app.** If you work in the desktop app rather than a terminal, Pulse had no way to see your limits: the desktop app hands the CLI a token through its own environment and renews it itself, so the login Pulse was reading went stale and never came back, and it never renders a status line either. Pulse can now read the session the desktop app is signed in with — a new "Desktop app" choice under Read usage from, and the route `Automatic` falls back to once you have allowed it. It asks for the keychain once, at launch, so there is nothing to go and find in Settings.
- **The new route says why it can't answer**, rather than leaving the last reading in place with nothing but its "Last read" time to give it away — which is what makes a refresh look as though it did nothing. It says whether the desktop app is signed out, or whether it was the keychain that was refused.
- **A reading could go backwards.** A newer figure already on file could be replaced on screen by an older one that had just arrived, and a refresh that had been given up on could still overwrite the one that replaced it — including, for an added account, the renewed login itself.
- **GitHub Copilot no longer shows a red ring for paid overage.** Going past the included allowance with overage permitted is not being blocked, and it was being drawn as though it were.
- **Codex no longer marks the wrong model group as spent.** A group reporting "limit reached" could put the mark on another group's window entirely.
- Removing your only added account no longer leaves the rail empty.

## 1.0.4

- **GitHub Copilot**, bringing it to twelve. Signs in with a device code, so there is no token to paste — Pulse asks GitHub for permission to read your profile and nothing else, and never for access to your repositories. Shows the completions, chat and premium-request allowances your plan actually has.
- **Whether a limit will last.** A switch in Settings puts one line under each limit on the card: whether it is on course to outlast its window, and roughly when it runs out if it isn't. Off by default, and it stays quiet when the figures can't carry it — the time only appears when it falls before the reset, and it is rounded, because usage comes in bursts and a figure to the minute would be made up.
- **Show what's left instead of what's spent.** Another switch, which turns the figure and the ring over together so a limit reads "88% left" rather than "12% used". The colour still means how close you are, so a nearly empty ring is still red.
- **Claude Code's card names the plan** — "Max 5x", "Pro", "Team" — as every other provider's already did. The multiplier is part of it, since a Max 5x and a Max 20x are different products.
- **The panel could quietly stop refreshing** after running a long time, and only come back when you next started Claude Code in a terminal. It notices when its own readings have gone stale and asks again, recovers from a fetch that never returned, and refreshes when the Mac wakes as well as when the display does.

## 1.0.3

- **The panel can go on a second display.** Drag it across; it remembers which screen you left it on, and comes home if that screen is unplugged.
- **Four more providers**: the GLM Coding Plan and MiniMax, each with a separate entry for the international and the mainland service, since they are separate accounts with separate keys.
- **A second arc can show how far through the window the clock is**, so "80% used" can be read against how much of the window is left. Off by default, in Settings.
- **The figure can sit above the ring** instead of below it. Also in Settings.
- A provider that needs an API key is no longer switched on by itself — it waits in Settings rather than taking a place on the rail to ask for a key.
- One that has no key says so, instead of saying "Reading…" for ever.
- Claude Code no longer shows a limit that has already reset. If its saved login has expired and no session has run for a while, the stale window is dropped rather than shown with an old reset time.
- The update window now shows the release notes itself, rather than loading the GitHub page inside it.

## 1.0.2

- **Multiple accounts.** Sign in to a second Claude Code or Codex subscription and watch both at once, each with its own ring.
- **Cursor**, reported as the two pools its own account page shows.
- **Ollama Cloud**, from PcOffeeP's pull request — with the session read out of your browser rather than copied by hand.
- **The rail can dock along the top of the screen**, above the menu bar.
- **A colour of your own for any ring**, and the gap between rings is now adjustable.
- **Percentages can be switched off** on either rail.
- The rail opens with the last reading instead of sitting blank.
- The activity mark no longer keeps turning for a minute after a turn has ended.
- The API-key field in Settings lets go when you click away from it.
- A limit you have used never reads as 0% any more.
- Quitting Codex no longer takes Pulse down with it.
- A new app icon, drawn on Apple's icon grid.

## 1.0.1

- **OpenCode Go** and **Kimi Code**, bringing it to five agents.
- **Put the rings in your own order**, in Settings.
- **A refresh button on every provider's pane**, with the age of the reading beside it.
- A new install starts with the agents you actually have, rather than five rings that say "not configured".
- The panel can be dragged by any part of the capsule, not only by its rings.
- Clicking a ring refreshes the one you clicked, whatever order the rail is in.
- The detail card no longer truncates itself at Small or sit half empty at Large.

## 1.0.0

- The first release. A floating rail of rings against the edge of the screen, one per coding agent, showing how much of each limit is left.
