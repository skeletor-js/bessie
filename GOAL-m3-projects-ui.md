# Goal: Implement Native Bessie Projects catalog and editor (Milestone 3)

**Status:** Complete (catalog/editor scope); full package/UI screenshot deferred until after M2 package pipeline
**Owner:** Hermes supervising an Amp implementation agent
**Parallel with:** Milestone 2 materializer (`GOAL.md`, agent `bessie-projects-materializer`, pane `w1S:pK`)

## Objective

Implement only the native Projects catalog and editor experience in BessieApp, backed by the already-complete `BessieProject` / `BessieProjectStore` APIs. Users must be able to browse, search, create, edit, preview, duplicate, archive, delete (Trash), reveal folder, and copy path **while disconnected**.

Do **not** implement live Open/materialization, launch review execution, workspace capture, Herdr Plus, or release signing. Open may appear in the UI as present-but-disabled / “coming once materializer lands,” or as a no-op stub that never calls Herdr.

## Read first

1. `AGENTS.md`
2. this file (`GOAL-m3-projects-ui.md`) — **not** `GOAL.md` (that belongs to Milestone 2)
3. `docs/plans/2026-07-31-native-bessie-projects.md` — catalog/editor sections
4. `Sources/BessieCore/BessieProjects.swift`
5. `Sources/BessieCore/BessieProjectStore.swift`
6. `Sources/BessieApp/ProductSurfaces.swift` — destination rail / shell patterns only
7. `Sources/BessieApp/BessieDesignSystem.swift`
8. `Sources/BessieApp/KeyboardShortcutCoordinator.swift` and `Sources/BessieCore/KeyboardShortcuts.swift`

## Parallel ownership rules (mandatory)

### You own

- New Project UI/state files under `Sources/BessieApp/` (preferred names):
  - `ProjectsSurface.swift` / `ProjectsCatalogView.swift`
  - `ProjectEditorView.swift`
  - `ProjectLayoutPreview.swift`
  - `ProjectsViewModel.swift` or equivalent coordinator
- Focused app-model tests under `Tests/BessieAppModelTests/` for Projects catalog/editor state
- Minimal destination / command-palette wiring needed to reach Projects

### You may touch only surgically

- `ProductSurfaces.swift`: add a **Projects** destination beside Workspaces; route content to the new surface; keep diffs small
- `KeyboardShortcuts.swift` / command palette: add Projects navigation and safe CRUD commands that do not open Herdr
- `docs/reports/goal-progress.md`: **append only** a clearly titled `## Projects Milestone 3` section

### Do not touch (Milestone 2 / shared Core)

- `Sources/BessieCore/BessieProjectMaterialization.swift`
- `Sources/BessieCore/HerdrProtocolContract.swift`
- `Sources/BessieCore/BessieProjects.swift` model/schema changes (consume as-is)
- `Sources/BessieCore/BessieProjectStore.swift` internals (consume public API as-is)
- `Tests/BessieCoreTests/BessieProjectMaterializationTests.swift`
- `Tests/BessieCoreTests/LiveHerdrTests.swift` materializer cases
- `GOAL.md`
- Ordinary Herdr sessions (`default`, production `bessie`)
- Commit, stage, push, publish, deploy, notarize

If a store/model API gap blocks the editor, **stop and report** the exact missing API rather than rewriting Core. Hermes will sequence a tiny Core follow-up.

### Mac verification exclusivity

Two agents share one Mac mirror and package pipeline.

1. Prefer focused `swift test --filter …Projects…` / app-model tests during development.
2. Run `./scripts/mac-verify.sh` only when Milestone 2 is **not** currently packaging/installing.
3. If mac-verify is contended, finish with focused Mac tests + `./scripts/check.sh` + `git diff --check`, document the contention, and stop rather than fighting rsync/package locks.
4. Always use injected `BESSIE_PROJECTS_PATH` (temp dir) for any app/UI verification that touches storage. Never write the real user Projects directory.
5. Never use destructive rsync against the Mac mirror.

## Product requirements

### Destination

- Add **Projects** as a first-class rail destination beside Workspaces.
- Works with an active product shell; catalog/editor logic must not require a healthy Herdr connection for CRUD (store is local). If the shell is only reachable when connected today, still ensure view models and store operations are connection-independent and unit-tested offline.

### Catalog

- List projects from `BessieProjectStore` with injected/testable root.
- Search by name, description, group, and working-directory path.
- Optional group sections + ungrouped.
- Show name, folder, tab/pane counts, and notable startup commands.
- Surface catalog issues (corrupt files, mismatches) without hiding healthy projects.
- Empty, loading, and error states.

### Editor

Native create/edit surface (sheet or full destination detail) supporting:

- name, description, optional group
- folder selection via `NSOpenPanel` (absolute directory only)
- add/rename/reorder/duplicate/remove tabs
- graphical split add/remove (right/down) with ratios and pane labels
- startup command fields (reviewed text only; no env/secrets)
- live validation using existing `BessieProject` validation
- layout + command preview
- save create/update through store revision/conflict APIs
- discard/cancel without writing

Do not expose TOML or require terminal editing.

### Actions

Wire:

- Edit
- Duplicate
- Archive / Unarchive
- Delete… with confirmation → store Trash path
- Reveal project folder (Finder)
- Copy folder path
- Create project

**Open project:** visible but disabled, or clearly stubbed with copy that opening lands in Milestone 4 after materializer verification. Must not call Herdr or materializer APIs yet.

**Save current workspace as project…:** omit or disable with “Milestone 5” affordance — do not implement capture here.

### Filename mismatch recovery

If the store surfaces a recoverable filename mismatch and `recoverFilenameMismatch` exists, expose a safe recovery action in the catalog issue UI. Never overwrite a healthy canonical neighbor.

## Design

- Use existing Bessie design tokens / surface language from `BessieDesignSystem`.
- Match workspace/layout visual language for the pane preview.
- Accessibility: labels, buttons, and destructive confirms must be usable from keyboard/VoiceOver basics.
- Keep Project UI out of the giant bodies of unrelated product surfaces except the minimal destination switch.

## Testing

Failure-first tests for:

- catalog search/filter/group
- offline create/edit/save/duplicate/archive/delete against temp store root
- validation errors block save
- stale revision / conflict surfaces without data loss
- corrupt companion files remain visible as issues while healthy projects list
- Open action does not invoke Herdr
- destination / command-palette entry reaches Projects

UI tests may be lightweight view-model tests if full SwiftUI hosting is heavy; prefer deterministic model tests over flaky UI automation.

## Verification

1. Focused Projects app/model tests on the Mac
2. `./scripts/check.sh`
3. `git diff --check`
4. Full suite / `./scripts/mac-verify.sh` only if not contending with M2
5. Confirm staging empty; ordinary Herdr untouched; real Projects dir untouched

Append exact evidence under `## Projects Milestone 3` in `docs/reports/goal-progress.md`.

## Pause conditions

Stop and report rather than inventing scope if:

- Core store/model lacks an API the editor truly needs
- Open/materialization pressure creeps in
- Capture/save-current-workspace is required to make the catalog useful (it is not)
- Design-system assets are missing for a layout preview and a honest simpler preview is unclear
- Mac package pipeline is locked by M2 for final verification

## Definition of done

Milestone 3 is complete only when:

- Projects is a real destination with searchable catalog
- create/edit/preview/duplicate/archive/delete/reveal/copy-path work against local store
- disconnected/offline store operations are tested
- Open is explicitly not live-wired
- no materializer/Core contract edits, no ordinary session mutation, no commit/push/notarize
- verification evidence is appended and checks pass within the parallel exclusivity rules
