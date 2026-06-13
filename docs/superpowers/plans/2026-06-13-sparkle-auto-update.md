# Sparkle Silent Auto-Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the running app silently detect, download, install, and relaunch into new versions via Sparkle, without manual quit/reopen.

**Architecture:** Add Sparkle 2.x (SPM) to the SwiftUI menu-bar app. Configure it for fully silent automatic updates against a GitHub-Release-hosted signed appcast. Because the build is an SPM CLI build with a hand-rolled `make` bundling step (not Xcode), the Makefile must embed and re-sign `Sparkle.framework` into `Contents/Frameworks/`. The Homebrew cask is marked `auto_updates true` so brew defers to Sparkle.

**Tech Stack:** Swift 5.9, SwiftUI, SPM CLI (`swift build`), Sparkle 2.x, `codesign`/`notarytool`/`stapler`, Homebrew cask.

**Important forward-only caveat:** Auto-update only works from the first Sparkle-enabled release onward. Installed 1.7/1.8 copies have no Sparkle, so users perform one final manual/brew upgrade to this release; subsequent releases auto-update. The release introducing this should bump the marketing version (e.g. to `1.9.0`, build `12`).

---

## File Structure

- `Package.swift` — add Sparkle dependency + linker rpath. (modify)
- `Info.plist` — add Sparkle keys (`SUFeedURL`, `SUPublicEDKey`, etc.) + version bump. (modify)
- `Makefile` — embed/sign `Sparkle.framework`; add `appcast` target. (modify)
- `ProcessMonitor/Services/UpdaterService.swift` — thin wrapper owning `SPUStandardUpdaterController`, silent config, `checkForUpdates()`. (create)
- `ProcessMonitor/ProcessMonitorApp.swift` — instantiate `UpdaterService`, pass into views. (modify)
- `ProcessMonitor/Views/ProcessListView.swift` — add "Check for Updates" affordance in footer. (modify)
- `Casks/devprocessmonitor.rb` — `auto_updates true` + version/sha bump. (modify)
- `Tests/ProcessMonitorTests/UpdaterServiceTests.swift` — unit tests for the wrapper. (create)
- `.claude/projects/.../memory/release-publish-flow.md` + `MEMORY.md` — document appcast step + key custody. (modify, via memory tooling)

---

## Task 1: Add Sparkle dependency and confirm it links

**Files:**
- Modify: `Package.swift:7-18`

- [ ] **Step 1: Add the Sparkle package + product dependency + rpath**

Replace the `dependencies` array and the `executableTarget` in `Package.swift` with:

```swift
    dependencies: [
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.36.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "ProcessMonitor",
            dependencies: [
                .product(name: "Sentry", package: "sentry-cocoa"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "ProcessMonitor",
            resources: [.process("Resources")],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
```

(Leave the `testTarget` unchanged.)

- [ ] **Step 2: Resolve and build**

Run: `swift build`
Expected: PASS — `Compiling Sparkle ...` then `Build complete!`. (First run downloads the Sparkle XCFramework artifact to `.build/artifacts/sparkle/`.)

- [ ] **Step 3: Confirm the XCFramework landed where the Makefile will copy from**

Run: `ls .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework`
Expected: lists `Sparkle`, `Versions/`, `Resources/`. If the path differs, run `find .build/artifacts -name Sparkle.framework -type d` and note the actual path for Task 4.

- [ ] **Step 4: Commit**

```bash
rtk git add Package.swift Package.resolved
rtk git commit -m "build: add Sparkle 2.x dependency + Frameworks rpath"
```

---

## Task 2: Create the UpdaterService wrapper (TDD)

A thin, testable wrapper around `SPUStandardUpdaterController` so the app and tests don't touch Sparkle internals directly.

**Files:**
- Create: `ProcessMonitor/Services/UpdaterService.swift`
- Create: `Tests/ProcessMonitorTests/UpdaterServiceTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/ProcessMonitorTests/UpdaterServiceTests.swift`:

```swift
import XCTest
@testable import ProcessMonitor

final class UpdaterServiceTests: XCTestCase {
    func testStartsWithAutomaticChecksEnabled() {
        let service = UpdaterService()
        XCTAssertTrue(service.automaticallyChecksForUpdates,
                      "Updater should auto-check by default for silent updates")
    }

    func testStartsWithAutomaticDownloadEnabled() {
        let service = UpdaterService()
        XCTAssertTrue(service.automaticallyDownloadsUpdates,
                      "Updater should auto-download for silent updates")
    }

    func testCanCheckForUpdatesIsExposed() {
        let service = UpdaterService()
        // canCheckForUpdates is published by Sparkle; just confirm the property is reachable.
        _ = service.canCheckForUpdates
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter UpdaterServiceTests`
Expected: FAIL — `cannot find 'UpdaterService' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `ProcessMonitor/Services/UpdaterService.swift`:

```swift
import Foundation
import Sparkle

