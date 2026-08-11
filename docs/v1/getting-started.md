# Getting started with Bessie V1

Bessie is currently pre-release: there is no public download. These instructions apply to approved local builds on macOS 14 or newer on Apple silicon.

## Before you open it

For **This Mac**, Bessie includes the compatible Herdr runtime. You do not need to install a separate Herdr binary for the default path.

For **Remote over SSH**, first make sure the Mac can run non-interactive SSH to the target using your normal OpenSSH configuration and agent. Bessie accepts an SSH config host alias or `user@host`; it does not collect a password or private key.

If you want Bessie to launch a coding agent, that agent's CLI must already be available to Herdr in the target host's execution environment.

## First run: This Mac

1. Open Bessie and select **This Mac**.
2. Click **Choose Folder…** and select the absolute folder for the first workspace.
3. Wait for Bessie to validate the included Herdr runtime, start or join its named `bessie` session, connect to the public API, and obtain a fresh snapshot.
4. Click **Continue**. Read the ownership primer: Herdr runs the terminals; Bessie draws and supervises them.
5. Review the five rail states: Needs you, Working, Done, Idle, and Unknown.
6. Choose a notification policy. Grant macOS permission only if you want notifications.
7. Click **Finish and open terminal**.

The folder must be absolute. Setup cannot finish until the selected Herd is connected and a real terminal can be opened. Bessie does not silently install over a system Herdr runtime; the included compatible runtime is isolated inside the app.

## First run: Remote over SSH

1. Confirm this works from Terminal without an interactive password prompt:

   ```bash
   ssh <host-alias-or-user@host> true
   ```

2. In Bessie, select **Remote over SSH** and choose **Add Remote Herd…**.
3. Give the connection a clear name, enter the SSH host, and optionally enter the Herdr session name. A blank session uses the remote default.
4. Enter an **absolute path on the remote host** for the initial workspace.
5. Continue only after Bessie reports the selected remote Herd connected.
6. Finish the state and notification steps as above.

Bessie asks the remote Herdr CLI for its authoritative socket locations and forwards the public API and terminal-session sockets through SSH to private local paths. It does not expose a Herdr socket over TCP. A stopped remote Herdr session may need to be started on that host before Bessie can connect.

SSH connections default to on demand. In **Settings → Herds**, enable **Connect at launch** only for remotes you want contacted every time Bessie starts.

## Herds, workspaces, and selection

A **Herd** is one configured machine/session running Herdr. A **workspace** is Herdr-owned live work, typically rooted in a folder. A **tab** contains a pane layout. A **pane** is a real terminal running a shell or an agent.

- Use the connection scope to view one Herd or all Herds.
- Use the hierarchy to choose a workspace, tab, or pane.
- Manual scopes can show the selected tab, all tabs in a workspace, all workspaces in a Herd, or all Herds.
- Bessie persists that presentation choice, but revalidates it against fresh Herdr topology. If a saved tab, workspace, or connection is gone, the scope falls back rather than recreating it.
- Use the `+` actions to create workspaces, tabs, panes, shells, or supported agents.
- Closing a Herdr pane, tab, or workspace can stop processes. Graphical close behavior follows the bundled Herdr default and reconciles the resulting cascade from fresh state. Quitting Bessie is safe and leaves Herdr work running.

## Keyboard commands changed for V1

Bessie's Herdr topology commands now use the bundled Herdr 0.8 default `Ctrl-B` prefix grammar instead of duplicate native Mac topology chords. Press `Ctrl-B`, release it, then press the command key. There is no timeout. The focused terminal header shows `PREFIX`; `Ctrl-B r` enters persistent resize mode and shows `RESIZE`. Press `Esc` to cancel either mode. Press `Ctrl-B Ctrl-B` deliberately to send one literal `Ctrl-B` to the hosted shell or TUI.

Common commands include:

| Action | V1 sequence |
| --- | --- |
| New workspace | `Ctrl-B Shift-N` |
| New tab | `Ctrl-B c` |
| Previous / next tab | `Ctrl-B p` / `Ctrl-B n` |
| Split right / down | `Ctrl-B v` / `Ctrl-B -` |
| Focus pane | `Ctrl-B h/j/k/l` |
| Previous / next pane | `Ctrl-B Shift-Tab` / `Ctrl-B Tab` |
| Close pane | `Ctrl-B x` |
| Toggle pane zoom | `Ctrl-B z` |
| Resize pane | `Ctrl-B r`, then `h/j/k/l`; `Esc` exits |

