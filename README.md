<!--
@name: 项目说明
@Descripttion: 介绍应用功能与开发使用方式。
@version: 1.0.0
@Author: sm
@Date: 2026-09-08 14:12:37
@LastEditTime: 2026-09-08 14:12:37
@FilePath: README.md
-->

# Codenotch

A macOS app that pins a small black notch to a screen edge, showing how much of
each coding assistant's usage limit you have burned — and whether it is still
working, done, or waiting on you.

![Collapsed notch with hover tooltip](docs/design/frame-124-hover-tooltip.png)

Hover a ring for its limit windows and when they reset. By default, Claude's ring shows the
same **current session** window Claude Code's own `/usage` leads with, so the
two never disagree.

## What it reads

| Provider | Source | How |
|---|---|---|
| **Claude Code** | official | The OAuth token in the login keychain, against the same endpoint Claude Code's own `/usage` uses. |
| **Cursor** | official | The editor's own signed-in session, read from its local SQLite state — no separate sign-in. |
| **Codex** | official | ChatGPT's usage endpoint, using the local Codex sign-in. Shows the 5-hour and weekly limits when available. |
| **Antigravity** | official where licensed, otherwise a request count | Antigravity's local language server first, then Google's quota endpoint; a plain count when neither will answer for the account. |
| **GLM** | official | Z.ai's Coding Plan monitor endpoint, with a key borrowed from whichever coding tool already holds one — Claude Code's `settings.json`, ZCode, or OpenCode. |
| **Grok** | official | The Grok CLI session in `~/.grok/auth.json`, against the same credits billing endpoint `/usage` uses. |
| **OpenCode** | official | The Go plan's official usage endpoint, with the `opencode-go` key OpenCode itself stores on sign-in. |

Codenotch supports automatic credentials from local tools and independent manual
credentials. Settings → Providers lets you add multiple accounts for the same
provider, choose a brand/system/image icon, edit, reorder, disable or delete a query.
Existing providers and their enabled states migrate on first launch. Deleted
entries stay deleted; new local profiles can be added from the editor.

Manual queries accept the credential required by the selected endpoint: for
example, Claude's OAuth access token, Cursor's Cookie, or a GLM API key. Manual
mode never falls back to another account on this Mac. Credentials are stored in
Codenotch's own macOS Keychain entries. Disabling a provider stops queries and
forgets readings; deleting it also removes its saved credentials and icon.

### Query templates

Choose a built-in query, an official balance template (DeepSeek, StepFun,
SiliconFlow, OpenRouter, Novita), NewAPI, Sub2API, GLM/Kimi/MiniMax Token Plan,
or custom JavaScript. Templates are editable. **Test query** previews results
before saving, and **Primary metric** selects the value shown beside the icon.
Other metrics and reset times appear on hover. Balances without a total are
shown as amounts, without inventing a percentage; unlimited quotas are distinct
from zero balances. Long provider lists and quota details can be scrolled.

Each entry has active and idle refresh intervals in **seconds**, defaulting to
60 and 300. Activity uses the app's existing local session signal; manual
accounts do not inherit local account sessions. Automatic refresh can be turned
off independently. Rate-limit responses defer retries, and failures mark the
last successful reading stale. Changing credentials or the query clears it.

Scripts return `{ request, extractor }`, matching Code Switch R's query shape:

```js
({
  request: {
    url: baseUrl + '/user/balance',
    method: 'GET',
    headers: { Authorization: 'Bearer ' + apiKey }
  },
  extractor: response => ({
    key: 'balance', label: 'Balance', remaining: response.balance, unit: 'USD'
  })
})
```

Available variables are `baseUrl`, `apiKey`, `accessToken`, `cookie`, `accountId`
and `userId`, also accessible through `variables`. Legacy quoted placeholders
such as `'Bearer {{apiKey}}'` are supported. Store secrets in credential fields
rather than embedding them in scripts. The extractor may return one item or an
array of up to 64, with unique `key`, `label`, `used`, `total`, `remaining`,
`unit`, `unlimited`, `nextReset` (ISO 8601), and `isValid` fields. A progress ring
requires a positive total and enough data to calculate used quota.

Scripts run in a separate JavaScriptCore helper process with no exposed file or
command APIs. Codenotch performs the HTTP request using an isolated session;
redirects are rejected and responses are limited to 2 MB. The configured timeout
limits the whole query, including the HTTP request and script execution; reaching
it cancels the request and terminates the script. Automatic and manual built-in
queries also use this deadline, although a provider may fail earlier under its
own network timeout. Query templates depend on provider endpoints and may need
updating when a provider changes its response. Saved scripts are preserved when
templates change; selecting another query method and then the desired template
loads its latest code.

