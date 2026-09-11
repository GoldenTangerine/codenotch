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
Debug build automatically, which is enough to run and debug locally. The one
thing an unsigned build can't do is keep a keychain "Always Allow" grant across
rebuilds — Claude Code's and Antigravity's credentials are guarded by an ACL
keyed on the signing identity, and an ad-hoc identity changes every build. In
practice this means the keychain prompt reappears each time you rebuild during
development; that's expected and doesn't affect anything else.

`make release` is different: it archives, signs with a Developer ID
certificate, notarizes with Apple, and regenerates the Sparkle auto-update
feed. That's the maintainer's job for cutting an official build, and it needs
credentials only the maintainer has. You won't need it to contribute.

## Automatic update releases

New builds read the Sparkle feed from
`https://github.com/GoldenTangerine/codenotch/releases/latest/download/appcast.xml`.
Each signed release must include both `appcast.xml` and `Codenotch.dmg`.
The feed points to the DMG under that specific release tag, so publishing a
new version cannot change the download associated with an older signature.

For CI releases, enable the repository variable `RELEASE_SIGNING=true` and
configure the signing secrets documented in `.github/workflows/release.yml`.
The Sparkle signing key must match the public key in `project.yml`; the Apple
signing configuration must also belong to the maintainer publishing the app.
The signed workflow uploads both assets, then compares numeric stable versions
before marking the release as Latest. Republishing an older version does not
replace Latest or the Pages mirror. Missing assets, API failures, and unknown
stable version formats stop promotion; draft and prerelease versions are skipped.
Unsigned releases do not replace Latest because they have no update feed.
Do not manually mark a release without `appcast.xml` as Latest.

For a local signed release, run `make release TAG=vX.Y.Z` with the matching
version in `project.yml`, then explicitly run `make publish TAG=vX.Y.Z` to
upload both assets to an existing release and promote it only if no newer
stable release exists. Local and CI publication share this version check.
CI still publishes a Pages mirror for older installed builds. Those builds
keep their original feed URL until upgraded; if that Pages address is
unavailable, install a release containing the new URL manually once.
Automatic updates become available only after a correctly signed release
with both assets has been published.

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
