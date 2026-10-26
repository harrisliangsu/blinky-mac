# Grok

Service: [`GrokUsageService.swift`](../../Sources/Pulse/Providers/GrokUsageService.swift). Extra accounts: [authentication.md](authentication.md).

This is the **account’s** weekly SuperGrok / xAI pool, not “Grok Build the CLI”. Grok Bot is a different bill: [grok-bot.md](grok-bot.md).

Extra accounts are supported. `keepsLocalTranscripts` is false. The primary account chooses a route (`UsageSource`, Automatic by default). An added account is not shown that row.

Issue history: [Pulse #9](https://github.com/qunqin24/Pulse/issues/9).

## Why the ring is called Grok

Since June 2026 a paid plan spends **one weekly pool** across every Grok product — web chat, Imagine, voice, the API, and the CLI. The reply’s `productUsage` lists `GrokChat` beside `GrokTasks`. There is no CLI-specific figure to show. Naming the ring after the CLI would claim one. The breakdown is **not** drawn as separate windows: they are shares of one limit.

## Primary credential

Same two billing endpoints, two logins. Default is `.automatic`.

1. **Grok Build’s CLI.** The OIDC access token in `~/.grok/auth.json`, when one is still usable. The file is only read. Its refresh token is not copied, and Pulse does not write the file, so a renewal cannot sign the CLI out.
2. **Blinky’s own login**, when that token is missing, every entry has expired, or the proxy answers 401 or 403. One device-code sign-in in Settings (Accounts → Grok account) stores it in `accounts.dat` under the primary `grok` key — the same RFC 8628 flow an added account already uses. Pulse refreshes that login with `OAuthLogin.refresh`. It does not read or write the CLI’s refresh token.
3. **No Blinky login yet.** The card says to sign in once in Settings (`.grokAccountSignInRequired`). A Blinky login that will no longer refresh, or that the proxy refuses, says to sign in again (`.grokAccountLoginExpired`).

Pinned `.endpoint` is the CLI only. A missing file is still `.grokSignInRequired` and an aged-out or refused token is still `.grokLoginExpired`: the instruction is to run `grok`, and the route does not fall through. `.signInRequired` names Codex — do not reuse it here. Pinned `.tooling` never opens `~/.grok/auth.json`.

A network failure, a rate limit, or a reply that will not parse is reported as itself. Those are not a reason to try the other login.

- `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits` for the figures, with header `x-xai-token-auth: xai-grok-cli`.
- `GET https://cli-chat-proxy.grok.com/v1/settings` for the plan name (`subscription_tier_display`, e.g. “SuperGrok”).

Neither endpoint is a public documented usage API. They are what the CLI itself calls and can change without notice. They are not the public xAI API, and the ring is not that API’s credit balance.

The CLI’s stored access token lasts about six hours. The CLI renews it while you use Grok. Blinky’s login is what keeps the primary ring up after that.

## The header selects the shape of the reply

Without `x-xai-token-auth: xai-grok-cli` the same path answers the **enterprise credit form** instead — `monthlyLimit`, `onDemandCap`, a history of billing cycles — which on a personal plan is zeroes throughout. A denominator of nothing is not a reading. **Historical:** it took a while to notice that the empty answer was the wrong *question*.

## Absent percentage is zero — inside a running period

The payload is proto3 serialised to JSON with **implicit** presence, so zeroes are simply absent. Visible in the same reply: `GrokChat` carries a product name and no `usagePercent` while `GrokTasks` carries one. Treating a missing figure as “no reading” would blank the ring for the first hours of every week.

It is only read as zero **inside a period that is currently running**. A reply describing a period that has already ended says nothing about the one that followed it.

This is the **opposite** of Grok Bot’s `usagePercent` rule (explicit presence there; absent means unset). See [grok-bot.md](grok-bot.md).

**At or past 100% the pool is spent** (`isExhausted`), the same as Grok Bot and every provider that reports a percentage: it is Grok's own figure saying the pool is gone. Until 1.5.2 it was left unmarked, so the ring filled but no "spent" notification or card state followed; the parsing tests caught it.

## Window length

Measured from the period’s own two timestamps (`currentPeriod` start and end), not from a `type` string. `reportsLength` is true. **Historical evidence, one account:** exactly 604,800 seconds. The `USAGE_PERIOD_TYPE_WEEKLY` enum is theirs to rename; the subtraction is not.

## Plan and balance

Settings call is on a shorter budget than usage — figures are already in hand. Only `subscription_tier_display` is read; the same reply carries subagent and planner settings, no use to Pulse.

`prepaidBalance` and `onDemandCap` are denominated in a unit the reply never names, and the cap is an allowance rather than a balance, so `creditBalance` stays nil.

## Added accounts

Same two endpoints with the token Pulse holds. Never looks at `~/.grok/auth.json`, and never uses the primary account’s Blinky login. Device-code OAuth, scopes `openid email offline_access grok-cli:access`. `billing:read` is **not allowed for this client** — not a missing scope Pulse forgot. Details: [authentication.md](authentication.md). The primary fallback is that same sign-in, written onto the primary key instead of a new ring.

## First run

Presence of `~/.grok` marks the chooser row as detected, without opening its auth file. New support is suggested once on upgrade if detected, never enabled automatically.
