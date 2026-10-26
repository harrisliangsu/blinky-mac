# Set up Grok in Blinky

Blinky shows your account's weekly Grok pool — the single allowance a SuperGrok or X Premium+ plan spends across Grok chat, Imagine, voice, the API, and Grok Build (the coding CLI). This is not the same as Grok Bot, which is a separate allowance billed through Cursor — see [Grok Bot setup](grok-bot.md) for that.

## What you need

A SuperGrok, SuperGrok Plus, SuperGrok Heavy, or X Premium+ subscription. If the Grok Build CLI is already signed in on this Mac, that is enough. If it is not, or its saved login has expired, sign in once in Blinky's settings. Blinky then keeps that login and renews it.

## Steps

1. Install Grok Build if you haven't already: `curl -fsSL https://x.ai/cli/install.sh | bash` (or `npm install -g @xai-official/grok`).
2. Run `grok login` in Terminal. It opens your browser to sign in with your xAI/X account, then stores the login at `~/.grok/auth.json`.
3. In Blinky, go to Settings → Grok and turn on "Show in panel". There is nothing to paste. "Read usage from" is Automatic: Blinky uses the CLI's login while it is still good, then a login Blinky holds.
4. Refresh Blinky (or wait for its next automatic check). A ring for Grok fills in on the Blinky panel with your weekly usage.

The CLI's saved login lasts about six hours unless you use Grok, which renews it. When that login is missing, expired, or refused, Blinky uses its own. The first time, the card says to sign in once in Settings.

### Sign in once in Settings

Go to Settings → Grok → Accounts, and click "Sign in…" on the Grok account row (not "Add another account"). Blinky shows a code and opens xAI's sign-in page. Sign in there and approve the code. Blinky stores that login on this Mac and renews it. It does not change `~/.grok/auth.json` or sign you out of the CLI.

If "Read usage from" is set to "CLI login", Blinky does not use this sign-in. Automatic and "Blinky login" do.

### Adding another Grok account

If you use more than one Grok account, go to Settings → Grok, and click "Add another account" in its Accounts group, then "Sign in…". Blinky shows a code and opens xAI's sign-in page — sign in there and approve the code. This is a separate login Blinky keeps for itself; it doesn't touch `~/.grok/auth.json` or your CLI session.

## If it doesn't work

| Message Blinky shows | What to do |
|---|---|
| Sign in to Grok once in Settings to see usage. | Settings → Grok → Accounts → Sign in… on the Grok account row. Approve the code on xAI's page. Blinky keeps that login. |
| Blinky's Grok login expired. Sign in again in Settings. | The same Sign in… button. Running `grok` renews the CLI's own login, which is a separate one. |
| Sign in to Grok to see usage. | "Read usage from" is set to CLI login, and the CLI has never signed in here. Blinky copies the command `grok` — run it in Terminal. If you're not signed in yet, it opens your browser to log in (or run `grok login` directly). |
| Grok's saved login expired. Use Grok to renew it. | "Read usage from" is set to CLI login, and that saved login has expired or was refused. Run `grok` (or `grok login`) again in Terminal. Switch "Read usage from" to Automatic if you would rather sign in once in Settings. |
| Sign in to this account again in Settings. (added accounts) | Click "Sign in again…" next to that account. |
| The service didn't respond. | Click Retry. |
| Checking too often — easing off. | Click Retry after a minute. |
| The service returned an error. | Click Retry. |
| Couldn't read the reply. | The provider's reply changed shape. Try again later; if it keeps happening, [report it](https://github.com/harrisliangsu/blinky-mac/issues). |
| No limits reported. | Your account reported no usage windows. Check that your plan is active. |

## What Blinky reads

For your main account, Blinky prefers the login the Grok Build CLI already saved at `~/.grok/auth.json`. It does not store a copy of that file, and it does not write to it. When that login is missing, expired, or refused, Blinky uses the sign-in it holds from Settings and renews that one. For any extra accounts you add, Blinky keeps a separate sign-in, encrypted on this Mac, and does not read the CLI's file. The weekly figure is the account's SuperGrok pool from the CLI's billing endpoint, not usage of an xAI API key.
