# Process Monitor

A lightweight macOS menu bar app that monitors developer processes, groups child processes under their parent, and warns you when memory limits are exceeded.

## Features

- **Menu bar app** -- lives in the top bar, no dock icon
- **Process tree grouping** -- child processes (e.g., Java/Gradle spawned by Cursor) are grouped under their parent
- **Per-process memory limits** -- configurable thresholds with slider controls
- **Add/remove processes** -- fully customizable monitored process list
- **Memory warnings** -- both in-app visual indicators and macOS system notifications (with 5-minute cooldown)
- **Kill processes** -- kill an entire process group or individual child processes
- **Auto-refresh** -- polls every 5 seconds

## Default Monitored Processes

| Process        | Default Memory Limit |
|----------------|---------------------|
| Cursor         | 4 GB                |
| Proxyman       | 1 GB                |
| Java           | 4 GB                |
| Gradle         | 2 GB                |
| Android Studio | 6 GB                |
| Xcode          | 8 GB                |

## Requirements

- macOS 13.0 (Ventura) or later
- Swift 5.9+

## Build & Run

```bash
# Build and create the app bundle
make bundle

# Build and launch
make run

# Clean build artifacts
make clean
```

### Manual build

```bash
swift build
```

The built binary is at `.build/arm64-apple-macosx/debug/ProcessMonitor`. To get full functionality (system notifications), run it as an app bundle via `make run`.

## How It Works

1. Every 5 seconds, the app runs `ps -eo pid,ppid,rss,comm` to get all running processes
2. It builds a process tree using parent PID (ppid) relationships
3. Processes matching monitored patterns are identified as roots
4. Child processes are walked via the ppid chain and grouped under their monitored parent
5. Memory is aggregated across the entire group for limit checks
6. If a group exceeds its configured limit, an in-app warning and system notification are triggered

## Configuration

Click the gear icon in the popover to open Settings, where you can:
- Adjust memory limits per process using sliders
- Add new processes to monitor (with custom name and command patterns)
- Remove processes you no longer want to track
- Reset everything to the built-in defaults

Settings are persisted in UserDefaults.
