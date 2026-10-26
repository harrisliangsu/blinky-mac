# Notifications

Owns: when Pulse posts a system notification, what it says, and what it refuses to say. Settings copy and layout: [ui/settings.md](ui/settings.md). Where readings come from: [refresh-and-data.md](refresh-and-data.md).

Source: [`Sources/Pulse/Usage/UsageAlerts.swift`](../Sources/Pulse/Usage/UsageAlerts.swift) for the usage notices, and [`Sources/Pulse/App/AppUpdate.swift`](../Sources/Pulse/App/AppUpdate.swift) with [`UpdateAnnouncement.swift`](../Sources/Pulse/App/UpdateAnnouncement.swift) for a newer version of Blinky. Settings: `AppSettings.alertThreshold` / `alertsOnReset` / `alertsOnFailure` / `lowBalanceAlerts` / `alertsOnOutage` / `alertsOnRecap`, plus the time-to-empty group (`exhaustionAlerts`, `exhaustionStages`, `exhaustionNotifyBeforeReset`). Every fetch goes through `UsageStore.commit(_:raw:for:)`, which passes both the raw result and the reconciled display reading. An explicit notification-setting change also calls `reconsiderAlerts()` after authorization succeeds. Celebrations (ribbons / Hero sound) are driven from the same `observe` path via `celebratesReset` / `celebratesHourlyReset` and `ResetCelebration`, and are not posted as notifications.

## What can be said

