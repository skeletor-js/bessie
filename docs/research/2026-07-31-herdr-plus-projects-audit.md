# Native Herdr Plus Projects in Bessie

> **Superseded:** Jordan decided Projects must be a native Bessie feature with no vendored or runtime Herdr Plus dependency. The canonical replacement is [`2026-07-31-native-bessie-projects.md`](../plans/2026-07-31-native-bessie-projects.md). This file remains only as the reviewed alternative and Herdr Plus behavior audit.

**Date:** 2026-07-31
**Status:** Superseded alternative
**Owners:** Bessie + Herdr Plus
**Target:** First post-V1 local macOS feature; normal project opening first, worktree opening second

## Objective

Give Bessie a native project browser that reads and opens the user's existing Herdr Plus Projects without replacing either owner:

- **Herdr Plus owns** project files, validation, normalization, and the procedure that materializes a project.
- **Herdr owns** the resulting workspace, tabs, panes, terminals, commands, and live state.
- **Bessie owns** discovery, native presentation, launch progress, error presentation, and navigation to the Herdr workspace after it opens.

The result should feel built into Bessie while remaining the same Herdr Plus project system. A project opened from Bessie must create an ordinary Herdr workspace that is immediately usable from Herdr itself.

## Reviewed baseline

This plan is based on the live installed setup and exact source revisions below.

### Bessie

- Repository: `/home/hermes/code/bessie`
- Branch at review: `feat/native-v1-alpha`
- Revision at review: `235817c`
- Herdr compatibility baseline: Herdr `0.7.5`, protocol `17`
- Bessie connects to a detached named Herdr session (`bessie`) and talks to its public NDJSON socket API.
- `HerdrSocketAPI` already exposes arbitrary public JSON requests and `HerdrActionClient` already handles ordinary workspace/tab/pane mutations.
- The connected terminal endpoint already carries the Herdr executable and socket paths needed to run a provider process against the exact same session.
- The current Workspaces surface distinguishes live Herdr workspaces but has no concept of durable launch recipes.

The repository already had unrelated uncommitted keyboard, settings, and surface work during this review. This plan adds only this document; implementation should preserve and rebase around that active work rather than overwrite it.

### Herdr Plus

- Installed plugin: `cloudmanic.herdr-plus`
- Version: `0.1.20`
- Revision: `a9aca9da3ca6d7406f3d878a1df1c1b9775e2723` (also current upstream `main` at review)
- Managed config root: `~/.config/herdr/plugins/config/cloudmanic.herdr-plus`
- Project files: `projects/*.toml`
- Local use at review: 16 project recipes. Every current recipe has two single-pane tabs (`Agents` running `hermes`, `Files` running `spf`) rooted at a canonical workstream directory.
- Bessie itself is represented by `projects/bessie.toml`, rooted at the retained Bessie workstream rather than the implementation repository.

Herdr Plus's complete project model supports:

- `name`, `description`, optional `group`, and `working_dir`
- ordered tabs
- a single-pane `command` shorthand or up to four explicit panes per tab
- pane `command`, optional `label`, and `split` (`down` or `right`)
- `~` expansion in `working_dir`
- normal opening and an optional worktree-opening path

Loading is deliberately strict: all `*.toml` files are parsed and validated; one invalid file fails the whole catalog. Projects are sorted by name. The working directory is checked only when a project is opened.

### How Herdr Plus currently uses Herdr

1. `cloudmanic.herdr-plus.projects` is a Herdr plugin action.
2. The action asks Herdr to open the plugin's `picker` entrypoint as a **zoomed plugin pane**.
3. Herdr runs `herdr-plus projects-ui` inside that real terminal pane and injects:
   - `HERDR_SOCKET_PATH`
   - `HERDR_BIN_PATH`
   - `HERDR_PLUGIN_CONFIG_DIR`
4. The Bubble Tea picker loads the managed TOML catalog.
5. Selecting a normal project calls Herdr's public JSON socket API:
   - `workspace.create(cwd, label, focus: true)`
   - rename the root tab
   - create later tabs without focusing them
   - split later panes from the previously created pane
   - apply optional pane labels
   - after the full layout exists, wait for each shell prompt and inject each command using Herdr terminal read/input APIs and a real Enter key
