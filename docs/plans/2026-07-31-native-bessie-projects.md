# Native Bessie Projects

**Date:** 2026-08-01
**Status:** Complete for V1 Projects scope (Milestones 0–6); public notarization deferred
**Owner:** Bessie
**Runtime:** Herdr
**Dependency decision:** No Herdr Plus runtime dependency and no vendored Herdr Plus code
**V1 slice:** 2, after the bundled-runtime/onboarding/Trouble release train

## Product decision

Projects are a native Bessie feature, not a graphical wrapper around Herdr Plus.

- **Bessie owns** project recipes, storage, creation/editing, browsing, launch orchestration, and launch history presentation.
- **Herdr owns** every live workspace, tab, pane, terminal, process, agent, event, and session fact created from a project.
- **Herdr Plus is optional prior art only.** Bessie does not install it, invoke it, link it, vendor it, or require it. A one-time importer may help existing users migrate recipes, but there is no synchronization or ongoing coupling.

This is intentional product differentiation: Projects should be a reason to use Bessie while preserving the rule that the running system underneath is ordinary Herdr.

## First release decision

The first Projects release includes:

- native project model, migration, validation, and local storage;
- catalog, create/edit, preview, duplicate, archive, and confirmed delete;
- opening a project into the active compatible local Herdr connection;
- exact-ID launch tracking and partial-workspace recovery;
- saving an authoritatively observable workspace shape as a reviewed project draft;
- command-palette and keyboard access;
- live Herdr, packaging, installation, relaunch, and process-survival verification.

The following are follow-ups, not release blockers:

- Herdr Plus import;
- worktrees;
- repository-local/shared project files;
- secrets and environment variables;
- remote Project opening;
- automatic reuse or reconciliation of a similar live workspace.

The catalog and editor work without a Herdr connection. Opening requires a compatible connected local endpoint. If the bundled-runtime release train has not shipped, Projects may still use the currently selected compatible runtime, but Projects must not introduce its own discovery or connection logic.

## User outcome

A user can stay in Bessie to:

1. Create a reusable project.
2. Choose its folder.
3. Define tabs, panes, layout, labels, and startup commands graphically.
4. Preview exactly what will be created and run.
5. Open the project into Bessie's connected Herdr session.
6. Edit, duplicate, reorder, archive, or delete the recipe later.
7. Quit Bessie without affecting the live Herdr workspace or processes.

Projects and Workspaces are distinct:

- **Project:** Bessie-owned reusable launch recipe.
- **Workspace:** Herdr-owned live runtime instance.

Opening the same project more than once creates multiple ordinary Herdr workspaces unless the user explicitly chooses an already-running instance.

## Boundary

A Bessie project is not a snapshot or shadow copy of a Herdr workspace. It contains desired launch configuration only:

- project identity and presentation metadata;
- working directory;
- ordered tabs;
- desired pane topology and labels;
- startup commands.

It does not persist:

- live Herdr workspace/tab/pane IDs;
- terminal contents or scrollback;
- process state;
- agent status;
- focus state;
- runtime-generated cwd changes;
- claims that a workspace still exists.

A launch may temporarily return Herdr IDs to navigate to the created workspace. Those IDs are session hints and are revalidated against a fresh snapshot.

## Native project model

Use versioned Codable models in `BessieCore`.

```swift
struct BessieProject: Codable, Identifiable, Sendable {
    let schemaVersion: Int
    let id: UUID
    var name: String
    var projectDescription: String
    var group: String?
    var workingDirectory: String
    var tabs: [BessieProjectTab]
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
}

struct BessieProjectTab: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var panes: [BessieProjectPane]
}

struct BessieProjectPane: Codable, Identifiable, Sendable {
    let id: UUID
    var label: String?
    var command: String?
    var placement: BessieProjectPanePlacement
}

enum BessieProjectPanePlacement: Codable, Sendable {
    case root
    case split(
        fromPaneID: UUID,
        direction: SplitDirection,
        ratio: Double
    )
}
```