Open **Bessie → Keyboard Reference…**, choose **Keyboard reference** in the command palette, or press `Ctrl-B ?` for the complete persistent list. The reference identifies Bessie graphical equivalents and sequences unavailable through protocol 19. In particular, `Ctrl-B [` cannot provide real Herdr copy mode in this release. Custom or remapped Herdr bindings and plugin bindings are not discoverable through protocol 19 and are not reflected by Bessie.

Native application shortcuts remain native: `Cmd+Shift+P` opens the command palette, `Option+Cmd+P` manages Projects, `Cmd+,` opens Settings, `Cmd+Shift+B` toggles the sidebar, and the documented Zen/agent shortcuts remain available. Existing terminal conveniences such as `Cmd+C`, `Cmd+V`, and Option-as-Alt retain their terminal behavior. `Cmd+W` once again closes the Bessie window through AppKit; it is not a pane, tab, or workspace close command. Closing the window and `Cmd+Q` quitting Bessie both leave Herdr and pane processes running.

## Projects: reusable setup, not live state

A **Project** is a Bessie-owned launch recipe. It remembers folders, tabs, pane splits, labels, and optional commands. It does not keep a workspace alive or mirror Herdr state.

### Create a Project

1. Open **Projects** and choose **New project**.
2. Name it, choose its target Herd, and choose the primary folder.
3. For a local Project, select multiple folders if panes need different roots. For SSH, enter absolute paths that exist on the target host.
4. Add tabs and split panes right or down. Drag dividers to set ratios.
5. Give each pane a label, initial folder, and optional one-line command. Do not put secrets in commands.
6. Review **What Bessie will run**, then save.

You can also capture a compatible live workspace into a recipe. Capture reads the fresh Herdr projection; it does not transfer ownership of the workspace.

### Launch a Project

Choose **Launch**, review the planned commands and target, then continue. Bessie materializes ordinary Herdr workspaces, tabs, and panes. If a running instance already exists, use **Open running workspace**. Partial failures are reported rather than hidden.

Deleting a Project moves only the recipe to Trash. It does not delete folders or close Herdr workspaces.

## Notifications

Policies are:

- **Off**
- **Needs you only**
- **Needs you and done** — includes settled Done/Idle transitions

Working never sends an interruption. Notification text does not include terminal content. Clicking a current notification routes to its exact connection and pane.

Permission is requested only when you click **Allow**. If permission was denied, use the **System Settings** button in Bessie or open macOS **System Settings → Notifications → Bessie**. **Send test notification** in Settings checks permission and delivery plumbing.

Snoozing a pane suppresses its pending and delivered Bessie notifications until it wakes. Use **Wake now** to restore ordinary routing immediately.

## Selecting and taking over a terminal

Click a pane in the hierarchy, The Herd, the menu-bar popover, a notification, or the command palette to make that exact pane current. The workspace surface shows a real Ghostty terminal, not a screenshot or terminal imitation.

Only one client can control a Herdr terminal pane at a time. If another client already controls it, Bessie opens the pane in read-only observe mode.

To take control:

1. Confirm you selected the intended pane and host.
2. Choose **Take over** on that pane.
3. Read the warning: the other terminal client will lose control.
4. Confirm only if that transfer is intentional.

Bessie reconnects with Herdr's public `--takeover` behavior only after that explicit confirmation. Input submitted while ownership is unresolved is held in order and forwarded once after the takeover produces a writable full terminal repaint.

Mouse forwarding is intentionally bounded in V1. Recognized Hermes panes receive Bessie's current synthesized SGR mouse path; other mouse-aware terminal applications are not guaranteed until Herdr exposes a negotiated public mouse capability upstream. Plain shells retain local text selection.

If keyboard input seems to target the wrong place, click the terminal surface, then reselect the pane from the hierarchy. Text fields, modal sheets, and IME composition intentionally keep their own input.

## The Herd, pinning, snoozing, and Zen

