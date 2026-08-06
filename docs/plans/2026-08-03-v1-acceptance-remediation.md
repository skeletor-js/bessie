# Bessie V1 acceptance remediation and release-hardening plan

**Date:** 2026-08-03  
**Status:** Implementation-ready product correction plan; no release approval implied  
**V1 slice:** M — acceptance remediation, followed by expanded K hardening  
**Order:** Preserve current verified baseline → M0–M7 → K performance/stability/release gate  
**Primary acceptance source:** Jordan's 2026-08-02 hands-on feedback  
**Visual references:** workstream `source-material/visual-explorations/native-v1-design-screens/`, especially `bessie-herd-design-final.png`; approved cowprint source `source-material/visual-explorations/cow-print-background-v1.html`

## 1. Outcome

Bessie V1 is not ready until every hands-on issue below is either fixed and evidenced or explicitly waived. The resulting product should:

1. open quickly and keep terminal interaction perceptually immediate;
2. behave like a faithful graphical Herdr client rather than a parallel workspace model;
3. make pane focus, status, connection scope, onboarding, and notifications obvious and testable;
4. remove prototype copy, redundant chrome, and setup-specific data;
5. restore the approved Bessie visual identity in light and dark appearances;
6. make The Herd the single, trustworthy place for agent status and needs-you routing;
7. include a bounded Zen mode in V1;
8. finish with measured speed, terminal, stability, clean-install, signing, and notarization gates.

The implementation must preserve the existing Herdr ownership boundary. In particular, mouse-aware TUI input is a Herdr public-protocol dependency, not permission to copy Herdr's private bincode protocol or invent a Bessie-only terminal model.

## 2. Feedback lock: nothing gets lost

### 2.0 M8 hands-on supersessions (2026-08-03)

The following later hands-on decisions supersede conflicting details below:

- Remove cowprint motion entirely, including the motion control and animation machinery.
- Remove the cowprint contrast control. Use the former slider maximum (`0.10`) in Light mode and former minimum (`0.015`) in Dark mode.
- Render one continuous cowprint at the app root. Sidebar, pane chrome, cards, and other shell layers use subtle semitransparent/frosted treatments over that single backdrop; they must not render independent repeated cowprints.
- Add stable app-owned feature flags. `fileBrowserEditor` and `followFiles` default off for V1 and hide their routes/chrome without deleting the retained implementations.
- Add a visible pane-level Zen entry button.
- Make workspace close discoverable. Closing a final tab or pane must close the authoritative Herdr workspace and reconcile selection from a new snapshot.
- Replace native ellipsis menus with accessible Bessie-styled action popovers.
- Sidebar order is collapsible **The Herd**, **Projects**, **Workspaces**, then **Panes**. Remove the sidebar **Tabs** section. The Herd mirrors the official Herdr TUI's complete agent roster; Panes lists every pane. Pin Settings at the bottom with an adjacent Dark/Light toggle.
- Pane switching and intermittent white terminal surfaces are release defects requiring lifecycle diagnosis, measured switching evidence, and live regression checks.
- File/media behavior remains tested behind its flags: valid Markdown and local images must not fail with opaque `WorkspacePathError` messages.

