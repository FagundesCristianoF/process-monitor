# Storage Cleaner — Design Spec

**Date:** 2026-06-10  
**Status:** Approved

---

## Overview

A new "Storage" tab in the Settings sidebar that lets users run configurable shell commands to free up disk space. Ships with sensible defaults, supports full customisation, and blocks dangerous commands before they can be saved.

---

## Data Model

```swift
struct CleanupCommand: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String        // "iOS Simulators"
    var command: String     // "xcrun simctl delete unavailable"
    var isEnabled: Bool     // included in "Run All"
}
```

Persisted to `UserDefaults` key `"cleanupCommands"` as JSON, identical pattern to `ProcessConfigStore`.

### Default commands (seeded on first launch)

| Name | Command | Enabled by default |
|------|---------|-------------------|
| iOS Simulators | `xcrun simctl delete unavailable` | ✅ |
| iOS Simulator Data | `xcrun simctl erase all` | ❌ (destructive) |
| Homebrew | `brew cleanup --prune=all` | ✅ |
| npm cache | `npm cache clean --force` | ✅ |
| Docker | `docker system prune --volumes -f` | ✅ |
| Android Studio | `rm -rf ~/Library/Application\ Support/Google/AndroidStudio$(($(date +%Y)-1)).*` | ✅ |
| Claude VM Bundles | `rm -rf ~/Library/Application\ Support/Claude/vm_bundles` | ✅ |

---

## New Files

- `ProcessMonitor/Stores/CleanupStore.swift` — state, persistence, command execution
- `ProcessMonitor/Views/StorageCleanerView.swift` — tab UI + edit sheet

---

## `CleanupStore`

`ObservableObject`. Responsibilities:

- Load/save commands from UserDefaults (seed defaults on first load)
- `add`, `update`, `remove`, `reorder` commands
- `run(id:)` — execute one command; `runAll()` — run all enabled sequentially
- `validate(command:) -> ValidationResult` — safety check (see below)
- Publish per-command `RunState` (`.idle`, `.running`, `.success(output)`, `.failure(output)`)

Execution: `Process` with `/bin/zsh -c "<command>"`, stdout+stderr captured via `Pipe`, dispatched on a background `DispatchQueue`, results published on main queue.

---

## Validation

Applied when the user tries to **save** a command (Add or Edit sheet). Invalid commands cannot be saved — the Save button is disabled and an inline error message is shown.

### Blocked patterns (case-insensitive regex)

| Pattern | Reason |
|---------|--------|
| `\bchmod\b` | Permission modification |
| `\bchown\b` | Ownership modification |
| `rm\s+-[a-zA-Z]*r[a-zA-Z]*f\s+/(?:\s|$)` | `rm -rf /` (root wipe) |
| `rm\s+-[a-zA-Z]*r[a-zA-Z]*f\s+~(?:/\s*$|\s|$)` | `rm -rf ~` (home wipe) |
| `rm\s+-[a-zA-Z]*r[a-zA-Z]*f\s+\$HOME` | `rm -rf $HOME` variant |
| `rm\s+-[a-zA-Z]*r[a-zA-Z]*f\s+/\*` | `rm -rf /*` |
| `:\s*\(\s*\)\s*\{.*:\|:&\s*\}` | Fork bomb |
| `>\s*/dev/sd` | Raw device write |
| `dd\b.*of=/dev/` | `dd` to block device |

Validation returns `.ok` or `.blocked(reason: String)`. The reason string is shown inline beneath the command text field.

---

## UI — `StorageCleanerView`

Follows existing `DetailCard` / `DetailHeader` / `settingsRow` patterns from `SettingsView.swift`.

### Layout

```
┌─────────────────────────────────────────────────────┐
│ Storage Cleaner                        [Run All]  [+]│
├─────────────────────────────────────────────────────┤
│ DetailCard                                           │
│  ┌─ Row ────────────────────────────────────────┐   │
│  │ [icon] iOS Simulators                        │   │
│  │        xcrun simctl delete unavailable  ···  │   │
│  │                          [toggle] [✎] [▶]   │   │
│  │ (expanded on run: output / spinner)          │   │
│  └──────────────────────────────────────────────┘   │
│  ┌─ Row ── … ──────────────────────────────────┐    │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

### Row states

- **Idle** — toggle (include in Run All), edit (pencil) button, run (▶) button
- **Running** — `ProgressView` spinner replaces run button, edit/toggle disabled
- **Success** — green checkmark badge, expandable output area (collapsed by default)
- **Failure** — red ✗ badge, expandable output area auto-expanded

### Edit sheet

Reuses `AddProcessView`-style sheet (420 × 320):
- **Name** — TextField
- **Command** — multiline `TextEditor` (monospaced font)
- Inline validation error beneath command field (red caption text)
- Save button disabled while `ValidationResult == .blocked`

### "Run All" behaviour

- Runs enabled commands sequentially (not parallel) — avoids race conditions (e.g. Docker + npm simultaneously)
- Each command's row updates live as it transitions through states
- If one command fails, the rest still run

### Tab entry in `SettingsTab`

```swift
case storage
// label: "Storage"
// icon:  "sparkles"
// color: Color(red: 0.20, green: 0.75, blue: 0.55)  // teal-green
```

---

## Error Handling

- Command not found (e.g. `docker` not installed): captured in stderr, shown as failure with the output — no crash
- Long-running commands: no timeout; spinner stays until process exits
- UserDefaults encode failure: silently skipped (existing pattern in codebase)

---

## Out of Scope

- Scheduling / cron triggers
- Dry-run / preview mode
- Space-freed calculation
- Undo
