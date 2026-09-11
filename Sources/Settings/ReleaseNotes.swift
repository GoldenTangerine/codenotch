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
    private static var local: [ReleaseNote] { [
        ReleaseNote(
            version: "1.6.21",
            headline: L10n.t("More providers and clearer usage tracking."),
            changes: [
                ReleaseNote.Change(title: L10n.t("Weekly limits and usage pacing")),
                ReleaseNote.Change(title: L10n.t("DeepSeek, Devin, Command Code and local models")),
                ReleaseNote.Change(title: L10n.t("Glass appearance, notch sizing and more languages")),
                ReleaseNote.Change(title: L10n.t("Keep your Code Switch R integration and custom queries"))
            ]
        ),
        ReleaseNote(
            version: "1.6.19",
            headline: L10n.t("More control over linked provider visibility."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("Choose from five display scopes"),
                    detail: L10n.t("Follow the tray, show all providers, or filter by remaining quota, exhausted quota or active requests. Settings keeps the complete list, including providers with unknown quota.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Include quota-disabled providers"),
                    detail: L10n.t("Code Switch R 2.11.22 sends enabled and quota-disabled providers across platforms without requiring proxy hosting. Manually disabled providers stay excluded.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Keep sessions and quota alerts visible"),
                    detail: L10n.t("Busy or waiting sessions can restore filtered suppliers without duplicate Codex placeholders. Manual hiding takes priority, and display filters no longer suppress quota alerts.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.18",
            headline: L10n.t("More control over linked provider visibility."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("Choose from five display scopes"),
                    detail: L10n.t("Follow the tray, show all providers, or filter by remaining quota, exhausted quota or active requests. Settings keeps the complete list, including providers with unknown quota.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Include quota-disabled providers"),
                    detail: L10n.t("Code Switch R 2.11.22 sends enabled and quota-disabled providers across platforms without requiring proxy hosting. Manually disabled providers stay excluded.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Keep sessions and quota alerts visible"),
                    detail: L10n.t("Busy or waiting sessions can restore filtered suppliers without duplicate Codex placeholders. Manual hiding takes priority, and display filters no longer suppress quota alerts.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.17",
            headline: L10n.t("Visible provider icons and a searchable brand library."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("Restore linked Codex icons"),
                    detail: L10n.t("OpenAI and other monochrome icons are visible on dark backgrounds again. Colored icons keep their original palette.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Find your brand icon"),
                    detail: L10n.t("Search 723 offline icon variants with previews and a selected indicator. Existing choices are preserved.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.16",
            headline: L10n.t("Clearer Kimi icons and reliable update sources."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("Kimi stays visible on light and dark backgrounds"),
                    detail: L10n.t("The icon keeps its blue accent and original size. Missing or outdated readings use a consistent gray appearance in the notch, details and linked provider settings.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Updates from this repository"),
                    detail: L10n.t("Automatic updates use signed releases from GoldenTangerine/codenotch. If the old update address is unavailable, install this version manually once.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.15",
            headline: L10n.t("Arrange linked providers your way."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("One provider order across settings and the notch"),
                    detail: L10n.t("Drag linked providers to reorder them locally. Settings and the notch share the same default and saved order without changing Code Switch R priorities.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Clearer drag placement"),
                    detail: L10n.t("Wider handles and insertion lines make placement easier. Cancelling a drag clears its state, and search must be cleared before reordering.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Compact rows with room for details"),
                    detail: L10n.t("See requests, cost and the main quota at a glance, then expand for more. Resize Settings from its edges; the window remembers its size and position.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.14",
            headline: L10n.t("Arrange linked providers your way."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("One provider order across settings and the notch"),
                    detail: L10n.t("Drag linked providers to reorder them locally. Settings and the notch share the same default and saved order without changing Code Switch R priorities.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Clearer drag placement"),
                    detail: L10n.t("Wider handles and insertion lines make placement easier. Cancelling a drag clears its state, and search must be cleared before reordering.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Compact rows with room for details"),
                    detail: L10n.t("See requests, cost and the main quota at a glance, then expand for more. Resize Settings from its edges; the window remembers its size and position.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.13",
            headline: L10n.t("Compare your linked providers at a glance."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("Provider statistics in one table"),
                    detail: L10n.t("Compare daily usage, latency, speed and quotas in Code Switch R settings. Search, hide or restore providers, and expand additional quotas when needed.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Current readings and consistent warnings"),
                    detail: L10n.t("Session-only providers no longer show cached data as current. Quotas use the same warning colors as the notch and highlight errors or the most-used allowance.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Restore all enabled providers"),
                    detail: L10n.t("Fix subscriptions that kept showing only tray providers. Code Switch R 2.11.21 also supports subscriptions from older Codenotch versions.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.12",
            headline: L10n.t("Choose your linked providers."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("Customize Code Switch R integration"),
                    detail: L10n.t("Choose tray providers or all proxy-hosted, enabled providers. Search, hide and restore suppliers in the new settings page. Full mode requires Code Switch R 2.11.20.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Keep Codex questions on the right supplier"),
                    detail: L10n.t("Native sessions and hooks share their supplier identity. Empty duplicate entries disappear, and hiding linked suppliers preserves independent local accounts.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Prevent continuous refresh loops"),
                    detail: L10n.t("Automatic refresh waits after each attempt finishes. Credential reads share the query timeout, so a stalled read releases the refresh state and allows a retry.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.11",
            headline: L10n.t("Reliable refresh and session recovery."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("Retry failed usage queries"),
                    detail: L10n.t("Timed-out queries no longer block another refresh. Successful retries restore the ring color, and the card shows refresh progress or the rate-limit retry time.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Keep activity on its supplier"),
                    detail: L10n.t("Recover supplier links when a session start event is missed. Unlinked CLI activity is labeled clearly. Update Code Switch R to 2.11.19 for packed session metadata support.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Recover waiting states safely"),
                    detail: L10n.t("Answers clear uniquely matched questions even when a call ID is missing or arrives later. Ambiguous parallel questions keep their waiting mark until the turn ends.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.10",
            headline: L10n.t("A simpler provider menu."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("Drag to reorder providers"),
                    detail: L10n.t("In Accounts, reorder providers by dragging their handles. The duplicate move actions have been removed from the menu.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.9",
            headline: L10n.t("Start alerts and more sounds."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("Alerts when a turn starts"),
                    detail: L10n.t("With CLI hooks installed, Claude Code and Codex can open the rings when you submit a message. Start alerts default to 5 seconds with sound off, with separate controls in Notifications.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Six new sounds and a smoother volume slider"),
                    detail: L10n.t("Choose from six bundled 8-bit sounds for start, finish and waiting alerts. The shared volume slider is now continuous, with a percentage and previews.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Waiting alerts keep your attention"),
                    detail: L10n.t("Start alerts from other sessions no longer interrupt a waiting alert during its set duration. Turn starts are also tracked more reliably when session details arrive later.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.8",
            headline: L10n.t("Separate colors for your interface and notch."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("Choose each accent independently"),
                    detail: L10n.t("In Appearance, set Interface accent color for Settings and What's New, and Notch accent color for rings and detail cards.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Keep your existing colors"),
                    detail: L10n.t("Upgrading keeps your previous accent for both choices. Future changes are saved separately and take effect immediately.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Position editing matches your notch"),
                    detail: L10n.t("The outline shown while moving the notch now uses its accent color. Warning and error colors keep their existing meaning.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.7",
            headline: L10n.t("More room for provider details."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("Choose your tooltip height"),
                    detail: L10n.t("In Appearance, choose Show all to fit every session, quota and available statistic. Default keeps the existing layout.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Fits your screen"),
                    detail: L10n.t("Bubbles grow with their content and scroll only when the screen cannot fit it all. Edge positioning and pointer interaction follow the new size.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Start each provider at the top"),
                    detail: L10n.t("Switching providers resets the bubble's scroll position. Refreshing the same provider keeps your place.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.6",
            headline: L10n.t("Notification sounds, at your volume."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("Adjust notification volume"),
                    detail: L10n.t("Set a shared volume from 0 to 100% for notifications and previews. Your choice is saved without changing system volume.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Choose which events make a sound"),
                    detail: L10n.t("Choose Off for Finished or Waiting on you to silence that event while keeping its visual alert.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Hear your changes right away"),
                    detail: L10n.t("Changing a sound or finishing a volume adjustment plays a preview. Manual replay remains available, even when notification sounds are off.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.5",
            headline: L10n.t("CLI activity alerts, ready to install."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("Claude Code and Codex CLI hooks"),
                    detail: L10n.t("Install hooks in Notifications to receive completion and waiting alerts. Click a session to return to its application. Codex also requires review in /hooks.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Waiting marks on every edge"),
                    detail: L10n.t("A question badge and amber breathing ring mark waiting sessions. Running keeps its spinner, and Code Switch R 2.11.17 can show the current supplier.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.4",
            headline: L10n.t("Know when your CLI needs you."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("Claude Code and Codex CLI hooks"),
                    detail: L10n.t("Install hooks in Notifications to receive completion and waiting alerts. Click a session to return to its application. Codex also requires review in /hooks.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Waiting marks on every edge"),
                    detail: L10n.t("A question badge and amber breathing ring mark waiting sessions. Running keeps its spinner, and Code Switch R 2.11.17 can show the current supplier.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("More reliable activity tracking"),
                    detail: L10n.t("Improved approval recovery, parallel calls and supplier changes. Uninstall clears activity immediately, with fewer repeated updates and alerts.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.3",
            headline: L10n.t("A cleaner trigger height setting."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("Clearer trigger height layout"),
                    detail: L10n.t("Removed the duplicate label and prevented wrapping. The number, pt unit and stepper stay vertically centered, with the number right-aligned.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.2",
            headline: L10n.t("Fewer accidental openings below your Mac's notch."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("A closer hover target"),
                    detail: L10n.t("When attached to the hardware notch, the default trigger boundary is now just 2pt below its bottom edge to reduce accidental openings over browser tabs.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Adjust the trigger height"),
                    detail: L10n.t("In Appearance, set Trigger height from -20 to +20pt. Positive values extend downward; negative values require moving further into the notch. Changes apply immediately and are saved.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.1",
            headline: L10n.t("Complete Chinese copy and clearer live request counts."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("Chinese throughout the new features"),
                    detail: L10n.t("Settings, menus, notifications, provider guidance, session activity, reset countdowns and release history now use localized copy.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Live request counts stand out"),
                    detail: L10n.t("In Code Switch R details, Calling follows your accent color while the count stays bold green with monospaced digits.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.6.0",
            headline: L10n.t("More displays, providers and alerts, with your custom queries preserved."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("Your custom providers stay with you"),
                    detail: L10n.t("Keep multiple accounts, manual credentials, query scripts, language settings and Code Switch R integration. Existing configurations can add Copilot and Gemini API from Add provider.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Drag to reorder the rings"),
                    detail: L10n.t("Settings keeps your configured providers and accounts; drag a provider row by its handle to change the order the notch draws them in.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Pin the notch to one display, or show it on every one"),
                    detail: L10n.t("A Displays picker in Appearance offers the main display or all of them; a second picker pins a single notch to a named screen.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("A ring says when it crosses 80% and 100%"),
                    detail: L10n.t("A system notification once per crossing, muted per provider from its own settings row.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("GitHub Copilot is a new ring"),
                    detail: L10n.t("Reads GitHub's Copilot quota endpoint using the GitHub CLI session already on the Mac.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Say when a session ends"),
                    detail: L10n.t("The notch opens itself for a few seconds and sounds a chime when an agent stops working or starts waiting on you; a click jumps to it.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("⌥-drag the pill along its edge"),
                    detail: L10n.t("Nudge it clear of another menu-bar app anchored to the same spot; remembered per edge.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Choose an accent colour"),
                    detail: L10n.t("The device accent by default, or a fixed colour for the ring's positive state — the amber and red warning colours stay fixed regardless.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("A countdown instead of a reset date"),
                    detail: L10n.t("Appearance's Reset time picker can show \"Resets in 3h 20m\" instead of a date and time.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Read Cursor from cursor-agent, and enterprise plans correctly"),
                    detail: L10n.t("A CLI-only Cursor login now gets a ring, and enterprise/team plans read their real usage instead of reporting nothing to meter.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Fewer keychain prompts for Claude and Antigravity"),
                    detail: L10n.t("Claude reads its own CLI's /usage first, touching the keychain only as a fallback; Antigravity's language server is asked before it.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Sub-1% usage no longer reads as 0%"),
                    detail: L10n.t("A reading under one percent shows a tenth (\"<0.1%\") instead of rounding to nothing.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Contributors can build without Xcode signing"),
                    detail: L10n.t("make build and make test sign themselves automatically when the maintainer's certificate isn't present, and CI now runs the suite on every push and pull request.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.5.8",
            headline: L10n.t("Follow your active Code Switch R providers."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("Live tray providers"),
                    detail: L10n.t("Active providers appear after your local entries, with the default provider shown when idle. Requires Code Switch R v2.11.16 or later on the same Mac.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Quotas, balances and daily usage"),
                    detail: L10n.t("Hover to inspect quota periods, request activity and statistics, with offline brand icons and explicit inactive periods.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Automatic connection recovery"),
                    detail: L10n.t("Linked entries hide when Code Switch R stops and return when it reconnects. Disable integration in Settings at any time.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.5.7",
            headline: L10n.t("Custom provider queries with reliable refresh status."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("Manage providers and manual queries"),
                    detail: L10n.t("Add accounts with independent credentials, icons, query scripts and refresh settings.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Refresh indicators recover correctly"),
                    detail: L10n.t("Signing out no longer leaves a spinner running. An older request cannot clear the indicator for a newer refresh.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Updated release history"),
                    detail: L10n.t("The in-app update history now includes the provider query features and these fixes.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.5.6",
            headline: L10n.t("Manage providers and query quotas with your own credentials."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("Your providers and accounts"),
                    detail: L10n.t("Add, reorder and customize providers, with separate credentials and icons for each account.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Manual credentials and query scripts"),
                    detail: L10n.t("Use API keys, access tokens or cookies with built-in queries, presets or custom JavaScript.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Independent refresh settings"),
                    detail: L10n.t("Choose a primary metric, refresh intervals and timeout for each query. Failed refreshes keep the last successful reading.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.5.5",
            headline: L10n.t("Put the notch where you need it, on any display."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("Drag to position"),
                    detail: L10n.t("Choose Edit position from the right-click menu, then drag to any screen edge. Release to save, or press Escape to cancel.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Your display and position are remembered"),
                    detail: L10n.t("Move between displays and restore the same position after relaunch. Disconnecting a display temporarily moves the notch to the main display.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Fits the corners and the camera notch"),
                    detail: L10n.t("Details stay visible near corners. The top centre snaps to the camera notch; other top positions stay below the menu bar.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.5.0",
            headline: L10n.t("Two more providers, and a live account plan that was silently dropped."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("Grok is a new ring"),
                    detail: L10n.t("SuperGrok's weekly Grok Build allowance, read from the same billing endpoint the CLI uses, with the session in ~/.grok/auth.json.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("OpenCode's Go plan is a new ring"),
                    detail: L10n.t("Reads the Go plan's official usage endpoint with the key OpenCode itself stores on sign-in — no second sign-in.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("A real Codex account went unmetered"),
                    detail: L10n.t("Codex's live reading only recognised a 5-hour and a 7-day window. A free-plan account's real limit was a 30-day one, which fell through unnoticed and showed as nothing metered on an account that was genuinely tracked.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Switching a provider off now really stops it"),
                    detail: L10n.t("Opening Settings could still read a switched-off provider's account, and a reply already in flight could restore a reading you had just asked it to forget.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Contributors can build without a certificate"),
                    detail: L10n.t("make build and make test now sign themselves automatically when the maintainer's Developer ID isn't present — no Apple account needed to work on this.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.4.1",
            headline: L10n.t("Waking from sleep no longer erases a reading."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("A ring survives waking your Mac"),
                    detail: L10n.t("A brief window right after sleep, where macOS won't allow a keychain prompt yet, was mistaken for being signed out — which erased the reading and left \"waiting for the first reading\" on screen. It now ages the number instead of throwing it away, and picks back up on its own.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.4.0",
            headline: L10n.t("Two more accounts, four community fixes, and honest duplicates."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("Multiple Claude Code accounts"),
                    detail: L10n.t("Keep a work login apart with CLAUDE_CONFIG_DIR? It now gets its own ring, its own limits, and its own row in Settings, beside your personal one.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("GLM added"),
                    detail: L10n.t("Z.ai's Coding Plan reads live now too, with a key borrowed from whichever tool already holds one.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("A stuck Claude ring recovers on its own"),
                    detail: L10n.t("One momentary failure — the Mac waking from sleep, most often — used to lock the ring until the app restarted. It now clears itself on the next check.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Cursor sessions stop reporting work that already ended"),
                    detail: L10n.t("A crashed or abandoned chat could read as \"still working\" for a day or more. It now notices when the writing has actually stopped.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("A months-old duplicate can no longer win"),
                    detail: L10n.t("Claude Code files a new keychain entry on every token rotation. An account signed in for a while could pick an old, expired one at random and show \"waiting for the first reading\" forever.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("A stray click no longer pins the notch open"),
                    detail: L10n.t("Clicking near the screen edge before the notch had even opened could leave it stuck open with nothing on screen explaining why.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.3.0",
            headline: L10n.t("Codex reads live, and Always show stays on."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("Codex is read live instead of from a log"),
                    detail: L10n.t("The figure came from a file Codex writes during a turn, so it was as old as the last time you used it — three days stale in one case. Codenotch now asks Codex itself, and matches its own panel.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("The Codex ring notices the desktop app"),
                    detail: L10n.t("It only ever watched the files the CLI and the VS Code extension write, so work done in the desktop app never made it spin.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Always show no longer turns itself off"),
                    detail: L10n.t("Clicking the notch toggled the same flag the setting used, so a stray click quietly put it back to showing on hover.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Far fewer keychain prompts"),
                    detail: L10n.t("Once a token expired, every check went back to the keychain — a prompt a minute. It now reads the secret only when the owning app has changed it, and never retries a refusal on a timer.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("A paused limit is shown as paused"),
                    detail: L10n.t("Some limits are reached while the headline still shows room. The ring reads as spent and says when it lifts.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Long messages are no longer cut off"),
                    detail: L10n.t("A tooltip with something to explain reserved one line for it however much it said.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.2.0",
            headline: L10n.t("Every session, and a tooltip that fits on the screen."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("Tooltips are no longer cut off"),
                    detail: L10n.t("A card is centred on the ring it belongs to, so the first and last providers threw half of it past the end of the panel — and what fell off was the title. The panel now keeps room for it.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("As many sessions as your screen can hold"),
                    detail: L10n.t("The list was capped at four whatever you were running on. It is now solved for the display: ten on a large one, and \"and N more\" only when there is genuinely no room for the rest.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("The ones that need you come first"),
                    detail: L10n.t("Waiting, then busy, then idle — so if anything is summarised away, it is what matters least.")
                )
            ]
        ),
        ReleaseNote(
            version: "1.1.0",
            headline: L10n.t("Antigravity's real numbers, and a switch that stays off."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("Antigravity shows its actual quota"),
                    detail: L10n.t("Google will not answer Codenotch directly, so it asks Antigravity's own language server instead — the same place Antigravity's usage panel gets its figure.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Usage reads both ways"),
                    detail: L10n.t("\"12% used · 88% left\", so a reading lines up with whichever end your vendor happens to show.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("A way back from a declined keychain prompt"),
                    detail: L10n.t("Declining no longer looks like being signed out, and Allow access… asks macOS again.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Switching a provider off now sticks"),
                    detail: L10n.t("It stopped being read but its last reading was kept, so the ring came back at the next launch.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Distant resets show a date"),
                    detail: L10n.t("A limit renewing in four weeks said \"Mon\", which read as this Monday. It says \"28 Sep\".")
                )
            ]
        ),
        ReleaseNote(
            version: "1.0.0",
            headline: L10n.t("The first release."),
            changes: [
                ReleaseNote.Change(
                    title: L10n.t("Put the notch anywhere"),
                    detail: L10n.t("Right, left, top or bottom. It keeps clear of the Dock and the menu bar, and follows when the Dock moves.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("It joins your Mac's own notch"),
                    detail: L10n.t("On the top edge it takes the hardware's shape, so the two read as one rather than as a bar parked underneath.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Claude, Cursor, Codex and Gemini"),
                    detail: L10n.t("Each read from the tool already signed in on this Mac. Codenotch never asks for a password.")
                ),
                ReleaseNote.Change(
                    title: L10n.t("Choose where Codenotch appears"),
                    detail: L10n.t("In the Dock, in the menu bar, or nowhere at all.")
                )
            ]
        )
    ] }
    private static var upstream: [ReleaseNote] {
        [
            ReleaseNote(
                version: "1.8.0",
                headline: L10n.t("A second ring for the week, Liquid Glass, French, and Claude Desktop read straight from its own cache."),
                changes: [
                    ReleaseNote.Change(
                        title: L10n.t("The week gets a ring of its own"),
                        detail: L10n.t("A second arc, inside the headline ring or outside it, for providers that publish a weekly limit as well as a session one. Off by default; Appearance has the switch.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Liquid Glass"),
                        detail: L10n.t("The open notch, its tooltip and the settings orb take the system's own glass surface, so they refract what is behind them instead of sitting on it. Reduce Transparency turns it solid.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Français"),
                        detail: L10n.t("A third language in Appearance, alongside English and 简体中文.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Claude Desktop usage, read from its own cache"),
                        detail: L10n.t("A third way to read a Claude account, used when the CLI and the token cannot answer. Nothing is sent anywhere: the cache is on this Mac and is only decompressed.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Claude Code found where npm puts it"),
                        detail: L10n.t("An install under nvm, Volta or pnpm is discovered like any other, which also restores the background sign-in renewal for those setups.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("No more transcript folders left behind"),
                        detail: L10n.t("Reading Claude usage ran in a fresh directory every poll, and Claude Code filed a transcript folder for each one. It now runs from a single place, in print mode, writing no session at all.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Reset times follow the Mac's clock"),
                        detail: L10n.t("A 24-hour Mac gets 24-hour reset times instead of AM and PM.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("A finished session says so"),
                        detail: L10n.t("Agent sessions carry a success state, so a run that has completed reads differently from one still going.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Antigravity: choose which limit leads"),
                        detail: L10n.t("The headline ring can follow a named limit rather than whichever happens to be tightest, and a CLI-only install counts as a real account.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Only the hardware notch wakes a notch joined to it"),
                        detail: L10n.t("A notch merged with the camera housing no longer wakes from a pointer anywhere along the whole top edge.")
                    ),
                ]
            ),
            ReleaseNote(
                version: "1.7.0",
                headline: L10n.t("Speaks Chinese, watches local models think, and stays welded to the edge."),
                changes: [
                    ReleaseNote.Change(
                        title: L10n.t("简体中文"),
                        detail: L10n.t("A Language picker in Appearance: follow the Mac, or hold the app to English or Simplified Chinese whatever the Mac is set to. Copy added since the translation was written falls back to English rather than going blank.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Ollama models show thinking and generation speed"),
                        detail: L10n.t("Each loaded model gets its own cell, with the tokens per second of its last response and a mark while it is thinking. The measurement is taken locally and nothing about a prompt leaves the machine.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Claude Code sessions started from the desktop app are counted"),
                        detail: L10n.t("A session launched from Claude for Mac now reaches the notch like any other. The sign-in also renews itself in the background, so a ring stops ageing out after a week of use.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("The notch is welded to the screen edge"),
                        detail: L10n.t("No hairline of wallpaper behind it at any size, and it stays anchored while the size slider is dragged instead of drifting and catching up at the end.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Set the size by slider as well as by preset"),
                        detail: L10n.t("Three named sizes for a decision made for you, or a slider when you have a particular size in mind.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("The notch folds away for a full-screen app"),
                        detail: L10n.t("Whatever is frontmost and full-screen gets the whole screen; the notch comes back when you leave it.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("The settings gear is a toggle"),
                        detail: L10n.t("It turns and presses in as it is clicked, and a second click closes Settings rather than doing nothing.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Cursor stops showing work that finished months ago"),
                        detail: L10n.t("Finished background agents were leaving the ring amber indefinitely. Only a real, current chat counts as waiting now.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Antigravity reads a CLI-only install"),
                        detail: L10n.t("An install with no desktop app is a real account rather than a missing one, and its daily quota is read directly.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("A ready-made download, no Xcode needed"),
                        detail: L10n.t("Every build now produces an app bundle you can run, so trying Codenotch no longer starts with a developer setup.")
                    ),
                ]
            ),
            ReleaseNote(
                version: "1.6.0",
                headline: L10n.t("Reorder the rings, pick a display, and get told when a limit is close."),
                changes: [
                    ReleaseNote.Change(
                        title: L10n.t("Drag to reorder the rings"),
                        detail: L10n.t("Settings splits into Connected and Not connected; drag a connected row by its handle to change the order the notch draws them in.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Pin the notch to one display, or show it on every one"),
                        detail: L10n.t("A Displays picker in Appearance offers the main display or all of them; a second picker pins a single notch to a named screen.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("A ring says when it crosses 80% and 100%"),
                        detail: L10n.t("A system notification once per crossing, muted per provider from its own settings row.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("GitHub Copilot is a new ring"),
                        detail: L10n.t("Reads GitHub's Copilot quota endpoint using the GitHub CLI session already on the Mac.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Say when a session ends"),
                        detail: L10n.t("The notch opens itself for a few seconds and sounds a chime when an agent stops working or starts waiting on you; a click jumps to it.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("⌥-drag the pill along its edge"),
                        detail: L10n.t("Nudge it clear of another menu-bar app anchored to the same spot; remembered per edge.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Choose an accent colour"),
                        detail: L10n.t("The device accent by default, or a fixed colour for the ring's positive state — the amber and red warning colours stay fixed regardless.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("A countdown instead of a reset date"),
                        detail: L10n.t("Appearance's Reset time picker can show \"Resets in 3h 20m\" instead of a date and time.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Read Cursor from cursor-agent, and enterprise plans correctly"),
                        detail: L10n.t("A CLI-only Cursor login now gets a ring, and enterprise/team plans read their real usage instead of reporting nothing to meter.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Fewer keychain prompts for Claude and Antigravity"),
                        detail: L10n.t("Claude reads its own CLI's /usage first, touching the keychain only as a fallback; Antigravity's language server is asked before it.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Sub-1% usage no longer reads as 0%"),
                        detail: L10n.t("A reading under one percent shows a tenth (\"<0.1%\") instead of rounding to nothing.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Contributors can build without Xcode signing"),
                        detail: L10n.t("make build and make test sign themselves automatically when the maintainer's certificate isn't present, and CI now runs the suite on every push and pull request.")
                    )
                ]
            ),
            ReleaseNote(
                version: "1.5.0",
                headline: L10n.t("Two more providers, and a live account plan that was silently dropped."),
                changes: [
                    ReleaseNote.Change(
                        title: L10n.t("Grok is a new ring"),
                        detail: L10n.t("SuperGrok's weekly Grok Build allowance, read from the same billing endpoint the CLI uses, with the session in ~/.grok/auth.json.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("OpenCode's Go plan is a new ring"),
                        detail: L10n.t("Reads the Go plan's official usage endpoint with the key OpenCode itself stores on sign-in — no second sign-in.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("A real Codex account went unmetered"),
                        detail: L10n.t("Codex's live reading only recognised a 5-hour and a 7-day window. A free-plan account's real limit was a 30-day one, which fell through unnoticed and showed as nothing metered on an account that was genuinely tracked.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Switching a provider off now really stops it"),
                        detail: L10n.t("Opening Settings could still read a switched-off provider's account, and a reply already in flight could restore a reading you had just asked it to forget.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Contributors can build without a certificate"),
                        detail: L10n.t("make build and make test now sign themselves automatically when the maintainer's Developer ID isn't present — no Apple account needed to work on this.")
                    )
                ]
            ),
            ReleaseNote(
                version: "1.4.1",
                headline: L10n.t("Waking from sleep no longer erases a reading."),
                changes: [
                    ReleaseNote.Change(
                        title: L10n.t("A ring survives waking your Mac"),
                        detail: L10n.t("A brief window right after sleep, where macOS won't allow a keychain prompt yet, was mistaken for being signed out — which erased the reading and left \"waiting for the first reading\" on screen. It now ages the number instead of throwing it away, and picks back up on its own.")
                    )
                ]
            ),
            ReleaseNote(
                version: "1.4.0",
                headline: L10n.t("Two more accounts, four community fixes, and honest duplicates."),
                changes: [
                    ReleaseNote.Change(
                        title: L10n.t("Multiple Claude Code accounts"),
                        detail: L10n.t("Keep a work login apart with CLAUDE_CONFIG_DIR? It now gets its own ring, its own limits, and its own row in Settings, beside your personal one.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("GLM added"),
                        detail: L10n.t("Z.ai's Coding Plan reads live now too, with a key borrowed from whichever tool already holds one.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("A stuck Claude ring recovers on its own"),
                        detail: L10n.t("One momentary failure — the Mac waking from sleep, most often — used to lock the ring until the app restarted. It now clears itself on the next check.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Cursor sessions stop reporting work that already ended"),
                        detail: L10n.t("A crashed or abandoned chat could read as \"still working\" for a day or more. It now notices when the writing has actually stopped.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("A months-old duplicate can no longer win"),
                        detail: L10n.t("Claude Code files a new keychain entry on every token rotation. An account signed in for a while could pick an old, expired one at random and show \"waiting for the first reading\" forever.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("A stray click no longer pins the notch open"),
                        detail: L10n.t("Clicking near the screen edge before the notch had even opened could leave it stuck open with nothing on screen explaining why.")
                    )
                ]
            ),
            ReleaseNote(
                version: "1.3.0",
                headline: L10n.t("Codex reads live, and Always show stays on."),
                changes: [
                    ReleaseNote.Change(
                        title: L10n.t("Codex is read live instead of from a log"),
                        detail: L10n.t("The figure came from a file Codex writes during a turn, so it was as old as the last time you used it — three days stale in one case. Codenotch now asks Codex itself, and matches its own panel.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("The Codex ring notices the desktop app"),
                        detail: L10n.t("It only ever watched the files the CLI and the VS Code extension write, so work done in the desktop app never made it spin.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Always show no longer turns itself off"),
                        detail: L10n.t("Clicking the notch toggled the same flag the setting used, so a stray click quietly put it back to showing on hover.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Far fewer keychain prompts"),
                        detail: L10n.t("Once a token expired, every check went back to the keychain — a prompt a minute. It now reads the secret only when the owning app has changed it, and never retries a refusal on a timer.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("A paused limit is shown as paused"),
                        detail: L10n.t("Some limits are reached while the headline still shows room. The ring reads as spent and says when it lifts.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Long messages are no longer cut off"),
                        detail: L10n.t("A tooltip with something to explain reserved one line for it however much it said.")
                    )
                ]
            ),
            ReleaseNote(
                version: "1.2.0",
                headline: L10n.t("Every session, and a tooltip that fits on the screen."),
                changes: [
                    ReleaseNote.Change(
                        title: L10n.t("Tooltips are no longer cut off"),
                        detail: L10n.t("A card is centred on the ring it belongs to, so the first and last providers threw half of it past the end of the panel — and what fell off was the title. The panel now keeps room for it.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("As many sessions as your screen can hold"),
                        detail: L10n.t("The list was capped at four whatever you were running on. It is now solved for the display: ten on a large one, and \"and N more\" only when there is genuinely no room for the rest.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("The ones that need you come first"),
                        detail: L10n.t("Waiting, then busy, then idle — so if anything is summarised away, it is what matters least.")
                    )
                ]
            ),
            ReleaseNote(
                version: "1.1.0",
                headline: L10n.t("Antigravity's real numbers, and a switch that stays off."),
                changes: [
                    ReleaseNote.Change(
                        title: L10n.t("Antigravity shows its actual quota"),
                        detail: L10n.t("Google will not answer Codenotch directly, so it asks Antigravity's own language server instead — the same place Antigravity's usage panel gets its figure.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Usage reads both ways"),
                        detail: L10n.t("\"12% used · 88% left\", so a reading lines up with whichever end your vendor happens to show.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("A way back from a declined keychain prompt"),
                        detail: L10n.t("Declining no longer looks like being signed out, and Allow access… asks macOS again.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Switching a provider off now sticks"),
                        detail: L10n.t("It stopped being read but its last reading was kept, so the ring came back at the next launch.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Distant resets show a date"),
                        detail: L10n.t("A limit renewing in four weeks said \"Mon\", which read as this Monday. It says \"28 Sep\".")
                    )
                ]
            ),
            ReleaseNote(
                version: "1.0.0",
                headline: L10n.t("The first release."),
                changes: [
                    ReleaseNote.Change(
                        title: L10n.t("Put the notch anywhere"),
                        detail: L10n.t("Right, left, top or bottom. It keeps clear of the Dock and the menu bar, and follows when the Dock moves.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("It joins your Mac's own notch"),
                        detail: L10n.t("On the top edge it takes the hardware's shape, so the two read as one rather than as a bar parked underneath.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Claude, Cursor, Codex and Gemini"),
                        detail: L10n.t("Each read from the tool already signed in on this Mac. Codenotch never asks for a password.")
                    ),
                    ReleaseNote.Change(
                        title: L10n.t("Choose where Codenotch appears"),
                        detail: L10n.t("In the Dock, in the menu bar, or nowhere at all.")
                    )
                ]
            )
        ]
    }

    static var all: [ReleaseNote] {
        local + upstream.filter { entry in !local.contains { $0.version == entry.version } }
    }

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
