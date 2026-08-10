# Bessie V1 features

This is the user-facing feature contract for the current Mac V1 candidate. It describes default shipping behavior, not every implementation present in the source tree.

## Platform and runtime

- macOS 14 or newer on Apple silicon.
- Native Swift 6 application: SwiftUI for app surfaces, AppKit for window, focus, and terminal hosting.
- Included Apple-silicon Herdr `0.8.0`, protocol `19`, source `346411fa21afd297f5ed3b3fa56f9e3fbf7654b7`.
- `libghostty-spm` `1.3.2` provides every visible terminal surface.
- Sparkle `2.9.5` provides the signed update flow in packaged production builds.

## Setup and connections

- Four-step onboarding: choose a Herd and folder, learn the Herdr ownership model, learn the rail states, and choose notifications.
- **This Mac** uses the included compatible Herdr runtime by default and starts Bessie's named Herdr session when needed.
- **Remote over SSH** uses an SSH config host or `user@host`, an optional Herdr session name, and an absolute folder on the target.
- Multiple enabled local and SSH Herds can contribute to one fleet.
- Each connection can start at app launch or remain on demand. Local defaults to launch; SSH defaults to on demand.
- Connections have honest connecting, stale, disconnected, retrying, disabled, and incompatible presentation. One connection cannot masquerade as another.
- OpenSSH remains responsible for authentication. Bessie stores connection definitions, not passwords or private keys.
- Settings can rerun setup and select an included, compatible system, or explicit custom runtime where supported.

## The Herd and navigation

- One authoritative agent roster across connected Herds and all their workspaces.
- Five semantic states: **Needs you**, **Working**, **Done**, **Idle**, and **Unknown**. Unknown is uncertainty, never inferred attention.
- Status counts and filters route to the exact connection, workspace, tab, and pane.
- Pane presentation controls: pin/unpin, snooze with bounded presets, wake now, and dedicated Pinned and Snoozed groups.
- Persisted manual hierarchy scopes cover selected tab, all tabs in a workspace, all workspaces in a Herd, and all Herds. Missing identifiers fall back against fresh topology rather than creating shadow state.
- Connection, workspace, tab, and pane hierarchy with exact focus, counts, health, rename/create/close actions, and fresh-snapshot reconciliation.
- Entity-aware command palette for actions and current connections, workspaces, tabs, panes, agents, and Projects, including alternate routes where available.
- Herdr topology uses the pinned Herdr 0.8 `Ctrl-B` prefix grammar, with focused-pane `PREFIX`/`RESIZE` feedback, a generated keyboard reference, a literal doubled-prefix path, and no timeout. Native application shortcuts remain available except where text entry, IME composition, or a modal owns input.
- Bounded **Zen** presents one real terminal with minimal context and an obvious exit.

## Workspaces, tabs, panes, and agents

- Create, rename, focus, reorder, and close Herdr workspaces and tabs.
- Create, split, resize, focus, reorder, zoom, rename, move, and close panes.
- Closing a final pane or tab reconciles the resulting workspace closure from Herdr's fresh snapshot.
- New-pane flow opens a shell or starts an agent from Herdr's manifest-backed catalog, with name, kind, arguments, and working context where supported.
- Graphical destructive behavior follows the bundled Herdr default and reconciles the actual cascade from fresh state; automation still uses its explicit confirmation-token contract.
- One deliberately owned Bessie window; no shadow multi-window session model.

## Terminals

- Real `GhosttyTerminal` views connected to Herdr's public terminal-session bridge.
- Full terminal output, keyboard input, paste, resize, scrolling, and selection. Bessie heuristically forwards synthesized SGR mouse bytes to recognized Hermes TUI panes while keeping plain shells local-selection-only. This is accepted bounded V1 behavior: it works for the intended Hermes integration, is not promised for every mouse-aware TUI, and can move to negotiated routing when Herdr exposes that public API upstream.
- One writable controller per visible pane. Ownership conflict remains read-only until the user confirms **Take over**, warning that the other terminal client will lose control. Input submitted while ownership is unresolved is held in order and forwarded once after an explicit takeover reaches a writable full repaint.
- Reconnect is bounded per outage and input stays frozen until a matching full repaint makes the controller ready. A successful connection resets the retry budget for the next independent outage.
- Pane selection is explicit. Clicking a Herd row, notification, menu-bar row, hierarchy item, or palette entity routes to the exact pane rather than guessing from a stale global selection.
- Idle terminal input retains ordinary text, Control/Option/function/navigation keys, paste, IME commit, and `Shift-Tab`. Prefix-owned sequences are consumed by the Herdr command layer and never replayed into the hosted terminal.
- Native Bessie application shortcuts and terminal conveniences remain separate from topology. `Cmd+W` closes the Bessie window and leaves Herdr running.
- Protocol 19 cannot expose custom/remapped/plugin keymaps or real Herdr copy mode, so Bessie documents those limits instead of simulating them.