| # | Feedback | Product decision | Acceptance evidence |
| --- | --- | --- | --- |
| 1 | Cowprint motion does not work | Replace whole-tile drift with visible, restrained edge deformation matching the approved exploration. Keep Reduce Motion and the motion toggle authoritative. | 5–8 second light/dark recordings plus automated nonzero pixel-delta test when motion is on and zero-delta test when paused. |
| 2 | Need a test-notification button | Add **Send test notification** to Notifications settings. It requests permission when needed, uses the real coordinator, presents a representative Bessie notification, and routes to the active pane when one exists. | Unit tests for permission/routing states and live notification delivery + click routing on the packaged app. |
| 3 | Startup is slow | Instrument cold launch, warm reattach, runtime validation, first snapshot, shell display, terminal-controller start, and first full frame. Optimize only from measured spans. | Performance report with p50/p95 timings and signpost trace on packaged app. |
| 4 | Terminal feels laggy | Instrument input enqueue → Herdr write → frame receive → libghostty application. Remove avoidable main-actor work, duplicate fits/resizes, and frame churn. | Local keystroke-to-visible-echo and sustained-output results against explicit budgets in §11. |
| 5 | Remove “Remote workspace files over SSH…” | Delete this explanatory sentence and any equivalent prototype copy. Files should explain only what is needed in the current state. | String audit and screenshots of local/remote Files states. |
| 6 | Remove “1 pane” and “Live” in top-right | Remove redundant count/live chips from workspace chrome. Status belongs in the sidebar/state glyphs. | Workspace screenshot with no redundant chips. |
| 7 | New Pane UI and adjacent ellipsis are unnecessary | Remove the global **New pane** button/sheet entry point and its adjacent overflow. Use the Workspaces/Tabs/Panes `+` controls to invoke ordinary Herdr create/split actions. Keep agent launch as an explicit secondary choice against a real pane. | Live creation checks prove resulting objects are ordinary Herdr workspaces/tabs/panes and visible from the Herdr TUI. |
| 8 | Focused pane outline does not swap | Make one focus contract: the white outline marks the pane receiving terminal input. A click makes the libghostty view first responder, calls `pane.focus`, reconciles a fresh projection, and moves the outline. | Two-pane click and keyboard focus tests plus live Herdr snapshot assertion after every swap. |
| 9 | Breadcrumbs are not needed; tabs belong there | Replace workspace breadcrumbs with the current workspace's tab strip inside the top bar. Remove the duplicate tab strip elsewhere. Non-workspace surfaces use a plain title. | Workspace screenshot and tab focus/create/close checks. |
| 10 | Strip Jordan/setup-specific content | Audit all shipping sources, resources, defaults, sample records, onboarding copy, screenshots, and packaged strings. Remove names, hosts, sessions, paths, workspace labels, and assumptions tied to one environment. Tests may use clearly synthetic fixtures. | Build-artifact string audit fails on a maintained denylist; clean profile launches with generic data only. |
| 11 | Mouse clicks in mouse-aware TUIs must work | Treat typed, negotiated inner-terminal mouse input as a V1 release blocker. Add/version a public Herdr terminal-controller mouse capability, then route button, drag, motion, coordinates, modifiers, and wheel through it. Preserve a modifier for local selection. No escape-sequence guessing. | Live checks in at least two mouse-aware TUIs, host selection regression, alternate-screen wheel check, and capability-off honest fallback. |
| 12 | Sidebar should show status, not only names | Every workspace, tab, and pane row gets a Herdr-derived semantic status glyph. Aggregate workspace/tab state by blocked → working → done → idle → unknown. | Projection tests and seeded screenshots covering every state. |
| 13 | Remove Workspaces nav; rename Open to Workspaces; add `+` to Workspaces/Tabs/Panes | Remove the standalone Workspaces destination. Rename the live-workspace group to **Workspaces**. Add small accessible `+` buttons to all three group headers. | Sidebar screenshot, keyboard accessibility, and live create/split actions. |
| 14 | No number beside pane-name dot; dot is status | Remove pane/workspace/tab count suffixes from entity rows. The dot is status only. Counts may appear in dedicated overview/filter contexts, never glued to a status glyph. | Sidebar screenshot and accessibility labels that name state without redundant counts. |
| 15 | “Group (Team or Category)” is unexplained | Remove the unused `group` field from the V1 Project editor and catalog UI. Preserve decode/migration compatibility for existing schema-v1 records; do not silently discard stored data during migration. | Migration tests and editor screenshot. |
| 16 | Projects should support multiple folders | Introduce Project schema v2 with one primary folder plus ordered additional folders. Tabs/panes may select an allowed folder as cwd; launch still materializes ordinary Herdr objects using absolute cwd values. | v1→v2 migration tests, multi-folder editor, launch verification, and ordinary Herdr attach check. |
| 17 | Popout modal corners mismatch | Consolidate sheet/popover/card radii into named shape tokens and apply them consistently. Do not fight native macOS window geometry; align Bessie-owned inner plates and overlays. | Radius audit and screenshots of onboarding, Project editor, launcher, palette, and confirmation surfaces. |
| 18 | Bessie logo invisible in light mode | Render the logo as a template/tint-aware mark or ship explicit light/dark variants with tested contrast. | Light/dark snapshot and contrast assertion. |
| 19 | Onboarding cannot configure settings; Finish does nothing | Make onboarding a guided setup surface over the same models/components used by Settings. Let users choose runtime, local/SSH connection, session, Project/folder, notification permission, and appearance as relevant. Finish atomically marks onboarding complete, dismisses the overlay, focuses a ready terminal, and persists completion. | Fresh-profile UI test, relaunch test, Settings consistency test, and explicit Finish regression test. |
| 20 | “All Connections” should be a host-filter dropdown | Replace the Settings shortcut with a menu showing **All connections**, Local, and each configured remote host with health/status. Scope Herd, workspace rows, tabs/panes, and relevant Files content to the selected filter. Selecting a concrete workspace activates its owning connection before opening it. | Two-host seeded tests and live local+SSH filter/routing check. |
| 21 | Herd and Attention feel too similar | Remove the standalone Attention destination. Fold blocked/needs-you filtering, count, blocked-first ordering, Open pane, next-needs-you routing, and notification coherence into The Herd. | No Attention sidebar destination or surface; blocked-only Needs you filter and routing tests pass in Herd. |
| 22 | Bring Zen mode into V1 | Promote a bounded Zen mode: one real terminal, minimal herd spine, obvious exit, next-agent, and next-needs-you commands. It is presentation only. | Shortcut, focus, blocked cue, reconnect, and exit tests; Herdr state remains unchanged. |
| 23 | Reorganize Settings | Use General, Connections, Projects, Terminal, Notifications, Appearance, and Advanced/Diagnostics. Reuse setting rows in onboarding. | Settings screenshots and navigation/accessibility checks. |
| 24 | Herd does not match the mockups | Rebuild against the retained native Herd design screen and the behavioral contract in §7, except where this feedback explicitly supersedes old mockup chrome. | Seeded blocked/working/done/idle and empty-state captures reviewed side by side with the retained reference. |

