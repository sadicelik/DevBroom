# DevBroom

A macOS menu bar app that shows how much developer junk is eating your disk (Xcode DerivedData, simulators, node_modules, build folders, package caches, AI models) and clears it out safely. It lives in the menu bar next to your free space, has no Dock icon, and never removes anything until you press Clean and confirm.

<!-- screenshot -->

Requires macOS 14 or later. Universal binary (Apple silicon and Intel).

## Install

1. Download `DevBroom.zip` from the [latest release](https://github.com/sadicelik/DevBroom/releases/latest) and unzip it.
2. Move `DevBroom.app` to `/Applications` and open it.
3. DevBroom is ad-hoc signed, not notarized, so macOS blocks the first launch. Open **System Settings > Privacy & Security**, scroll to the message about DevBroom and click **Open Anyway**. This is needed only once.
   Alternatively, remove the quarantine flag in Terminal: `xattr -dr com.apple.quarantine /Applications/DevBroom.app`
4. At first launch DevBroom asks to send notifications (used only for the low disk space alert).
5. On the first scan macOS may ask to let DevBroom read Desktop, Documents or Downloads, because the default project scan root is your home folder. Denying only skips that folder. You can narrow the project scan roots in Settings.

Items moved to the Trash free their space only after you empty the Trash.

## What it cleans

Two kinds of row: **Rebuilds** (regenerates on its own) and **Re-download** (shows a warning and is never ticked by default).

| Category | Kind | Removal |
|---|---|---|
| Xcode DerivedData | Rebuilds | Trash |
| Package caches: npm, Yarn, pnpm, pip, uv, Homebrew, CocoaPods, Gradle, Gradle wrapper, Cargo, Go modules, Bun | Rebuilds | Trash |
| Package caches: Maven, Dart/Flutter | Re-download | Trash |
| App caches (`~/Library/Caches`) | Rebuilds | Trash |
| node_modules | Rebuilds | Trash |
| Project builds (HarmonyOS `build`, `oh_modules`, `.hvigor`; Android/Gradle `build`; Flutter `build`; Xcode `build`; Rust `target`; Python `.venv`) | Rebuilds | Trash |
| iOS DeviceSupport | Re-download | Trash |
| Wallpaper downloads | Re-download | Trash (only the `videos` folder contents) |
| AI model downloads (Hugging Face models in `~/.cache/huggingface/hub` and in `hub` folders inside projects) | Re-download | Trash |
| Old editor extensions (VS Code and Cursor) | Rebuilds | Trash |
| Simulator devices | Re-download | `xcrun simctl delete <udid>`, permanent |
| Simulator runtimes | Re-download | `xcrun simctl runtime delete <identifier>`, permanent |
| Docker | Re-download | `docker system prune -a -f`, permanent (volumes are never touched) |

Trash removal is recoverable until you empty the Trash. Permanent removals go through the vendor's own command after a second confirmation.

## Safety rules

1. **Never touches active work.** Anything used in the last 14 days (configurable) starts unticked and is tagged "recently used".
2. **No background scanning.** It scans only when the popover is open. While closed, the only work is a cheap free-space check.
3. **No waiting.** Opening the popover shows the last scan's results at once; sizes refresh row by row.
4. **Nothing removed without you.** Nothing is removed until you press Clean and confirm the summary.
5. **Build folders need a project marker.** A build folder is listed only when its project marker is next to it (for example `build.gradle`, `pubspec.yaml`, `Cargo.toml`). It is skipped when git tracks any file inside it. "Recently used" is measured over the whole project, meaning the nearest parent folder with a `.git` folder, so a recent edit in another module protects the build folder.
6. **Model downloads are never ticked.** AI model downloads are Re-download items, so they always start unticked and show the warning.
7. **Only old extension versions are offered.** For VS Code and Cursor, DevBroom lists a version only when a newer version of the same extension sits next to it. Anything listed in the editor's `extensions.json` is protected. If that file is missing, nothing is offered.

## Build from source

```
swift test
scripts/build-release.sh
```

The script builds a universal binary and writes `dist/DevBroom.app` and `dist/DevBroom.zip`.

## License

[MIT](LICENSE) (c) 2026 Sadi Celik