Rules:

- A project needs a non-empty name, resolvable working directory, and at least one tab.
- A tab needs a non-empty name and at least one pane.
- Project, tab, and pane labels are trimmed; empty optional labels normalize to `nil`.
- Exactly one pane per tab is the root.
- Every split references an earlier pane in the same tab, creating an acyclic materialization order.
- Pane UUIDs are unique within the project, every split target belongs to the same tab, and deterministic replay of the procedural split order must produce the intended recursive tree.
- Ratios are bounded to Herdr-supported values.
- Commands may be empty; an empty pane opens a shell.
- A first-release startup command is one exact shell submission. Carriage returns and line feeds are rejected; multi-step behavior must be expressed explicitly in one shell command. Bessie performs no interpolation, quoting, shell rewriting, or secret expansion.
- Pane labels are optional.
- UUIDs, not names or array positions, are stable recipe identities.
- The model is versioned from day one and decoded through explicit migrations.

This is Bessie's schema. It should not copy Herdr Plus's source types, filenames, limits, or compatibility behavior.

## Storage

Store one atomic JSON document per project under Bessie's application-support directory:

```text
~/Library/Application Support/Bessie/Projects/<project-uuid>.json
```

Suggested implementation:

- `Sources/BessieCore/BessieProjects.swift`
  - models and validation
  - schema migration
- `Sources/BessieCore/BessieProjectStore.swift`
  - list/load/save/duplicate/archive/delete
  - atomic temporary-file replacement
  - deterministic sorting
  - corruption isolation

Storage behavior:

- One corrupt project file does not hide healthy projects.
- Surface corrupt files individually with filename and decoding error.
- Save atomically so an app crash cannot truncate the last good recipe.
- Do not put project recipes in `UserDefaults`.
- Do not persist secrets in commands or environment fields. Environment/secrets support is out of the first release.
- Deletion requires confirmation and moves the file to Trash where macOS permits; archiving is the safer ordinary action.
- The store accepts an injected root URL so tests and live verification never target the user's real Projects directory.
- The shipped test override is `BESSIE_PROJECTS_PATH`, matching the existing presentation/connection-store pattern.
- Saving an existing project uses optimistic conflict detection based on the last loaded `updatedAt` and file identity. If another process changed the file, preserve both versions and ask the user to reconcile rather than silently overwriting either one.
- A filename/project-UUID mismatch is recoverable corruption: load the embedded UUID as authoritative, surface the mismatch, and never overwrite another recipe.
- If moving a deleted project to Trash fails, preserve the source file and report the owner error; do not fall back to permanent deletion.
- Plain absolute folder paths are sufficient for the current non-sandboxed release. If Bessie adopts App Sandbox, security-scoped bookmarks require a separately planned schema migration.

## Native Projects experience

Add **Projects** as a first-class destination beside Workspaces.

### Catalog

- Search by name, description, group, and path.
- Group optionally, with an ungrouped section.
- Show project name, folder, tab/pane count, and most important commands.
- Show running instances only by matching transient Bessie launch records to a fresh Herdr snapshot; never infer identity solely from labels.

### Project editor

A native create/edit sheet or full surface supports:

- name, description, and optional group;
- folder selection through `NSOpenPanel`;
- add, rename, reorder, duplicate, and remove tabs;
- add/remove panes by graphically splitting a selected pane right or down;
- adjust split ratios;
- label panes;
- enter startup commands;
- preview the resulting layout and exact commands;
- validate before save and again before launch.

Any project containing startup commands shows a final launch review. The review names the active Herdr connection, target folder, tabs, panes, and exact command text. Opening a shell-only project may proceed directly after validation.

The editor should use Bessie's existing workspace/layout visual language. It should not expose TOML or require terminal editing.

### Project actions

- **Open project**
- **Edit**
- **Duplicate**
- **Archive**
- **Delete…** with confirmation
- **Reveal project folder**
- **Copy folder path**
- **Save current workspace as project…**