## 3. Governing interaction contracts

### 3.1 Sidebar and top bar

The sidebar becomes navigation plus live Herdr topology, not a directory of duplicate product concepts:

- Product destinations: **The Herd**, **Projects**, **Files**.
- No standalone **Workspaces** destination.
- Connection filter at top: menu, not Settings shortcut.
- Entity groups when applicable:
  - **Workspaces** `+`
  - **Tabs** `+`
  - **Panes** `+`
- Each entity row: status glyph, name, selection treatment. No pane counts at row end.
- Group `+` actions map directly to public Herdr mutations:
  - Workspaces `+` → `workspace.create` with a compact folder/name prompt only where required;
  - Tabs `+` → `tab.create` in the current workspace;
  - Panes `+` → menu for split right, split down, and start supported agent in a real pane.
- Destructive/less-common actions remain contextual to the entity; remove the redundant top-bar New Pane + ellipsis pair.

Workspace top bar:

- no `Hermes VPS / Bessie / Agents` breadcrumb;
- current tabs occupy the top bar and remain directly clickable;
- no `1 pane` or `Live` chips;
- the active tab and pane are derived from the fresh Herdr projection;
- one white pane border marks the actual terminal first responder/input target.

### 3.2 Connection scope

Add a presentation-only `ConnectionScope`:

```swift
enum ConnectionScope: Equatable, Sendable {
    case all
    case connection(id: String)
}
```

It filters Bessie's projections; it does not create a second connection/session model. Rules:

1. All connections aggregates fleet-level Herd and workspace navigation.
2. A selected host filters every host-aware surface and preserves status/health in the menu.
3. Opening a workspace/pane owned by another host first activates that connection, then focuses the exact Herdr IDs.
4. Projects remain visibly local-only until remote Project support is separately designed; the filter must not imply otherwise.
5. Connection failures remain visible in the menu and as scoped degraded states.
6. Persist only the user's selected scope preference. Revalidate missing connection IDs on launch and fall back to All.

### 3.3 Focus

Bessie currently risks conflating local selection, SwiftUI navigation, AppKit first responder, and Herdr focus. Replace that with one state machine:

1. Pointer/keyboard selection requests `pane.focus` for the owning connection.
2. On success, install the returned projection and make that pane's `BessieTerminalView` first responder.
3. Render the white outline only when both the projection and responder target agree.
4. During request/reconnect, keep the prior input target marked or show a neutral pending state—never outline two panes.
5. External Herdr focus changes resnapshot and move Bessie's selection without stealing macOS focus from another app.
6. Sidebar row selection and pane outline consume the same focused-pane source.

### 3.4 Status glyphs

Use Herdr semantic state only. Workspace/tab aggregate precedence is:

`blocked > working > done > idle > unknown`

A shell pane without a semantic agent remains neutral/unknown rather than being labeled live. Tooltip and accessibility text name the status. Numeric counts belong in Herd filters or overview summaries only.

## 4. Projects v2: multiple folders without a shadow runtime

### 4.1 Model

Migrate from one `workingDirectory` to:

```swift
struct BessieProjectFolder: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var path: String
    var isPrimary: Bool
}

struct BessieProjectPane {
    // existing identity, label, command, placement
    var folderID: UUID? // nil resolves to primary folder
}
```

Rules:

- exactly one primary folder;
- additional folders are ordered, unique after path normalization, and local directories for V1;
- every pane resolves to an absolute cwd before materialization;
- Project schema v1 migrates its `workingDirectory` to one primary folder;
- retain legacy `group` data in migration storage/round-trip if needed, but stop exposing it in V1 UI;
- startup commands remain reviewed exact text; no secrets fields or implicit `cd` shell wrapping;
- the resulting workspace/tabs/panes remain ordinary Herdr-owned objects.

### 4.2 Editor

Replace Group + Folder with a **Folders** section:

- primary folder row;
- `+ Add folder` using `NSOpenPanel` with multiple directory selection enabled;
- rename display label, reorder, remove, and mark primary;
- pane inspector chooses “Primary” or one additional folder;
- exact command preview includes resolved cwd;
- validation explains missing/unavailable folders without data loss.

Before implementation, verify whether Herdr `tab.create`/`pane.split` accepts the required cwd on every materialization path. If not, use the narrowest public sequence available or make the missing generic Herdr capability a release blocker—do not inject hidden `cd` commands.

