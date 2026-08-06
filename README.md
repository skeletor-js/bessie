<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/assets/bessie-banner-dark.gif">
  <source media="(prefers-color-scheme: light)" srcset=".github/assets/bessie-banner-light.gif">
  <img alt="Bessie. Your herd. One window." src=".github/assets/bessie-banner-light.gif" width="100%">
</picture>

<p align="center">
  <strong>A native Mac client for <a href="https://github.com/herdrdev/herdr">Herdr</a>.</strong><br>
  Workspaces, terminals, and coding agents in one window. Quit Bessie and they keep running.
</p>

<p align="center">
  <img alt="Release candidate 0.1.0 RC3" src="https://img.shields.io/badge/status-0.1.0--rc.3-f1ede3?style=flat-square&labelColor=050505">
  <img alt="macOS 14 or newer" src="https://img.shields.io/badge/macOS-14%2B-f1ede3?style=flat-square&labelColor=050505&logo=apple&logoColor=white">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-f1ede3?style=flat-square&labelColor=050505&logo=swift&logoColor=white">
  <a href="https://github.com/herdrdev/herdr"><img alt="Herdr 0.7.5" src="https://img.shields.io/badge/Herdr-0.7.5-f1ede3?style=flat-square&labelColor=050505"></a>
  <a href="https://github.com/Lakr233/libghostty-spm"><img alt="libghostty 1.3.2" src="https://img.shields.io/badge/libghostty-1.3.2-f1ede3?style=flat-square&labelColor=050505"></a>
</p>

![Bessie workspace with two live terminal panes](.github/assets/workspace.png)