`Save current workspace as project…` captures only structure Bessie can prove from the current snapshot/projection: tab labels, pane topology, split ratios, and pane labels. Capture a working directory only if the pinned Herdr contract exposes it authoritatively; otherwise initialize it from a user-selected folder and require review. Leave startup commands blank unless Bessie has an explicit trustworthy launch record; current process contents are never reverse-engineered into commands.

## Native materialization into Herdr

Add a `BessieProjectMaterializer` in `BessieCore`. It uses only Herdr's public JSON socket API and existing Bessie terminal-input seams.

The current `HerdrActionClient.perform` intentionally discards mutation response bodies and returns a fresh projection. The materializer must not discover new objects by labels or by set-difference guesses. Add typed decoders for Herdr creation responses and call `HerdrMutationAPI.request` through a narrow creation client that preserves the returned workspace, tab, and pane IDs.

Suggested files:

- `Sources/BessieCore/BessieProjectMaterialization.swift`
- `Tests/BessieCoreTests/BessieProjectMaterializationTests.swift`

### Launch algorithm

1. Validate the recipe and working directory.
2. Create a focused Herdr workspace with `workspace.create`.
3. Decode and capture the returned workspace, root-tab, and root-pane IDs using the protocol-17 response contract proven in Milestone 0.
4. Rename the root tab to the first recipe tab.
5. Create remaining tabs in order without stealing final focus.
6. For each tab:
   - use its root pane;
   - materialize each split only after its referenced parent pane exists;
   - set split direction and ratio;
   - apply optional pane labels.
7. After all topology exists, wait for every created pane to appear in a fresh snapshot and for the public input path to accept a bounded readiness probe. Do not detect shell readiness by matching prompt text.
8. Send each startup command through a dedicated public command-input adapter. Do not misuse terminal paste semantics or depend on a visible `GhosttyTerminal` controller.
9. Submit with Herdr's typed Enter-key path so terminal mode is respected.
10. Resnapshot Herdr.
11. Verify the created workspace ID, tab IDs, pane IDs, and expected topology exist.
12. Focus the intended first tab/pane and navigate Bessie to the live workspace.

Do not send commands while layout is still being constructed. This prevents full-screen applications from changing terminal behavior before later panes exist.

Milestone 0 proved protocol 17 lacks a semantic shell-ready signal. Jordan approved the fail-safe observable technique frozen below: bounded pane-output readiness polling, exact command submission, echo confirmation, then Enter. Either timeout stops without continuing blindly and leaves the workspace visible as partial.

### Milestone 0 protocol contract (frozen 2026-08-02)

Source inspection at the pinned Herdr compatibility revision `b4112743cff42452b5d18558bf2d55bbbfff8c69` and an isolated live Herdr 0.7.5 / protocol-17 probe establish these wire contracts. Every request and response uses the public NDJSON envelope `{"id":"<request-id>","method":"<method>","params":{...}}` / `{"id":"<request-id>","result":{...}}`.

| Operation | Exact request params | Successful `result` |
| --- | --- | --- |
| `workspace.create` | `cwd?: string`, `focus: bool`, `label?: string`, `env?: object` | `{"type":"workspace_created","workspace":WorkspaceInfo,"tab":TabInfo,"root_pane":PaneInfo}` |
| `tab.create` | `workspace_id?: string`, `cwd?: string`, `focus: bool`, `label?: string`, `env?: object` | `{"type":"tab_created","tab":TabInfo,"root_pane":PaneInfo}` |
| `pane.split` | `target_pane_id?: string`, `workspace_id?: string`, `direction:"right"|"down"`, `ratio?: number`, `cwd?: string`, `focus: bool`, `env?: object` | `{"type":"pane_info","pane":PaneInfo}` |
| `workspace.rename` / `workspace.focus` | `workspace_id: string`, plus `label: string` for rename | `{"type":"workspace_info","workspace":WorkspaceInfo}` |
| `tab.rename` / `tab.focus` | `tab_id: string`, plus `label: string` for rename | `{"type":"tab_info","tab":TabInfo}` |
| `pane.rename` / `pane.focus` | `pane_id: string`, plus `label: string|null` for rename | `{"type":"pane_info","pane":PaneInfo}` |
| `pane.send_input` | `pane_id: string`, `text: string`, `keys: [string]` | `{"type":"ok"}` |
| `pane.send_keys` | `pane_id: string`, `keys: [string]` | `{"type":"ok"}` |