## 5. Onboarding and Settings

### 5.1 Settings information architecture

1. **General** — launch/startup behavior, default Project/workspace, app-level behavior.
2. **Connections** — local runtime/session and SSH hosts; add/edit/test/remove.
3. **Projects** — default Project location/behavior and multi-folder explanation.
4. **Terminal** — font, key behavior, selection modifier, pane spacing.
5. **Notifications** — policy, authorization status, **Send test notification**, system-settings handoff.
6. **Appearance** — system/light/dark, density, app icon, cowprint on/intensity/motion, Reduce Motion explanation.
7. **Advanced & Diagnostics** — runtime selection/path, compatibility facts, logs/export, reset onboarding.

Do not duplicate model logic between onboarding and Settings. Extract reusable setting sections/rows and bind both surfaces to `BessieSettingsModel`, connection definitions, notification coordinator, and Projects model.

### 5.2 First-run path

1. Welcome and ownership explanation.
2. Runtime and connection: bundled default, explicit compatible system/custom choice, or configured SSH host.
3. Workspace/Project: choose existing Project, create Project with folder(s), or create a plain workspace.
4. Terminal preferences and input primer, including local selection modifier.
5. Notifications: explain policy, request permission, and offer a test.
6. Ready check: connected projection + workspace + pane + terminal full frame.
7. Finish: persist completion, dismiss onboarding, focus the ready terminal, and never reappear unless reset or setup becomes unrecoverable.

`Finish` must be a testable state transition rather than another call to generic `advanceSetup`.

## 6. Notifications

Add a coordinator method dedicated to tests, using the same `UNUserNotificationCenter` as production:

- `.notDetermined`: request authorization, then offer/send after the result;
- `.denied`: show exact status and Open System Settings;
- allowed: enqueue a uniquely identified immediate notification;
- representative title/body, clearly marked as a test;
- if an active pane exists, include a real `BessieNotificationDeepLink` to it;
- if no pane exists, clicking activates Bessie and opens Notifications settings or the relevant empty state without fabricating a pane;
- expose success/failure in Settings and diagnostic log;
- never mutate planner state or pretend an agent changed status.

## 7. The Herd owns status and needs-you routing

The Herd answers both: **What is every agent doing?** and **Which agents need me now?** A separate Attention destination is removed from V1 because Herdr exposes `blocked` as an agent state, not a durable attention-item model.

Use the retained `bessie-herd-design-final.png` as the card/hierarchy reference, updated by the new sidebar/top-bar contracts:

- All / Needs you / Working / Done / Idle filters with counts;
- **Needs you** includes connected authoritative Herdr agents whose `agent_status` is exactly `blocked`;
- blocked-first ordering in All;
- card anatomy: status glyph + agent identity, authoritative state, connection, workspace/tab location, bounded current title/activity when available, and one quiet **Open pane** action plus **Details** where useful;
- blocked cards receive the strongest status treatment without becoming a second card system;
- no duplicated `LOCAL`, `LIVE`, count, or badge soup;
- no invented semantic copy when Herdr reports unknown;
- compact responsive grid with deliberate card width and top alignment rather than a giant generic empty plate;
- empty states distinguish no agents from no filter matches and offer a contextual next action;
- New agent may remain only if it materializes an ordinary Herdr pane and `agent.start` through the public API.

### 7.1 Shared needs-you behavior

Keep `requiresUserAction` as a Core semantic predicate, not a destination or persisted model:

1. `requiresUserAction` is true only for `.blocked`; completion notification policy remains separate.
2. Build Herd from `fleet.agents` / authoritative `projection.agents`, never pane-reconstructed lossy agent values.
3. Apply selected `ConnectionScope` before cards and counts.
4. The Needs you filter count, blocked-first ordering, sidebar Herd cue, next-needs-you command, Zen blocked cue, and blocked notifications consume the same predicate.
5. When Herdr reports a non-blocked state or removes the agent, it leaves Needs you after authoritative reconciliation.
6. Disconnected hosts contribute no live needs-you count. Show host unavailability separately; never present cached status as live.
7. Do not persist attention records or add Resolved, All, snooze, dismiss, seen, age, reason, or local history.
8. No guessed Allow/Deny controls from terminal text. V1 resolution remains **Open pane** and answer in the real terminal.
9. Keep done visible in Herd and optionally notify on completion according to user policy; done never enters Needs you.

### 7.2 Remove the standalone Attention product surface

Implementation corrections against the integrated baseline:

- remove the **Attention** sidebar destination, `AttentionSurface`, and navigation route;
- remove `AttentionListBuilder`, `AttentionItemModel`, `ConnectionFleetViewModel.attentionAgents`, and tests that exist only for the duplicate list;
- rename next-attention commands and accessibility text to **next needs you** / **open next agent that needs you** while preserving shortcut behavior where useful;
- update workspace/sidebar blocked counts to use the shared Herd predicate;
- remove notification routing's generic “fall back to Attention” behavior. A stale or unavailable target shows an honest route error and lands in Herd or the relevant connection recovery state;
- retain no compatibility stub or empty hidden destination. A future dedicated Attention queue must be justified by durable typed Herdr attention objects.

