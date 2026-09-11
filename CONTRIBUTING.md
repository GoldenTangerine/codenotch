<!--
@name: 贡献与发布指南
@Descripttion: 说明本地开发检查及版本发布要求。
@version: 1.0.0
@Author: sm
@Date: 2026-09-11 11:05:39
@LastEditTime: 2026-09-11 11:05:39
@FilePath: CONTRIBUTING.md
-->
# Contributing

## Building

```sh
brew install xcodegen   # once — project.yml generates the .xcodeproj
make build               # Debug build, ad-hoc signed
make test                # unit tests
make run                 # build and launch
```

None of these need an Apple Developer account. `xcodebuild` ad-hoc signs a
Debug build automatically, which is enough to run and debug locally.

A note on the keychain, because it is not only a development annoyance. A
keychain item has an access list, which is what "Always Allow" writes to, and a
*partition list*, which nothing in the GUI ever writes to. An app outside the
partition list is refused before the access list is consulted, so approving the
dialogue is good for one read. Claude Code recreates its keychain items on every
token rotation, and a new item's partition list admits only Apple's own tools —
which refuses a properly signed release build as surely as an ad-hoc one.

So `ClaudeCredentials.read` never shows the dialogue from a background refresh:
interaction is switched off for the read, and a refusal is retried through
`/usr/bin/security`, which is Apple-signed and on the item's access list. The
one read that may prompt is the one somebody clicks **Allow access…** for in
Settings. To stop the refusal happening at all, `Scripts/fix-keychain-partitions.sh`
adds Codenotch's Team ID to those items' partition lists — once, with your login
password.

`make release` is different: it archives, signs with a Developer ID
certificate, notarizes with Apple, and regenerates the Sparkle auto-update
feed. That's the maintainer's job for cutting an official build, and it needs
credentials only the maintainer has. You won't need it to contribute.

## Automatic update releases

New builds read the Sparkle feed from
`https://github.com/GoldenTangerine/codenotch/releases/latest/download/appcast.xml`.
Each release must include both `appcast.xml` and `Codenotch.dmg`.
The feed points to the DMG under that specific release tag, so publishing a
new version cannot change the download associated with an older signature.

For CI releases, configure `SPARKLE_EDDSA_KEY` as described below. Leave the
repository variable `RELEASE_SIGNING` unset or `false` for an ad-hoc build without
Apple Developer ID or notarization. Both build tracks generate a real signed
appcast, verify the DMG signature against the archived app's `SUPublicEDKey`,
and publish both assets. Setting `RELEASE_SIGNING=true` optionally enables
Apple signing and notarization and requires the additional secrets listed in
`.github/workflows/release.yml`.

The workflow compares numeric stable versions before marking the release as
Latest. Republishing an older version does not replace Latest or the Pages
mirror. Missing assets, invalid update metadata, API failures, and unknown
stable version formats stop promotion; draft and prerelease versions are skipped.
Do not manually mark a release without a valid `appcast.xml` as Latest.

For a local signed release, run `make release TAG=vX.Y.Z` with the matching
version in `project.yml`, then explicitly run `make publish TAG=vX.Y.Z` to
upload both assets to an existing release and promote it only if no newer
stable release exists. Local and CI publication share this version check.
CI still publishes a Pages mirror for older installed builds. Those builds
keep their original feed URL until upgraded; if that Pages address is
unavailable, install a release containing the new URL manually once.
Automatic updates become available only after a correctly signed release
with both assets has been published.

## Sparkle key setup