Nine things, and nothing else in that list. Each is something you would want to know *while looking at something else*, which is the test for belonging here rather than on the card. Advance reminders are a separate list, below: they are scheduled before a time, not spoken after a reading. The time-to-empty notices are the same list as the percentage ones: they speak after a reading, and they are not a second system. A newer version of Blinky is announced separately ([An update](#an-update)); it is not one of these nine.

| Alert | Fires when | Gated by |
|---|---|---|
| `approaching(percent:)` | A window's used share reaches the chosen step | `alertThreshold` |
| `spent` | The provider reports the window exhausted, or the share rounds *down* to 100 | `alertThreshold` |
| `reset` | A window that was warned about has unambiguously turned over | `alertsOnReset` + `alertThreshold` |
| `unreadable(_:)` | Three eligible failures; cached figures remain protected for their first 30 minutes, while a failure with no usable figures counts immediately | `alertsOnFailure` |
| `lowBalance(remaining:)` | A prepaid balance falls under the figure set for that account | `lowBalanceAlerts[account]` |
| Service outage (`OutageMemory`) | A provider's own status page (44 have one) reports a component its account runs on down, worse, or back | `alertsOnOutage`, and the provider switched on |
| Recap ready (`RecapNoticeRule`) | In the first three days of a month, last month had records in the scan Pulse already holds, and that month has not been announced | `alertsOnRecap`, and Token spend reading on |
| `exhaustion` | The pace from one reading puts the time left inside a stage the reader set | `exhaustionAlerts`, the account is in the forecast list, and the window is the weekly limit or, when there is no weekly limit, the longest other one with a stated length and `resetsAt`. A five-hour window is not one of these |
| `exhaustionBeforeReset` | That same pace runs out before that same window resets | `exhaustionNotifyBeforeReset`, and the same scope |

The percentage, failure, outage, recap and before-reset switches are off by default. The time-to-empty notice starts **on**, with one stage at 24 hours left. All ask for the **default sound**; the mute switch is macOS's own per-app "Play sound for notifications".

## Time to empty

The card and these notices share one pace (`BurnRate`, [refresh-and-data.md](refresh-and-data.md#forecast-burnrate)). The line and **Which accounts** are on Settings → Usage (**Exhaustion estimate**). The system notices are on Settings → Notifications: **Limit reminders** is the percentage line and the reset that follows a warning, **Running out** is the remaining-time notices, **Service status** is a reading that stops and a service that is down, and **Monthly recap** is the month. Hiding a child row does not change the setting it edits. The account list is one control: the estimate and the running-out notices both use it.

- **Who.** Every account on the panel, unless the reader switches to a list. The first time they do, the list starts as whoever is shown, so the forecast does not go quiet. One scope for the card and the notices.
- **The card** (`showsForecast`, on unless a stored choice says off). One line under the weekly limit, or under the longest other limit that states a length when the reading has no weekly one. A five-hour window is never that line, including a provider whose only limit is five hours: nothing is written. A weekly row that states no length is still the weekly row, so a five-hour sibling is not used in its place, and without a stated length there is still no pace. A time only inside **Countdown up to** (6 hours unless moved; the stepper shows that number): the window's short name and a rounded span, “Weekly · may run out in about 4 hours”, or, once the horizon is far enough, “Weekly · may run out in 1d 13h”. Past that horizon the reset sentence wins when it is on (“At the current pace, about 1d 13h before the next reset.”), otherwise the quieter hint with no time. A window that lasts still says so, so the line does not appear only for bad news. A weekly limit that has barely opened, and has barely been used, says it is expected to last, without dividing the few minutes since the reset into a rate. One that has barely opened and is already well used still shows the ordinary estimate, with a dimmer line under it that the early pace is only a guide. That second line is not added to the card's height budget: the frame already reserves a forecast line on every limit, and only one limit draws the forecast. The horizon, the hint and the reset sentence hide while the line is off.
- **Running out.** One stage at 24 hours left. **Add a stage** appends another, each with its own remaining time (1 hour through 14 days, and two stages cannot share an hour). The same windows as the card: weekly, or the longest other stated limit, never five hours. The percentage track above still sees every limit. The memory key is the stage's id plus its hours, so editing the hours asks again and a pace that wobbles across the old line does not. Cleared only when the window's turnover is confirmed, the same evidence as a percentage reset — not on a dip, and not on a pending glitch. A window already spent is the percentage track's word; a time of zero is not a second notice. A limit already inside a stage the first time it is seen is said once. A pace still inside the early floor, with use already high enough to divide, does not notify. The card shows that estimate and says it is only a guide; the notice speaks once the floor has passed.
- **Before the reset.** The card sentence is on. The notice for the same fact is its own switch, off. If both a stage and that notice match one pass, both may post; the shipped pair does not, because 24 hours left is a stage and the before-reset notice is off.
- **Permission.** Nothing is asked at launch. Opening this pane asks, because the switch starts on and would otherwise never move from off to on. A grant already decided is not asked again. The card stays usable in an unbundled build; the notice controls do not (`UsageAlerts.isSupported`).

## Advance reminders

These fire **before** a time, and they are not the five above. `alertsOnReset` still speaks only after a warned window has turned over. `celebratesReset` still plays ribbons after that same evidence. Neither is an advance reminder, and the settings copy says so.

Two switches, both off by default, in the **Reset reminders** group. Each has its own lead: 12, 24 or 48 hours. Both ask for the same notification grant. A `swift run` build disables them (`UsageAlerts.isSupported`).

| Reminder | Fires when | Does not fire when |
|---|---|---|
| Predicted reset | Codex Resets has `scheduled_reset.scheduled_for`, at lead before that instant (or immediately, if the lead has already started and the instant is still ahead) | `active_watch` alone, a null `scheduled_for`, an instant already in the past, or `latest_reset`. The card may count down to a watch's `expires_at` as a forecast bound; a reminder never does. `announced_at` is not a reset time either |
| Regular resets | A shown account's window has a stated length at least as long as the lead, at lead before that window's `resetsAt` | The window is shorter than the lead (a 5-hour window with a 12-hour lead), the length was not stated, or `resetsAt` has passed |

Deduped per announcement id plus `scheduled_for`, and per account plus window plus `resetsAt`. Changing the lead moves a notification that has not fired yet. One that already fired is not posted again. Switching a reminder off removes its pending notifications. The book is `advance-reminders.json`, next to `alerts.json`. Codex Resets itself is polled on its cache lifetime (never under two minutes, never over thirty) while a Codex account is shown or the predicted reminder is on; a failure keeps the last status. See [providers/codex.md](providers/codex.md).

This was silent first, with a changelog note saying to add a sound in System Settings if you wanted one. **That note was wrong.** A notification with no `sound` is delivered silently, and the system switch cannot put one back — it only takes away one the app asked for. The choice was never quiet versus loud, it was a working off switch in the place people look for it versus no switch at all. `requestAuthorization` therefore asks for `[.alert, .sound]`: without `.sound` in the grant, `soundSetting` is disabled outright and every `content.sound` is dropped whatever the user does with the switch.

One rule for all of them rather than sound only for the consequential ones. macOS offers one switch per app, so a distinction drawn here would be one nobody could turn off and nobody could discover. And a silent banner on a second display, or behind a full-screen window, is a message that was never delivered — which is the opposite of the test these had to pass to be here.

### A `balance` window is not a limit, and neither is a `topUp` one

Guarded on the kind, pinned by `AlertMemoryTests`:

- **`Kind.balance` (prepaid credit) never resets.** `resetsAt` is nil, so `movedOn` is never true, and the forty-point fall is not evidence (on DeepSeek that fraction is a setting).
- **Only `isExhausted` may call a `balance` spent**, not the step rule clamping against a denominator Pulse observed or the reader typed.
- **`Kind.topUp` follows both rules.** V2EX's 加油包 is bought on top of the window's allowance, with no expiry or clock ([providers/v2ex.md](providers/v2ex.md)); a second pack drops the fraction over forty points with nothing turned over. Only V2EX's `remaining_tokens` may say the pack is gone.
- **`Kind.credits`, `Kind.sharedCredits` and Qoder's parts (`planCredits`, `dedicatedCredits`) reset only when `nextResetAt` moves forward**, never on the forty-point fall: a bought pack raises the limit ([providers/qoder.md](providers/qoder.md)). A team pool states no reset and is never announced as reset. StepFun's Token Plan is the same kind ([providers/stepfun.md](providers/stepfun.md)): a monthly plan states no refill date, so its renewal is not announced.

### Low balance is about money, not a share of anything

Prepaid providers (DeepSeek first) report **no allowance**, so `alertThreshold` has nothing to act on; the warning is about the money.

- **It asks for permission like the others.** Entering a figure calls `requestAuthorizationIfNeeded`, then reconsiders current readings, so a balance already under the line is announced once. (Without it, `observe` bailed on `.notDetermined` forever on a fresh install.)
- **Per account**, because providers price in different currencies. `Provider.reportsSpendableBalance` lists the providers that hand over `ProviderUsage.creditRemaining` (a number *and* a currency), unlike the display string `creditBalance`, which for Codex can be "Unlimited".
- **Live readings only**, as for limits: the account may have been topped up since the cache banked its figure.
- **Once.** The memory records the figure warned about, so **moving the line warns again**; climbing back over re-arms it.
- **Nothing is said when it comes back.** Only the reader refills it.

### A service outage is the provider's word about its service

Requested 2026-10-04, after the status rows on the Codex, Claude Code and DeepSeek panes; Cursor's joined on 2026-10-15, and the same day every provider with a page Pulse can read (44, [providers/README.md](providers/README.md#service-status)). One switch, **When a service is down**, off by default; its subtitle names no provider. Pinned by `OutageMemoryTests`.

- **Only for a provider switched on.** `UsageAlerts.checkServices` reads the pages of providers among `shownAccounts` only.
- **Only about what the tool runs on** (`StatusPage.notifiesAbout`: the rows the pane shows, narrowed by the page's `notifies`). Claude: of the six status.claude.com components the pane shows, only **Claude Code** and **Claude API**, by id. Codex: its Codex group, all four. DeepSeek: rows whose name contains "API" ([providers/deepseek.md](providers/deepseek.md#service-status)). Cursor: the IDE, the CLI and Cloud Agents, by id ([providers/cursor.md](providers/cursor.md#service-status)). Every other provider's: the table in [providers/README.md](providers/README.md#service-status).
- **Down means the page says so**: degraded performance, partial or full outage. Maintenance and unreadable values are not outages; an unreadable page changes nothing.
- **Once per outage.** Said when a component first goes down, again only when worse (degraded → full), and once when operational again — only if it was announced. Better-but-still-down is recorded silently. An outage already under way when the switch goes on is said at once: the switch calls `checkServices` itself (not `reconsiderAlerts`, which would refetch every provider), and so does launch, right after the grant is read.
- **Only what is still watched is remembered.** Memory is per page. A component no longer listed (a Statuspage row shown only while degraded) and a page no longer watched (switch or provider off) are forgotten silently; kept, they silenced the next outage and later said "back to normal" about one that ended unwatched.
- **One odd entry is skipped, not fatal.** Component lists decode entry by entry; a null name on an unrelated component once failed the whole page.
- **One notification per provider**, every component in one sentence ("OpenAI reports CLI (Partial outage) and Codex API (Degraded performance)."), identifier `service-status-<provider>`, so a newer one replaces the last.
- **Every five minutes, on its own clock** (`ServiceStatus.checkInterval`, a loop `UsageAlerts.start` begins), not the refresh pass, which stretches to 30 minutes when idle. Not more often: status pages are written by people minutes into an incident. A tick returns at once unless the switch is on and a provider with a page is in use. The sleep is on the continuous clock, so a tick due during sleep runs right after waking. Each check reads only the current state, one request per feed — a company's page shared by two providers (Cursor and Grok Bot) is read once; one check at a time, its feeds concurrently.
- **Its own file**, `status-alerts.json`, not a field on `AlertMemory`: that type decodes as a whole, and a key old files lack would discard every limit already warned about. This switch alone writes no `alerts.json`.

### The monthly recap

"Your September recap is ready", about the month that just ended. Off by default; **When a recap is ready** in the Notifications pane, greyed out in an unbundled build and, to turn it on, while Token spend reading is off (a switch already on stays operable). Opens [the recap window](recap.md#the-window). Rule: `RecapNoticeRule` (pure, `Usage/RecapPeriods.swift`); clock: `RecapNotice` (`Usage/RecapNotice.swift`). Pinned by `RecapWindowTests`.

- **Only what Pulse witnessed.** It reads **only the scan `SpendWarmer` already keeps** (`AgentLedgers.keptSnapshot`), never a read of its own, and only while Token spend reading is on. Last month's tokens come from `SpendSummary.of`, off the main actor. No kept scan yet is "not known": nothing is said or remembered, and the next check asks again (`RecapNotice.launchDelay` 90 seconds after launch, then every 30 minutes, `checkInterval`).
- **Only when the month had records.** Zero tokens is never announced.
- **At most once per month.** `AppSettings.recapAnnouncedMonth` ("2026-09") is written **before** the notification is handed to the system, shown or not, so a relaunch, a second check, toggling the setting or a refused grant says nothing more.
- **The first three days only.** The 1st, or the 2nd and 3rd for a Mac shut or asleep on the 1st. Switching on inside those days announces at once (the limits' "already past the line" rule); outside them it waits for next month.
- **Default sound**, as [above](#what-can-be-said).
- **Clicking opens the recap window on that month**, not Settings: `NotificationTapHandler` reads the month from the identifier `recap-ready-<yyyy>-<mm>`.
- **Months only.** Day and week recaps ([recap.md](recap.md#the-window)) say nothing: a daily notice would come every morning about something the reader can open at any time, and a weekly one is the same at a lower rate.
- **Not a usage alert.** `wantsUsageAlerts` excludes it (no `alerts.json` entry); `wantsAlerts`, which decides whether permission is worth asking for, includes it. `AppSettings.onRecapAlertChange` asks for permission, not the view.

## An update

"Blinky 1.5.8 is available", when a scheduled check finds a newer version and **When an update is found** is **Notify first** (Settings → About, the default). It is not one of the nine usage notices: there is no switch beside the threshold, and `wantsNotificationPermission` stays false so a usage-alert prompt is not raised just because this is the default. Opening About, choosing Notify first, or a scheduled find that has not been allowed to post is what asks. **Show the window** does not ask and does not post this notice.

- **The window opens when the notification is clicked.** The identifier is `blinky-update`. `NotificationTapHandler` routes that click to `AppUpdate.check`, which brings forward the offer Sparkle is already holding. Dismissing the notice does not open the window; Check for Updates… still does, and so does About's Check now. Both open the window without posting a notice, whatever the setting is. While the notice is waiting, that update session stays open, so the next scheduled check waits until the offer is opened or dismissed.
- **A refused grant shows the window.** If the system status is denied, or the prompt comes back refused, or the centre cannot be used, the scheduled find shows Sparkle's offer instead of posting. The update is not dropped.
- **Default sound**, as [above](#what-can-be-said). One notice at a time; a later find replaces it. The session withdraws it when the reader has the offer in front of them, or when the offer is dismissed.
- The choice and the fallback are `UpdateAnnouncement`. `UpdateAnnouncementTests` pins them. [ui/settings.md](ui/settings.md), [releasing.md](releasing.md#sparkle).

## Rules that are not obvious

**A first sighting starts at nothing announced**, so a limit already past the line is said once, immediately — including when the setting is switched on or the threshold lowered (`UsageStore.reconsiderAlerts()`). Otherwise someone who switches it on at 93% gets silence and then a wall; the cost is at most one notification per limit.

**Copy is a status, not an event** — "92% used", never "just passed 90%" — so it stays true whenever read.

**100% is the provider's word.** `spent` comes from `UsageWindow.isExhausted`, or a share reaching 100 rounding *down* (99.6% stays 99). See [decisions/reported-figures.md](decisions/reported-figures.md).

**Limits are judged on `.live` readings only.** A `.stale` reading can carry a cached figure *lower* than the recorded one, and a falling figure is how a reset is detected; the cache once announced a reset on every network hiccup.

**A live snapshot is not live forever.** Limit rules need a dated reading no older than the cache's 24-hour maximum and skip windows whose reset time has passed. Reconsidering applies the same guards and requests a refresh when a displayed reading is stale, undated, too old or has an expired window; valid windows can still warn at once.

**A reset needs unambiguous evidence.** A few points of drift is not a reset — a rolling window (Kimi's week) slides down without anything having turned over. A clock that inches forward by a few minutes is not one either: Codex (and Spark) push `resetsAt` on every poll, which CodexBar treats as the same window. A jump counts only when it is more than 30 minutes **and** a quarter of the window's length. A forty-point drop together with that kind of jump is a turnover on the first sample. A forty-point drop while the clock holds still, or only slides a little, has to show up on a second live reading — Codex has reported 0% used without refilling. A drop with no reset time on either side still counts on the first sample (Kimi). The reset *notification* follows this rule.

**Ribbons use that evidence on a week or a month by default.** A top-up pack never expires, and a credit allowance — personal or the team pool — is not one of those windows, so neither plays a ribbon. Spend, balance, a daily roll, a message allowance, and any kind added later are quiet too: `celebratesReset(includingFiveHour:)` answers `false` from `default`, so a new case does not fail the build and does not start throwing ribbons until somebody decides it should. (`Kind` is declared in this module, so `@unknown default` warns, and a warning fails CI.) Five-hour windows stay off unless **Also celebrate hourly quota resets** is on — they roll several times a day, and Codex's session clock used to throw ribbons when nothing the user would call a reset had happened. That clock is still refused by the jump-and-drop rule. The hourly switch is how Zhipu and Kimi's short quota (Zhipu's five-hour row reports no `resetsAt`, so a forty-point drop is the only evidence it can give) can play the same overlay. Both switches are off by default. `celebratesReset` is not a notification: no grant, no `UNUserNotificationCenter`, works in a `swift run` build. It names the account, and plays the system `Hero` sound with the ribbons (the same job CodexBar's fanfare does). It does **not** require a prior warning, and it is **not** hidden while "Warn at" is Off. The hourly row is hidden while the parent switch is Off; `celebratesHourlyReset` stays as it was stored. First sighting of a low figure is not a celebration. Two bars of the same account turning over together is one overlay, not two. Settings copy: [ui/settings.md](ui/settings.md).

**The announced step is cleared by that same evidence, not by any drop.** Clearing on a 5-point dip re-announced 95% → 89% → 93% (`oscillationDoesNotReAnnounce`). A reset is only announced for a window warned about on the way up, which is why the reset row is greyed out while the threshold is Off.

**A push route going quiet is never a failure.** Claude Code's status line writes only while a session runs, so its capture goes stale ten minutes after the last response; that means nobody used Claude Code. `UsageSource.reportsOnlyWhenUsed(for:)` is the flag; `AlertMemory` takes it as `staleMeansFailure`.

**A reading from an app's own saved state is spared too.** Devin's figures are written when its app launches, so stale means not relaunched. `UsageAlerts.staleMeansFailure(route:raw:for:)` spares `UsageRoute.appCache` (by the raw reading's recorded origin) as well as the push route. The *origin* is spared, not the provider: an `.endpoint` failure on Devin still counts.

**The push exemption belongs to the route, not the provider.** Of Claude Code's four routes only one is a push; `.endpoint` and `.desktopApp` ask a server every pass, and an **added** account has no status line. The exemption covers only the primary Claude Code account on `.automatic` or `.tooling` (conservatively, by configured route, since a capture remains eligible to answer). Neither exemption excuses an endpoint failure.

**`.stale` alone is not a failure** for the rest. `UsageCache.reconciled` returns a stale reading for a *successful* fetch too, when a newer banked reading beats a capture the status-line route still calls live.

**Classification uses the raw fetch, not the cached replacement.** A closed Antigravity's raw `.antigravityNotRunning` stays neutral however old its cached figures. A genuine failure behind the cache counts only after `stalenessBeforeSaying` (30 minutes). A raw live answer clears the streak even if reconciliation shows a newer cached reading. A service's own raw `.stale` is judged by age and the push-route exemption.

**Unavailable is not failed.** `AlertMemory.standing(of:)` exhaustively sorts results into:

- **Failure:** a credential that went bad, a request that did not get through.
- **Answered** (clears the failure streak and the reported-outage mark): complete answers without numbers — `grokBotNotIncluded`, `noLimitsReported`, `zaiNoCodingPlan` (a working key with no plan).
- **Neutral:** setup steps (`apiKeyMissing`, `notSignedIn`, `volcengineSignInRequired`, `kimiSignInRequired`, `kimiLoginExpired`, `qoderSessionMissing`), an app not running, and `systemProxyOff` (Pulse chose not to ask; [networking.md](networking.md#holding-back)). Ark CLI's generic sign-in response cannot tell never-configured from expired, so it is not evidence of an outage.

**Three failures, not one** — six minutes to an hour and a half at the 2–30 minute interval. These endpoints are undocumented; one dropped connection is not news. Reported once per outage: `reportedFailure` is cleared only by a working reading.

## Memory

`AlertMemory` is persisted to `alerts.json` in [`PulseStorage.directory`](../Sources/Pulse/Usage/ModelPrices.swift), keyed by account id, then window id — except `lowBalanceWarnedFor`, per account. It must be on disk, or every relaunch (Pulse starts at login) would re-announce everything over the line.

It is updated even when a grant was refused or the build is unbundled, so neither later announces a backlog. **An unresolved authorization is different:** readings are not consumed while authorization is unknown in a bundled app or a request is in flight; they stay eligible for the evaluation after a grant.

`AlertMemory.alerts(for:as:…)` is pure apart from `self`; the clock is passed in as `now`. Every rule here is covered by `AlertMemoryTests` ([testing.md](testing.md)); change one, change that.

`UsageAlerts.observe` returns immediately when `AppSettings.wantsUsageAlerts` is false **and** `celebratesReset` is false (`wantsAlerts` adds the outage and recap switches, for permission only), so nothing is tracked and no file is written for a feature nobody has switched on. Ribbons keep the same file: they need the previous fraction to know a reset happened. Without that guard the memory was written on the first pass of every launch — measured — and failures were counted up against accounts for nothing.

## Test notification

**Test notification → Send**, at the foot of the Notifications pane, posts one notification now (`UsageAlerts.sendTest`) so the reader can see that notifications reach them. It is the one notification about nothing Pulse saw — the reader asked for exactly that, and its text says it is a test. It asks for permission whatever is switched on (pressing the button is the request), is remembered nowhere, and uses the default sound. The row then says what came of it: sent (with where to look if no banner appeared: Focus, System Settings › Notifications), turned off for Blinky in System Settings, or not yet allowed (the prompt closed without an answer; pressing again asks again). Greyed out in an unbundled build.

## Permission, and the unbundled build

`UNUserNotificationCenter.current()` raises without an app bundle and kills the process. `swift run` builds a bare executable, so every entry point is guarded by `UsageAlerts.isSupported` (`Bundle.main.bundleIdentifier != nil`) and the Settings row says why the switches are dead. **Test notifications from `./Scripts/bundle.sh`, never from `swift run`.**

Permission is asked when a switch goes on in Settings, never at launch (a prompt for a feature nobody switched on gets denied for good). The update notice is separate: it asks when Notify first is left on, from About or from a scheduled find, and a refusal shows Sparkle's window. The request is awaited before reconsidering readings; concurrent changes share one in-flight request. Refreshes finishing while the prompt is open update the display but cannot mark warnings announced. A refused request triggers no reconsideration; the completion re-checks that alerts are still wanted. The update notice re-checks that Notify first is still the choice.

The delegate implements the completion-handler `willPresent` and requests banner, list and sound even while Settings is active; otherwise enabling a warning in Settings could consume it while macOS suppressed it. System notification and sound settings still apply. Tests verify authorization ordering and the delegate selector, not real banner delivery.

The subtitle reports `UNAuthorizationStatus`, not the switches, since a grant can be withdrawn later. **It is re-read every time the settings window opens** (`refreshAuthorization`); read once at launch, it showed alerts on while macOS discarded them.

## Clicking one

Opens the Settings window on the last-shown pane (except the recap notification, above, and the update notification, which opens Sparkle's update window). Not the account's own pane: the selection is `SettingsView`'s state, and threading it out is not worth it. Dismissing the update notification does not open that window.

The delegate uses the **completion-handler** spelling of `userNotificationCenter(_:didReceive:withCompletionHandler:)`. These are optional protocol requirements, so a mismatched signature compiles and is never called.