The isolated live response returned workspace `w1`, root tab `w1:t1`, root pane `w1:p1`, second tab `w1:t2`, its root pane `w1:p2`, and split pane `w1:p3`. Duplicate labels were deliberately used. Each ID came directly from its creation response and every returned ID was then found by exact equality in a fresh `session.snapshot`; labels, ordering, and collection differences played no role. Future typed decoders must reject a mismatched response `type` or a missing required object/ID rather than attempting correlation.

Protocol-17 `PaneInfo` has optional `cwd` and `foreground_cwd`; `WorkspaceInfo` has no workspace cwd. Herdr derives `cwd` from its terminal/runtime state and `foreground_cwd` from the foreground process when available. The isolated snapshots exposed both fields for all three created panes and canonicalized the requested `/var/.../project-cwd` spelling to `/private/var/.../project-cwd`. Save-current-workspace may capture the project folder only when every pane needed by the recipe has a present, canonicalized, unambiguous `cwd` compatible with one project working directory. If any required cwd is absent or the pane cwd values disagree, Bessie must require the user to select or confirm the project folder. It must not use `foreground_cwd` as the saved project root or infer a path from output, prompts, arguments, labels, or process text.

Protocol 17 does **not** expose a semantic shell-ready signal. `pane.send_input` and `pane.send_keys` return `{"type":"ok"}` when bytes enter the runtime queue, not when the shell consumes them. Herdr Plus handles this by polling `pane.read` until the pane is nonblank, typing the command, polling until an echo probe appears, then sending Enter. Its implementation at commit `a9aca9da3ca6d7406f3d878a1df1c1b9775e2723` polls every 50 ms for up to 5 seconds and proceeds blindly after timeout.

Jordan approved the same observable two-stage technique for Bessie on 2026-08-02 with stricter failure semantics. Bessie may use bounded polling to observe nonblank pane output, submit the exact reviewed command without a newline, and confirm a stable command echo before sending a real Enter key. A readiness timeout stops before command submission. An echo timeout stops before Enter. Either timeout produces a visible partial launch failure and leaves the workspace alive; Bessie never continues blindly or reports success from the mutation's `ok` response alone. Shell-specific prompt matching, fixed wait-and-hope sleeps, and visible-controller dependence remain prohibited.

Materialization identity and failure boundaries are frozen as follows for that later implementation:

- Scope every launch to `(BessieConnectionDefinition.id, canonical socket path, in-memory connection generation)`. Mint a new generation after every successful bootstrap; never persist it. A disconnect, reconnect, connection switch, runtime/socket change, or app quit invalidates the generation and cancels orchestration. Raw Herdr IDs are meaningful only inside that scope, preventing collisions such as `w1:p1` across sessions or server restarts.
- Before each mutation, check cancellation and generation. After each successful creation, retain only the exact returned IDs, take a fresh snapshot on the same generation, and verify those IDs before continuing. A response without its authoritative IDs is failure, not permission to inspect labels or compute a collection diff.
- Cancellation before `workspace.create` performs no mutation. Cancellation or disconnect after workspace creation stops before the next mutation, makes no retry or rollback attempt, and reports the known workspace ID as partial if the same generation can still be snapshotted. If it cannot, report the last acknowledged stage as unverified rather than success.
- Disconnect during `tab.create` or `pane.split` leaves the outcome unknown because the server may have applied the request before the response was lost. Do not resend it. On a later explicit user action, resnapshot and expose the surviving workspace without inferring which unlabeled object corresponds to the lost response.
- App quit or connection switch cancels only Bessie's in-memory orchestration. It never closes the workspace, pane, Herdr server, or process. A later launch starts no automatic retry and trusts no stale live ID without same-endpoint revalidation.
- Failure before command submission leaves the verified topology visible. A readiness timeout sends no command. An echo timeout sends no Enter and is partial because text may remain in the line editor. Failure after Enter is partial and non-retriable because Bessie cannot assume what the shell executed; final topology success still requires a fresh snapshot on the same generation.