/// Thin wrapper around Sparkle configured for fully silent automatic updates.
/// Owns the updater lifecycle; exposes a manual check for the "Check for Updates" UI.
@MainActor
final class UpdaterService: ObservableObject {
    private let controller: SPUStandardUpdaterController

    /// Mirrors Sparkle's `canCheckForUpdates`, used to enable/disable the menu item.
    @Published var canCheckForUpdates = false

    init() {
        // startingUpdater: true begins the scheduled check cycle immediately.
        // No delegate / no UI driver overrides → uses SUStandard* Info.plist keys.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        let updater = controller.updater
        updater.automaticallyChecksForUpdates = true
        updater.automaticallyDownloadsUpdates = true

        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)

        Telemetry.breadcrumb("Updater started", category: "update")
    }

    var automaticallyChecksForUpdates: Bool {
        controller.updater.automaticallyChecksForUpdates
    }

    var automaticallyDownloadsUpdates: Bool {
        controller.updater.automaticallyDownloadsUpdates
    }

    /// Triggers a user-initiated check (shows UI if an update is found via this path).
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
```

Note: `publisher(for:)` requires `import Combine`. Add `import Combine` at the top if the build complains.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter UpdaterServiceTests`
Expected: PASS (3 tests).

Note: if `SPUStandardUpdaterController` aborts in the test process because the test bundle lacks `SUFeedURL`/`SUPublicEDKey`, change the tests to assert against a non-started instance instead: construct with `startingUpdater: false` inside `UpdaterService` only when an env flag `PM_TESTING` is set, and have tests set `setenv("PM_TESTING","1",1)` before init. Prefer the simple version first; only add the flag if tests crash.

- [ ] **Step 5: Commit**

```bash
rtk git add ProcessMonitor/Services/UpdaterService.swift Tests/ProcessMonitorTests/UpdaterServiceTests.swift
rtk git commit -m "feat: add UpdaterService wrapper around Sparkle (silent config)"
```

---

## Task 3: Add Sparkle keys to Info.plist + version bump

**Files:**
- Modify: `Info.plist:29-32` (version) and add new keys before `</dict>` at line 41.

- [ ] **Step 1: Bump version**

In `Info.plist`, change:
```xml
	<key>CFBundleShortVersionString</key>
	<string>1.9.0</string>
	<key>CFBundleVersion</key>
	<string>12</string>
```

- [ ] **Step 2: Add Sparkle keys**

Insert before the closing `</dict>` (line 41). Leave `SUPublicEDKey` value as the literal placeholder `REPLACE_WITH_ED_PUBLIC_KEY` for now — Task 5 fills it after key generation:

```xml
	<key>SUFeedURL</key>
	<string>https://github.com/FagundesCristianoF/process-monitor/releases/latest/download/appcast.xml</string>
	<key>SUPublicEDKey</key>
	<string>REPLACE_WITH_ED_PUBLIC_KEY</string>
	<key>SUEnableAutomaticChecks</key>
	<true/>
	<key>SUAutomaticallyUpdate</key>
	<true/>
	<key>SUScheduledCheckInterval</key>
	<integer>14400</integer>
```

- [ ] **Step 3: Validate the plist parses**

Run: `plutil -lint Info.plist`
Expected: `Info.plist: OK`

- [ ] **Step 4: Commit**

```bash
rtk git add Info.plist
rtk git commit -m "feat: add Sparkle Info.plist keys; bump to 1.9.0 (12)"
```

---

## Task 4: Embed and sign Sparkle.framework in the Makefile

This is the highest-risk task. Sparkle ships XPC services and helper apps inside `Sparkle.framework` that must be embedded under `Contents/Frameworks/` and individually signed with the hardened runtime, or the relaunched app fails Gatekeeper/notarization.

**Files:**
- Modify: `Makefile` (`bundle` target lines 21-31, `export` target lines 39-52)

- [ ] **Step 1: Add a reusable variable + embed function for both targets**

After line 10 (`RESOURCE_BUNDLE = ...`) add:

```makefile
# Sparkle framework source (resolved by `swift build`). Verify with:
#   find .build/artifacts -name Sparkle.framework -type d
SPARKLE_FRAMEWORK = .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework
```

- [ ] **Step 2: Embed + sign Sparkle in the `export` target**

In the `export` target, AFTER the `strip` line (line 49) and BEFORE the existing `codesign` of the bundle (line 50), insert:

```makefile
	mkdir -p "$(BUNDLE_NAME)/Contents/Frameworks"
	cp -R "$(SPARKLE_FRAMEWORK)" "$(BUNDLE_NAME)/Contents/Frameworks/Sparkle.framework"
	codesign --force --options runtime --sign "$(SIGN_IDENTITY)" --team-id "$(TEAM_ID)" \
		"$(BUNDLE_NAME)/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
	codesign --force --options runtime --sign "$(SIGN_IDENTITY)" --team-id "$(TEAM_ID)" \
		"$(BUNDLE_NAME)/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
	codesign --force --options runtime --sign "$(SIGN_IDENTITY)" --team-id "$(TEAM_ID)" \
		"$(BUNDLE_NAME)/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
	codesign --force --options runtime --sign "$(SIGN_IDENTITY)" --team-id "$(TEAM_ID)" \
		"$(BUNDLE_NAME)/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
	codesign --force --options runtime --sign "$(SIGN_IDENTITY)" --team-id "$(TEAM_ID)" \
		"$(BUNDLE_NAME)/Contents/Frameworks/Sparkle.framework"
```

Then change the existing bundle-signing line (was line 50) to NOT use `--deep` (deep re-signing nested already-signed code is discouraged; sign the outer bundle only):

```makefile
	codesign --force --options runtime --sign "$(SIGN_IDENTITY)" --team-id "$(TEAM_ID)" "$(BUNDLE_NAME)"
```

Note: the inner version dir is `Versions/B` for current Sparkle 2.x. If signing fails with "no such file", run `ls "$(BUNDLE_NAME)/Contents/Frameworks/Sparkle.framework/Versions/"` and substitute the actual letter.

- [ ] **Step 3: Build the release bundle**

Run: `make export`
Expected: completes through `Signed and zipped to export/ProcessMonitor.zip`.

- [ ] **Step 4: Verify the framework is embedded and signature is valid**

Run:
```bash
codesign --verify --deep --strict --verbose=2 "ProcessMonitor.app" && \
ls "ProcessMonitor.app/Contents/Frameworks/Sparkle.framework"
```
Expected: `ProcessMonitor.app: valid on disk` / `satisfies its Designated Requirement`, and the framework directory lists.

- [ ] **Step 5: Smoke-test the app launches with Sparkle linked**

Run: `open ProcessMonitor.app` then confirm the menu-bar icon appears (cpu icon). Quit it (menu → Quit).
Expected: launches with no crash. (A crash here usually means rpath/embedding is wrong — fix before proceeding.)

- [ ] **Step 6: Commit**

```bash
rtk git add Makefile
rtk git commit -m "build: embed and sign Sparkle.framework in app bundle"
```

---

## Task 5: Generate EdDSA keys, fill public key into Info.plist

**Files:**
- Modify: `Info.plist` (`SUPublicEDKey` value)

- [ ] **Step 1: Locate Sparkle's generate_keys tool**

Run: `find .build/artifacts -name generate_keys -type f`
Expected: a path like `.build/artifacts/sparkle/Sparkle/.../bin/generate_keys`. Export it: `GEN_KEYS=<that path>`.

- [ ] **Step 2: Generate the keypair (stores private key in Keychain)**

Run: `"$GEN_KEYS"`
Expected: prints a base64 public key and stores the private key in the login Keychain under "Private key for signing Sparkle updates". COPY the printed public key.

If a key already exists it prints the existing public key instead — that's fine, use it.

- [ ] **Step 3: Put the public key into Info.plist**

Replace `REPLACE_WITH_ED_PUBLIC_KEY` in `Info.plist` with the copied base64 public key.

- [ ] **Step 4: Validate**

Run: `plutil -lint Info.plist`
Expected: `Info.plist: OK`

- [ ] **Step 5: Back up the private key (manual, out-of-band)**

Run: `find .build/artifacts -name generate_keys -execdir ./generate_keys --export-key ~/pm-sparkle-private-key.txt \;` is unreliable; instead export via the tool's documented flag: `"$GEN_KEYS" -x ~/pm-sparkle-private-key.txt`. Store that file in your password manager / secret store, then delete the local copy: `rm ~/pm-sparkle-private-key.txt`.
Expected: a private key file is produced and securely stored. **This must never be committed.**