Bessie is a graphical client, not a second session manager. [Herdr](https://github.com/herdrdev/herdr) remains the authority for workspaces, tabs, panes, terminal processes, and agent state. Bessie subscribes to that state and turns it into a native SwiftUI and AppKit interface backed by real [libghostty](https://github.com/Lakr233/libghostty-spm) terminals.

`0.1.0-rc.3` is the verified foundation preview. Real V1 adds the compatible Herdr runtime inside the signed app, first-run onboarding and Trouble, and Native Bessie Projects for reusable workspace blueprints.

## What works

- **Live workspaces:** create, rename, reorder, open, and close Herdr workspaces.
- **Tabs and panes:** split, resize, zoom, focus, reorder, and move panes across tabs or workspaces.
- **Real terminals:** every visible pane is a Ghostty surface connected to a Herdr terminal controller.
- **Coding agents:** start supported agents from Herdr's manifest-backed catalog and follow their reported state.
- **Attention routing:** jump straight to panes that need you or have finished.
- **Safe ownership:** observe a terminal without taking control, then confirm before takeover.
- **Native notifications:** opt in from Settings; blocked and completed work routes back to the exact pane.
- **Seamless local startup:** Bessie starts and reopens its own detached Herdr session when needed.
- **One unified herd:** local and saved SSH Herdr sessions stay connected together, so their agents appear in one roster without a connection switcher.
- **Process survival:** close and reopen Bessie without killing the shells and agents Herdr owns.
- **Two app icons:** choose the dark or light icon in Settings. Bessie reapplies it to the Dock and app switcher at launch.

## Requirements

- Apple silicon Mac running macOS 14 or newer
- Herdr 0.7.5 for the current foundation preview; real V1 includes the compatible runtime
- An agent CLI on your login `PATH` if you want to start an agent
- Xcode command-line tools and Swift 6 only when building from source

Bessie checks `BESSIE_HERDR_PATH`, the current `PATH`, `~/.local/bin/herdr`, and the repository-local `.local/herdr/herdr`, in that order. It then opens the named Herdr session `bessie`, starting it as a detached background server if necessary. Other Herdr sessions are not reused, stopped, or modified.

## Install the release candidate

The current candidate is source-built and ad hoc signed. It is not notarized yet.

From a checkout on the Mac:

```bash
./scripts/package-app.sh
ditto dist/Bessie.app /Applications/Bessie.app
open /Applications/Bessie.app
```

The bundle reports version `0.1.0` with build number `3`. This branch is the `0.1.0-rc.3` acceptance candidate.

## Using Bessie

1. Open Bessie. It starts the local `bessie` Herdr session and reconnects every saved SSH connection.
2. Open **The herd** to see local and remote agents together. Opening a card routes workspace and terminal actions to the connection that owns it.
3. Use **Workspaces** and **New pane** to open shells or start supported agents in the current workspace context.
4. Open **Attention** when work needs you.

The herd retains every Herdr-tracked agent across every workspace, including idle, blocked, done, and temporarily unknown agents—not only agents currently working.

Bessie never silently steals a terminal controlled by another client. A conflicting pane opens read-only. Use **Take over terminal control** only when you mean it.

The background server survives Bessie quitting, so reopening the app returns to the same shells and agents. Bessie ignores an inherited generic `HERDR_SOCKET_PATH` so an unrelated shell cannot redirect it; diagnostics can opt into a socket only with `BESSIE_HERDR_SOCKET_PATH`. Set `BESSIE_HERDR_AUTOSTART=0` only when diagnosing startup manually.

## Remote VPS sessions

Open **Settings → Connections → Add SSH connection**, enter an SSH config host (or `user@host`), and optionally name a Herdr session. Leave the session blank for the remote default session. Every configured connection participates in The herd automatically; there is no connection switcher.

Bessie asks the remote `herdr status --json` command for the authoritative Unix-socket path, then forwards both public Herdr Unix sockets to private sockets under `/tmp` with `0700` directory permissions. A stopped remote session must be started on its host first. No Herdr socket is exposed over TCP. Authentication remains entirely in OpenSSH configuration and the user's SSH agent; Bessie stores the host alias and session name but never a password or private key. See [Herdr's persistence and remote-access guide](https://herdr.dev/docs/persistence-remote/).

## Settings

Settings covers:

- local and SSH Herdr connections included in one herd
- dark or light Dock icon
- cowprint contrast and motion
- terminal font size
- pane spacing
- startup behavior
- notification policy and permission
- pinned Herdr and libghostty versions

Notification permission is requested only after you click **Allow notifications**.

![Bessie Settings](.github/assets/settings.png)

## Test this candidate

The highest-value acceptance pass is short:

- drag workspaces and tabs in both directions
- resize a split using the divider
- move a pane to another tab and another workspace
- open a pane in observe mode, then confirm takeover
- allow notifications and follow one back to its pane
- start a shell and a Codex agent
- quit Bessie, reopen it, and confirm both are still there
- switch between the dark and light app icons

Record anything surprising, even if it is only a rough edge. This candidate remains the foundation preview; it is not the complete V1 until bundled-runtime/onboarding/Trouble and Native Projects pass the integrated release contract.

## Keyboard shortcuts

Bessie uses Ghostty-style native macOS Command shortcuts. Product chords (split, close pane, tabs, rail, palette, …) use **one window-scoped policy** — they do not change based on whether the terminal or chrome currently has focus. They only yield to ordinary text fields, IME composition, and modal sheets.

Press `Cmd+Shift+P` to open the searchable command palette (also **Bessie → Command Palette…**). Browse every action and its shortcut there. In the palette: `↑`/`↓` move, `Return` runs, `Cmd+Return` runs the alternate route when present, `Esc` closes.

### Product / topology
- `Cmd+N` new workspace · `Cmd+T` new tab · `Cmd+1`–`9` jump to tab
- `Cmd+[` / `Cmd+]` cycle **panes** · `Cmd+Shift+[` / `Cmd+Shift+]` cycle **tabs**
- `Cmd+W` close **pane** (confirm) · `Cmd+Shift+W` close workspace · close tab via palette
- `Cmd+D` split right · `Shift+Cmd+D` split down · `Cmd+Shift+Enter` zoom pane
- `Option+Cmd+Arrow` focus pane · `Shift+Option+Cmd+Arrow` swap · `Control+Cmd+Arrow` resize
- `Cmd+Shift+J` / `Cmd+Shift+K` walk the rail · `Cmd+Shift+B` toggle rail · `Cmd+,` Settings
- `Option+P` Projects · `Cmd+Shift+G` workspaces · `Cmd+Shift+Z` Zen · `Option+Cmd+N` next needs-you
- `Shift+Option+Cmd+[` / `]` previous/next agent · `Esc` exits Zen

### Terminal-focused (Ghostty-style)
- `Cmd+B` → one byte `0x02` (Herdr prefix; same as your Ghostty `cmd+b=text:\\x02`)
- `Cmd+G` → delete entire line (`Ctrl-A` + `Ctrl-K`) — Ghostty uses ⌘G for search-next; Bessie has no terminal search yet
- `Cmd+Backspace` → kill to start of line (`Ctrl-U`) · `Cmd+Delete` → kill to end (`Ctrl-K`)
- `Cmd+←` / `Cmd+→` → beginning / end of line
- `Option+←` / `Option+→` → word left / right (ESC b / ESC f)
- `Cmd+C` copy selection, or `0x03` interrupt if nothing selected
- `Cmd+V` paste · `Cmd+A` select all · `Cmd+K` clear scrollback
- `Cmd+↑` / `Cmd+↓` jump to previous/next prompt
- Ordinary typing and Control sequences stay with the terminal

System chords `Cmd+Q` / `H` / `M` / `` ` `` always pass through to AppKit.

## How it is built

Bessie keeps only presentation preferences and a last-workspace hint. It does not persist a shadow copy of Herdr's session. Snapshot reconciliation is authoritative, and all mutations go through Herdr's public actions.

Terminal controllers use bounded reconnect delays of `0.25`, `0.5`, `1`, `2`, and `4` seconds. Input stays frozen until a matching full repaint makes the controller ready again. Observe mode is read-only; takeover is explicit.

See the [V1 plan](docs/plans/2026-07-31-bessie-v1.md) and [Mac verification report](docs/reports/mac-v1-alpha.md) for the full contract and evidence.

## Development

Run the static checks on any machine:

```bash
./scripts/check.sh
```

Run the native acceptance suite from the VPS repository with the configured Mac mirror:

```bash
BESSIE_AGENT_KIND=codex ./scripts/mac-verify.sh
```

The verifier:

- syncs to the Mac without destructive mirroring
- isolates Herdr config, state, and sockets under the repository
- runs the Swift test suite
- builds, packages, signs, and validates `dist/Bessie.app`
- exercises live Herdr, libghostty, shell, and agent flows
- proves Bessie can start a detached named Herdr session without touching the default session
- tests reconnect and survival across app reopen
- captures and checks native Workspace and Settings screenshots
- removes only the processes and state it created

It refuses to reuse or stop an unrelated Herdr server.

## V1 boundaries

This candidate does not include graphical remote sessions, worktrees, plugins, IDE surfaces, or generic activity feeds. Remote Herdr remains available through `herdr --remote`. Inner-terminal mouse and focus reporting and Kitty keyboard protocol handling remain outside the verified V1 baseline. Shift-drag still provides local terminal selection.

The app is ad hoc signed for local testing. Public distribution still needs release signing and notarization.
