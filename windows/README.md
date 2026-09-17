<!--
@name: 项目构建与文档
@Descripttion: 维护 README.md 的项目实现与上游兼容。
@version: 1.0.0
@Author: sm
@Date: 2026-09-11 15:51:14
@LastEditTime: 2026-09-11 15:51:14
@FilePath: windows/README.md
-->
# Codenotch for Windows

A Windows port of [Codenotch](https://github.com/vinzdg/codenotch) — the usage notch that
sits on the edge of your screen and answers two questions at a glance:
**how much of my AI allowance is left**, and **is Claude still working**.

Same design language as the macOS original (inverse-rounded pill, colour-graded rings,
hover card with per-window bars), rebuilt for Windows in Rust + Tauri 2 / WebView2.
No code is copied from the Swift app; the providers are reimplemented from their
documented behaviour and the wire formats.

## What it shows

| Cell | Source | How it reads it |
|---|---|---|
| **Claude** | `GET https://api.anthropic.com/api/oauth/usage` with the token Claude Code keeps in `~/.claude/.credentials.json` | Session / weekly windows, 429 back-off with a persisted deadline, stale readings dimmed with their age. Renews that token by running the standalone `claude -p` shortly before it expires (Claude Code inside the desktop app never writes this file), and never sends an expired one. A thin arc spins inside the ring while a Claude session is working, and pulses amber when one is waiting on you (Claude Code hooks + transcript watcher, desktop app included). |
| **Codex** | The local Codex sign-in in `~/.codex/auth.json` (read only, never refreshed), falling back to the newest session snapshot | Live primary/secondary windows (5h + weekly on paid plans, a monthly window on free) while Codex is signed in; Spark and Code review appear on the hover card when Codex reports them; otherwise the last snapshot, marked stale by its own timestamp. |
| **Cursor** | The editor's own session from `state.vscdb` → `cursor.com/api/usage-summary` | Included usage / API usage / on-demand, reset at billing-cycle end. Nothing to sign into: it borrows the editor's session, so there is only ever one account. |
| **Grok** | The Grok CLI's own session in `~/.grok/auth.json` (read only, never refreshed) → `cli-chat-proxy.grok.com/v1/billing?format=credits`, the endpoint that CLI's own `/usage` asks | The weekly Grok Build allowance, with the account on the hover card. Only a session minted by `auth.x.ai` is used — the file can also hold a customer IdP token meant for that customer's private proxy. A fresh weekly period reads 0 %, not "unmetered". |
| **Antigravity** | Official `agy` CLI `/usage` print when installed; otherwise the existing local `language_server` bridge, Google Cloud Code API, or transcript model count | Official four quota rows (Gemini & Claude/GPT 5h/weekly) without running the full IDE. When CLI is absent, falls back to legacy local bridge/API. |

Providers that are not installed simply do not get a cell.

### Antigravity

- **Official CLI (Preferred)**: When the official Antigravity CLI (`agy.exe`) is installed (`%LOCALAPPDATA%\agy\bin\agy.exe` or on `PATH`) and signed in, Codenotch reads official quotas directly without keeping the full IDE running.
- **Execution**: Runs the official CLI in a hidden Windows pseudo-console, with a 70-second timeout and cleanup of its process tree. It does not need PowerShell scripts or a separate service.
- **Refresh**: Checks at startup and on hover/explicit request when readings are at least five minutes old; failed attempts are also limited to once per five minutes. It keeps previous readings on failure, without switching to legacy APIs. The CLI is not launched periodically while idle.
- **Fallback**: When the official CLI is not installed, Codenotch preserves the legacy local bridge (`language_server`), Credential Manager, and transcript model turn counting to maintain compatibility with existing installations.
- **Official CLI Reference**: Standalone `/usage` printing is described in the [official Antigravity CLI documentation](https://www.antigravity.google/docs/cli/headless). Note: no categorical Terms of Service guarantee is made.

Restart Codenotch after installing or removing `agy`: the source is selected at startup.
The CLI's text report is parsed defensively; an unsupported format or failed sign-in
shows an error or the last reading marked stale. Codenotch does not automate sign-in.

## Install / build

This fork provides Windows source and an optional NSIS installer configuration.
Its release workflow currently publishes the macOS DMG only.

Build prerequisites: Rust (MSVC toolchain), WebView2 runtime (ships with Windows 11).

```powershell
# from this directory (the repo root here; `windows/` inside the upstream repo)
cargo build --release
.\target\release\codenotch.exe          # pill appears on the right edge of the primary monitor
.\target\release\codenotch.exe doctor   # self-diagnosis: credentials, data sources, icons, hooks
```

To build the installer locally:

```powershell
# the hook gets its own target dir, so the bundler never copies it onto itself
cargo build --release --locked -p codenotch-hook --target-dir target/hook
cd codenotch
npx @tauri-apps/cli@2 build --config tauri.bundle.conf.json
# → ..\target\release\bundle\nsis\Codenotch_<version>_x64-setup.exe
```

Tray menu: the readings themselves — a line per provider with its headline figure, and under it
one line per limit window — then **Refresh all**, **Settings…** and **Quit Codenotch**. Clicking a
provider's line re-reads that provider. Everything else is in the settings window: which rings the
notch shows, its size, the weekly ring, which screen edge it sits on and which screen,
start with Windows, the language, Claude Code hooks, reset
position, and the data folder (`%APPDATA%\codenotch` — logs, persisted readings, icon overrides).

When sign-in or refresh fails, the menu shows the reason alongside any historical readings.
The icon, menu and hover text share one snapshot per provider on a two-second refresh cycle;
native updates occur only when their displayed content changes, including secondary limits
and reset times.

### Where the notch sits

The notch pins to one edge of one screen. **Appearance → Edge** picks left, right, top or bottom:
it stands upright on the left and right edges with the hover card opening sideways, and lies flat
on the top and bottom ones with the card opening below or above. **Appearance → Screen** appears
once more than one monitor is attached.

Dragging does both at once: pick the pill up, drop it anywhere, and it snaps to the nearest edge
of the screen it was dropped on — across monitors, and across a change of DPI between them. The
choice is stored as `notch_edge`, `notch_monitor` (the device name, e.g. `\\.\DISPLAY2`) and
`notch_y` (the position along the edge, 0–1) in `config.json`. A monitor that is no longer
attached falls back to the primary one, so unplugging a screen cannot strand the notch off-screen;
**Recentre** also puts it back on the primary screen's right-hand edge.

Tray layouts include two numeric readings, one to five provider bars, or a plain app icon.
Choose providers and preview the icon in Appearance; failed saves restore the previous selection.

The page checks can run on macOS or Windows with Node.js:

```sh
node windows/scripts/check-ui-scripts.mjs
node --test windows/scripts/upstream-sync.test.mjs
```

Run these from the repository root. The regression tests use a simulated DOM and
Tauri bridge; Rust builds and real WebView2 interactions still need Windows verification.
Ukrainian is supported in both settings and usage cards, including automatic language selection.
Claude token renewal allows up to three attempts per expiry value during an app run, waiting
10 and then 20 minutes between attempts. A changed expiry starts a new retry budget while
retaining the cooldown.

### Icons

Provider marks are the SVGs from [`@lobehub/icons-static-svg`](https://github.com/lobehub/lobe-icons)
(MIT), embedded unmodified — see `codenotch/glyphs/NOTICE.md`. Drop your own
`claude|codex|cursor|grok|gemini.svg` (or `.png`) into `%APPDATA%\codenotch\glyphs\` to override.
The marks remain the trademarks of their owners.

### Translations

Three surfaces draw their own text, so each keeps its own table:

| Surface | Table | Languages today |
|---|---|---|
| Tray menu | `codenotch/src/i18n.rs` (`tr`), `codenotch/src/traymenu.rs` (`label`) | en · ru · zh · ja · ko · uk |
| Hover card | `codenotch/ui/notch.html` (`TEXT`, `PATTERNS`, `UI`) | en · ru · zh · uk |
| Settings window | `codenotch/ui/settings.html` (`STATIC_TEXT`, `STATUS_TEXT`) | en · ru · zh · ja · ko · uk |

Help is welcome on the gaps, which fall back to English rather than breaking anything:

- the hover card has no Japanese or Korean;
- Korean has none of the window names the Mac's catalog carries — `Current session`, `Weekly limit`,
  `Monthly limit`, `5-hour Limit`, `Included usage`, `API usage` — because the catalog has no Korean
  to take them from.

Keys are the exact English string. A string the Mac also shows should be taken from
`Sources/Localizable.xcstrings` rather than translated afresh, so both platforms word it the same
way. A test in `traymenu.rs` fails if the menu and the card stop naming the same window.

## Layout

```
.
├── codenotch/          the Windows app (pill, hover card, settings, providers)
└── codenotch-hook/     tiny helper Claude Code calls to report session events
```

A pull request that touches this tree is built and tested; the check is skipped
inside forks until the pull request is opened here.

## Relationship to upstream

This port follows the upstream design and provider semantics. It is developed at
[Im-Midi/codenotch-windows](https://github.com/Im-Midi/codenotch-windows) and offered to the
upstream project as its `windows/` tree; the two are kept in sync. Session detection
originated in [Im-Midi/Pac-Man](https://github.com/Im-Midi/Pac-Man) (MIT).

## License

MIT — see `LICENSE`. The Codenotch design and name belong to the upstream author.
