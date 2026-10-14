# Fresh

A small menu bar app for macOS that shows how much memory, CPU and GPU your Mac is using, which apps are using it, and lets you force stop the ones you don't need.

## Features

- **Menu bar readout.** Memory, CPU and GPU use at a glance. Choose which figures to show, with or without icons, and whether memory is a percentage, a size, or both.
- **Quick look.** Click the menu bar item for memory pressure, the top memory users, and a shortcut to the full monitor.
- **Full monitor window** with three tabs:
  - **Memory:** used, app, wired, compressed, cached and swap, measured the same way as Activity Monitor, plus macOS's own memory pressure level.
  - **CPU:** total, user and system load, per-core use (performance and efficiency cores shown separately), load averages and uptime.
  - **GPU:** overall, renderer and tiler use, and GPU memory.
- **Process list** with name, PID, user, parent, memory, CPU %, GPU % and threads. Sort by any column and search by name. By default, helper processes are grouped under the app they belong to, so an app's total includes all its helpers.
- **Force Stop.** Ends an app with all its helpers, or any single process. Fresh asks politely first (SIGTERM), then forces it (SIGKILL) after 2 seconds. Stopping a process owned by another user or by the system asks for an administrator password. Fresh refuses to stop the kernel, `launchd` or itself, and warns before stopping processes that would end your session, such as `WindowServer`.
- **Seven colour themes.**
- **Light on resources:** about 3% CPU and under 40 MB of memory with the window open.

Fresh makes no network connections and collects no data.

## Install

1. Download the latest `Fresh-<version>.dmg` from [Releases](../../releases).
2. Open it and drag **Fresh** to **Applications**.
3. Open Fresh from Applications. It runs in the menu bar and has no Dock icon.

Requires macOS 14 Sonoma or later, on Apple Silicon or Intel. Releases are signed with a Developer ID and notarized by Apple.

> Without administrator rights, macOS doesn't let other apps read memory and thread counts for system processes, so Fresh shows `—` for those cells.

## Build from source

You need Swift 6 or later. The Xcode Command Line Tools are enough; Xcode itself is optional.

```sh
swift run Fresh          # run a debug build
scripts/test.sh          # run the tests
scripts/bundle.sh        # build Fresh.app (universal, release)
```

`bundle.sh` signs with your Developer ID Application certificate if one is in the keychain, and otherwise signs ad hoc for local use.

To redraw the app icon after changing `scripts/make-icon.swift`, run `swift scripts/make-icon.swift`.

## Release

One-time setup:

1. Create a **Developer ID Application** certificate at [developer.apple.com](https://developer.apple.com/account/resources/certificates/list) and install it in your login keychain.
2. Create an App Store Connect API key with the Developer role, then store it for `notarytool`:
   ```sh
   xcrun notarytool store-credentials fresh-notary \
     --key AuthKey_XXXXXXXXXX.p8 --key-id XXXXXXXXXX --issuer <issuer-uuid>
   ```

For each release:

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
2. Run `scripts/release.sh`.

The script runs the tests, builds and signs the app, notarizes and staples it, then creates, signs, notarizes and staples `dist/Fresh-<version>.dmg`.

## Project layout

| Path | Contents |
|---|---|
| `Sources/MemoryCore` | Sampling and process control, with no UI: system memory, processes, CPU, GPU, app grouping and force stop |
| `Sources/Fresh` | The SwiftUI and AppKit app: menu bar item, monitor window, settings and themes |
| `Tests/MemoryCoreTests` | Unit tests, written with Swift Testing |
| `scripts` | Build, test, release and icon scripts |

## Credits

The theme palettes are adapted from [awesome-design-md](https://github.com/VoltAgent/awesome-design-md), © 2026 VoltAgent, used under the MIT License.

## License

[MIT](LICENSE) © 2026 devfoundry
