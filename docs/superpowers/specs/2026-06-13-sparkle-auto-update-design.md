# Sparkle Silent Auto-Update — Design

**Date:** 2026-06-13
**Status:** Approved (pending spec review)
**App:** ProcessMonitor (SwiftUI menu-bar app, bundle `com.cristianofagundes.ProcessMonitor`)

## Problem

The app has no self-update mechanism. Updates ship via Homebrew cask + GitHub
releases. When a user upgrades (e.g. `brew upgrade --cask`), brew swaps the
`.app` bundle on disk, but the already-running instance keeps running the old
version until the user manually quits and reopens it. Goal: the running app
should pick up new versions automatically, with no manual quit/reopen.

## Goals

- Running app detects, downloads, installs, and relaunches into new versions
  automatically (silent, no user prompt).
- Works for both direct-download users and Homebrew users without version
  desync between brew and the app.
- Reuses the existing GitHub release + notarization pipeline; no new hosting
  infrastructure.

## Non-Goals

- Sparkle delta (binary diff) updates — skip for now (YAGNI). Full-zip updates
  only.
- Per-install-source detection logic — avoided by cask convention (see below).
- Rollback / channel selection (beta vs stable) — out of scope.

## Chosen Approach

**Sparkle 2.x** as the in-app updater, configured for silent automatic
updates. Appcast feed hosted as a **GitHub Release asset** at a stable
`latest/download` URL. Homebrew cask marked `auto_updates true` so `brew
upgrade` defers to Sparkle instead of fighting it.

### Why this resolves the brew/Sparkle conflict

A brew-managed copy that self-updates via Sparkle would normally desync brew's
tracked version (brew thinks 1.7, disk is 1.8). Setting `auto_updates true` in
the cask makes `brew upgrade` skip the cask by default (only `--greedy`
upgrades it). Result: brew remains the **installer** (first install), Sparkle
becomes the **updater**. No install-source detection code required. Single
build serves all users.

## Architecture

### Components

1. **Sparkle dependency** — added to `Package.swift` as an SPM package
   (`https://github.com/sparkle-project/Sparkle`, 2.x). Joins the existing
   `sentry-cocoa` dependency on the `ProcessMonitor` executable target.

2. **Updater controller** — `SPUStandardUpdaterController` instantiated in
   `ProcessMonitorApp.swift`. Owns the update lifecycle. Configured for silent
   background operation. A "Check for Updates…" item is added to the menu-bar
   menu as a manual fallback (wired to the updater).

3. **Signing keys** — one EdDSA (Ed25519) keypair, generated once via Sparkle's
   `generate_keys`:
   - Public key → `Info.plist` as `SUPublicEDKey`.
   - Private key → stored in macOS Keychain (where `generate_keys` puts it) and
     backed up to a secret store. **Never committed.**

4. **Appcast feed** — `appcast.xml`, generated per release by Sparkle's
   `generate_appcast`, signed with the private key. Uploaded as a GitHub Release
   asset.

### Info.plist additions

| Key | Value | Purpose |
|-----|-------|---------|
| `SUFeedURL` | `https://github.com/FagundesCristianoF/process-monitor/releases/latest/download/appcast.xml` | Feed location |
| `SUPublicEDKey` | (Ed25519 public key) | Verify update signatures |
| `SUEnableAutomaticChecks` | `true` | Check on schedule |
| `SUAutomaticallyDownloadUpdates` | `true` | Silent download |
| `SUScheduledCheckInterval` | `14400` | Re-check every 4h (24/7 menu-bar app) |

Silent install + auto-relaunch is achieved by configuring the updater to apply
updates without UI (set `automaticallyChecksForUpdates` and the automatic
install behavior on the `SPUUpdater`). On finding a new version while running,
Sparkle downloads in the background, installs, and relaunches the app.

### Data flow

```
app running (1.7)
  ↓ scheduled check (on launch + every 4h)
GET .../releases/latest/download/appcast.xml
  ↓ appcast advertises 1.8 + EdDSA signature
download ProcessMonitor.zip (background)
  ↓ verify EdDSA signature against SUPublicEDKey
install in place
  ↓
Sparkle relaunches → app running (1.8)
```

## Release flow changes

Current flow: `make release` → `make export` (sign + zip) → `make notarize`
(staple + re-zip) → upload zip to GitHub release → update cask.

New steps appended:

1. **`make appcast`** — after `notarize`, run Sparkle's `generate_appcast`
   over the directory containing the signed/notarized `ProcessMonitor.zip`.
   Produces a signed `appcast.xml`. Requires the private key (from Keychain).
2. **Upload `appcast.xml`** alongside `ProcessMonitor.zip` to the GitHub
   release (so `latest/download/appcast.xml` resolves).
3. **Cask** — add `auto_updates true` to `Casks/devprocessmonitor.rb`.

The release/publish memory (`release-publish-flow.md`) is updated to document
the new appcast step and the key-handling requirement.

## Error handling

- **Signature mismatch / corrupt download** — Sparkle refuses to install
  (built-in EdDSA verification). App stays on current version; retries next
  cycle. No special handling needed.
- **Feed unreachable / offline** — Sparkle silently skips; retries on next
  scheduled check. App keeps running.
- **Notarization missing on the zip** — Gatekeeper would block the relaunched
  app. Mitigation: appcast generation happens **after** notarize+staple, over
  the stapled zip, so the enclosure is always notarized.
- **Telemetry (optional)** — Sentry breadcrumb on update-install events to aid
  debugging field issues.

## Testing

- **Unit** — verify the updater controller is constructed and the manual
  "Check for Updates" action is wired (no network in unit tests).
- **Manual / integration** — stage a fake `appcast.xml` advertising a higher
  version pointing at a signed test zip; run a lower-version build; confirm
  silent download → install → relaunch into the new version.
- **Signature negative test** — tamper the zip; confirm Sparkle rejects it and
  the app stays on the old version.
- **Brew coexistence** — confirm `brew upgrade` skips the cask once
  `auto_updates true` is set (and `--greedy` still upgrades).

## Open risks

- Silent relaunch interrupts a menu-bar app the user may have open; acceptable
  per the chosen "fully silent/automatic" UX. The restart is brief and the app
  reopens in the same agent (no-dock) mode.
- Private key custody: losing it means future releases can't be signed for the
  existing public key shipped in installed apps. Must be backed up securely.