- [ ] **Step 6: Commit (public key only)**

```bash
rtk git add Info.plist
rtk git commit -m "feat: add Sparkle EdDSA public key to Info.plist"
```

---

## Task 6: Add the `appcast` Makefile target

**Files:**
- Modify: `Makefile` (`.PHONY` line 1; add `appcast` target after `notarize`)

- [ ] **Step 1: Add appcast to .PHONY**

Change line 1 to include `appcast`:
```makefile
.PHONY: build run clean bundle release export notarize appcast install uninstall identities dev
```

- [ ] **Step 2: Add a variable for generate_appcast**

After the `SPARKLE_FRAMEWORK` variable (Task 4 step 1), add:
```makefile
# generate_appcast lives alongside generate_keys in the Sparkle artifact bin dir.
# Verify with: find .build/artifacts -name generate_appcast -type f
GENERATE_APPCAST = $(shell find .build/artifacts -name generate_appcast -type f | head -1)
```

- [ ] **Step 3: Add the appcast target after the `notarize` target (after line 72)**

```makefile
appcast:
	@test -f "$(EXPORT_DIR)/ProcessMonitor.zip" || (echo "Run 'make export && make notarize' first." && exit 1)
	@test -n "$(GENERATE_APPCAST)" || (echo "generate_appcast not found; run 'swift build' first." && exit 1)
	@echo "Generating signed appcast.xml from $(EXPORT_DIR)/ProcessMonitor.zip..."
	"$(GENERATE_APPCAST)" "$(EXPORT_DIR)"
	@echo ""
	@echo "Done. Upload these to the GitHub release:"
	@echo "  $(EXPORT_DIR)/ProcessMonitor.zip"
	@echo "  $(EXPORT_DIR)/appcast.xml"
```

`generate_appcast` reads every zip in `EXPORT_DIR`, signs with the Keychain private key, and writes `appcast.xml` there.

- [ ] **Step 4: Test the target end-to-end (requires Task 4/5 done)**

Run: `make export && make notarize && make appcast`
Expected: `export/appcast.xml` exists and contains a `<sparkle:edSignature>` attribute on the enclosure.

Run: `grep -c edSignature export/appcast.xml`
Expected: `1` (or more).

- [ ] **Step 5: Commit**

```bash
rtk git add Makefile
rtk git commit -m "build: add make appcast target (signed Sparkle feed)"
```

---

## Task 7: Wire UpdaterService into the app + add "Check for Updates" UI

**Files:**
- Modify: `ProcessMonitor/ProcessMonitorApp.swift:20-76`
- Modify: `ProcessMonitor/Views/ProcessListView.swift:396-415`

- [ ] **Step 1: Instantiate UpdaterService in the App**

In `ProcessMonitorApp.swift`, add a state object after line 27 (`@StateObject private var cleanupStore: CleanupStore`):
```swift
    @StateObject private var updaterService: UpdaterService
```

In `init()`, after `let cleanup = CleanupStore()` (line 43) add:
```swift
        let updater = UpdaterService()
```
and after `_cleanupStore = StateObject(wrappedValue: cleanup)` (line 49) add:
```swift
        _updaterService = StateObject(wrappedValue: updater)
```

- [ ] **Step 2: Pass it into the view**

In the `MenuBarExtra` content, add the parameter to `ProcessListView(...)` (after `cleanupStore: cleanupStore` on line 65):
```swift
                cleanupStore: cleanupStore,
                updaterService: updaterService
```

- [ ] **Step 3: Build to confirm the new param is required next**

Run: `swift build`
Expected: FAIL — `ProcessListView` has no parameter `updaterService`. (Confirms wiring; fixed in Step 4.)

- [ ] **Step 4: Accept the service in ProcessListView and add the UI**

In `ProcessListView.swift`, add a stored property alongside the other injected stores (near the top of the struct, matching the existing `let`/`@ObservedObject` style used for `cleanupStore`):
```swift
    @ObservedObject var updaterService: UpdaterService
```

Then in the footer `HStack` (lines 396-414), insert a "Check for Updates" button between the version `Text` (ends line 401) and the `Quit` button (line 403):
```swift
            Button(action: { updaterService.checkForUpdates() }) {
                Text("Check for Updates")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.quaternary.opacity(0.5)))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!updaterService.canCheckForUpdates)
```

- [ ] **Step 5: Build**

