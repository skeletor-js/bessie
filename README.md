<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/assets/bessie-banner-dark.gif">
  <source media="(prefers-color-scheme: light)" srcset=".github/assets/bessie-banner-light.gif">
  <img alt="Bessie. Your herd. One window." src=".github/assets/bessie-banner-light.gif" width="100%">
</picture>

<p align="center">
  <strong>A native Mac client for <a href="https://github.com/herdrdev/herdr">Herdr</a>.</strong><br>
  See every coding agent, shape its terminal workspace, and leave the work running.
</p>

<p align="center">
  <img alt="Pre-release" src="https://img.shields.io/badge/status-pre--release-f1ede3?style=flat-square&labelColor=050505">
  <img alt="macOS 14 or newer on Apple silicon" src="https://img.shields.io/badge/macOS-14%2B%20Apple%20silicon-f1ede3?style=flat-square&labelColor=050505&logo=apple&logoColor=white">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-f1ede3?style=flat-square&labelColor=050505&logo=swift&logoColor=white">
  <a href="https://github.com/herdrdev/herdr"><img alt="Herdr 0.8.0 protocol 19" src="https://img.shields.io/badge/Herdr-0.8.0%20%2F%20protocol%2019-f1ede3?style=flat-square&labelColor=050505"></a>
  <a href="LICENSE"><img alt="Apache-2.0 license" src="https://img.shields.io/badge/license-Apache--2.0-f1ede3?style=flat-square&labelColor=050505"></a>
</p>

![Bessie workspace with two live terminal panes](.github/assets/workspace.png)

Bessie is a graphical window onto Herdr, not another session manager. Herdr owns the live workspaces, tabs, panes, terminals, processes, agents, and durable session state. Bessie presents that state through native SwiftUI and AppKit, with every visible terminal rendered by [libghostty](https://github.com/Lakr233/libghostty-spm).

Quit Bessie and the Herdr work keeps running.

## Install status

**There is no public download yet.** The current `0.1.0` build `9` candidate is for local acceptance: it is Developer ID signed, but it has not been notarized or approved as a public release. Do not treat a source checkout or locally packaged app as a published binary.

The intended V1 release is direct distribution—not a Mac App Store submission—through `bessie.dev`, an immutable GitHub release, and verified Homebrew and/or `curl` install commands pointing at the same notarized archive.

Bessie currently supports **macOS 14 or newer on Apple silicon**. The app includes the compatible Apple-silicon Herdr `0.8.0` runtime (protocol `19`, source `346411fa21afd297f5ed3b3fa56f9e3fbf7654b7`). A compatible system or custom runtime is an explicit advanced option, not a setup requirement.

Building from source requires Swift 6 and the Xcode command-line tools.

## V1 highlights

- **One Herd across machines:** supervise local and SSH-connected Herdr sessions in one roster.
- **Useful status at a glance:** Needs you, Working, Done, Idle, and Unknown, plus pin, snooze, and hierarchy filters.
- **Real terminal workspaces:** create and shape Herdr workspaces, tabs, splits, and panes in native Ghostty terminals; start shells or supported coding agents.
- **Projects:** save reusable launch recipes for folders, tabs, pane layouts, and commands, then materialize them as ordinary Herdr work.
- **Fast navigation:** exact-pane routing, bounded Zen, an entity-aware command palette, a menu-bar companion, and native notifications.
- **Native fit and finish:** System, Bessie, and Catppuccin themes; density and terminal controls; bounded Ghostty configuration compatibility.
- **Operational surfaces:** startup or on-demand connections, first-run setup, Trouble diagnostics, secure Sparkle update UI, and a local CLI/MCP intent bus.

See [the complete V1 feature contract](docs/v1/features.md), including deliberate exclusions.

## First run

When an approved build is available to you:

1. Open Bessie and choose **This Mac** or **Remote over SSH**.
2. Select an absolute workspace folder.
3. Continue through the ownership and Herd-state primer.
4. Choose a notification policy and, if wanted, grant macOS permission.
5. Finish setup to open the first real terminal.

The included runtime is the default for **This Mac**. SSH setup uses your existing OpenSSH configuration and agent; Bessie stores the host alias and Herdr session name, not passwords or private keys.

Read [Getting started](docs/v1/getting-started.md) for local and SSH setup, Projects, notifications, terminal takeover, troubleshooting, and updates.

## The ownership boundary

Bessie may keep presentation preferences, Project recipes, and last-opened Herdr identifiers. Those identifiers are only hints and are revalidated against a fresh Herdr snapshot.

Herdr remains authoritative for all live work. Closing a Herdr workspace, tab, or pane is therefore a real destructive action and can stop its processes; Bessie confirms destructive cascades. Closing Bessie's window or quitting the app is different: it must not stop Herdr or pane processes.

Bessie uses Herdr's public JSON API, CLI surfaces, and terminal-session bridge. It does not copy Herdr's private protocol, maintain a shadow session database, or invent graphical approval actions that Herdr does not expose.

## Documentation

- [Documentation index](docs/README.md)
- [V1 features and non-goals](docs/v1/features.md)
- [Getting started](docs/v1/getting-started.md)
- [CLI, MCP, and intent-bus automation](docs/v1/automation.md)
- [Architecture](docs/v1/architecture.md)
- [Development and release operations](docs/v1/development.md)
- [Release engineering](docs/releases/README.md)
- [Credits](CREDITS.md) and [packaged asset attribution](Sources/BessieApp/Resources/ATTRIBUTION.md)
- [Apache-2.0 license](LICENSE)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)

## Development quick start

On an Apple-silicon Mac with macOS 14+, Swift 6, and the Xcode command-line tools:

```bash
swift package resolve
swift build
swift test
```

Run the repository checks from any supported development host:

```bash
./scripts/check.sh
```

The package pins `libghostty-spm` `1.3.2` and Sparkle `2.9.5`. Development may use the repository-local runtime and configuration under `.local/`; it must not silently install or overwrite a system Herdr installation.

Maintainers with the approved Developer ID identity can package and install the current local acceptance candidate from an interactive Mac GUI login:

```bash
./scripts/dogfood-install-signed.sh
```

That command writes `/Applications/Bessie.app`; it is not a public installer and does not make the unnotarized candidate a release.

`./scripts/mac-verify.sh` is a broad release gate, not the ordinary development command. Follow [AGENTS.md](AGENTS.md) before changing implementation or packaging behavior.

## Release status

Current candidate: **Bessie `0.1.0` build `11`**.

- Developer ID signed: **yes**
- Notarized: **no**
- Public download: **no**
- Public V1 release: **not yet**

Release packaging and Sparkle support are implemented, but publishing still requires the clean-machine, signing, notarization, update, and explicit release-approval gates in [the release documentation](docs/releases/README.md).
