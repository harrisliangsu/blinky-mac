# Set up Antigravity in Blinky

Blinky shows Antigravity's quota buckets — a 5-hour and a weekly limit for Gemini models, and the same pair for Claude/GPT models — plus your plan name.

## What you need

Antigravity (the desktop app or the standalone IDE), installed and signed in, or the `agy` command signed in on this Mac. There is no key to paste in advance.

## Steps

1. Download Antigravity from https://antigravity.google/download, install it, open it, and sign in.
2. In Blinky, go to Settings → Antigravity and turn on "Show in panel". While Antigravity is open, Blinky talks to its own local server. There is nothing to paste for that. If you want separate rings for your Gemini allowance and your Claude/GPT allowance instead of one combined ring, turn on "A ring for each model group" in the same pane.
3. If you use the `agy` command instead of the app, and it is not signed in yet, stay in Settings → Antigravity and press Sign in. Blinky opens one Google page. When that page shows a code, paste it into the field under Sign in and press Continue. A second Sign in while that page is open does not open another one.
4. Success looks like a ring for Antigravity on the Blinky panel while Antigravity is open, or after the `agy` sign-in has finished. It shows no reading while Antigravity is closed and `agy` is not signed in — that is expected, not a fault.

Antigravity does not support adding a second account in Blinky.

## If it doesn't work

| Message Blinky shows | What to do |
|---|---|
| Open Antigravity to see its usage. | Open Antigravity (the app or the IDE) and sign in. |
| Sign in to Antigravity in Settings. The page shows a code; paste it there. | Press Sign in under Settings → Antigravity. Paste the code the page shows, then press Continue. |
| Antigravity isn't available for this Google account's region. | Antigravity does not serve that account's region. Blinky will not open the sign-in page again for a while. |
| Antigravity is open but didn't answer. Restarting it usually helps. | Quit and reopen Antigravity, then click Retry. |
| No limits reported. | Refresh again once Antigravity has fully started; if it persists, confirm your account has an active plan in Antigravity itself. |

## What Blinky reads

While Antigravity is running, Blinky asks its local language-server process — over this Mac's own loopback address, not the internet — for your quota summary, using a connection token that process generated for this run only. Blinky does not keep a copy of the Google login. When the app is closed, Blinky can ask the `agy` command for the same figures, using the login that command saved.