1. Download and extract the tools from the official
   [Sparkle release](https://github.com/sparkle-project/Sparkle/releases/latest).
   Open a terminal in the extracted directory containing `bin/generate_keys`.
   For an existing key, use the same Keychain account originally used; do not
   create a replacement merely to configure CI. To create a new project key:

   ```sh
   ./bin/generate_keys --account codenotch
   ```

   This stores the private key in your login Keychain and prints the public key.
   Repeat with the same account to display the same public key.

2. Set `SUPublicEDKey` to that **public** key in both `project.yml` and
   `Sources/Info.plist`. XcodeGen uses `project.yml` to generate the plist, so
   changing only the plist is insufficient. Never put the private key in either
   file. The current repository key must be replaced if you do not own its
   matching private key. Existing copies trusting a different key may require
   one manual installation of the new build before future in-app updates work.

3. Export the private key outside the repository and upload the file contents
   directly to the repository secret using GitHub CLI (authenticate `gh` first):

   ```sh
   umask 077
   sparkle_key_dir=$(mktemp -d)
   ./bin/generate_keys --account codenotch -x "$sparkle_key_dir/private-key"
   gh secret set SPARKLE_EDDSA_KEY --repo GoldenTangerine/codenotch < "$sparkle_key_dir/private-key"
   rm "$sparkle_key_dir/private-key"
   rmdir "$sparkle_key_dir"
   ```

   Use your existing account instead of `codenotch` when exporting an existing
   key. Alternatively set the file's complete base64 contents in GitHub →
   Settings → Secrets and variables → Actions → New repository secret, named
   `SPARKLE_EDDSA_KEY`. Use a **secret**, not an Actions variable. Keep a secure
   backup of the key; do not regenerate it for each release or commit its export.

4. Leave `RELEASE_SIGNING` unset or set it to `false` under Actions **Variables**.
   No Apple signing secrets are needed. Commit the public-key configuration and
   workflow changes, add the matching changelog entry, then push a new stable
   version tag. CI publishes `Codenotch.dmg` and `appcast.xml` and promotes Latest
   after validation. Test Check now from an older build with the same public key
   installed in Applications, not running from the DMG.

The default DMG is not notarized: first launch may need approval in macOS
Privacy & Security, and ad-hoc identity changes may cause Keychain prompts after
updates. Sparkle still verifies downloaded updates using EdDSA. See the official
[Sparkle setup and key-export documentation](https://sparkle-project.org/documentation/).

## Before opening a PR

- `make test` passes.
- `python3 -m unittest discover -s Scripts -p 'test_*.py'` passes for release tooling changes.
- New behavior has a test. `Tests/` mirrors `Sources/` by concern, not by
  file — look for the existing test class closest to what you're changing
  before adding a new one.
- If you're changing layout math in `Sources/Notch/NotchLayout.swift`, check it
  against `docs/design/frame-124-hover-tooltip.png` — every constant there is
  quoted from that frame in design-frame pixels via `Design.px(_:)`.

## Code style

- Comments explain **why**, not what — a hidden constraint, a bug a piece of
  code works around, a design decision that would otherwise look arbitrary.
  If removing a comment wouldn't confuse the next reader, it shouldn't be
  there.
- No premature abstraction. Three similar lines beat an early helper.
- A provider adapter (`Sources/Providers/`) should degrade every failure to a
  visible, honest status — `stale`, `needsAuth`, `accessDenied`, `error` — and
  never invent a number. See `UsageProviderError` and `ProviderStatus`.

## Visible copy

- User-visible strings (settings, menus, tooltips, notifications, What's New,
  provider labels and status) go through `L10n.t("English source")`. The
  English source **is** the key.
- English is the source language. Put optional translations in
  `Sources/Localizable.xcstrings`. A missing translation falls back to
  English and must not fail tests — do not gate CI on any locale being
  complete.
- Don't freeze `L10n.t` in a `static let` — lookup has to see the current
  language.
- Follow System plus the in-app Language setting; don't set `AppleLanguages`.
- Windows `windows/codenotch/src/i18n.rs` is a separate system — don't merge
  the two.

## Adding a provider

Implement `UsageProvider` (`Sources/Providers/UsageProvider.swift`). At
minimum:

- Declare a `Fidelity` — `.official` if the number comes from the vendor's own
  endpoint or local state, `.derived` if you computed it yourself (the
  tooltip prefixes a `~`), `.manual` if it's a placeholder.
- Every failure path should map to a `ProviderStatus`, not throw something the
  UI can't render — see how `ClaudeOAuthProvider` and `CodexLocalProvider`
  handle theirs.
- If the credential lives in the keychain, hold it with `CredentialCache`
  rather than reading on every poll — see its doc comment for why.

## Reporting a bug

Include the unified log around the time it happened:

```sh
/usr/bin/log show --last 10m --predicate 'subsystem == "com.vinz.codenotch"' --info --debug
```
