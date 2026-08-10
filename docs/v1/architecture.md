# Bessie V1 architecture

This is the current V1 architecture, not a restatement of the historical implementation plans.

## Ownership and data flow

Bessie is a native macOS client for Herdr, never a replacement runtime or fork.

| Owner | Authoritative or durable data |
| --- | --- |
| Herdr | Every live workspace, tab, pane, layout, terminal, PTY, process, agent identity/state, focus fact, and server-owned scrollback |
| Bessie | Presentation/preferences, connection definitions, runtime selection, pane pin/snooze presentation, last-opened hints, and versioned Project recipes |
| macOS/frameworks | Window and responder mechanics, notification permission/delivery, and Sparkle update mechanics |

```text
SwiftUI product UI + AppKit window/focus/terminal hosting
       │
       ├── Bessie-owned settings, Projects, notifications, updates, intents
       └── BessieCore (pure Swift)
              ├── public Herdr JSON socket API
              ├── public `herdr terminal session` NDJSON bridge
              └── local Unix sockets or SSH-forwarded Unix sockets
                         │
                         ▼
Herdr server: topology, terminals, PTYs, processes, agents, history
                         │ ANSI viewport frames
                         ▼
GhosttyTerminal / InMemoryTerminalSession: native rendering surface
```

Bessie can keep transient projections and optimistic navigation presentation, but never a competing durable session. For each herd it subscribes to events, buffers while requesting `session.snapshot`, installs that snapshot as the complete projection, and snapshots again if events raced bootstrap. Later events are invalidation hints, not a globally revisioned transaction log; Bessie coalesces them and resnapshots. Mutations use public Herdr actions and reconcile from responses plus fresh snapshots. Quitting releases Bessie clients but does not stop Herdr or pane processes.

`BessieCore` owns typed models, public transports, compatibility, sequencing, projections, Projects, persistence, and intent contracts. `BessieApp` owns the SwiftUI/AppKit shell and narrow libghostty host. `bessie` and `bessie-mcp` call the running app's intent socket rather than creating another route to live state.

## Local and SSH connections

A Bessie connection names a local or SSH herd, optional Herdr session, enabled state, and launch policy. Enabled connections contribute to one roster. On-demand connections start only when selected or targeted by a Project.

### Local

The canonical local connection uses Herdr's named `bessie` session. Bessie ignores a generic inherited `HERDR_SOCKET_PATH`; only its explicit diagnostic override may redirect the connection. After resolving and validating a runtime, Bessie asks for server status, starts that named server detached when allowed and needed, checks version/protocol identity, and connects to the public JSON Unix socket. The detached Herdr server survives Bessie.

### SSH

Bessie stores a validated SSH host alias or `user@host` and session name, not a password or private key. Authentication remains in OpenSSH configuration and the user's agent.

1. Run remote `herdr [--session NAME] status --json` to discover the authoritative socket.
2. Create a private local directory with mode `0700`.
3. Use `/usr/bin/ssh` stream-local forwarding for both public sockets: `herdr.sock` for JSON control/events and `herdr-client.sock` for terminal sessions.
4. Point the ordinary local adapters at those forwarded sockets.

Bessie forces strict host-key checking, batch mode, and atomic forward failure. No Herdr socket is exposed over TCP. A multiplexed control master may be reused briefly. A stopped remote session must be started on its host; normal connection does not silently create it. Supported remote file operations reuse the authenticated SSH channel and enforce path containment.

## Runtime selection and bundling

V1 targets macOS 14+ on Apple Silicon and pins:

- Herdr `0.8.0`, protocol `19`, release/source baseline `346411fa21afd297f5ed3b3fa56f9e3fbf7654b7`;
- `libghostty-spm` / `GhosttyTerminal` `1.3.2` exactly;
- Sparkle `2.9.5` exactly.

The distributable app contains the exact arm64 Herdr executable as a signed nested resource. **Included** is the default selection. System and absolute custom paths are explicit advanced choices and must be executable arm64 regular files reporting the exact compatible Herdr version/protocol. The bundled runtime additionally must match its lockfile digest, canonical bundle location, and code signature. A missing or changed bundled runtime is app damage, not permission to download a replacement silently.

Development may use `.local/herdr/herdr` and repository-isolated state. It must never install over or rewrite system Herdr.

## Terminal, control, input, and focus lifecycle

Every visible interactive pane hosts one libghostty surface and one public process:

```text
herdr terminal session control <pane-id> --cols N --rows N
```

