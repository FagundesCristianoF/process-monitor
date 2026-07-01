# Storage Cleaner — Pre-Run Size Estimate — Design Spec

**Date:** 2026-07-01
**Status:** Approved

---

## Overview

The Storage Cleaner (Settings → Storage) currently only shows bytes freed *after* a command runs (via free-disk-space delta). This adds a **pre-run estimate** — a "~X" pill per command showing roughly how much disk space that command would reclaim, computed by measuring the folder(s) or tool cache the command targets, before the user hits Run.

Explicitly called out as out of scope in the original Storage Cleaner spec (`2026-06-10-storage-cleaner-design.md`); this spec supersedes that exclusion.

---

## Estimation Strategy

Estimates are **best-effort**, not exhaustive. Two mechanisms, tried in order:

### 1. Path-based (generic)

Applies to any command containing `rm -rf`, `rm -f`, or `find ... -delete`. The estimator extracts the target path argument(s) from the command string and re-runs a **read-only** sibling command that measures size instead of deleting:

- `rm -rf <paths>` / `rm -f <paths>` → verb swapped for `du -sck <paths> 2>/dev/null | tail -1` (grand total line, in KB)
- `find <path> ... -delete` → the leading path argument to `find` is measured directly with `du -sk`

This reuses the *exact same* path text (including escaped spaces, globs, `~` expansion) via the same `/bin/zsh -lc` invocation the real run uses (`unsetopt nomatch` included), so estimate and actual deletion always agree on what "the target" means. Because it's `du`/`find` (no `-delete`), nothing is modified.

Multiple `rm -rf` clauses in one command (e.g. Cursor Cache, which lists six cache subfolders) are summed via `du`'s own `-c` grand-total flag — one estimator call, one number.

### 2. Known-tool heuristics (seeded non-path commands only)

A small fixed lookup, matched by scanning the command string for a known tool invocation:

| Command contains | Estimate via |
|---|---|
| `brew cleanup` | `du -sk $(brew --cache)` |
| `npm cache clean` | `du -sk $(npm config get cache)` |
| `docker system prune` | `docker system df` → parse the `Reclaimable` column |
| `pod cache clean` | `du -sk ~/Library/Caches/CocoaPods` |
| `xcrun simctl delete unavailable` | sum `du -sk` over device dirs listed by `xcrun simctl list devices unavailable -j` |
| `xcrun simctl erase all` | sum `du -sk` over all device dirs from `xcrun simctl list devices -j` |

This list is **not extensible via UI** — it's a fixed table matched against known seeded commands. Custom user-added commands that don't hit the path-based case (mechanism 1) get no estimate.

### 3. No estimate

- Read-only `Scan:` commands (they delete nothing) — always nil, no pill.
- Any command matching neither mechanism above (custom user commands with no `rm`/`find`, e.g. a hypothetical `defaults delete ...`) — nil, no pill. This is a known gap, not a bug: the row simply shows no size pill, same as today.

If any estimator command fails (tool not installed, `du` errors, malformed path) → treated as nil, no pill, no error surfaced (this is advisory data, not a run result — failures here should never look like a cleanup failure).

---

## State & Data Flow

`CleanupStore` adds:

```swift
@Published private(set) var estimatedBytes: [UUID: Int64?] = [:]
// value: nil = "not yet computed", Int64 = last computed estimate (0 counts as a valid answer)
// key absent = "no estimator applies to this command" (permanent, no pill ever)
```

- `refreshEstimates()` — called from `StorageCleanerView.onAppear`. For each **enabled** command with an applicable estimator, sets `estimatedBytes[id] = nil` (pending) synchronously, then dispatches the actual `du`/tool-check work to a **dedicated background queue**, separate from the existing cleanup-run queue — estimating never blocks or delays the Run button.
- Estimates run **concurrently** across commands (unlike cleanup runs, which are sequential) since `du`/`docker system df` are read-only and safe to overlap.
- An `isEstimating` flag guards against re-entrancy: if `refreshEstimates()` is called again while a previous pass is still in flight (e.g. user flips tabs quickly), the second call is a no-op. Next `onAppear` after the in-flight pass completes will refresh again — satisfies "recompute live every time the tab is shown" without stacking duplicate scans.
- Once a command actually runs (`performRun`), its entry in `estimatedBytes` is irrelevant for display — `freedBytes`/`runState` take priority in the UI (see below). The estimate isn't cleared but simply stops being read for that row.

---

## UI — `StorageCleanerView`

Row pill logic (`CleanupCommandRow`), evaluated in this order:

1. `runState == .success(...)` and `freedBytes` present → existing green **"Freed X"** / **"Nothing to free"** pill (unchanged behavior — actual result always wins over estimate).
2. Otherwise, if `estimatedBytes[id]` exists as a key:
   - value `nil` → gray **"Calculating…"** pill
   - value `Int64` → gray **"~X"** pill (`ByteCountFormatter`, same style as the freed pill but neutral gray tint, not green, to visually distinguish estimate from confirmed result)
3. Otherwise (no key, no estimator applies) → no pill, same as today.

No changes to Run All / Run behavior, validation, or persistence format.

---

## Error Handling

- Estimator subprocess failures (missing tool, permission denied, bad glob) are swallowed → nil result, no pill, no user-facing error. This mirrors "Out of Scope: Space-freed calculation" being advisory-only — it must never be mistaken for a cleanup failure.
- No timeout on estimator commands (matches existing `execute()` behavior for real runs) — a slow `du` on a huge DerivedData folder just delays that one pill, doesn't block the row or other rows.

---

## Testing

- Manual: open Storage tab, verify path-based seeded commands (Xcode DerivedData, Gradle Caches, Android Studio, Claude VM Bundles, Cursor Cache) show a "~X" pill that transitions from "Calculating…".
- Manual: verify known-tool commands (Homebrew, npm cache, Docker, CocoaPods, both `xcrun simctl` entries) show estimates.
- Manual: verify `Scan:` commands and a freshly-added custom command with no `rm`/`find` show no pill.
- Manual: run a command, confirm its pill switches from "~X" (gray) to "Freed X" (green) and stays that way until the tab is revisited (which re-triggers estimation for the *other* not-yet-run rows, but a just-run row's `runState`/`freedBytes` still takes priority per the ordering above).
- Unit test: path/verb-swap extraction function (`rm -rf ~/foo/*` → `du -sck ~/foo/* ... | tail -1`, multi-path Cursor Cache case, `find ... -delete` case) — pure string transform, easily testable without shelling out.

---

## Out of Scope

- Extensible/user-editable known-tool heuristic table (fixed list only).
- Estimates for arbitrary custom commands with no recognizable delete verb.
- Caching estimates across app launches (recomputed fresh each time the tab is shown, per approved design).
- Progress indication finer than "Calculating…" (no percentage, no per-path breakdown in the row).