6. The picker exits and Herdr removes the temporary plugin pane. The new workspace remains ordinary Herdr state.

The existing `herdr-plus open <name>` command skips the picker but uses the exact same `openProject` path. It resolves managed config through `herdr plugin config-dir`, requires `HERDR_SOCKET_PATH` to target a running Herdr session, and prints human text rather than a machine-readable result.

Important behavioral facts to preserve:

- Opening always creates a new workspace; there is no name-based deduplication.
- Layout creation is sequential and is **not transactional**. A later failure can leave a partial but valid Herdr workspace.
- Pane-label failures are warnings; structural and startup-command failures stop the open.
- Startup commands are arbitrary trusted user configuration and run in the project's real Herdr panes.
- Worktree opening uses `worktree.create`; Herdr events and a separate Herdr Plus worktree recipe perform layout. It does not reuse the project's `[[tabs]]` layout.

## Architectural decision

### Chosen approach: Herdr Plus as a versioned project provider

Add a small, machine-readable, headless Projects contract to Herdr Plus and have Bessie invoke that provider binary from the plugin installation reported by Herdr's public `plugin.list` API.

Bessie must **not** parse Herdr Plus TOML or recreate `openProject` itself.

This gives the three systems clean authority boundaries:

```text
Herdr Plus TOML
      │
      ▼
Herdr Plus provider ── validates, normalizes, materializes
      │                         │
      │ JSON catalog/result     │ public Herdr socket calls
      ▼                         ▼
Bessie native UI           Herdr session
      │                         │
      └──── resnapshot/focus ◀──┘
```

### Why not the obvious alternatives?

1. **Invoke `plugin.action.invoke` unchanged.** This only opens the existing terminal picker. It works in Herdr, but it is not a native Bessie feature and provides no project catalog to SwiftUI.
2. **Read TOML in Bessie and issue Bessie's existing mutations.** This duplicates validation, pane normalization, shell-readiness pacing, command injection, worktree behavior, and future schema changes. The two clients would drift.
3. **Copy Herdr Plus code into Bessie or add Go as an embedded library.** This creates a second release/coupling problem for a contract that can remain process-based and local.
4. **Invent a Bessie-owned project format.** This violates the requirement that the user's normal Herdr setup remain authoritative.
5. **Wait for a generic synchronous Herdr plugin-RPC system.** That may be the eventual platform-level answer, but it is not required. Herdr already exposes plugin metadata and the provider already has a headless opening path.

## Provider contract to add to Herdr Plus

Treat this as a public, versioned local protocol rather than scrapeable CLI output.

### Catalog command

Add a headless command along the lines of:

```bash
herdr-plus projects --json
```

With no `--json`, `projects` must retain its current plugin-action behavior.

The JSON envelope should include:

- `schema_version`
- plugin ID and provider version
- managed projects directory
- normalized projects in display order
- one stable project ID derived from the source filename, not the display name
- `name`, `description`, and `group`
- expanded or explicitly resolved working directory plus the authored value if useful for display
- ordered, normalized tabs and panes
- pane label, split direction, and command
- capabilities such as normal open and worktree open

Use the source filename as the machine ID because names are presentation and duplicate names are currently possible. Keep exact absolute source file paths out of the public identity; the managed directory plus filename is enough.

Catalog failures should emit a structured JSON error and non-zero exit. Preserve strict whole-catalog validation so Bessie and the terminal picker report the same broken configuration.

### Open command

Extend the existing headless path, for example:

```bash
herdr-plus open --project-id bessie.toml --json
```

Requirements:

- Use the same loaded project object and `openProject` implementation as the terminal picker.
- Keep `open <name>` for human/backward compatibility.
- Read `HERDR_SOCKET_PATH` and target exactly that Herdr session.
- Use `HERDR_BIN_PATH` when resolving Herdr-managed plugin config.
- Return a structured success containing project ID/name and the created Herdr workspace ID.
- On failure after workspace creation, return a structured error containing:
  - stage (`validate`, `create_workspace`, `layout_tabs`, `run_command`, etc.)
  - human message
  - created workspace ID when one exists
  - whether the result may be partial
