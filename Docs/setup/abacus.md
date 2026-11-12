# Set up Abacus AI in Blinky

Blinky shows your Abacus AI (ChatLLM / RouteLLM) compute credits: used out of your plan's total, with your next billing date as the reset.

## What you need

An Abacus AI subscription, signed in to a browser at [apps.abacus.ai](https://apps.abacus.ai).

## Steps

1. Sign in at [apps.abacus.ai](https://apps.abacus.ai) in your browser.
2. In Blinky: **Settings → Abacus AI**. Turn on **Show in panel**.
3. Under **Read from browser**, pick the browser you signed in with (or leave it on Default browser) and click **Read**.
   - Chrome, Edge, Brave, Arc, Vivaldi and ego lite: macOS asks once for keychain permission.
   - Safari: give Blinky Full Disk Access first, in System Settings → Privacy & Security.
   - Firefox: nothing extra.
4. Within a few seconds the ring appears. Its card shows "Credit allowance" and, when Abacus reports it, your next billing date and plan.

## If it doesn't work

| Blinky says | What to do |
|---|---|
| Read a browser session in Settings. | Click **Read** under **Read from browser**. |
| No session found. Sign in at abacus.ai first. | The browser picked has no Abacus session Blinky recognizes. Sign in, or pick the browser you use Abacus in. |
| The browser session expired. Sign in on the website, then read it again in Settings. | Sign in to Abacus AI again, then click **Read** again. |
| No limits reported. | Abacus reports no credit total for this account. |
| The service didn't respond. / Checking too often — easing off. / The service returned an error. | A temporary network or server problem. Wait a moment and try again. |
| Couldn't read the reply. | Abacus sent something Blinky doesn't recognize. These are Abacus's own web endpoints and may change. |

## What Blinky reads

Blinky keeps only Abacus's session cookies from your browser, stores them encrypted on this Mac, and sends them only to `apps.abacus.ai`, asking the same two things its own pages ask: your compute credits, and your billing date and plan.