### 7.3 Visual acceptance

Create deterministic seeded previews/captures for:

1. blocked + working + done + idle across local and remote;
2. All and every state filter, especially Needs you;
3. no agents;
4. no filter matches;
5. one degraded connection;
6. several blocked agents with clear blocked-first hierarchy.

Review side by side against the retained Herd reference; do not declare parity from code inspection alone.

## 8. Cowprint, logo, shape, and Zen

### 8.1 Cowprint motion

The current implementation translates a raster tile by a few points. That does not match the approved “restrained, almost living edge movement” and can appear static. Replace it with a low-amplitude domain-warp/edge-deformation treatment over a fixed composition:

- spots do not travel like wallpaper or a lava lamp;
- boundaries breathe/morph visibly at normal settings;
- each surface retains its unique crop/composition;
- light and dark use contrast-correct masks;
- motion pauses for app inactivity where practical, `cowPrintMotion == false`, or accessibility Reduce Motion;
- avoid a full-window redraw rate that harms terminal latency.

Prefer a GPU-backed SwiftUI/Metal shader or equivalent cached mask deformation. Do not regenerate large bitmap tiles on the main thread. Add a deterministic phase injection for tests.

### 8.2 Logo and radii

- Make `BessieLogoMark` appearance-aware and verify WCAG-style contrast against actual shell surfaces.
- Define and use a small shape vocabulary such as `surfaceRadius`, `controlRadius`, and `popoverInnerRadius`.
- Audit every Bessie-owned rounded overlay/sheet; remove arbitrary 2/6/8 values unless the token explicitly calls for them.

### 8.3 Bounded V1 Zen mode

Zen is a presentation mode over the currently focused real terminal:

- one libghostty pane fills the content area;
- sidebar/top bar hide;
- a minimal edge spine shows connection plus herd status dots and blocked cue;
- commands: Exit Zen, next agent, previous agent, next needs you;
- completion/blocked cues never steal terminal focus;
- connection loss and ownership conflict remain visible and actionable;
- entering/exiting Zen creates no Herdr objects and changes no durable topology;
- shortcut is owned by the app menu and must not consume ordinary terminal input unexpectedly.

## 9. Mouse-aware TUIs: upstream blocker and integration plan

The audited Herdr 0.7.5 public terminal-session bridge exposes raw input, resize, scroll, and release, but no negotiated typed mouse events or authoritative mouse-capture state. Bessie's current `mouseDown` only focuses the view and swallows ordinary clicks unless Shift is held for selection. This explains the reported failure.

### M0 protocol spike

Before Bessie UI implementation:

1. inspect current live Herdr schema/source and libghostty input APIs again;
2. define a generic public Herdr capability, not a Bessie extension, for:
   - capability negotiation/version;
   - current inner-terminal mouse mode/capture state;
   - button down/up, drag/motion, cell coordinates, pixel coordinates if supported, modifiers, and wheel;
   - clear behavior when host selection modifier is held;
3. implement and test it upstream in Herdr;
4. bundle the compatible Herdr version and update Bessie's compatibility lock;
5. route `BessieTerminalView` mouse events through the typed capability only when negotiated.

### Required behavior

- ordinary click in a mouse-aware alternate-screen TUI reaches the application;
- ordinary click outside mouse capture focuses the pane without injecting text;
- Shift (or the documented configured modifier) forces local selection;
- mouse drag reaches the app when captured and selects locally when forced;
- wheel does not both scroll Herdr history and the inner app;
- unsupported older Herdr versions show an honest capability limitation rather than swallowing clicks silently.

This item blocks public V1 unless Jordan explicitly waives it. A private-protocol copy, guessed ANSI mouse sequence, or local screen-mode inference is not an acceptable shortcut.

## 10. Personalization and shipping-content audit

Add a release check over `Sources/`, bundled resources, generated app resources, defaults, and extracted strings from the packaged executable. Seed denylist categories:

- personal names/usernames;
- real hostnames and SSH aliases;
- `/Users/<real-user>` and `/home/<real-user>` paths;
- real workspace/project labels such as environment-specific Hermes/Bessie/agent names;
- private URLs, email addresses, team IDs, and account identifiers;
- assumptions that all users have the same agents, folders, sessions, or remote host.

Keep tests synthetic (`example-user`, `example.test`, `/tmp/bessie-fixture`) and ensure previews cannot leak into the release bundle. The product name, its own `bessie` managed session name, supported agent names, and generic localhost concepts are not personalization leaks.

## 11. Performance budgets and measurement

These are release targets, not claims about the current build. Capture baseline before optimization and final numbers from the packaged app on the same Mac/power state.