The Herd is the complete current agent roster across connected Herds:

- **Needs you** — waiting on a human.
- **Working** — actively progressing.
- **Done** — completion reported by Herdr.
- **Idle** — not currently working or asking.
- **Unknown** — Herdr cannot classify the state; do not treat it as attention.

Pin keeps a pane in the Pinned section. Snooze moves it to Snoozed and suppresses its notifications for the selected duration. Both are Bessie presentation preferences tied to an exact pane incarnation; they do not modify agent state in Herdr.

Use **Zen** for one focused real terminal. `Esc` exits Zen; `Cmd+Shift+Z` toggles it.

## Menu bar and command palette

The menu-bar companion shows Needs you and Working rows plus Done, Idle, and conditional Unknown totals. Settings controls whether it is visible, what contributes to its badge, and whether clicking a row focuses the pane or only opens Bessie.

Press `Cmd+Shift+P` for the entity-aware command palette. Search actions, connections, workspaces, tabs, panes, agents, and Projects. `Return` takes the primary route; `Cmd+Return` uses an alternate route when one is shown.

The palette's topology rows display the same `Ctrl-B` sequences used by the terminal prefix grammar. They run through the same fresh-snapshot resolver and public Herdr API dispatcher rather than a parallel Bessie shortcut implementation.

## Troubleshooting

### Setup does not continue

- Confirm the folder path is absolute and belongs to the selected host.
- Wait for the selected Herd to become connected.
- For SSH, test `ssh <host> true` from Terminal and resolve host-key, agent, VPN, or shell startup errors there first.
- A remote session that is not running may need to be started on the target host.

### Runtime or connection failure

Open **Trouble** or **Settings → Runtime** and read the reported stage. Bessie distinguishes missing or non-executable runtimes, incompatible Herdr versions/protocols, permission/filesystem failures, server-start failures, API failures, terminal-control failures, and loss of a previously healthy connection.

Use **Retry** after fixing the cause. Use **Run Setup Again** to choose another Herd or folder. Setup does not erase Herdr work. Disabled connection definitions remain saved for recovery, but Bessie requires at least one enabled connection.

### Remote is stale or disconnected

Bessie keeps stale content visibly stale; it does not present old data as live. Check SSH reachability and the remote Herdr session, then retry the connection. SSH Herds that are not configured for launch remain dormant until selected or required by a Project.

### Terminal is read-only

Another client owns the terminal controller. Continue observing, close the other client, or explicitly **Take over**. If no other client should exist, retry after the stale controller has gone away.

### Notifications do not appear

- Check Bessie's policy is not Off.
- Check macOS permission in System Settings.
- Make sure the pane is not snoozed.
- Use **Send test notification**.
- Remember that Working does not notify, and the default policy notifies only Needs you.

### Quitting and reopening

`Cmd+Q` quits Bessie, not Herdr. Reopening Bessie reconnects and resnapshots the live session. If a remembered pane no longer exists, Bessie reconciles to current topology instead of restoring fake state.

## Updates

Packaged production builds use Sparkle. In **Settings → Updates** you can control automatic checks and automatic download/install behavior, run **Check for Updates…**, and restart when a verified update is ready.

An unbundled `swift run` or development executable is intentionally ineligible for production updates. Until public distribution begins, there is no production appcast or public download to install.

When public distribution begins, Bessie will not silently replace itself outside the Sparkle flow. Downloaded updates are signature-checked; installation is exposed through Sparkle's UI and Bessie's explicit ready-to-restart state.

## Local automation

While Bessie is running, the `bessie` CLI and `bessie-mcp` can discover the local intent catalog. Start by asking the running app rather than copying a command list:

```bash
bessie intents
bessie status
bessie call <intent-id> --json '{"connection_id":"<id>"}'
```

The Unix socket exists only while Bessie runs. Destructive intents return a one-shot confirmation token with cascade text. CLI/MCP automation cannot grant macOS permissions, paste secrets, take over a terminal controller, or invent graphical approvals.

Read [CLI, MCP, and the intent bus](automation.md) before integrating automation. It documents discovery, result and exit behavior, MCP methods, connection scoping, fresh-revision requirements, and destructive confirmation.