Read-only views use observe mode. Bessie never copies Herdr's private bincode protocol. An ownership conflict remains read-only until explicit user confirmation invokes public `--takeover`. One shared gate holds raw committed bytes and intercepted operations while ownership is unresolved, then releases them in original order only after takeover reaches a writable full repaint.

### Frames and controller lifetime

1. Start with the current libghostty grid and freeze input.
2. Wait for an initial `full: true` ANSI frame for that grid.
3. Base64-decode and feed frames to `InMemoryTerminalSession` strictly by sequence.
4. Ignore old/duplicate frames. On a gap, malformed stream, stale grid, or process loss, show reconnecting, freeze input, recreate the controller, and wait for a new full frame.
5. Retry with bounded delays of `0.25`, `0.5`, `1`, `2`, and `4` seconds.
6. Debounce viewport changes, send `terminal.resize`, and wait for Herdr's full repaint; do not stretch stale cells.
7. On view teardown send `terminal.release` and stop only the controller subprocess.

Herdr owns terminal emulation, mode state, history, the PTY, and inner process. Local libghostty renders Herdr's viewport; it is not an independent terminal history.

### Composite input

One ordered queue preserves operations across public surfaces:

- ordinary committed bytes: `terminal.input`;
- special keys/modifier chords: `pane.send_keys`, encoded by Herdr against live modes;
- paste: `pane.send_input.text`, including Herdr-owned bracketed-paste handling;
- wheel/viewport scroll: `terminal.scroll`;
- resize: the terminal-session controller.

Bessie intercepts app-level Command shortcuts; unclaimed text/control/navigation input belongs to the focused terminal. IME preedit stays local and only committed text is sent. Bessie does not infer cursor-key, paste, or focus-reporting modes from rendered ANSI. Mouse forwarding is the deliberate exception: V1 recognizes Hermes panes and synthesizes SGR mouse bytes as a bounded compatibility path. Herdr 0.8.0/protocol 19 exposes no negotiated public mouse capability, so Bessie does not promise this behavior for every mouse-aware TUI.

### Prefix command boundary

The window-scoped coordinator implements the pinned Herdr 0.8 `Ctrl-B` grammar only while an eligible Bessie terminal is first responder. Its owner token includes window, connection generation, pane, controller, and terminal incarnation. Focus changes, sheets, palette entry, IME composition, app/window deactivation, reconnect, or connection replacement synchronously cancel the mode before another responder can receive its RHS. Standard Command equivalents return to AppKit. Unknown and protocol-19-unavailable RHS values are consumed and cleared rather than leaked into a TUI.

Supported topology RHS values never become terminal bytes. They enter a shared Herdr-default resolver used by prefix, palette, menu/button, and intent routes. The resolver takes a fresh authoritative snapshot, validates or resolves the exact target, serializes only the finite mutation attempt, then reconciles off the mutation lane. A generation replacement can win before submission and send nothing; an accepted/transmitted request whose response is lost is reported as `mutationOutcomeUnknown`, recovered with a generation-checked snapshot, and never automatically replayed. Resize alone has a bounded FIFO that sends and reconciles one public `pane.resize` request at a time.

The doubled prefix is different by design: it sends one semantic `pane.send_keys(["ctrl+b"])` operation through the same terminal ownership/order gate as other terminal input. Protocol 19 does not expose Herdr's effective custom/plugin keymap or real copy-mode state, so the pinned reference states those limits instead of creating shadow modes.

### Focus and writable ownership

AppKit first responder, a pending Bessie navigation, and Herdr's authoritative focused pane are distinct facts. Bessie may paint navigation chrome immediately, but settled terminal focus requires responder focus and the reconciled Herdr pane to agree. Generation-tagged requests make the newest rapid navigation win and reject stale completions.

A writer conflict becomes explicit UI: observe, cancel, or deliberate take over. Additional Bessie views observe or route to the existing controlled view. V1 never creates multiple writers for one pane, and native focus alone never injects terminal focus-report sequences.

## Projects materialize ordinary Herdr state

A Native Bessie Project is a versioned JSON launch recipe, not a saved workspace. Schema v3 records a target connection, named folders, tabs, split relationships/ratios, labels, and optional one-line startup commands. Files live under `~/Library/Application Support/Bessie/Projects` by default. Supported older schemas migrate with validation and backup/rollback safeguards.

Launch:

1. validates recipe and target connection generation/identity;
2. resolves folders in that connection's filesystem namespace, including remote validation over SSH;
3. calls public Herdr workspace/tab/pane methods in dependency order;
4. snapshots and verifies IDs, labels, topology, working directories, and final state;
5. waits for pane readiness before an optional command, sends text, verifies echo, then sends Enter separately;
6. opens the resulting ordinary Herdr workspace.

