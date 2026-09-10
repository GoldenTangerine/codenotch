<!--
@name: 项目说明
@Descripttion: 介绍应用功能与开发使用方式。
@version: 1.0.0
@Author: sm
@Date: 2026-09-08 14:12:37
@LastEditTime: 2026-09-08 14:12:37
@FilePath: README.md
-->
<div align="center">

# Codenotch

[![Release](https://github.com/GoldenTangerine/codenotch/actions/workflows/release.yml/badge.svg)](https://github.com/GoldenTangerine/codenotch/actions/workflows/release.yml)
![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-black)
![Swift](https://img.shields.io/badge/swift-5-orange)
![License](https://img.shields.io/badge/license-MIT-green)

**A macOS app that pins a small black notch to a screen edge, showing how much
of each coding assistant's usage limit you have burned — and whether it is
still working, done, or waiting on you.**

![Collapsed notch with hover tooltip](docs/design/frame-124-hover-tooltip.png)

</div>

Hover a ring for its limit windows and when they reset. By default, Claude's ring shows the
same **current session** window Claude Code's own `/usage` leads with, so the
two never disagree.

In **Settings → Appearance → Tooltip height**, choose **Show all** to expand
provider details to their content, including every session and available statistic.
The bubble scrolls only when its content exceeds the current screen's usable
height. **Default** preserves the existing compact layout.

## Windows

A Windows port — Rust/Tauri 2, same design and providers — lives in [`windows/`](windows/README.md).

## What it reads

### Code Switch R integration

Linked quotas show inactive periods explicitly. Brand icons are bundled offline
from `@lobehub/icons-static-svg` 1.73.0 (MIT; license in
`Sources/CodeSwitchIcons.bundle/LICENSE.txt`), using the same color aliases as
Code Switch R. The PNG resources total about 1.7 MB and require no network access.

With a compatible Code Switch R running on the same Mac, Codenotch automatically
appends its current tray suppliers after your existing providers. Active requests
select the active suppliers; idle platforms show their default supplier. Hover a
ring for quota, balance, reset time, calling status and daily statistics. Disable
this in Settings with **Code Switch R integration**.

The integration reads only `~/Library/Caches/code-switch/tray-snapshot-v1.json`.
It does not read Code Switch R credentials or query suppliers itself. Supplier
changes normally appear within one second; quota and statistics refresh every
60 seconds in Code Switch R, including while its tray is closed. Normal exit
removes the linked providers; a heartbeat older than three seconds also hides
them. They return automatically when Code Switch R reconnects. Both applications
must include this integration; older installed versions do not publish snapshots.

With the activity integration on both sides, Claude Code and Codex CLI hooks
can also attach a live session to the supplier that actually handled its latest
request. The optional `sessionBindings` field in each platform snapshot uses
SHA-256 of `<tool>\n<trimmed session id>` (lowercase hex), plus supplier identity,
icon, a monotonically increasing route sequence and a millisecond timestamp.
Code Switch R records this independently of session affinity, including fallback
attempts, and retains at most 4,096 recent associations for 24 hours. It exports
no prompts, tool arguments or credentials. Claude native subagent routes are
excluded when their agent-id header identifies them, so they cannot move their
parent's indicator.

Waiting sessions keep their supplier visible after requests settle, with the
last available quota reading. When an association cannot be established, or the
bridge disconnects, the session appears under its CLI tool instead. The same
fallback applies until an association is newer than the current submitted turn;
an old route is never inherited by a new turn, and an unknown turn start is not
used to guess a supplier. The same
event is announced once even if its supplier changes. Older snapshots keep the
existing request spinner without guessing which supplier a question belongs to.

### Local providers

| Provider | Source | How |
|---|---|---|
| **Claude Code** | official | Claude Code's own `/usage`, asked of the installed `claude`. Falls back to the OAuth token in the login keychain, against the endpoint that command uses, when Claude Code isn't installed. |
| **Cursor** | official | The editor's signed-in session in its local SQLite state, or the `cursor-agent` login in the keychain — no separate sign-in. |
| **Codex** | official | ChatGPT's usage endpoint, using the local Codex sign-in. Shows the 5-hour and weekly limits when available. |
| **Antigravity** | official where licensed, otherwise a request count | Antigravity's local language server first, then Google's quota endpoint; a plain count when neither will answer for the account. |
| **GLM** | official | Z.ai's Coding Plan monitor endpoint, with a key borrowed from whichever coding tool already holds one — Claude Code's `settings.json`, ZCode, or OpenCode. |
| **Grok** | official | The Grok CLI session in `~/.grok/auth.json`, against the same credits billing endpoint `/usage` uses. |
| **OpenCode** | official | The Go plan's official usage endpoint, with the `opencode-go` key OpenCode itself stores on sign-in. |
| **GitHub Copilot** | official | GitHub's Copilot quota endpoint, authenticated with the GitHub CLI session already on the Mac (`gh auth login`). |
| **Gemini API** | local token usage | Token usage from Gemini CLI, OpenCode and Hermes, with an optional monthly token budget in Settings. |

Codenotch supports automatic credentials from local tools and independent manual
credentials. Settings → Accounts lets you add multiple accounts for the same
provider, choose a brand/system/image icon, edit, reorder, disable or delete a query.
Existing providers and their enabled states migrate on first launch. Deleted
entries stay deleted; new local profiles can be added from the editor.
Existing configurations can add GitHub Copilot or Gemini API through
**Add provider → Automatic → Local provider**. Drag a provider's handle to
reorder it.

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

Settings lists the connected providers in the order the notch draws them, and
you can drag one by its handle to move it. The order is remembered across
launches. A provider you switch back on joins the end of that list rather than
reclaiming an older position, so nothing you cannot currently see jumps ahead
of something you placed deliberately.

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

## Session notifications

For **Claude Code and Codex CLI**, open **Settings → Notifications → Hooks**
and install the integration separately for each configuration directory. Existing
third-party hooks and other JSON settings are preserved. Repair updates only
Codenotch entries; uninstall removes only those entries. Additional profile
directories can be selected there. No CLI configuration is changed at launch.
Uninstall also clears that directory's activity immediately and ignores hooks
still emitted by an already running CLI until the integration is installed again.

After installation, start a new CLI session. **Codex additionally requires you
to open `/hooks` and review/trust the Codenotch definitions**; changed definitions
need review again. See the [official Codex hooks documentation](https://developers.openai.com/codex/hooks).
The installed indicator and last received event are separate: installation alone
does not prove that a CLI has loaded or trusted the hooks. Use a current CLI
version that supports the configured lifecycle events; older versions without
hooks retain only their existing monitoring capabilities.

Hooks report a submitted turn, question-tool calls, approval requests and an
explicit turn stop. Questions are recognized as tool events, not inferred from
punctuation in an ordinary reply. The helper sends bounded metadata over a
private local Unix datagram socket and exits without approving, denying or
answering anything. Codenotch does not need to be running for the CLI to proceed.
The helper briefly retries a full socket queue. Codex approvals without call IDs
are reconciled against in-flight calls of the same tool; ambiguous parallel calls
retain the waiting mark until all candidate calls finish.
Return to the original application to answer or approve; the panel does not
offer remote approval controls.

While running, the existing spinner is unchanged. A waiting session adds an
amber breathing ring and question-mark badge while retaining the supplier logo,
on the top notch and either screen edge. Reduced Motion keeps the waiting mark
static. Waiting takes priority if another session on the same supplier is still
working. Hover for sessions and click a row to activate its application; overflow
rows remain available from the “and N more” menu. A temporary activity-only entry
is removed shortly after completion, while a waiting entry stays visible.

Claude's local session records remain a fallback, merged with hook events by
process. A newer explicit Claude status can replace a missed hook transition.
Codex's older log-write heuristic remains a running-only fallback:
silence in the log is never treated as a completed turn. Desktop applications,
IDE extensions and other CLI tools retain their previous monitoring paths.

With Claude Code or Codex CLI hooks installed, submitting a message opens the
notch for five seconds. In **Settings → Notifications → When a turn starts**,
switch this off or choose 3, 5 or 10 seconds independently of completion alerts.
Start sounds default to off, with `8bit_start` selected when enabled. Opening a
CLI session, running tools or resuming after approval does not trigger this alert;
desktop apps and activity monitoring without hooks do not infer turn starts.

The notch also opens itself for five seconds when an agent stops working, or stops
to ask you something, and sounds the system alert. Clicking it while it is open
brings that session's application to the front.

The app, not the tab. A session publishes its pid and nothing else — no window,
no tab, no tty — so the app is found by walking up the process tree from the
agent to whatever launched it. Choosing the *tab* inside that app needs the
terminal's own scripting interface, and there is no general one: Terminal.app
and iTerm2 can match a tab by tty, Warp and Ghostty publish no scripting
dictionary at all. So the app is raised for everybody and the tooltip names the
session, which leaves the last hop one keystroke rather than working for two
terminals and silently doing nothing in a third.

Both halves switch off separately in Settings, because they fail differently:
the peek is no use behind a full-screen window, and the sound is no use in a
meeting. Started, finished and waiting events each have their own sound choice
and preview button. All three share a volume control with a continuous slider
and percentage display; previews remain available with notification sounds off.
The six bundled CodeIsland `8bit_*.wav` sounds are available in every sound picker,
alongside macOS and user-installed sounds, without requiring CodeIsland at runtime.

The sound is played as a file on the ordinary output rather than handed to
`NSSound` as a system alert. A system alert goes through the interface
sound-effects channel, which System Settings → Sound can switch off — and on a
Mac where it is off, `NSSound.play()` reports success and nothing is heard.

Only *leaving* busy counts. A question being answered is not a piece of work
ending, and a session whose file disappears mid-turn — which is what quitting
Claude Code looks like — is not announced at all, since there is no window left
to jump to. Nothing is announced from the first reading either: every session
already running at launch arrives with no history, and treating that as a
transition would ring once per open window on every start.

That transition rule applies to the fallback monitors. A fresh, explicit hook
turn submission or request for input is announced even if it is the first event seen for that
session. Hook cancellations and process exits are silent; replayed notifications
are deduplicated. Several events arriving together produce one sound and peek,
with waiting taking priority over finished, then started. Disabled and outdated
events are skipped before choosing an announcement.
After a waiting alert is displayed or sounded, new start alerts are suppressed
for its configured duration, or until that wait is resolved. Suppressed starts
are not replayed later; completion and new waiting alerts remain available.
When a submission omits its turn ID, later tool events can supply it without
discarding the start alert or resetting the turn's activity.

## Alerts

A provider's headline limit crossing **80%** — and reaching **100%** —
becomes a system notification: once per crossing, never repeated while it
stays crossed, and again only after the window has genuinely rolled over.
Each provider can be muted from its own row in Settings, and macOS permission
is asked on the first real alert rather than at launch.

## Placement

Right-click the notch and choose **Edit position** to drag it along any of the
four edges or onto another display. Release to save; press Escape to cancel.
The position survives relaunches. A disconnected display temporarily falls back
to the main display and restores when reconnected, unless you save a new position.
Changing the edge in Settings centres the notch on that edge of the selected display.
On a Mac with a hardware notch, dragging near the top centre snaps into it;
other top positions stay below the menu bar.

Settings → Appearance can show the notch on one display or every display.
Each display expands independently; the chosen edge and relative drag position
are shared. In single-display mode, choose a named display or follow the active
window. Option-drag also nudges the notch along its current edge.

The notch lives on any of the four screen edges. Right and left keep a
vertical column; top and bottom lay the readings out side by side. It pins
itself to the *usable* edge, so a bottom notch rests on the Dock and follows
when the Dock hides or moves. On a Mac with a hardware notch, the top
placement takes its exact shape, so the two read as one rather than as a bar
parked underneath it.

At rest it is a small pill on the screen edge that unfolds when the pointer
reaches it — configurable in Settings to always show, or to hide entirely.
Settings live in an orb below the notch: an arc at rest, a gear on hover.

In Settings → Appearance → Reset time, choose **Time remaining** for countdowns
like "Resets in 3 Days 3h". **Reset date** keeps the reset date and time, with
minutes shown when less than an hour remains.

Appearance has separate **Interface accent color** and **Notch accent color**
choices. The interface colour applies to Settings and What's New; the notch
colour applies to rings and detail cards on every display. Each choice is saved
independently and takes effect immediately. Both default to the device accent;
fixed presets are available for pink, red, orange, yellow, green, teal, blue,
indigo, purple and off-white. Upgrading preserves the previous colour for both
choices, which can then be changed independently. Warning and error colours
keep their existing meaning.

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
[CONTRIBUTING.md](CONTRIBUTING.md). GitHub Actions runs tests, packages the DMG,
and publishes a release only when a version tag such as `v1.6.2` is pushed.
Branch pushes and pull requests do not trigger a separate CI workflow.

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

**Keychain:** Claude's readings do not use it where Claude Code is installed.
Claude Code files a *new* keychain item on every token rotation, and the new
item's access list does not carry this app, so an "Always Allow" granted
against the old one stops working about an hour later — asking `claude` itself
avoids the question entirely. Where the keychain is still the source (no
Claude Code on the machine, or Antigravity), the app is signed with a stable
Developer ID identity so a grant survives rebuilds, and the secret is read
only when the owning app has actually changed it — checked via the item's
modification date, which isn't behind the same access prompt as the
credential — so a valid grant does not mean a prompt on every poll.

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

[MIT](LICENSE) © 2026 Vinz