This contract is approved for the V1 spike. Milestone 0 may complete after focused tests prove timeout safety, echo-probe behavior, exact command preservation, and no blind fallback. General Project model, store, materializer, and UI implementation remain deferred to later staged loops.

### Materialization result

Return structured progress and result types:

```swift
struct BessieProjectLaunchResult {
    let projectID: UUID
    let workspaceID: String
    let tabIDsByRecipeID: [UUID: String]
    let paneIDsByRecipeID: [UUID: String]
}

struct BessieProjectLaunchFailure: Error {
    let projectID: UUID
    let workspaceID: String?
    let stage: Stage
    let message: String
    let partial: Bool
}
```

Never find the created workspace by label. Labels can duplicate. Use IDs returned by Herdr and verify them with a fresh snapshot.

### Failure behavior

Materialization is sequential and cannot be assumed transactional.

- Failure before `workspace.create`: remain in Projects; nothing was created.
- Failure after workspace creation: resnapshot and show the surviving partial workspace.
- Do not retry automatically; that could create a duplicate workspace.
- Do not automatically close a partial workspace; it may contain useful output or running processes.
- Offer **Open partial workspace** and a separately confirmed **Close partial workspace** action.
- Record the exact failed stage and recipe tab/pane to make repair straightforward.

Quitting Bessie during or after launch must not terminate the Herdr server or successfully launched pane processes.

## View-model integration

Use a Projects-specific view model/coordinator rather than adding launch orchestration to `ConnectionViewModel.actionInFlight`:

- catalog loading/loaded/error;
- selected project;
- editor draft and validation;
- per-project opening state;
- partial launch result;
- transient launch records keyed by Bessie project UUID, Bessie connection ID, endpoint/socket identity, and Herdr workspace ID.

Catalog storage is local and can load before Herdr connects. Opening actions require a compatible connected Herdr endpoint.

When the runtime/socket changes:

- cancel UI expectations tied to the old endpoint;
- retain project recipes;
- discard or revalidate transient workspace links;
- never rewrite a recipe from live Herdr state automatically.

Public IDs may collide across sessions. Revalidation must use the same endpoint identity that created the launch record. Quitting Bessie cancels only remaining orchestration; already-created Herdr state and processes remain alive.

## Herdr Plus migration, not dependency

Existing Herdr Plus users should not have to manually recreate every recipe, but migration must be strictly optional and one-way.

### One-time importer

A later migration task may add **Import Herdr Plus Projects…**:

1. User selects the Herdr Plus projects folder or Bessie detects a conventional local folder and asks permission.
2. A migration-only TOML decoder reads the supported subset.
3. Bessie previews every conversion.
4. User chooses which recipes to import.
5. Bessie writes native project JSON with new UUIDs.
6. Imported projects are independent from then on.

Rules:

- No Herdr Plus installation requirement.
- No invocation of the Herdr Plus binary.
- No shared storage.
- No background synchronization.
- No promise that editing one side updates the other.
- Unsupported worktree behavior or schema extensions are reported, not guessed.
- Import code remains in an isolated migration adapter and never becomes Bessie's primary project model.

For Jordan's current 16 simple recipes, a repository-local one-time migration fixture/script may be used during implementation to validate conversion without making Herdr Plus part of the shipped runtime.

## Worktrees

Worktree creation remains a separate follow-up. Native Projects should first ship ordinary workspace materialization.