### 11.1 Startup signposts

Record monotonic spans for:

- process start → first window content;
- settings/project-catalog decode;
- bundled-runtime validation;
- Herdr process reuse/start;
- socket ready;
- events subscribed;
- first authoritative snapshot installed;
- first workspace shell visible;
- terminal controller spawned;
- first `full: true` frame applied to libghostty.

Targets:

| Scenario | Target |
| --- | --- |
| First window content, cold process | p95 ≤ 0.75 s |
| Warm reattach to existing Herdr session: usable shell | p95 ≤ 1.5 s |
| Cold bundled Herdr start: usable shell | p95 ≤ 3.0 s |
| UI main-thread stall during startup | none > 100 ms after first window |

Likely optimization candidates to verify rather than assume:

- do not block first paint on every connection, Project catalog, notification status, or agent catalog;
- validate immutable bundled runtime metadata once per app version, then perform a cheap integrity/capability check;
- show shell chrome from the first snapshot while secondary fleet connections continue in background;
- create terminal controllers only for visible panes;
- cache static cowprint/logo assets and avoid animated full-window CPU work.

### 11.2 Terminal signposts

Attach sequence IDs/timestamps to debug-only input/frame instrumentation without changing production protocol semantics:

- AppKit event received;
- operation enqueued;
- write completed to Herdr controller/API;
- corresponding frame received when correlation is observable;
- frame bytes fed to `InMemoryTerminalSession`/libghostty;
- display commit/sample in the live automation harness.

Targets on local Herdr:

| Measure | Target |
| --- | --- |
| Printable key → visible echo | p50 ≤ 25 ms; p95 ≤ 50 ms; p99 ≤ 100 ms |
| Special key/paste ordering | 0 reorder/drop in 10,000-operation stress |
| Frame receive → libghostty feed | p95 ≤ 8 ms |
| Sustained output UI responsiveness | no input freeze > 100 ms; no unexplained sequence gaps |
| Resize storm | final grid converges within 250 ms after drag end |

Remote latency is reported separately against measured SSH RTT; do not hold it to the local budget or hide transport delay.

Audit `GhosttyPaneSurface.updateNSView`: `fitToSize()` must not trigger redundant resize work on every SwiftUI update. Audit diagnostic logging and `@Published` updates for per-frame main-thread churn. Batch/coalesce only presentation work; never reorder terminal bytes.

## 12. Additional approved V1 release safeguards

Jordan approved these as part of the 2026-08-03 acceptance pass. They are release requirements, not post-V1 suggestions.

### 12.1 One-window contract

- Bessie is single-window in V1.
- A second launch or New Window request activates the existing main window.
- Remove or disable unsupported Window/New Window commands.
- One window owns terminal controllers, connection scope, pane responder focus, notification routing, and Zen presentation.
- Multi-window behavior is deferred until Herdr controller ownership and Bessie focus semantics are deliberately designed.

### 12.2 Upgrade, migration, and rollback

- Version every persisted Bessie-owned format, including preferences, onboarding state, connections, and Projects.
- Project v1→v2 migration is transactional: write, decode/validate, then replace while retaining a recoverable backup.
- Unknown newer schema opens read-only or fails clearly; never rewrite it as an older schema.
- Test interrupted migration, corrupted catalog/preferences, app upgrade while Herdr remains running, bundled-Herdr version change, and rollback to the previous Bessie build.
- Publish a Bessie↔Herdr compatibility policy and retain enough diagnostic facts to explain refusal/recovery.

### 12.3 Security and privacy

- Preserve SSH host-key verification and surface changed-key failures; never silently accept them.
- Project files contain no secrets fields; exact startup commands remain reviewable.
- Notifications default to identity/state/location and never raw terminal output.
- Redact secrets, environment values, personal paths/hosts, and terminal content from logs/support bundles where practical.
- Support bundles are previewable before export.
- Audit packaged resources and macOS logging for accidental terminal output or personal data.

### 12.4 Terminal conformance

The V1 terminal matrix covers modifiers and special keys, key repeat, dead keys/IME/composed text, Unicode/emoji/wide/combining characters, copy/paste/bracketed and multiline paste, selection versus inner-TUI mouse capture, alternate-screen scroll, resize storms, hyperlinks, cursor shape/visibility, focus reporting, and representative shell/Vim/tmux/`less`/mouse-aware TUI scenarios. “Real terminal” is a release contract, not a compilation claim.

### 12.5 Freshness and disconnected status

- Keep semantic state separate from freshness: live, stale, disconnected.
- A disconnected host never keeps a confident working/blocked/done presentation.
- Last-known state may be shown only when explicitly labeled stale and must not count toward the live Needs you filter.
- Connection failures stay visible even when a host filter would otherwise hide entity rows.

### 12.6 Destructive-action semantics

