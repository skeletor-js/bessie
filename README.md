# Bessie

Bessie is a native macOS client for Herdr. Herdr owns the session, workspaces, tabs, panes, terminals, and processes; quitting Bessie must leave them running.

## Development checks

From the VPS source repository:

```bash
./scripts/check.sh
./scripts/mac-verify.sh
```

`mac-verify.sh` verifies the intentional mirror at `/Users/jordanstella/GitHub/bessie` and syncs without `rsync --delete`. It downloads the official Herdr 0.7.5 Apple Silicon release only to `.local/herdr/herdr`, verifies SHA-256 `37350546b0012555943b92eaf962665de4e264395baeb44227b8015e8ff5b0d6`, and uses per-run repository-local `HERDR_CONFIG_PATH`, `HERDR_SOCKET_PATH`, `XDG_CONFIG_HOME`, and `XDG_STATE_HOME` values. It runs Swift tests plus live ping/subscription/snapshot checks, exercises typed workspace/tab/pane/layout mutations, proves external Herdr CLI mutations converge into the running app, packages `dist/Bessie.app`, drives live terminal panes, launches a real shell and supported agent through the app, restarts only the isolated server, and proves the app reconnects. The agent defaults to `codex`, can be selected with `BESSIE_AGENT_KIND`, comes from the Mac login PATH, and receives no model prompt during verification. The run observes a semantic agent state and proves that agent survives Bessie quitting and reopening. It also analyzes native Workspace and Settings screenshots for the retained dark monochrome palette and measurable ASCII cowprint texture.

After a passing run, inspect the packaged artifact with:

```bash
ssh jordan-macbook 'open -na /Users/jordanstella/GitHub/bessie/dist/Bessie.app'
```

The verifier cleans up its isolated server, app, and controller processes before returning, so reopening afterward shows the honest Connect/setup state unless another compatible Herdr server is already running. Rerun `mac-verify.sh` for the complete connected live exercise; no global installation or path selection is required.

When connected, Bessie projects Herdr's authoritative workspace list, active tabs, focused pane, and recursive split layout into native SwiftUI. Every visible pane is a real `GhosttyTerminal` surface backed by `InMemoryTerminalSession` and an explicit Herdr control or observe process. Bessie never silently steals terminal ownership: observe is read-only, takeover requires confirmation, and unavailable controllers expose recovery actions. Herdr full and contiguous delta frames feed libghostty; frame gaps and controller exits freeze input until a new matching full repaint arrives. Controller identity survives ordinary SwiftUI updates, and removing a visible pane releases its controller without closing the Herdr pane or process.

Committed terminal input follows the public composite path: libghostty raw input uses `terminal.input`, intercepted special keys use `pane.send_keys`, paste uses `pane.send_input.text`, and wheel/page scrolling uses `terminal.scroll`. Inner-application mouse reporting, focus reporting, and Kitty keyboard-protocol handling are explicitly unsupported in V1. Shift-drag remains available for local terminal selection.

The verifier stops the Bessie and isolated Herdr processes it started. It refuses to reuse or stop another repository-local Herdr process and never touches a system Herdr installation or ordinary Herdr session.

## Product surfaces

Bessie's focused V1 navigation contains The herd, Attention, Workspaces, and Settings. Running workspaces appear directly under **Open** in the rail; selecting one opens its live terminal grid without a second, redundant Workspace navigation item. Connect handles setup and recovery states. The native SwiftUI/AppKit shell uses the supplied cow logo and ASCII cowprint tile, 244pt rail, compact topbars, tabs and pane headers, flat charcoal cards, thin borders, monochrome states, and a compact status line.

**The herd** lists real Herdr agent panes and their reported state. Filters appear only when agents exist; **Details** opens the selected agent's real Ghostty terminal, prompt composer, and concise pane facts. **Workspaces** is the chooser and manager, with create, open, rename, drag reorder, and confirmed close actions. Selecting an open workspace exposes tab and pane focus, create, split, resize, zoom, rename, drag reorder, movement across tabs or workspaces, and confirmed close actions. Split dividers resize panes directly while preserving Herdr as the authority. **New pane** opens a shell or starts a supported agent from Herdr's manifest-backed catalog. Unavailable agents include a concrete reason, semantic names remain unique, and a failed `agent.start` leaves the valid shell pane open. **Attention** contains only Herdr-reported needs-you/done panes and routes directly to the relevant pane.

Settings exposes cowprint contrast and motion, terminal font size, pane spacing, startup behavior, notification policy, permission status, and the pinned Herdr/libghostty versions. Notification permission is requested only through an explicit action. Needs-you and optional done transitions are deduplicated, suppressed for the active pane, and routed back to the exact workspace, tab, and pane. Cow motion respects Reduce Motion, terminal font size configures each Ghostty surface, pane gap changes the native split grid, and the last workspace is persisted only as a hint and revalidated against the next Herdr snapshot.

Each Mac verification run writes app-owned 1180 x 740 screenshots of the actual connected two-pane Workspace and Settings surfaces to `/Users/jordanstella/GitHub/bessie/dist/Bessie-window.png` and `Bessie-settings.png`. Workspace capture waits until both visible terminal controllers report live. Both PNGs are captured without Screen Recording permission and checked for regressions to a light/warm shell or a flat rail without measurable cowprint texture.
