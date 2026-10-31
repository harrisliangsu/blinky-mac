# Set up DimAgent in Blinky

Blinky shows the subscription DimAgent reports through its own CLI: plan credits, any add-on packs, token windows, and the web-search allowance, each as DimAgent states them.

## What you need

- The Dim CLI, `dim`, installed and signed in on this Mac (`dim auth login`). Blinky runs `dim usage --json`. It does not ask for a key, a cookie, or a password, and it does not read the CLI's credential files.

## Steps

1. Install the Dim CLI and sign in with `dim auth login`. Check that `dim usage --json` works in Terminal.
2. In Blinky: **Settings → DimAgent**. Turn on **Show in panel**. There is nothing to paste.
3. Within a few seconds the ring appears. The card lists plan credits, reported token windows, and the web-search allowance separately. Add-on packs appear on their own rows when DimAgent reports them.

A full token window can pause consumption even when plan credits remain. The reset time on that row is the one DimAgent reports. Credit expiry is an expiry, not a renewal Blinky invents. Credits are not a cash balance, and local token logs are not used to estimate this subscription.

## If it doesn't work

| Blinky says | What to do |
|---|---|
| Nothing saved on this Mac yet. Open the service's app once, then retry. | Blinky can't find `dim`. Install it, including the mise shim at `~/.local/share/mise/shims` when that is how `dim` is installed, then refresh. |
| Sign in with this service's own app or command-line tool first. | Run `dim auth login`, confirm `dim usage --json` works, then refresh. |
| The saved login has expired. Sign in again with the service's own app or tool. | Sign in again with `dim auth login`, then refresh. The previous quota is not shown in place of a signed-out account. |
| No limits reported. | `dim` answered without a plan, add-on, token window, or web-search allowance Blinky could read. |
| Couldn't read the reply. | `dim` printed something Blinky doesn't recognize. Update the CLI and try `dim usage --json` in Terminal. |
| The service didn't respond. | `dim` took longer than 20 seconds, or the connection failed. The last reading stays, dated. Try again later. |
| Checking too often — easing off. | DimAgent asked Blinky to wait. The next check is later on its own. |

## What Blinky reads

Blinky runs `dim usage --json` with the login `dim` already saved. The command runs in a temporary directory, with empty input, a 20-second limit, and no API keys from Blinky's own environment. Its `PATH` includes the mise shims so an application opened from the Finder can still find a mise-managed `dim`.