- Every close/remove/interrupt confirmation states exactly which Herdr processes or Bessie-owned recipes/folders are affected.
- Cover pane, tab, workspace, Project, Project folder, connection, and agent interruption/removal.
- Closing Bessie remains clearly distinct from closing Herdr-owned topology.
- Test final-pane/final-tab cascades and stale-target races before mutation.

### 12.7 Accessibility

- Complete keyboard navigation without stealing terminal input.
- VoiceOver names for status, freshness, connection scope, entity `+` controls, pane focus, and Zen.
- Visible keyboard focus is distinguishable from the terminal's Herdr/input focus.
- Support Increase Contrast and Reduce Motion; do not communicate status through color alone.
- Verify light/dark contrast and usable layout at larger accessibility text sizes.

### 12.8 Resource and scale budgets

- Record idle CPU with cowprint on/off/moving, memory per visible terminal controller, and energy impact.
- Exercise at least 10 panes, large Herd fleets with many blocked agents, sustained output, reconnect churn, and overnight soak.
- Pause cowprint animation when hidden, minimized, occluded, inactive, or Reduce Motion disables it.
- Set measured release budgets in the final K report rather than accepting unbounded regressions.

### 12.9 Crash and recovery

- Relaunch reattaches to ordinary surviving Herdr state.
- Persisted Herdr IDs remain hints and are revalidated.
- Corrupt Bessie preferences/Project catalogs do not prevent Trouble or a safe recovery path from opening.
- Interrupted Project materialization exposes the partial ordinary Herdr workspace without inventing success.
- Crash reporting may be optional; crash recovery is mandatory.

### 12.10 Scope consistency

Before implementation, update every V1 index/scope/decision document to agree on L → M → K, bounded Zen, multi-folder Projects, public-protocol mouse input, single-window behavior, and the safeguards above. Automated doc anchors should fail if the old “Zen deferred” or “L then K” release contract returns.

## 13. Execution order

### M0 — Freeze evidence and protocol prerequisites

- Reconcile the V1 scope/index/decision documents and lock the single-window contract.
- Capture current light/dark screenshots and short recordings for shell, Herd and every filter, workspace, Settings, onboarding, Project editor, modal, and terminal focus.
- Add feedback checklist to the progress report.
- Add performance signposts and record startup/terminal baseline.
- Complete the public Herdr mouse-capability spike and decide exact upstream implementation/version path.

**Exit:** every issue has reproducible evidence; mouse path is proven feasible through a public contract; no optimization claim yet.

### M1 — Correctness blockers

- Fix onboarding configuration and Finish transition.
- Add test notification and click routing.
- Fix pane focus/responder/outline state machine.
- Land negotiated Herdr mouse support, compatibility lock, Bessie routing, and live TUI tests.
- Add shipping personalization audit.

**Exit:** onboarding, focus, notifications, and mouse checks pass on packaged app.

### M2 — Navigation and connection information architecture

- Connection-scope dropdown and filtering.
- Remove Workspaces destination.
- Workspaces/Tabs/Panes group `+` controls.
- Move tabs into top bar; remove breadcrumbs.
- Remove New Pane + ellipsis, redundant pane/live chips, counts, and prototype Files copy.
- Add authoritative status glyphs.

**Exit:** topology created in Bessie is verified in ordinary Herdr; two-host routing/filter tests pass.

### M3 — Settings, Projects, and shape consistency

- Reorganize Settings and share components with onboarding.
- Remove Group UI.
- Implement Project schema v2 multi-folder migration/editor/materialization.
- Normalize Bessie-owned modal/surface radii.
- Fix light-mode logo.

**Exit:** migration and launch tests pass; screenshots accepted in both appearances.

### M4 — Herd consolidation and needs-you correction

- Lock one authoritative Herd model and blocked-only Needs you semantics in Core tests.
- Rebuild Herd hierarchy/cards against retained mockup.
- Remove the standalone Attention destination, models, routes, and duplicate tests.
- Fold count, routing, shortcut, notification coherence, and Zen blocked cues into Herd's shared predicate.
- Remove stale notification-to-Attention fallback routing in favor of Herd or connection recovery.
- Add deterministic seeded visual states.

**Exit:** semantics tests pass and side-by-side screenshots are accepted.

### M5 — Cowprint and Zen

- Replace raster drift with edge deformation and performance-safe phase control.
- Add motion/reduced-motion verification.
- Implement bounded Zen mode and status spine.

**Exit:** recordings show intended motion; Zen preserves terminal focus and ordinary Herdr state.

### M6 — Performance optimization

- Re-record traces after all UI changes.
- Fix measured startup critical path and terminal latency sources.
- Run cold/warm launch series, input stress, sustained output, resize, multi-pane, and local/remote comparison.
- Run the complete terminal-conformance matrix and resource/scale budgets.

**Exit:** budgets in §11 pass or every miss is explicitly reviewed by Jordan with trace evidence.

