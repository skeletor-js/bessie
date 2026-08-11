<p align="center">
  <strong>The native Mac layer for <a href="https://github.com/herdrdev/herdr">Herdr</a>.</strong><br>
  See every agent. Shape every workspace. Quit Bessie; the work keeps running.
</p>

<p align="center">
  <img alt="Pre-release" src="https://img.shields.io/badge/status-pre--release-f1ede3?style=flat-square&labelColor=050505">
  <img alt="macOS 14 or newer on Apple silicon" src="https://img.shields.io/badge/macOS-14%2B%20Apple%20silicon-f1ede3?style=flat-square&labelColor=050505&logo=apple&logoColor=white">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-f1ede3?style=flat-square&labelColor=050505&logo=swift&logoColor=white">
  <a href="https://github.com/herdrdev/herdr"><img alt="Herdr 0.8.0 protocol 19" src="https://img.shields.io/badge/Herdr-0.8.0%20%2F%20protocol%2019-f1ede3?style=flat-square&labelColor=050505"></a>
  <a href="LICENSE"><img alt="Apache-2.0 license" src="https://img.shields.io/badge/license-Apache--2.0-f1ede3?style=flat-square&labelColor=050505"></a>
</p>

Herdr keeps coding agents, terminals, and workspaces alive. Bessie adds the native Mac experience around it: a visual Herd, real terminal layouts, attention states, reusable Projects, notifications, navigation, settings, and diagnostics.

If you already use Herdr, Bessie does not ask you to adopt a second session system. It connects to the same durable work and makes it easier to see, shape, and return to.

## What Bessie adds to Herdr

- See your whole Herd across this Mac and remote machines in one roster.
- Know which agents need you without polling every terminal; filter by Needs you, Working, Done, Idle, or Unknown.
- Shape work visually with native tabs, splits, and panes, all rendered by [libghostty](https://github.com/Lakr233/libghostty-spm).
- Turn repeatable setups into Projects that launch folders, commands, tabs, and pane layouts as ordinary Herdr work.
- Jump directly to an agent or pane, focus with bounded Zen, search from the command palette, or check the Herd from the menu bar.
- Use the Mac features Herdr alone does not provide: native notifications, themes, connection setup, diagnostics, secure updates, and a local CLI/MCP intent bus.

The [V1 feature contract](docs/v1/features.md) lists the complete scope and deliberate exclusions.

## Never heard of Herdr?

[Herdr](https://github.com/herdrdev/herdr) is an open-source runtime for long-lived terminal workspaces and coding agents. It owns the sessions, processes, panes, and durable state, so the work survives when a client disconnects.

Bessie is designed to be the best way to use Herdr on a Mac. It includes the compatible Herdr runtime, walks you through local setup, renders every terminal with libghostty, and adds the native interface Herdr does not provide. You can start on this Mac without installing Herdr separately, then bring existing remote Herds into the same window over SSH.

Herdr remains available through its own CLI and public APIs. Bessie is not a walled garden around it; it is the native front door.

## Availability

Bessie is pre-release. There is no public binary yet, and a source checkout or locally packaged app is not a published release.

V1 targets **macOS 14 or newer on Apple silicon**. The app bundles the compatible Apple-silicon Herdr `0.8.0` runtime (protocol `19`, source `346411fa21afd297f5ed3b3fa56f9e3fbf7654b7`). Compatible system and custom runtimes remain explicit advanced options.

## Still Herdr underneath

Bessie is not a fork or a second runtime. Herdr remains the source of truth for every live workspace, tab, pane, terminal, process, agent, and durable session fact.

Bessie may keep presentation preferences, Project recipes, and last-opened Herdr identifiers. Those identifiers are only hints and are revalidated against a fresh Herdr snapshot.

Closing a Herdr workspace, tab, or pane is a real destructive action and can stop its processes. Closing Bessie's window or quitting the app does not.

Bessie uses Herdr's public JSON API, CLI surfaces, and terminal-session bridge. It does not copy Herdr's private protocol, maintain a shadow session database, or invent graphical approval actions that Herdr does not expose.

## Documentation

- [Documentation index](docs/README.md)
- [V1 features and non-goals](docs/v1/features.md)
- [Getting started](docs/v1/getting-started.md)
- [CLI, MCP, and intent-bus automation](docs/v1/automation.md)
- [Architecture](docs/v1/architecture.md)
- [Development and release operations](docs/v1/development.md)
- [Release engineering](docs/releases/README.md)

[Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [Credits](CREDITS.md) · [License](LICENSE)

## Development quick start

Building Bessie requires an Apple-silicon Mac running macOS 14+, Swift 6, and the Xcode command-line tools.

```bash
swift package resolve
swift build
swift test
```

```bash
./scripts/check.sh
```

The package pins `libghostty-spm` `1.3.2` and Sparkle `2.9.5`. Development may use the repository-local runtime and configuration under `.local/`; it must not silently install or overwrite a system Herdr installation.

Read [the development guide](docs/v1/development.md) before changing implementation or packaging behavior.