If the connection changes or a response is lost, Bessie reports its verified partial result and marks an in-flight outcome unknown. It does not blindly retry creation or pretend to roll back live Herdr objects safely. Capturing a workspace creates a recipe from a fresh snapshot; later recipe edits and live workspace changes remain independent. Startup commands are explicit user-authored executable input, not trusted terminal metadata.

## Presentation persistence

Bessie persists only what it owns:

- visual, terminal-presentation, startup, menu-bar, and notification preferences;
- connection definitions and selected/default connection IDs;
- explicit runtime selection;
- last-workspace hints per connection and workspace-scope presentation;
- pane pin/snooze records tied to exact connection, pane, and terminal incarnation;
- onboarding/recoverable setup attempts;
- Project recipe files.

Herdr identifiers are hints revalidated against a fresh snapshot. Pane presentation is revisioned/incarnation-scoped so reused IDs do not inherit stale state. Stores use schema checks, size limits, atomic writes, restrictive permissions/locks, and unsafe-file/symlink rejection where applicable.

Bessie does not persist live topology, processes, agents, PTY history, terminal frames, or an event replay log.

## Notifications, updates, and intents

### Notifications and menu bar

Bessie derives native notifications from transitions in Herdr's authoritative semantic agent state. Permission is requested only after user action. Notifications exclude terminal content, suppress active/snoozed panes, and carry connection/workspace/tab/pane IDs. Activation revalidates those IDs against the current projection before navigation. Menu-bar rows and badges are another presentation of the same multi-herd projection, not another state model.

### Updates

Sparkle runs only for the production app identity or an explicit HTTPS/loopback test contract. It owns checking, download, and install-on-quit mechanics; Bessie presents preferences, failures, readiness, and restart-to-update. Signed archives/appcasts, notarization, and feed publication are separate release-pipeline trust decisions. Test packages must not impersonate production identity.

### CLI and MCP intents

The app exposes a versioned NDJSON intent catalog over an owner-only local Unix socket with a process lock. `bessie` and `bessie-mcp` validate schemas and route to that bus. Each intent declares Bessie/Herdr ownership, read/navigate/mutate/destructive risk, and connection requirements. Herdr-owned intents still use public Herdr APIs. Destructive operations require a one-shot confirmation token; this is not a general shell endpoint.

## Trust boundaries

- **Herdr streams:** authoritative for live state but parsed as untrusted external input; validate envelopes, sizes, sequences, identity, and compatibility. Never use private protocols.
- **Terminal content:** ANSI, titles, links, and text originate from pane processes. Unknown URI schemes require refusal/confirmation; displayed text cannot manufacture a graphical approval or shell execution.
- **SSH:** OpenSSH owns authentication/host trust. Bessie validates inputs, requires strict key checking, forwards only Unix sockets privately, and stores no credentials.
- **Local persistence/sockets:** use owner-only permissions, locks, regular-file checks, bounds, containment, and atomic replacement. Generic environment variables are not implicit authority.
- **Projects:** paths and startup commands are user configuration in the target machine's namespace and can create objects/execute input, so validation and honest partial failure are mandatory.
- **Notifications:** include semantic state/location only, not terminal content; routes are revalidated.
- **Updates/releases:** runtime digest/signature, app signing, Sparkle signature, notarization, and publication are separate gates.
- **Intent callers:** owner-only socket access permits catalogued operations; destructive operations also require one-shot confirmation and all parameters remain schema-bound.

## Deferred and feature-flagged scope

`BessieFeatureFlags.v1` enables no developer-only surfaces. `BESSIE_DEVELOPER_FEATURES=fileBrowserEditor,followFiles` may expose file browser/editor and follow-files surfaces for development; they are not in the default V1 contract.

Deferred unless a negotiated public Herdr capability and focused tests land:

- generic approval/deny UI inferred from terminal text;
- generic inner-app mouse-mode negotiation beyond the bounded recognized-Hermes-pane policy, plus terminal focus reporting through the raw controller;
- Kitty graphics, OSC 52 terminal clipboard requests, and native search/selection over full server history;
- multiple writable Bessie views of one pane;
- worktree orchestration, generic IDE/browser surfaces, and other roadmap scope;
- private bincode clients, custom remote TCP services, or a Bessie-only Herdr fork/plugin required by core Projects.

These gaps belong in versioned public Herdr capabilities or a reusable public client transport, not screen scraping or copied private wire types.