When worktrees are added, Bessie should model them natively and call Herdr's public `worktree.create`. It should not inherit Herdr Plus's event-driven worktree recipe behavior or branch-prefix configuration implicitly.

## Test plan

### Project model/store tests

- valid project round-trip
- schema migration
- duplicate names with distinct UUIDs
- validation of roots, references, ratios, and cycles
- atomic save behavior
- stale-write conflict behavior and recovery
- one corrupt file isolated from healthy projects
- duplicate/archive/delete semantics
- Trash failure preserves the source project
- UUID/filename mismatch isolation
- command newline rejection and exact-text round-trip
- no persistence of live Herdr IDs in recipe JSON

### Materializer unit tests

Use a fake `HerdrMutationAPI` to assert exact ordering:

- validate before any mutation
- create workspace once
- rename/create tabs in recipe order
- split only after referenced parent exists
- preserve ratios and labels
- finish topology before commands
- decode exact creation-result IDs rather than inferring by label or collection difference
- wait for typed input readiness, send exact text, then send Enter
- return exact Herdr IDs
- structured failures at every stage
- no auto-retry or auto-close after partial failure
- cancellation before workspace creation makes no mutation
- cancellation after workspace creation returns a partial result and never rolls back automatically
- a connection switch invalidates the launch and never applies later actions to the new endpoint
- partial failures identify connection/session, endpoint, project UUID, recipe tab/pane UUID, and the last verified Herdr IDs

### Live isolated Herdr tests

Extend `scripts/mac-verify.sh` with Bessie-native JSON fixtures:

- two ordinary tabs with commands;
- mixed right/down pane topology and non-default ratios;
- pane labels;
- duplicate project names;
- a command whose pane output can be asserted;
- missing directory failure;
- partial command failure;
- duplicate labels without ID confusion;
- missing or malformed IDs in mutation responses;
- app quit during materialization leaves created Herdr state alive and prevents remaining actions.

Assert through live Herdr snapshot and pane reads:

- exact workspace ID and cwd;
- tab/pane labels and order;
- split tree and ratios;
- startup command output;
- intended focus;
- default Herdr session untouched;
- workspace/process survival after Bessie quits and reopens.

### Native UI verification

Capture and inspect:

- empty Projects onboarding;
- populated catalog;
- project editor and folder picker;
- graphical pane-layout editor;
- command preview;
- opening progress;
- validation errors;
- partial workspace recovery;
- save-current-workspace flow.

Required checks remain:

```bash
./scripts/check.sh
./scripts/mac-verify.sh
```

Then package, install `/Applications/Bessie.app`, relaunch, and verify the installed executable and live Herdr behavior.

## Delivery sequence

### Milestone 0 — Protocol and product contract spike

1. Record exact protocol-17 response shapes for `workspace.create`, `tab.create`, and `pane.split` using the isolated runtime.
2. Prove the public headless input/readiness path for a newly created shell without requiring a visible terminal controller or prompt-text matching.
3. Confirm which cwd facts are authoritative in the snapshot used by `HerdrSessionProjection`.
4. Define cancellation and disconnect behavior at every mutation boundary.
5. Freeze the first-release schema, command trust rules, archive representation, and local-only connection gate.

**Exit:** implementation has no unresolved dependency on guessed IDs or cwd. Startup commands use the approved bounded observable readiness-and-echo contract and fail safely without Enter on timeout.

### Milestone 1 — Native model and storage

1. Add Codable project models, validation, and schema versioning.
2. Add atomic project store and isolated corruption handling.
3. Add unit tests and fixture projects.

**Exit:** Bessie can safely create, load, edit, duplicate, archive, and delete native project recipes without Herdr Plus.

### Milestone 2 — Herdr materializer

1. Add typed materialization plan/results.
2. Build workspace/tab/pane topology through public Herdr APIs.
3. Add shell-readiness and startup-command sequencing.
4. Add structured partial failures and resnapshot verification.
5. Pass isolated live Herdr tests.