## Native Projects

Projects are Bessie-owned launch recipes, not live workspaces.

- Create, edit, duplicate, delete, and recover catalog filename mismatches.
- Choose a target Herd and a primary folder; local Projects can include additional folders, and remote Projects use absolute target-host paths.
- Define tabs, split trees, ratios, pane labels, initial folders, and optional one-line commands.
- Capture a compatible live Herdr workspace as a Project recipe.
- Review what will run before launch, materialize transactionally into ordinary Herdr objects, report partial failures honestly, and open an already-running instance.
- Versioned Project persistence and schema migration, including the schema-v1 to schema-v2 folder model and guarded target migration tooling.
- Deleting a recipe does not delete its folders or close Herdr workspaces.

## Notifications and menu bar

- Notification policies: Off, Needs you only, or Needs you and settled work (Done/Idle transitions).
- Permission is requested only after a user action. Denial links to macOS notification settings.
- Notifications omit terminal content and deep-link to the exact pane incarnation.
- Snoozing suppresses pending and delivered notifications for that pane; stale incarnations do not route as if current.
- A test notification verifies permission and routing setup.
- Menu-bar companion shows Needs you and Working rows, Done/Idle/conditional Unknown totals, configurable badge policy, and exact-pane or open-app row behavior.

## Appearance and native behavior

- System, Bessie Dark, Bessie Light, Catppuccin Latte, Frappé, Macchiato, and Mocha themes.
- Themes apply transactionally to native chrome and active Ghostty terminals.
- Comfortable/compact density, terminal font size, pane spacing, rail collapse, and light/dark app icons.
- Bounded Ghostty configuration compatibility can import only supported appearance keys from a selected config path; Bessie and Herdr-required behavior still wins. Unsupported keys remain explicit diagnostics, not silent terminal behavior changes.
- Reduced-motion behavior, native focus and accessibility semantics, standard macOS quit/hide/minimize/window behavior, and deliberate single-window ownership.
- Quitting Bessie or closing its window does not stop Herdr or pane processes.

## Trouble, updates, and automation

- Trouble diagnostics distinguish runtime resolution, validation, server startup, API connection, compatibility, terminal control, and previously healthy connection loss.
- Retry and setup-again paths retain honest diagnostics instead of replacing failures with empty workspaces.
- Production app bundles expose Sparkle automatic-check and automatic-download preferences, manual **Check for Updates…**, ready-to-restart state, and restart-to-install action.
- Update UI is intentionally unavailable for an unbundled development executable.
- A local Unix-socket intent bus exists only while Bessie runs.
- `bessie` CLI discovers the effective intent catalog and can read status/context, navigate, mutate Bessie-owned pane presentation, inspect Projects, and request confirmed destructive Herdr actions.
- `bessie-mcp` exposes the same effective catalog over MCP stdio. Schemas, owner, risk, connection requirements, and one-shot confirmation tokens are discoverable rather than copied into a second command catalog.

See [CLI, MCP, and the intent bus](automation.md) for command syntax, MCP methods, connection scoping, revision-safe pin/snooze mutations, destructive confirmation, and failure behavior.

## Ownership and safety boundary

Herdr owns every live workspace, tab, pane, terminal, process, agent, state, focus target, and durable session fact. Bessie owns only its presentation preferences and Project recipes. Last-opened Herdr identifiers are revalidated hints.

Bessie uses Herdr's public JSON socket API, CLI wrappers, and public terminal-session bridge. It does not use Herdr's private client protocol. Quitting Bessie must leave Herdr and pane processes running; closing a Herdr object is different and can stop its processes.

## Feature-flagged exclusions

Two implementations are present for development evaluation but are **off by default and not V1 product surfaces**:

- `fileBrowserEditor` — workspace file browser, previews, markdown editing, and file operations.
- `followFiles` — touched-file following and pinning in agent detail.

They can be enabled only through the developer feature environment contract. Their presence in source or tests does not make them supported default V1 behavior.

## Explicit non-goals

V1 does not include:

- Search the Herd or terminal search;
- worktrees or branch management;
- layout presets;
- a generic IDE, general code editor, or in-app browser;
- graphical approval, Allow/Deny, or suggested-answer controls without a typed upstream contract;
- a standalone Attention queue, history, resolved inbox, age model, dismiss/seen state, or completion-review inbox;
- a full agent trace/diff/provenance workspace;
- graphical remote desktop sessions;
- Broadcast, Shepherd, plugin hosting, or a shadow task/session database;
- multiple Bessie windows.

These exclusions are deliberate. Bessie is a native Herdr client for supervising and shaping terminal work, not a replacement runtime or an IDE.