Run: `swift build`
Expected: PASS.

- [ ] **Step 6: Run the full test suite**

Run: `swift test`
Expected: PASS (existing tests + UpdaterServiceTests).

- [ ] **Step 7: Commit**

```bash
rtk git add ProcessMonitor/ProcessMonitorApp.swift ProcessMonitor/Views/ProcessListView.swift
rtk git commit -m "feat: wire silent updater into app + add Check for Updates button"
```

---

## Task 8: Mark the Homebrew cask auto_updates

**Files:**
- Modify: `Casks/devprocessmonitor.rb:2-3,15-17`

- [ ] **Step 1: Add auto_updates true + bump version/sha**

In `Casks/devprocessmonitor.rb`, bump `version` to `1.9.0` and update `sha256` to the new zip's hash (compute after the real notarized release: `shasum -a 256 export/ProcessMonitor.zip`). Add `auto_updates true` after the `app` stanza (line 17):
```ruby
  app "ProcessMonitor.app"

  auto_updates true
```

- [ ] **Step 2: Validate the cask syntax (if brew available)**

Run: `brew style --fix Casks/devprocessmonitor.rb || true`
Expected: no style errors (or auto-fixed).

- [ ] **Step 3: Commit**

```bash
rtk git add Casks/devprocessmonitor.rb
rtk git commit -m "chore(cask): auto_updates true; bump to v1.9.0"
```

---

## Task 9: Manual integration test — full update round-trip

No code; this validates the whole pipeline before publishing. Do this in a scratch dir.

- [ ] **Step 1: Build, notarize, and generate appcast for 1.9.0**

Run: `make export && make notarize && make appcast`
Expected: `export/ProcessMonitor.zip` (notarized) + `export/appcast.xml` (signed).

- [ ] **Step 2: Stage a higher fake version to prove auto-update**

Temporarily bump `Info.plist` to `1.9.1` / build `13`, rebuild + appcast into a separate `export2/` dir, and host both `appcast.xml` and the zip locally (`cd export2 && python3 -m http.server 8000`). Temporarily set `SUFeedURL` in the installed 1.9.0 app to `http://localhost:8000/appcast.xml`.

- [ ] **Step 3: Install 1.9.0 and observe**

Install the 1.9.0 build (`make install`), then trigger a check (footer button or wait for the scheduled interval). 
Expected: Sparkle silently downloads 1.9.1, installs, and relaunches; footer shows `v1.9.1`.

- [ ] **Step 4: Negative test — tampered zip**

Corrupt the 1.9.1 zip (append a byte), regenerate the http dir WITHOUT re-signing, trigger a check.
Expected: Sparkle rejects the update (signature mismatch); app stays on 1.9.0.

- [ ] **Step 5: Revert test scaffolding**

Restore `Info.plist` `SUFeedURL` to the GitHub URL and version to `1.9.0`/`12`. Delete `export2/`.
Expected: `rtk git diff Info.plist` shows no leftover localhost URL.

---

## Task 10: Document the new release flow in memory

**Files:**
- Modify (via memory tooling): `release-publish-flow.md`, `MEMORY.md`

- [ ] **Step 1: Update the release-publish-flow memory**

Append the new steps to the release flow: after `make notarize`, run `make appcast`; upload BOTH `ProcessMonitor.zip` and `appcast.xml` to the GitHub release (so `latest/download/appcast.xml` resolves). Document that the EdDSA private key lives in the Keychain + secret backup and must never be committed, and that auto-update is forward-only (pre-Sparkle users upgrade once manually).

- [ ] **Step 2: Verify MEMORY.md index still points correctly**

Confirm the `MEMORY.md` line for release-publish-flow still describes it accurately; update the hook text if needed.

---

## Self-Review Notes

- **Spec coverage:** Sparkle dep (T1), silent config + Info.plist keys (T2/T3), framework embedding (T4), keys (T5), appcast target (T6), app wiring + manual check UI (T7), cask auto_updates (T8), testing incl. signature negative + brew coexistence note (T9), release-flow docs (T10). All spec sections covered.
- **Forward-only caveat** and **version bump** are called out (spec implied; made explicit here).
- **Risk:** Sparkle `Versions/B` path and artifact paths can vary by Sparkle version — each such step includes a `find`/`ls` verification fallback rather than assuming.
- **No placeholders** except the deliberately-tracked `REPLACE_WITH_ED_PUBLIC_KEY` (filled in T5) and the real sha256 (computed at publish time in T8).
