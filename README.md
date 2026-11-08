# ClashBar

## Switch history

Open **Switch History…** (⌘H) to inspect the last hour, 24 hours, 7 days or 30 days. Filter by controller or group, inspect full nested selection paths, and compare observed node selection durations, median test latency and failed tests. Path changes through different groups are retained even when the terminal node stays the same. Mode and group configuration changes are separate events.

History starts when recording is enabled. Polling may miss transitions between refreshes; timestamps indicate detection time. Sleep, disconnection and paused recording leave gaps. Load balancing has no single terminal node. Tests cover only the default exit; failures do not prove outages and selection duration is not uptime or traffic usage.

Records stay in the local application support directory at `History/history.sqlite`, readable only by the current user. The database contains no plaintext controller secrets or addresses, visited domains or connection details. It retains 30 days plus up to five daily recovery backups, which may contain older records. Pause recording or clear all controller history and backups from the history window. Removing a controller configuration does not automatically remove its history. History is not uploaded to the developer.

English | [简体中文](README.zh-CN.md)

A native macOS menu bar app for Clash-API cores (Clash, Mihomo, sing-box). At a glance it tells you which country or region your default exit is in, and lets you switch modes and nodes without opening a dashboard.

> Early development (v0.1.2). Builds are not yet signed with a Developer ID.

## Install

```sh
brew tap fangxuanxin/tap
brew trust fangxuanxin/tap
brew install --cask fangxuanxin/tap/clashbar
```

Or download `ClashBar.zip` from [Releases](https://github.com/fangxuanxin/ClashBar/releases). Because the app is not notarized yet, macOS blocks the first launch: open System Settings → Privacy & Security and click **Open Anyway**, or run `xattr -dr com.apple.quarantine /Applications/ClashBar.app`.

## Menu bar icon

| Icon | Meaning |
| --- | --- |
| Line-drawn cat + **US** / **JP** / **HK** … | Region of the default exit node |
| Cat only | Region could not be recognised from the node or group names |
| Faded cat | The current node did not answer the latency test, or still connecting |
| Cat + **→** | Direct mode, or the default group selects `DIRECT` |
| Cat + **×** | The default exit is `REJECT` |
| Cat + **!** | Controller unreachable, wrong secret, or not configured |

The default exit is the policy of the `MATCH` rule (rule mode) or `GLOBAL` (global mode), followed through every group's current selection down to the final node. The region is read from the final node's name first, then from the groups along the path: flag emoji (🇺🇸), uppercase codes as separate words (`US`, `JPN`), then Chinese / English place names (美国, 东京, Singapore …). `GB` is shown as `UK`. No group naming convention is assumed.

## Using it

Click the icon to open the menu:

- **Status card**: exit group, node, latency, mode, core version, and last update time.
- **Outbound Mode**: Rule / Global / Direct (⌘1 / ⌘2 / ⌘3).
- **Proxy Groups**: each group shows its current selection. Open a group to see its members and their latest latency, pick a member (Selector groups only), or test the group.
- **Test Latency** (⌘T), **Refresh** (⌘R), **Copy Exit Info** (⌘C).
- **Controller**: switch between saved controllers and automatic detection.
- **Settings…** (⌘,).

ClashBar never switches nodes on its own. It refreshes every 30 seconds by default, and each refresh tests only the current exit node with a single request.

## Controllers

Automatic mode tries saved controllers in order, including their individual secrets, and keeps the first reachable configuration until it fails or the network changes. Configurations sharing an IP remain separate. If all fail, ClashBar keeps them and retries periodically. Manual selection stays on the chosen controller.

When no controllers are saved, ClashBar looks for a controller automatically:

- `external-controller`, `external-controller-unix`, and `secret` in local configs (Clash Verge, ClashX Meta, Mihomo Party, `~/.config/clash`, `~/.config/mihomo`, …)
- `127.0.0.1:9090` / `9097`
- port `9090` / `9097` on the default gateway (for example a router running OpenClash)

If nothing works, Settings → Controllers opens and lists what was detected. A controller that needs a secret is marked **Needs secret**. Click **Add**, enter the secret, and use **Test Connection**. Controllers are stored in `~/Library/Application Support/ClashBar/controllers.json`, readable only by your user. Requests to the controller always bypass the system proxy.

## Build

Requirements: macOS 13+ and Xcode Command Line Tools. Full Xcode is optional. Direct builds download and verify a pinned Sparkle framework on first use, then use the cached copy.

```sh
Scripts/build.sh              # runs core tests, builds build/ClashBar.app
Scripts/install.sh            # regenerate cat icon, build, install to /Applications, remove old copies
Scripts/package.sh            # universal (arm64 + x86_64) build/ClashBar.zip + sha256
Scripts/make-icon.sh          # regenerate Resources/AppIcon.icns
```

Set `SIGN_IDENTITY="Developer ID Application: …"` to sign with hardened runtime. Without it the build is ad hoc signed, which works locally but Gatekeeper blocks it once downloaded. Public releases need Developer ID signing and notarization.

All build scripts share `Scripts/build-env.sh`. Optionally set `CLASHBAR_SSD_ROOT` (external working directory) and `CLASHBAR_SSD_UUID` (volume UUID) in the ignored `Scripts/build-storage.local.sh`. When that volume is mounted and writable, caches, temporary files and outputs go into its `ClashBar/build/`; otherwise they use the project's local `build/`. Source and Git stay in the project.

An `Xcode.app` inside the external working directory is selected automatically when available; otherwise the local tools are used. The system `xcode-select` setting is unchanged. Use `CLASHBAR_STORAGE=local Scripts/build.sh` to force local storage. An explicit `DEVELOPER_DIR` takes priority. Xcode must be installed separately; GUI caches are not relocated. Keep the drive connected throughout a build.

## Updates

Developer ID signed direct builds use Sparkle for automatic checks, downloads and installation, with stable and beta channels. Homebrew installations check their owning tap and offer a confirmed Brew upgrade. Development builds open Releases; `CLASHBAR_DISTRIBUTION=app-store` excludes Sparkle and external update controls for future store distribution.

Existing v0.1.1 installations need one manual upgrade. Production direct updates require Developer ID signing, notarization and publication of the signed feed; these have not been published as part of this implementation. See [update and release procedures](docs/updates.md) for candidate generation, key backups and integration tests.

## Layout

```
Sources/Core   Clash API client (HTTP + Unix socket), exit resolver, region detection, discovery, localization
Sources/App    menu bar item, status card, settings window, app state
Tests          dependency-free checks for the core (run by build.sh)
Resources      Info.plist, app icon, localized InfoPlist.strings
Scripts        build / install / package / icon generation
```

English and Simplified Chinese are built in. The app follows the system language by default; change it in Settings → General → Language.
