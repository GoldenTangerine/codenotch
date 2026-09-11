/**
 @name: 应用内更新记录
 @Descripttion: 提供各版本首次启动时展示的更新内容。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-08 14:34:20
 @LastEditTime: 2026-09-08 14:34:20
 @FilePath: Sources/Settings/ReleaseNotes.swift
 */
import Foundation

/// What one release changed, in the app's own words.
struct ReleaseNote: Equatable {
    /// Matched against `CFBundleShortVersionString`, so it has to be exactly
    /// the string `MARKETING_VERSION` is set to.
    let version: String
    /// One line under the title. What this release is *about*.
    let headline: String
    let changes: [Change]

    /// A title carries the change; the detail is optional, so a small fix can
    /// be a single line rather than a line padded out to match its neighbours.
    struct Change: Equatable {
        let title: String
        let detail: String

        init(title: String, detail: String = "") {
            self.title = title
            self.detail = detail
        }
    }
}

/// The release history the app ships with.
///
/// Written here rather than fetched from the appcast: it has to be there on a
/// first launch with no network, and it belongs to the build it describes.
/// Bumping `MARKETING_VERSION` without adding an entry is caught by
/// `testTheCurrentVersionHasANote`.
enum ReleaseNotes {
    static let all: [ReleaseNote] = [
        ReleaseNote(
            version: "1.6.16",
            headline: String(localized: "Clearer Kimi icons and reliable update sources."),
            changes: [
                ReleaseNote.Change(
                    title: String(localized: "Kimi stays visible on light and dark backgrounds"),
                    detail: String(localized: "The icon keeps its blue accent and original size. Missing or outdated readings use a consistent gray appearance in the notch, details and linked provider settings.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Updates from this repository"),
                    detail: String(localized: "Automatic updates use signed releases from GoldenTangerine/codenotch. If the old update address is unavailable, install this version manually once.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.15",
            headline: String(localized: "Arrange linked providers your way."),
            changes: [
                ReleaseNote.Change(
                    title: String(localized: "One provider order across settings and the notch"),
                    detail: String(localized: "Drag linked providers to reorder them locally. Settings and the notch share the same default and saved order without changing Code Switch R priorities.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Clearer drag placement"),
                    detail: String(localized: "Wider handles and insertion lines make placement easier. Cancelling a drag clears its state, and search must be cleared before reordering.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Compact rows with room for details"),
                    detail: String(localized: "See requests, cost and the main quota at a glance, then expand for more. Resize Settings from its edges; the window remembers its size and position.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.14",
            headline: String(localized: "Arrange linked providers your way."),
            changes: [
                ReleaseNote.Change(
                    title: String(localized: "One provider order across settings and the notch"),
                    detail: String(localized: "Drag linked providers to reorder them locally. Settings and the notch share the same default and saved order without changing Code Switch R priorities.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Clearer drag placement"),
                    detail: String(localized: "Wider handles and insertion lines make placement easier. Cancelling a drag clears its state, and search must be cleared before reordering.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Compact rows with room for details"),
                    detail: String(localized: "See requests, cost and the main quota at a glance, then expand for more. Resize Settings from its edges; the window remembers its size and position.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.13",
            headline: String(localized: "Compare your linked providers at a glance."),
            changes: [
                ReleaseNote.Change(
                    title: String(localized: "Provider statistics in one table"),
                    detail: String(localized: "Compare daily usage, latency, speed and quotas in Code Switch R settings. Search, hide or restore providers, and expand additional quotas when needed.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Current readings and consistent warnings"),
                    detail: String(localized: "Session-only providers no longer show cached data as current. Quotas use the same warning colors as the notch and highlight errors or the most-used allowance.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Restore all enabled providers"),
                    detail: String(localized: "Fix subscriptions that kept showing only tray providers. Code Switch R 2.11.21 also supports subscriptions from older Codenotch versions.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.12",
            headline: String(localized: "Choose your linked providers."),
            changes: [
                ReleaseNote.Change(
                    title: String(localized: "Customize Code Switch R integration"),
                    detail: String(localized: "Choose tray providers or all proxy-hosted, enabled providers. Search, hide and restore suppliers in the new settings page. Full mode requires Code Switch R 2.11.20.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Keep Codex questions on the right supplier"),
                    detail: String(localized: "Native sessions and hooks share their supplier identity. Empty duplicate entries disappear, and hiding linked suppliers preserves independent local accounts.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Prevent continuous refresh loops"),
                    detail: String(localized: "Automatic refresh waits after each attempt finishes. Credential reads share the query timeout, so a stalled read releases the refresh state and allows a retry.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.11",
            headline: String(localized: "Reliable refresh and session recovery."),
            changes: [
                ReleaseNote.Change(
                    title: String(localized: "Retry failed usage queries"),
                    detail: String(localized: "Timed-out queries no longer block another refresh. Successful retries restore the ring color, and the card shows refresh progress or the rate-limit retry time.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Keep activity on its supplier"),
                    detail: String(localized: "Recover supplier links when a session start event is missed. Unlinked CLI activity is labeled clearly. Update Code Switch R to 2.11.19 for packed session metadata support.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Recover waiting states safely"),
                    detail: String(localized: "Answers clear uniquely matched questions even when a call ID is missing or arrives later. Ambiguous parallel questions keep their waiting mark until the turn ends.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.10",
            headline: String(localized: "A simpler provider menu."),
            changes: [
                ReleaseNote.Change(
                    title: String(localized: "Drag to reorder providers"),
                    detail: String(localized: "In Accounts, reorder providers by dragging their handles. The duplicate move actions have been removed from the menu.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.9",
            headline: String(localized: "Start alerts and more sounds."),
            changes: [
                ReleaseNote.Change(
                    title: String(localized: "Alerts when a turn starts"),
                    detail: String(localized: "With CLI hooks installed, Claude Code and Codex can open the rings when you submit a message. Start alerts default to 5 seconds with sound off, with separate controls in Notifications.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Six new sounds and a smoother volume slider"),
                    detail: String(localized: "Choose from six bundled 8-bit sounds for start, finish and waiting alerts. The shared volume slider is now continuous, with a percentage and previews.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Waiting alerts keep your attention"),
                    detail: String(localized: "Start alerts from other sessions no longer interrupt a waiting alert during its set duration. Turn starts are also tracked more reliably when session details arrive later.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.8",
            headline: String(localized: "Separate colors for your interface and notch."),
            changes: [
                ReleaseNote.Change(
                    title: String(localized: "Choose each accent independently"),
                    detail: String(localized: "In Appearance, set Interface accent color for Settings and What's New, and Notch accent color for rings and detail cards.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Keep your existing colors"),
                    detail: String(localized: "Upgrading keeps your previous accent for both choices. Future changes are saved separately and take effect immediately.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Position editing matches your notch"),
                    detail: String(localized: "The outline shown while moving the notch now uses its accent color. Warning and error colors keep their existing meaning.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.7",
            headline: String(localized: "More room for provider details."),
            changes: [
                ReleaseNote.Change(
                    title: String(localized: "Choose your tooltip height"),
                    detail: String(localized: "In Appearance, choose Show all to fit every session, quota and available statistic. Default keeps the existing layout.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Fits your screen"),
                    detail: String(localized: "Bubbles grow with their content and scroll only when the screen cannot fit it all. Edge positioning and pointer interaction follow the new size.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Start each provider at the top"),
                    detail: String(localized: "Switching providers resets the bubble's scroll position. Refreshing the same provider keeps your place.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.6",
            headline: String(localized: "Notification sounds, at your volume."),
            changes: [
                ReleaseNote.Change(
                    title: String(localized: "Adjust notification volume"),
                    detail: String(localized: "Set a shared volume from 0 to 100% for notifications and previews. Your choice is saved without changing system volume.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Choose which events make a sound"),
                    detail: String(localized: "Choose Off for Finished or Waiting on you to silence that event while keeping its visual alert.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Hear your changes right away"),
                    detail: String(localized: "Changing a sound or finishing a volume adjustment plays a preview. Manual replay remains available, even when notification sounds are off.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.5",
            headline: String(localized: "CLI activity alerts, ready to install."),
            changes: [
                ReleaseNote.Change(
                    title: String(localized: "Claude Code and Codex CLI hooks"),
                    detail: String(localized: "Install hooks in Notifications to receive completion and waiting alerts. Click a session to return to its application. Codex also requires review in /hooks.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Waiting marks on every edge"),
                    detail: String(localized: "A question badge and amber breathing ring mark waiting sessions. Running keeps its spinner, and Code Switch R 2.11.17 can show the current supplier.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.4",
            headline: String(localized: "Know when your CLI needs you."),
            changes: [
                ReleaseNote.Change(
                    title: String(localized: "Claude Code and Codex CLI hooks"),
                    detail: String(localized: "Install hooks in Notifications to receive completion and waiting alerts. Click a session to return to its application. Codex also requires review in /hooks.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Waiting marks on every edge"),
                    detail: String(localized: "A question badge and amber breathing ring mark waiting sessions. Running keeps its spinner, and Code Switch R 2.11.17 can show the current supplier.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "More reliable activity tracking"),
                    detail: String(localized: "Improved approval recovery, parallel calls and supplier changes. Uninstall clears activity immediately, with fewer repeated updates and alerts.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.3",
            headline: String(localized: "A cleaner trigger height setting."),
            changes: [
                ReleaseNote.Change(
                    title: String(localized: "Clearer trigger height layout"),
                    detail: String(localized: "Removed the duplicate label and prevented wrapping. The number, pt unit and stepper stay vertically centered, with the number right-aligned.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.2",
            headline: String(localized: "Fewer accidental openings below your Mac's notch."),
            changes: [
                ReleaseNote.Change(
                    title: String(localized: "A closer hover target"),
                    detail: String(localized: "When attached to the hardware notch, the default trigger boundary is now just 2pt below its bottom edge to reduce accidental openings over browser tabs.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Adjust the trigger height"),
                    detail: String(localized: "In Appearance, set Trigger height from -20 to +20pt. Positive values extend downward; negative values require moving further into the notch. Changes apply immediately and are saved.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.1",
            headline: String(localized: "Complete Chinese copy and clearer live request counts."),
            changes: [
                ReleaseNote.Change(
                    title: String(localized: "Chinese throughout the new features"),
                    detail: String(localized: "Settings, menus, notifications, provider guidance, session activity, reset countdowns and release history now use localized copy.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Live request counts stand out"),
                    detail: String(localized: "In Code Switch R details, Calling follows your accent color while the count stays bold green with monospaced digits.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.0",
            headline: String(localized: "More displays, providers and alerts, with your custom queries preserved."),
            changes: [
                ReleaseNote.Change(
                    title: String(localized: "Your custom providers stay with you"),
                    detail: String(localized: "Keep multiple accounts, manual credentials, query scripts, language settings and Code Switch R integration. Existing configurations can add Copilot and Gemini API from Add provider.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Drag to reorder the rings"),
                    detail: String(localized: "Settings keeps your configured providers and accounts; drag a provider row by its handle to change the order the notch draws them in.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Pin the notch to one display, or show it on every one"),
                    detail: String(localized: "A Displays picker in Appearance offers the main display or all of them; a second picker pins a single notch to a named screen.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "A ring says when it crosses 80% and 100%"),
                    detail: String(localized: "A system notification once per crossing, muted per provider from its own settings row.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "GitHub Copilot is a new ring"),
                    detail: String(localized: "Reads GitHub's Copilot quota endpoint using the GitHub CLI session already on the Mac.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Say when a session ends"),
                    detail: String(localized: "The notch opens itself for a few seconds and sounds a chime when an agent stops working or starts waiting on you; a click jumps to it.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "⌥-drag the pill along its edge"),
                    detail: String(localized: "Nudge it clear of another menu-bar app anchored to the same spot; remembered per edge.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Choose an accent colour"),
                    detail: String(localized: "The device accent by default, or a fixed colour for the ring's positive state — the amber and red warning colours stay fixed regardless.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "A countdown instead of a reset date"),
                    detail: String(localized: "Appearance's Reset time picker can show \"Resets in 3h 20m\" instead of a date and time.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Read Cursor from cursor-agent, and enterprise plans correctly"),
                    detail: String(localized: "A CLI-only Cursor login now gets a ring, and enterprise/team plans read their real usage instead of reporting nothing to meter.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Fewer keychain prompts for Claude and Antigravity"),
                    detail: String(localized: "Claude reads its own CLI's /usage first, touching the keychain only as a fallback; Antigravity's language server is asked before it.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Sub-1% usage no longer reads as 0%"),
                    detail: String(localized: "A reading under one percent shows a tenth (\"<0.1%\") instead of rounding to nothing.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Contributors can build without Xcode signing"),
                    detail: String(localized: "make build and make test sign themselves automatically when the maintainer's certificate isn't present, and CI now runs the suite on every push and pull request.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.5.8",
            headline: String(localized: "Follow your active Code Switch R providers."),
            changes: [
                ReleaseNote.Change(
                    title: String(localized: "Live tray providers"),
                    detail: String(localized: "Active providers appear after your local entries, with the default provider shown when idle. Requires Code Switch R v2.11.16 or later on the same Mac.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Quotas, balances and daily usage"),
                    detail: String(localized: "Hover to inspect quota periods, request activity and statistics, with offline brand icons and explicit inactive periods.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Automatic connection recovery"),
                    detail: String(localized: "Linked entries hide when Code Switch R stops and return when it reconnects. Disable integration in Settings at any time.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.5.7",
            headline: String(localized: "Custom provider queries with reliable refresh status."),
            changes: [
                ReleaseNote.Change(
                    title: String(localized: "Manage providers and manual queries"),
                    detail: String(localized: "Add accounts with independent credentials, icons, query scripts and refresh settings.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Refresh indicators recover correctly"),
                    detail: String(localized: "Signing out no longer leaves a spinner running. An older request cannot clear the indicator for a newer refresh.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Updated release history"),
                    detail: String(localized: "The in-app update history now includes the provider query features and these fixes.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.5.6",
            headline: String(localized: "Manage providers and query quotas with your own credentials."),
            changes: [
                ReleaseNote.Change(
                    title: String(localized: "Your providers and accounts"),
                    detail: String(localized: "Add, reorder and customize providers, with separate credentials and icons for each account.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Manual credentials and query scripts"),
                    detail: String(localized: "Use API keys, access tokens or cookies with built-in queries, presets or custom JavaScript.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Independent refresh settings"),
                    detail: String(localized: "Choose a primary metric, refresh intervals and timeout for each query. Failed refreshes keep the last successful reading.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.5.5",
            headline: String(localized: "Put the notch where you need it, on any display."),
            changes: [
                ReleaseNote.Change(
                    title: String(localized: "Drag to position"),
                    detail: String(localized: "Choose Edit position from the right-click menu, then drag to any screen edge. Release to save, or press Escape to cancel.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Your display and position are remembered"),
                    detail: String(localized: "Move between displays and restore the same position after relaunch. Disconnecting a display temporarily moves the notch to the main display.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Fits the corners and the camera notch"),
                    detail: String(localized: "Details stay visible near corners. The top centre snaps to the camera notch; other top positions stay below the menu bar.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.5.0",
            headline: String(localized: "Two more providers, and a live account plan that was silently dropped."),
            changes: [
                ReleaseNote.Change(
                    title: String(localized: "Grok is a new ring"),
                    detail: String(localized: "SuperGrok's weekly Grok Build allowance, read from the same billing endpoint the CLI uses, with the session in ~/.grok/auth.json.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "OpenCode's Go plan is a new ring"),
                    detail: String(localized: "Reads the Go plan's official usage endpoint with the key OpenCode itself stores on sign-in — no second sign-in.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "A real Codex account went unmetered"),
                    detail: String(localized: "Codex's live reading only recognised a 5-hour and a 7-day window. A free-plan account's real limit was a 30-day one, which fell through unnoticed and showed as nothing metered on an account that was genuinely tracked.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Switching a provider off now really stops it"),
                    detail: String(localized: "Opening Settings could still read a switched-off provider's account, and a reply already in flight could restore a reading you had just asked it to forget.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Contributors can build without a certificate"),
                    detail: String(localized: "make build and make test now sign themselves automatically when the maintainer's Developer ID isn't present — no Apple account needed to work on this.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.4.1",
            headline: String(localized: "Waking from sleep no longer erases a reading."),
            changes: [
                ReleaseNote.Change(
                    title: String(localized: "A ring survives waking your Mac"),
                    detail: String(localized: "A brief window right after sleep, where macOS won't allow a keychain prompt yet, was mistaken for being signed out — which erased the reading and left \"waiting for the first reading\" on screen. It now ages the number instead of throwing it away, and picks back up on its own.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.4.0",
            headline: String(localized: "Two more accounts, four community fixes, and honest duplicates."),
            changes: [
                ReleaseNote.Change(
                    title: String(localized: "Multiple Claude Code accounts"),
                    detail: String(localized: "Keep a work login apart with CLAUDE_CONFIG_DIR? It now gets its own ring, its own limits, and its own row in Settings, beside your personal one.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "GLM added"),
                    detail: String(localized: "Z.ai's Coding Plan reads live now too, with a key borrowed from whichever tool already holds one.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "A stuck Claude ring recovers on its own"),
                    detail: String(localized: "One momentary failure — the Mac waking from sleep, most often — used to lock the ring until the app restarted. It now clears itself on the next check.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Cursor sessions stop reporting work that already ended"),
                    detail: String(localized: "A crashed or abandoned chat could read as \"still working\" for a day or more. It now notices when the writing has actually stopped.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "A months-old duplicate can no longer win"),
                    detail: String(localized: "Claude Code files a new keychain entry on every token rotation. An account signed in for a while could pick an old, expired one at random and show \"waiting for the first reading\" forever.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "A stray click no longer pins the notch open"),
                    detail: String(localized: "Clicking near the screen edge before the notch had even opened could leave it stuck open with nothing on screen explaining why.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.3.0",
            headline: String(localized: "Codex reads live, and Always show stays on."),
            changes: [
                ReleaseNote.Change(
                    title: String(localized: "Codex is read live instead of from a log"),
                    detail: String(localized: "The figure came from a file Codex writes during a turn, so it was as old as the last time you used it — three days stale in one case. Codenotch now asks Codex itself, and matches its own panel.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "The Codex ring notices the desktop app"),
                    detail: String(localized: "It only ever watched the files the CLI and the VS Code extension write, so work done in the desktop app never made it spin.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Always show no longer turns itself off"),
                    detail: String(localized: "Clicking the notch toggled the same flag the setting used, so a stray click quietly put it back to showing on hover.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Far fewer keychain prompts"),
                    detail: String(localized: "Once a token expired, every check went back to the keychain — a prompt a minute. It now reads the secret only when the owning app has changed it, and never retries a refusal on a timer.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "A paused limit is shown as paused"),
                    detail: String(localized: "Some limits are reached while the headline still shows room. The ring reads as spent and says when it lifts.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Long messages are no longer cut off"),
                    detail: String(localized: "A tooltip with something to explain reserved one line for it however much it said.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.2.0",
            headline: String(localized: "Every session, and a tooltip that fits on the screen."),
            changes: [
                ReleaseNote.Change(
                    title: String(localized: "Tooltips are no longer cut off"),
                    detail: String(localized: "A card is centred on the ring it belongs to, so the first and last providers threw half of it past the end of the panel — and what fell off was the title. The panel now keeps room for it.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "As many sessions as your screen can hold"),
                    detail: String(localized: "The list was capped at four whatever you were running on. It is now solved for the display: ten on a large one, and \"and N more\" only when there is genuinely no room for the rest.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "The ones that need you come first"),
                    detail: String(localized: "Waiting, then busy, then idle — so if anything is summarised away, it is what matters least.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.1.0",
            headline: String(localized: "Antigravity's real numbers, and a switch that stays off."),
            changes: [
                ReleaseNote.Change(
                    title: String(localized: "Antigravity shows its actual quota"),
                    detail: String(localized: "Google will not answer Codenotch directly, so it asks Antigravity's own language server instead — the same place Antigravity's usage panel gets its figure.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Usage reads both ways"),
                    detail: String(localized: "\"12% used · 88% left\", so a reading lines up with whichever end your vendor happens to show.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "A way back from a declined keychain prompt"),
                    detail: String(localized: "Declining no longer looks like being signed out, and Allow access… asks macOS again.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Switching a provider off now sticks"),
                    detail: String(localized: "It stopped being read but its last reading was kept, so the ring came back at the next launch.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Distant resets show a date"),
                    detail: String(localized: "A limit renewing in four weeks said \"Mon\", which read as this Monday. It says \"28 Sep\".")
                )
            ]
        ),
        ReleaseNote(
            version: "1.0.0",
            headline: String(localized: "The first release."),
            changes: [
                ReleaseNote.Change(
                    title: String(localized: "Put the notch anywhere"),
                    detail: String(localized: "Right, left, top or bottom. It keeps clear of the Dock and the menu bar, and follows when the Dock moves.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "It joins your Mac's own notch"),
                    detail: String(localized: "On the top edge it takes the hardware's shape, so the two read as one rather than as a bar parked underneath.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Claude, Cursor, Codex and Gemini"),
                    detail: String(localized: "Each read from the tool already signed in on this Mac. Codenotch never asks for a password.")
                ),
                ReleaseNote.Change(
                    title: String(localized: "Choose where Codenotch appears"),
                    detail: String(localized: "In the Dock, in the menu bar, or nowhere at all.")
                )
            ]
        )
    ]

    static func note(for version: String) -> ReleaseNote? {
        all.first { $0.version == version }
    }

    /// The note worth showing on this launch, if there is one.
    ///
    /// `notes` is a parameter so the rule can be tested against a fixed history
    /// rather than against whatever the app happens to ship this week.
    static func unseen(in version: String,
                       lastSeen: String?,
                       notes: [ReleaseNote] = ReleaseNotes.all) -> ReleaseNote? {
        guard lastSeen != version else { return nil }
        return notes.first { $0.version == version }
    }
}
