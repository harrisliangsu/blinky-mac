# Docs

Maintained map. Change the topic file that owns a behaviour in the same patch as the code. [CLAUDE.md](../CLAUDE.md) is a short AI entry; [CONTRIBUTING.md](../CONTRIBUTING.md) is the human process.

The name on screen is **Blinky** (menu bar, Settings, About, update notes), and the bundled app is `Blinky.app`. The Swift module, the `Pulse` executable inside that bundle, the URL scheme `pulse`, and the bundle identifier `io.github.qunqin24.Pulse` stay as they are, so an existing install keeps its data and its updates. An in-app update replaces the app at its current path; the next time a copy still named `Pulse.app` opens, it renames itself to `Blinky.app` when that folder has no `Blinky.app` yet. The release scripts name the disk image and the update archive `Blinky-<version>.dmg` and `Blinky-<version>.zip`. This fork lives at [harrisliangsu/blinky-mac](https://github.com/harrisliangsu/blinky-mac). Upstream remains [qunqin24/Pulse](https://github.com/qunqin24/Pulse).

`Docs/` is the only docs tree. Investigation notes that are not “how it works now” live under [history/](history/) rather than being folded into current architecture.

## Start here

Topic docs, at the top of this folder. Subfolders are under [Folders](#folders).

| Doc | Owns |
|---|---|
| [features.md](features.md) | Every feature in full, the long form of the README's list (English) |
| [supported-services.md](supported-services.md) | The 76 providers and how each is read, and the Token spend sources, as the README used to list them (English) |
| [architecture.md](architecture.md) | App shell, settings state, first-run / offer-once, login item, defaults domain |
| [networking.md](networking.md) | System/manual proxy boundary, URLSession coverage, helper environment, Sparkle exception |
| [refresh-and-data.md](refresh-and-data.md) | Refresh loop, cache, connection diagnostics and server replies, activity, ledger, forecast, estimate, currency, chart hover |
| [token-spend.md](token-spend.md) | Token spend: the window beside the usage card, agents read, model drill-down, pricing, what may be said about the figures |
| [token-spend-sources.md](token-spend-sources.md) | The complete agent/source catalog: default macOS location, format, counters reported, evidence level |
| [recap.md](recap.md) | The shareable month and year recap cards: which cards a recap gets, nil means left out, language rules, the review render |
| [notifications.md](notifications.md) | When Pulse posts a notification, and what it refuses to say |
| [development.md](development.md) | Localization, resources, layout budgets, how to add UI |
| [testing.md](testing.md) | What `swift test` covers, fixtures, why the gaps are gaps |
| [json-output.md](json-output.md) | The `--json` contract for status lines and scripts |
| [integrations.md](integrations.md) | Raycast, tmux, sketchybar, shell prompt setup and account links |
| [extensions.md](extensions.md) | The extension contract: folder, manifest, how a program is run, what it prints |
| [window-starter.md](window-starter.md) | Starting Claude Code's and Codex's usage windows after a reset: the risk confirmation, when, and what is sent |
| [build-from-source.md](build-from-source.md) | Toolchain, `swift build`, `#Preview`, local run |
| [releasing.md](releasing.md) | Tag, bundle, Sparkle, DMG, CI |
| [update-mirror.md](update-mirror.md) | Upstream's update.qunqin.org mirror, which this fork does not read; this fork's feeds stay on harrisliangsu/blinky-mac |
| [ollama-cloud.md](ollama-cloud.md) | The current contract for Ollama Cloud: how usage is read from a signed-in page (no quota API); [providers/ollama-cloud.md](providers/ollama-cloud.md) only places it in the matrix |

## Folders

| Folder | Holds |
|---|---|
| [ui/](ui/README.md) | Panel geometry, input, rail menu, shortcuts, glass/rings, settings window |
| [providers/](providers/README.md) | Per-provider routes, auth, cookies, extra accounts, service status pages. Current routes and sign-in behaviour live here; do not duplicate them in architecture or UI docs |
| [setup/](setup/) | One page per provider, for users: where the key or login comes from and where it goes in Pulse. **Setup help** in the app opens these (`ConnectionRemedy.helpURL`), so a new provider needs one, and a changed settings label or failure message means updating its page. English only; no internals |
| [decisions/](decisions/README.md) | Why / failure lessons |
| [history/](history/) | Investigation notes and snapshots kept as evidence, not contracts; where one disagrees with a topic doc or the code, the doc and the code win. [grok-bot-usage.md](history/grok-bot-usage.md): the Grok Bot / Cursor “Sand” investigation. [entropy-audit.md](history/entropy-audit.md): 2026-09-26 snapshot of structural debt |
| [images/](images/) | Screenshots and animations used by the READMEs, [features.md](features.md), [token-spend.md](token-spend.md) and [ui/rings-and-surface.md](ui/rings-and-surface.md) |
| [icons/](icons/) | The provider and agent marks (SVG) drawn in the tables of [supported-services.md](supported-services.md); generated by `Scripts/readme-icons.py`, see [development.md](development.md) |

## Outside this folder

- Release notes: what each release changed. Chinese is [../CHANGELOG.zh-CN.md](../CHANGELOG.zh-CN.md); English is [../CHANGELOG.md](../CHANGELOG.md). Sparkle prefers the Chinese file; the GitHub page is Chinese first. How a release is cut: [releasing.md](releasing.md).
- [../README.md](../README.md) with [zh-CN](../README.zh-CN.md) / [zh-Hant](../README.zh-Hant.md) / [ja](../README.ja.md) / [ko](../README.ko.md) / [ru](../README.ru.md) — product pages. Keep all six in parity. They are not the architecture source of truth.
