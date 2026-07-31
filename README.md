# Bessie

Bessie is a native macOS client for Herdr. Herdr owns the session, workspaces, tabs, panes, terminals, and processes; quitting Bessie must leave them running.

## Development checks

From the VPS source repository:

```bash
./scripts/check.sh
./scripts/mac-verify.sh
```

`mac-verify.sh` verifies the intentional mirror at `/Users/jordanstella/GitHub/bessie` and syncs without `rsync --delete`. It downloads the official Herdr 0.7.5 Apple Silicon release only to `.local/herdr/herdr`, verifies SHA-256 `37350546b0012555943b92eaf962665de4e264395baeb44227b8015e8ff5b0d6`, and uses per-run repository-local `HERDR_CONFIG_PATH`, `HERDR_SOCKET_PATH`, `XDG_CONFIG_HOME`, and `XDG_STATE_HOME` values. It runs Swift tests plus live ping/subscription/snapshot checks, exercises typed workspace/tab/pane/layout mutations, proves external Herdr CLI mutations converge into the running app, packages `dist/Bessie.app`, drives live terminal panes, launches a real shell through the app, restarts only the isolated server, and proves the app reconnects. It also analyzes the packaged app's native screenshot for the retained dark monochrome palette and measurable ASCII cowprint texture. It queries `server.agent_manifests` and runs the agent-start live path only when a supported executable is present on the Mac PATH; otherwise it records that missing prerequisite instead of claiming agent success.

After a passing run, inspect the packaged artifact with:

```bash
ssh jordan-macbook 'open -na /Users/jordanstella/GitHub/bessie/dist/Bessie.app'
```

The verifier cleans up its isolated server, app, and controller processes before returning, so reopening afterward shows the honest Connect/setup state unless another compatible Herdr server is already running. Rerun `mac-verify.sh` for the complete connected live exercise; no global installation or path selection is required.

When connected, Bessie projects Herdr's authoritative workspace list, active tabs, focused pane, and recursive split layout into native SwiftUI. Every visible pane is a real `GhosttyTerminal` surface backed by `InMemoryTerminalSession` and one writable `herdr terminal session control` process. Herdr full and contiguous delta frames feed libghostty; frame gaps and controller exits freeze input until a new matching full repaint arrives. Controller identity survives ordinary SwiftUI updates, and removing a visible pane releases its controller without closing the Herdr pane or process.

Committed terminal input follows the public composite path: libghostty raw input uses `terminal.input`, intercepted special keys use `pane.send_keys`, paste uses `pane.send_input.text`, and wheel/page scrolling uses `terminal.scroll`. Inner-application mouse reporting, focus reporting, and Kitty keyboard-protocol handling are explicitly unsupported in V1. Shift-drag remains available for local terminal selection.

The verifier stops the Bessie and isolated Herdr processes it started. It refuses to reuse or stop another repository-local Herdr process and never touches a system Herdr installation or ordinary Herdr session.

## Product surfaces

Bessie's focused V1 navigation contains The herd, Attention, Workspaces, and Settings. Running workspaces appear directly under **Open** in the rail; selecting one opens its live terminal grid without a second, redundant Workspace navigation item. Connect handles setup and recovery states. The native SwiftUI/AppKit shell uses the supplied cow logo and ASCII cowprint tile, 244pt rail, compact topbars, tabs and pane headers, flat charcoal cards, thin borders, monochrome states, and a compact status line.

**The herd** lists real Herdr agent panes and their reported state. Filters appear only when agents exist; **Details** opens the selected agent's real Ghostty terminal, prompt composer, and concise pane facts. **Workspaces** is the chooser and manager, with create, open, rename, move, and confirmed close actions. Selecting an open workspace exposes tab and pane focus, create, split, resize, zoom, rename, reorder, and confirmed close actions. **New pane** opens a shell or starts a supported agent from Herdr's manifest-backed catalog. Unavailable agents include a concrete reason, semantic names remain unique, and a failed `agent.start` leaves the valid shell pane open. **Attention** contains only Herdr-reported needs-you/done panes and routes directly to the relevant pane.

Settings exposes cowprint contrast and motion, terminal font size, pane spacing, startup behavior, and the pinned Herdr/libghostty versions. Cow motion respects Reduce Motion, terminal font size configures each Ghostty surface, pane gap changes the native split grid, and the last workspace is persisted only as a hint and revalidated against the next Herdr snapshot. Deferred notification controls are not presented as working settings.

Each Mac verification run writes an app-owned 1180 x 740 screenshot of the actual launched two-pane window to `/Users/jordanstella/GitHub/bessie/dist/Bessie-window.png`. Capture waits until both visible terminal controllers report live, validates the PNG without Screen Recording permission, and rejects regressions to a light/warm shell or a flat rail without measurable cowprint texture.