- Keep diagnostics on stderr and the single JSON envelope on stdout.
- Define stable exit codes for invalid request, catalog/config failure, unavailable Herdr, and partial materialization.

Refactor `openProject`/`layoutTabs` only enough to return structured progress. Do not add rollback in this feature: automatically closing a partial workspace can destroy useful process output and changes Herdr Plus's existing behavior.

### Provider tests

Add focused Go tests for:

- catalog JSON encoding and `schema_version`
- normalized shorthand and multi-pane tabs
- stable filename IDs, ordering, groups, labels, split defaults, and command preservation
- duplicate display names opened by exact project ID
- invalid config as a structured whole-catalog failure
- missing working directory before workspace creation
- structured success with workspace ID
- failures before and after workspace creation, including `partial: true`
- legacy `projects` and `open <name>` behavior remaining intact
- Linux/macOS/Windows provider binary resolution where applicable

Prefer a narrow Herdr client interface around the existing concrete client so sequencing and failure stages can be tested without a live terminal.

## Bessie implementation

### 1. Add plugin discovery to `BessieCore`

Create a typed adapter around public `plugin.list` rather than teaching SwiftUI about raw JSON.

Suggested types/files:

- `Sources/BessieCore/HerdrPlugins.swift`
  - installed plugin DTOs needed by Bessie
  - `HerdrPluginCatalog.load(api:)`
  - lookup for enabled `cloudmanic.herdr-plus`
  - platform-compatible action/root validation
- tests in `Tests/BessieCoreTests/HerdrPluginTests.swift`

Use Herdr's returned `plugin_root`, `version`, `enabled`, warnings, and source metadata. Do not reconstruct `~/.config/herdr/plugins/...` paths.

### 2. Add the Herdr Plus provider client to `BessieCore`

Suggested file:

- `Sources/BessieCore/HerdrPlusProjects.swift`

Responsibilities:

- locate the platform-appropriate provider executable under the Herdr-reported plugin root
- run catalog/open commands off the main actor
- set an explicit, sanitized environment:
  - `HERDR_SOCKET_PATH` = Bessie's connected session socket
  - `HERDR_BIN_PATH` = Bessie's detected Herdr executable
  - `HERDR_SESSION` = Bessie's managed session name
  - preserve the config environment used by Bessie's Herdr runtime
  - never inherit an unrelated socket override
- decode only a supported provider `schema_version`
- cap captured stdout/stderr and surface process exit status honestly
- expose pure models for project summaries, tab/pane previews, capabilities, open success, and partial failure

Do not add a TOML package to Bessie. Do not call `workspace.create`, `tab.create`, `pane.split`, or command-input APIs from this client; Herdr Plus owns those semantics.

The current `HerdrTerminalEndpoint` is terminal-specific. Either introduce a small shared connected-runtime context (`executablePath`, `socketPath`, `sessionName`, managed environment) or add a separate project-provider context. Avoid making project discovery depend on a visible terminal pane.

### 3. Add catalog and launch state to `ConnectionViewModel`

Model explicit states rather than overloading `actionInFlight`:

- loading
- available(projects)
- empty(config directory)
- unavailable(plugin missing/disabled)
- incompatible(provider protocol unsupported)
- invalid configuration(error + config directory)
- opening(project ID)
- partial(workspace ID + error)

Load the catalog after a compatible connection is established, alongside the agent catalog. Invalidate and reload it after explicit user refresh and when the connected runtime/socket changes. Do not poll project files continuously in the first version.

Opening flow:

1. Mark only the selected project as opening and block duplicate launch clicks.
2. Ask the provider to open the stable project ID against Bessie's socket.
3. On success, resnapshot Herdr and verify the returned workspace ID exists.
4. If the event stream has not projected it yet, use a short bounded resnapshot retry rather than guessing by label.
5. Focus/select the returned workspace and navigate to the Workspace surface.
6. On a partial error, resnapshot, retain the workspace, navigate to it when possible, and explain what stage failed. Never retry automatically because that would create a duplicate workspace.

### 4. Add a native Projects surface

Keep **Projects** (durable recipes) visually and conceptually distinct from **Workspaces** (live Herdr state).

