# DevBroom

A macOS menu bar app that shows how much developer junk is eating your disk (Xcode DerivedData, simulators, node_modules, caches) and clears it out safely. It lives in the menu bar next to your free space, has no Dock icon, and never removes anything until you press Clean and confirm.

<!-- screenshot -->

Requires macOS 14 or later. Universal binary (Apple silicon and Intel).

## Install

1. Download `DevBroom.zip` from the [latest release](https://github.com/sadicelik/DevBroom/releases/latest) and unzip it.
2. Move `DevBroom.app` to `/Applications` and open it.
3. DevBroom is ad-hoc signed, not notarized, so macOS blocks the first launch. Open **System Settings > Privacy & Security**, scroll to the message about DevBroom and click **Open Anyway**. This is needed only once.
   Alternatively, remove the quarantine flag in Terminal: `xattr -dr com.apple.quarantine /Applications/DevBroom.app`

## What it cleans

Two kinds of row: **Rebuilds** (regenerates on its own) and **Re-download** (shows a warning and is never ticked by default).

| Category | Kind | Removal |
|---|---|---|
| Xcode DerivedData | Rebuilds | Trash |
| Package caches (npm, Yarn, pnpm, pip, Homebrew, CocoaPods, Gradle) | Rebuilds | Trash |
| App caches (`~/Library/Caches`) | Rebuilds | Trash |
| node_modules | Rebuilds | Trash |
| iOS DeviceSupport | Re-download | Trash |
| Wallpaper downloads | Re-download | Trash (only the `videos` folder contents) |
| Simulator devices | Re-download | `xcrun simctl delete <udid>`, permanent |
| Simulator runtimes | Re-download | `xcrun simctl runtime delete <identifier>`, permanent |
| Docker | Re-download | `docker system prune -a -f`, permanent (volumes are never touched) |

Trash removal is recoverable until you empty the Trash. Permanent removals go through the vendor's own command after a second confirmation.

## Safety rules

1. **Never touches active work.** Anything used in the last 14 days (configurable) starts unticked and is tagged "recently used".
2. **No background scanning.** It scans only when the popover is open. While closed, the only work is a cheap free-space check.
3. **No waiting.** Opening the popover shows the last scan's results at once; sizes refresh row by row.
4. **Nothing removed without you.** Nothing is removed until you press Clean and confirm the summary.

## Build from source

```
swift test
scripts/build-release.sh
```

The script builds a universal binary and writes `dist/DevBroom.app` and `dist/DevBroom.zip`.

## License

[MIT](LICENSE) (c) 2026 Sadi Celik