It also answers **"is it still working?"** — a thin arc spins inside a
provider's ring while a session is busy, and becomes a pulsing amber ring when
one is blocked waiting on you. Hover for every live session by name, where it
is running, and what it wants.

Two Claude Code logins can have separate rings. A work profile created with
`CLAUDE_CONFIG_DIR=~/.claude-work claude` can be selected under **Add provider →
Automatic → Local provider**, with its own limits and sessions.
Available `~/.claude-<slug>` directories are discovered at launch. The initial
list places the default first and the other profiles alphabetically; subsequent
ordering follows your saved provider list.

## Placement

Right-click the notch and choose **Edit position** to drag it along any of the
four edges or onto another display. Release to save; press Escape to cancel.
The position survives relaunches. A disconnected display temporarily falls back
to the main display and restores when reconnected, unless you save a new position.
Changing the edge in Settings centres the notch on that edge of the selected display.
On a Mac with a hardware notch, dragging near the top centre snaps into it;
other top positions stay below the menu bar.

The notch lives on any of the four screen edges. Right and left keep a
vertical column; top and bottom lay the readings out side by side. It pins
itself to the *usable* edge, so a bottom notch rests on the Dock and follows
when the Dock hides or moves. On a Mac with a hardware notch, the top
placement takes its exact shape, so the two read as one rather than as a bar
parked underneath it.

At rest it is a small pill on the screen edge that unfolds when the pointer
reaches it — configurable in Settings to always show, or to hide entirely.
Settings live in an orb below the notch: an arc at rest, a gear on hover.

The app itself can show a Dock icon, a menu bar icon, or neither.

## Updates

Codenotch updates itself. [Sparkle](https://sparkle-project.org) checks daily
and installs in the background without prompting; Settings says so and can
switch it off. Every update is EdDSA-signed, so nothing installs that wasn't
built and signed by the maintainer.

## Building

```sh
brew install xcodegen   # once
make run                # generate, build, launch a Debug build
make test               # unit tests
```

No signing identity is required for either. `make release` — which archives,
notarizes, and produces a signed auto-update feed — needs a Developer ID
certificate and an App Store Connect notary profile, and is only ever run by
the maintainer to cut an official release. See
[CONTRIBUTING.md](CONTRIBUTING.md).

Run with `CODENOTCH_DEMO=1` to see fixed sample data instead of live readings.

## Architecture

Every provider implements `UsageProvider` (`Sources/Providers/`) and declares
its own `Fidelity` — `.official`, `.derived`, or `.manual` — so the UI never
presents a guess as if a vendor had published it. `UsageStore`
(`Sources/Model/`) polls them on a timer, keeps the last good reading across
launches, and degrades every failure to a visible status rather than a
made-up percentage.

The notch itself works in one-dimensional **stack space** (`along`/`across`)
regardless of which screen edge it's on; `NotchPlacement` is the only place
that maps that back onto real screen coordinates. `NotchLayout` holds every
measurement, quoted from `docs/design/frame-124-hover-tooltip.png` so the
layout can be checked against the design frame directly.

- Design spec: [`docs/specs/2026-08-28-usage-notch-design.md`](docs/specs/2026-08-28-usage-notch-design.md)
- Implementation history: [`TASKS.md`](TASKS.md)

## The honest caveat

No vendor publishes a clean "your session limit is N% used" API for any of
these tools. Each adapter reads whatever the owning app itself reads from —
an internal endpoint, a local database, a language server's own RPC — and
those can change without notice. Every adapter's response shape is pinned by
tests, and every failure degrades to a visible status (`stale`, `needsAuth`,
`error`) rather than an invented number.

**Keychain:** the app is signed with a stable Developer ID identity so the
one-time "Always Allow" grant on Claude Code's and Antigravity's keychain
items survives rebuilds. The secret itself is read only when the owning app
has actually changed it — checked via the item's modification date, which
isn't behind the same access prompt as the credential — so a valid grant does
not mean a prompt on every poll.

**Rate limits:** Claude's endpoint returns 429 if polled too hard, with an
unhelpful `Retry-After: 0`. The back-off treats that as a floor-raiser only —
60s, doubling per consecutive 429, capped at 15 minutes — and the deadline is
persisted, so relaunching during a penalty waits instead of spending an
attempt on it. Polling drops to every 5 minutes when nothing is running, and
right-clicking the notch offers **Refresh now**.

**Logs:** the app has no window, so anything worth diagnosing goes to the
unified log.

```sh
/usr/bin/log stream --predicate 'subsystem == "com.vinz.codenotch"' --level debug
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