Recommended first UI:

- Add `Projects` to `ProductDestination` and the navigation rail near Workspaces.
- Add a native searchable project list grouped by Herdr Plus `group` when groups exist.
- Each row/card shows name, description, working directory, and a compact tab/pane summary.
- A detail/preview region shows ordered tabs, panes, labels, split directions, and startup commands before opening.
- Primary action: **Open project**.
- Opening progress belongs on the chosen item, not as a global frozen UI.
- On success, navigate directly to the returned live workspace.
- Add **Refresh projects** and **Reveal projects folder** where a config directory is available.
- Add an `Open Project…` command-palette command that opens/focuses the Projects surface. A dedicated global shortcut can wait until the existing shortcut system settles.

State-specific UX:

- **Plugin missing/disabled:** explain that Projects come from Herdr Plus and show the exact detected condition. Do not install or enable it automatically.
- **Provider too old:** say which provider protocol is needed and offer the user's normal Herdr/plugin update path; do not silently fall back to a second implementation.
- **Empty:** show the managed directory and a minimal recipe example or reveal-folder action.
- **Invalid catalog:** show the provider's complete validation error, preserving the offending filenames.
- **Missing project directory:** fail before creating a workspace and keep the user in Projects.
- **Partial open:** make the surviving live workspace visible and explain that Herdr owns it; offer navigation, not destructive cleanup.

Opening is allowed to create multiple workspaces from one project, matching Herdr Plus. Do not deduplicate by project name.

### 5. Keep worktree opening as phase two

The current user recipes do not exercise worktree opening, and Bessie's retained scope explicitly deferred worktrees. Normal opening should ship first.

Prepare the provider DTO with capabilities, but do not expose **Open as worktree** until Bessie has a proper worktree presentation and validation path. Phase two should:

- prompt for branch name and apply Herdr Plus's configured prefix
- call the provider's worktree opening command, not Herdr directly
- project Herdr's resulting worktree workspace
- account for event-driven layout from Herdr Plus `worktrees/` recipes
- show that the selected project's `[[tabs]]` are not used on this path

## End-to-end validation

### Bessie unit tests

Add tests for:

- `plugin.list` decoding, missing/disabled/warned Herdr Plus, and plugin-root use
- provider JSON decoding and unsupported schema versions
- sanitized environment construction, especially ignoring inherited `HERDR_SOCKET_PATH`
- catalog state transitions and refresh behavior
- successful open selecting by returned workspace ID, never by label
- bounded snapshot retry
- partial failure projection without auto-retry or auto-close
- duplicate project names with distinct project IDs
- Projects surface projection/grouping/search and accessibility labels

### Isolated live Herdr test

Extend `scripts/mac-verify.sh` with an isolated project-provider fixture under Bessie's repository-local Herdr config:

1. Install/link the compatible Herdr Plus build into the isolated test config without touching the user's plugin installation.
2. Create fixtures for:
   - two ordinary single-pane tabs
   - one tab with mixed right/down panes and labels
   - one startup command whose output can be asserted
   - one invalid catalog fixture tested separately
3. Start/reuse only the named `bessie` Herdr session.
4. Open a fixture through Bessie's provider client.
5. Assert via live Herdr snapshot and pane reads:
   - workspace ID and working directory
   - workspace/tab/pane labels and order
   - split tree shape
   - startup command output
   - focus on the created workspace
6. Assert the ordinary/default Herdr session remains untouched.
7. Quit and reopen Bessie; verify the workspace and processes survive because Herdr owns them.

### Native visual verification

Capture and inspect screenshots for:

- populated Projects list/detail
- empty catalog
- plugin unavailable/upgrade required
- invalid catalog
- opening progress
- partial failure with surviving workspace

The implementation is not complete from mocks or compilation alone. It must pass:

```bash
./scripts/check.sh
./scripts/mac-verify.sh
```

Then package/install `/Applications/Bessie.app`, relaunch it, and perform the repository's required installed-binary and live Herdr verification.

## Delivery sequence

### Milestone 1 — Provider contract in Herdr Plus