### M7 — Stability soak and expanded K release gate

- Run all automated checks.
- Run repeated launch/quit/reattach and process-survival soak.
- Exercise disconnect/reconnect, controller conflict/takeover, multiple hosts, notification routing, onboarding reset, Project migration/launch, Zen transitions, and mouse-aware TUIs.
- Verify single-window enforcement, migration/rollback, security/privacy, accessibility, destructive actions, stale status, and crash recovery.
- Clean-profile install; verify no personal defaults.
- Capture final 14+ surface light/dark visual set and feedback checklist.
- Package, sign, notarize, staple, Gatekeeper-open, and install only with Jordan's credentials/approval.

**Exit:** complete evidence report, no open P0/P1, explicit release approval. This plan never grants release approval by itself.

## 14. File map

Expected areas; exact factoring may change after M0 inspection:

| Area | Primary files |
| --- | --- |
| App startup/fleet/onboarding | `Sources/BessieApp/BessieApp.swift`, `OnboardingView.swift`, `BessieSettings.swift` |
| Sidebar/top bar/Herd/workspace | `Sources/BessieApp/ProductSurfaces.swift`, remove Attention surface/route and extract focused view/model files rather than expanding the monolith further |
| Terminal/focus/mouse/performance | `Sources/BessieApp/TerminalPaneController.swift`, `Sources/BessieCore/TerminalInput.swift`, Herdr upstream public controller/schema |
| Notifications | `Sources/BessieApp/BessieNotifications.swift`, Notifications settings section, notification model tests |
| Projects | `Sources/BessieCore/BessieProjects.swift`, `ProjectEditorView.swift`, `ProjectsViewModel.swift`, codec/migration/materializer tests |
| Brand/motion/shapes | `Sources/BessieApp/BessieDesignSystem.swift`, assets/shaders, visual probes |
| Connection scope | `ConnectionFleetViewModel`, surface builders, connection UI/model tests |
| Release checks | `scripts/check.sh`, `scripts/mac-verify.sh`, new performance/packaged-string/soak scripts |
| Evidence | `docs/reports/YYYY-MM-DD-v1-acceptance-remediation.md` |

`ProductSurfaces.swift` and `BessieSettings.swift` are already large. Split new work into narrowly named views/builders while preserving behavior and testability; do not use the remediation as an excuse for an unrelated rewrite.

## 15. Verification matrix

Minimum automated and live checks:

- Core: connection scope, status aggregation, Herd Needs you semantics, Project v1→v2 migration, folder validation, notification route model.
- App model: onboarding Finish, settings reuse, focus transitions, connection activation/routing, sidebar actions.
- Terminal unit/integration: raw/special/paste ordering, negotiated mouse encoding, selection modifier, frame sequencing, resize coalescing.
- Live terminal: shell, editor, two mouse-aware TUIs, Unicode, paste, wheel, two panes, rapid focus swaps, resize, sustained output.
- Multi-host: All/Local/Remote scope, degraded host, cross-host open pane, notification route.
- Visual: light/dark logo, cowprint still/moving/reduced motion, Herd seeded states and filters, workspace top tabs/sidebar status, Settings, onboarding, Project multi-folder editor, modal radii, Zen.
- Persistence: clean first run, Finish, relaunch, reset onboarding, Project migration, selected scope fallback.
- Herdr fidelity: create/focus/split/agent launch visible in ordinary Herdr TUI; quitting Bessie leaves all work running.
- Performance: cold/warm startup series and terminal latency report against §11.
- Release: `./scripts/check.sh`, `./scripts/mac-verify.sh`, packaged executable identity, signing, notarization, staple, Gatekeeper.

## 16. Pause and approval conditions

Stop and surface evidence if:

- negotiated mouse input requires a private Herdr protocol or cannot land in a compatible public runtime;
- multiple Project folders cannot materialize exact cwd through public Herdr actions;
- performance budgets cannot be met without changing the Herdr/libghostty ownership model;
- a visual change conflicts with the retained reference and this feedback does not resolve it;
- signing, notarization, redistribution, account credentials, publish/push, or remote-repository changes are required.

Only Jordan can waive a release blocker, approve credentialed release operations, or approve public distribution.

## 17. Definition of done

This remediation is complete only when:

1. all 24 feedback rows have linked evidence and Pass/Waived status;
2. no shipping UI or bundled defaults contain setup-specific personal data;
3. mouse clicks work in negotiated mouse-aware TUIs through a public Herdr capability;
4. startup and local terminal latency meet the budgets or have explicit evidence-backed waivers;
5. onboarding configures real settings and Finish reliably exits first run;
6. focus outline, sidebar status, connection scope, Projects v2, Herd and Needs you, cowprint, light logo, modal shape, and Zen pass their live checks;
7. ordinary Herdr can attach to and operate the same resulting session after Bessie quits;
8. the expanded K report is complete and Jordan gives explicit V1 release approval.