**Exit:** BessieCore opens a native project into an ordinary Herdr workspace and returns verified runtime IDs.

### Milestone 3 — Projects catalog and editor

1. Add Projects destination and searchable catalog.
2. Add native project editor and layout preview.
3. Wire edit/duplicate/archive/delete/reveal actions; opening remains behind the verified materializer from Milestone 2.
4. Add command-palette and accessibility coverage.

Put Projects-specific views and state in new files rather than expanding the already-large `ProductSurfaces.swift`.

**Exit:** Projects can be safely authored and managed without Herdr Plus, including while disconnected.

### Milestone 4 — Open and recover

1. Add final launch review for projects with commands.
2. Wire opening to the active compatible local connection.
3. Present structured progress without blocking unrelated Bessie interaction.
4. Navigate to created or partial workspaces by exact ID.
5. Revalidate transient running-instance links against fresh connection-specific snapshots.

**Exit:** a reviewed native Project opens into ordinary Herdr state, and partial failures remain visible and non-destructive.

### Milestone 5 — Save workspace as project

1. Convert authoritative Herdr snapshot topology into a project draft.
2. Make unverifiable startup commands explicitly blank.
3. Let the user review/edit before saving.

**Exit:** A useful live Herdr layout can become a reusable Bessie project without pretending Bessie can infer command history.

### Deferred follow-up — Optional Herdr Plus migration

1. Add isolated one-time import adapter or migration utility.
2. Preview and explicitly confirm conversion.
3. Verify Jordan's current simple recipes convert correctly.
4. Keep imported projects independent.

**Exit:** Existing users can migrate without making Herdr Plus a Bessie dependency.

### Milestone 6 — Release verification

Run full Mac, live Herdr, visual, packaging, installation, relaunch, and survival checks.

## Acceptance criteria

- Bessie Projects works when Herdr Plus is absent.
- The shipped Bessie app contains no vendored Herdr Plus source or binary.
- Bessie owns recipe CRUD and native project UX.
- Herdr owns every resulting live runtime object and remains directly usable through ordinary Herdr.
- Bessie creates layouts using only public Herdr APIs and terminal bridges.
- Recipes never persist live Herdr IDs or terminal/process state.
- Opening verifies exact returned IDs with a fresh snapshot.
- Startup commands are shown exactly before launch, are not interpolated, and use a proven public input/readiness path.
- Partial failures are visible, non-destructive, and never auto-retried.
- Save-current-workspace captures only facts Bessie can prove and requires user input for an unavailable cwd.
- Quitting Bessie leaves Herdr workspaces and processes running.

## Explicit non-goals

- Vendoring Herdr Plus
- Requiring or invoking Herdr Plus at runtime
- Maintaining Herdr Plus TOML as Bessie's native format
- Bidirectional synchronization with Herdr Plus
- Persisting a shadow copy of live Herdr state
- Inferring startup commands from arbitrary running terminal contents
- Automatic rollback of partial Herdr workspaces
- Worktrees in the first native Projects release
- Remote Projects before Bessie's remote control/terminal bridge is complete
- Secrets management in project recipes
- Running startup commands through arbitrary sleeps, prompt-text matching, or a required visible terminal controller

## Approval gate

Before implementation begins, Jordan should explicitly approve:

1. Projects as roadmap priority 2 after the bundled-runtime release train;
2. local-only opening for the first release;
3. final launch review whenever startup commands are present;
4. Herdr Plus import as deferred follow-up rather than a release requirement;
5. the Milestone 0 fail-safe Herdr Plus technique: bounded pane-output polling and command-echo confirmation are allowed, but fixed wait-and-hope sleeps and blind timeout fallback are not.

Jordan granted final concept approval on 2026-08-01 with staged Amp goal loops and approved the fail-safe Herdr Plus readiness technique on 2026-08-02. Milestones 1–6 remain gated on completing Milestone 0 evidence and tests.