1. Define the versioned JSON envelopes and stable project ID.
2. Add machine-readable catalog output.
3. Add machine-readable exact-ID opening and structured partial errors.
4. Refactor behind a testable Herdr client interface without changing picker behavior.
5. Run the full Go suite and manual live Herdr smoke checks.
6. Release/version the provider so Bessie can declare a real compatibility floor.

**Exit:** A shell can list and open the same managed recipes deterministically against a chosen Herdr socket, with a workspace ID returned.

### Milestone 2 — Bessie core integration

1. Add plugin discovery.
2. Add provider process/JSON client and connected-runtime environment.
3. Add catalog/open state to the view model.
4. Cover missing, incompatible, malformed, success, and partial paths with tests.

**Exit:** BessieCore can list and open a Herdr Plus project against an isolated live Bessie session without SwiftUI.

### Milestone 3 — Native Projects UX

1. Add Projects destination and rail entry.
2. Build search/group/list/detail states.
3. Wire open, refresh, reveal-folder, progress, and errors.
4. Navigate by provider-returned workspace ID.
5. Add command-palette routing and accessibility.

**Exit:** A user can browse an existing Herdr Plus catalog and open a project without entering the terminal picker.

### Milestone 4 — Release verification

1. Extend isolated Mac verification fixtures.
2. Add visual captures and inspect them.
3. Verify ordinary Herdr remains fully usable before, during, and after Bessie.
4. Package, install, relaunch, and verify the installed app.
5. Document the minimum Herdr Plus version and troubleshooting states.

**Exit:** The installed app opens real recipes into real Herdr workspaces and survives reconnect/app restart without owning runtime state.

### Milestone 5 — Worktree parity (separate follow-up)

Implement native branch prompting and provider-driven worktree opening only after normal Projects is accepted.

## Acceptance criteria

- Bessie discovers Herdr Plus through Herdr's public API; it does not hard-code installation directories.
- Bessie displays the catalog from the provider's normalized, versioned output; it does not parse TOML.
- The same recipe opens with the same layout and commands from Herdr's picker, `herdr-plus open`, and Bessie.
- Every resulting workspace/tab/pane is owned by Herdr and remains usable from ordinary Herdr after Bessie quits.
- Bessie targets only its connected socket/session and cannot accidentally mutate an inherited/default session.
- Duplicate project names remain independently addressable by stable project ID.
- Success is verified by returned workspace ID plus a fresh Herdr snapshot.
- Partial failure never triggers silent retry, duplicate creation, or destructive rollback.
- Missing/disabled/old Herdr Plus and invalid project files produce honest native states.
- Existing Herdr Plus picker and human CLI behavior do not regress.
- Normal opening ships before worktree opening.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Bessie and Herdr Plus protocol drift | Version the JSON schema, feature-detect, reject unsupported versions explicitly, and maintain contract fixtures in both repos. |
| Plugin update changes its managed path | Resolve `plugin_root` fresh through `plugin.list`; never persist it as durable state. |
| Wrong Herdr session is mutated | Build a sanitized environment from Bessie's connected runtime and overwrite socket/session variables explicitly. |
| Partial workspace after command/layout failure | Return workspace ID and stage; resnapshot and surface it; never auto-retry or auto-close. |
| Duplicate project display names | Address opens by source-derived stable ID, not name. |
| Commands are hidden behind a friendly card | Show normalized tab/pane/command preview and state that opening runs those commands. |
| Bessie begins owning project configuration | Keep editing out of the first scope; reveal the Herdr Plus managed folder instead. |
| The plugin is not installed in Bessie's config context | Detect via the connected Herdr server and show unavailable/upgrade states; never assume the user's shell setup matches. |
| UI work lands on top of active ProductSurfaces changes | Implement core/provider tests first, then rebase the Projects surface against the accepted UI branch. |

## Explicit non-goals

- A Bessie-specific project file format
- Native project editing in the first release
- Automatic Herdr Plus installation, enabling, or upgrade
- Quick Actions integration (separate feature using a similar provider pattern)
- Worktree opening in the first Projects release
- Remote graphical sessions before Bessie's remote socket/terminal bridge exists
- Transactional rollback of Herdr workspaces
- Deduplicating live workspaces by project name
- Replacing the existing Herdr Plus terminal picker
