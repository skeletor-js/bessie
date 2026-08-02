---
title: "Agent Intent Bus (CLI, MCP, Skill) - Plan"
type: feat
date: 2026-08-02
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
product_contract_source: ce-plan-bootstrap
execution: code
origin_session: default
---

# Agent Intent Bus (CLI, MCP, Skill) - Plan

## Goal Capsule

**Objective.** Give agents full Bessie capability parity through one stable intent API: the same intents the UI already runs, reached via a local transport, with CLI, MCP, and skill as thin skins that share one schema and never diverge.

**Authority.** Workstream `DECISIONS.md` 14–16 and product boundaries (Herdr owns live state; Bessie owns recipes/app config). Repo `AGENTS.md` and `docs/plans/2026-08-02-v1-shared-substrate.md` for package ownership and connection identity. This plan does not override Herdr authority or invent a Bessie session runtime.

**Stop when.** A versioned intent registry exists in `BessieCore`; UI mutation paths used for the pilot set execute only through the bus; a local agent transport is live when the app is running; CLI, MCP, and skill expose the **same** intent names/params; automated parity checks prove skins cannot drift; destructive intents require explicit confirm; Mac verify covers at least one end-to-end agent path (list → read → mutate → observe).

**Execution profile.** Code on macOS Swift package `Bessie` (`BessieCore` + `BessieApp` + new thin executable targets). No Rust rewrite. No network-exposed control plane in this plan.

**Out of goal.** GUI puppeting; headless always-on `bessie server` as durable session owner; rebranded live-session vocabulary that replaces `herdr`; companion plugin as agent API; full human-feature catalog beyond the registration architecture and a pilot intent set; remote MCP/HTTP auth surface.

## Product Contract

### Summary

Agents drive Bessie the way the UI does: discover intents, call them with typed params, get structured results and the same Herdr-backed outcomes. Parity is architectural—every UI capability registers on one bus as it lands—not a separate agent feature roadmap.

### Problem Frame

Today only humans (and ad-hoc shell/`herdr`) can operate Bessie. Agents cannot safely or completely drive Projects, connections, focus, or other app features without guessing UI or inventing a second control plane. Product doctrine already forbids a Bessie-owned session runtime and a parallel operator vocabulary for live Herdr state.

### Requirements

- R1. One **intent registry** is the sole capability catalog for agents and for UI dispatch of registered intents.
- R2. Every registered intent has a stable name, JSON Schema params, human description, owner (`bessie` | `herdr`), risk class (`read` | `navigate` | `mutate` | `destructive`), and whether a live connection is required.
- R3. UI paths for the pilot set invoke the bus (not a parallel `model.perform` / shortcut-only fork). New UI capabilities that agents should share must register before or with the UI change (parity-by-construction discipline + automated check).
- R4. A **local transport** lets external agents call the bus when Bessie is running (Unix domain socket under the user’s app support, not a public network port).
- R5. **CLI**, **MCP (stdio)**, and **skill** are thin skins over the same registry/client: same names, same params, no skin-specific business logic.
- R6. Live session mutations go through the same Herdr paths the app already uses (`HerdrAction` / materializer / existing clients). Intent names may be ergonomic for agents but must not invent a durable alternate Herdr API.
- R7. Results are structured and agent-usable: success/error codes, connection-scoped IDs per shared substrate, and snapshot/projection facts where the UI would refresh from Herdr.
- R8. Destructive intents refuse without explicit confirmation. Executor returns `needs_confirmation` with the **same human-readable cascade text** the UI would show, plus a one-shot `confirm_token` bound to intent+args. Re-invoke with that token (CLI `--confirm <token>`; MCP `confirm_token`). Global always-yes master override is out of scope. Match seriousness for workspace/tab/pane close and project delete/trash.
- R9. When Bessie is not running, skins fail honestly (`bessie_not_running`) rather than silently talking to a shadow daemon—except pure offline Bessie-owned file reads that the registry marks `offline_ok` (project recipe list/show only if implemented without app state). Disconnected Herdr must return `not_connected` (never silent no-op like today’s UI `guard let actionClient`).
- R10. Skill documents fidelity rules (Herdr truth, quit survival, no second runtime) and how to list/call intents; it does not define a second command set.
- R11. Multi-connection ops carry `connection_id` whenever Herdr IDs are used (shared substrate). Agent execute uses **explicit target IDs** (or a documented race-prone `use_focus: true`); do not require agents to scrape GUI selection.
- R12. **Human-only (never agent-executable):** OS permission sheets, Keychain/biometrics, notarization/signing identity entry, pasting secrets/API keys, GUI puppeting, silent terminal controller takeover, stopping the Herdr server as a synonym for quitting Bessie, fabricated Allow/Deny without a versioned Herdr contract.
- R13. High-risk **terminal keystroke/input injection** is not in the pilot set; if added later it is its own risk class with strict policy—not implied by “control Bessie.”

### Actors

- Human using Bessie GUI
- External coding/ops agent (Hermes, Codex, Claude Code, etc.) via CLI or MCP
- BessieApp process hosting the bus
- Herdr (live authority)

### Key Flows

1. **Discover.** Agent: `bessie intents` / MCP `tools/list` → registry dump.
2. **Read context.** Agent: connection status + session projection / attention slice via read intents.
3. **Mutate.** Agent: focus pane / split / materialize project → bus → existing Herdr/BessieCore path → structured result + updated facts.
4. **Destructive.** Agent omits confirm → `needs_confirmation`; with confirm → executes.
5. **UI parity.** Human hits palette/shortcut → same intent execution path as agent.

### Acceptance Examples

- AE1. With Bessie running and connected, agent lists intents and sees pilot set including at least connection status, session snapshot/projection read, pane focus, and one project recipe read.
- AE2. Agent focuses a pane via CLI; UI focus and Herdr focus agree; quit Bessie leaves Herdr processes running.
- AE3. MCP `tools/list` names equal CLI intent names for the registry (same set).
- AE4. Close workspace without token returns `needs_confirmation` + cascade text + `confirm_token`; execute with token closes once; token reuse fails.
- AE5. Bessie quit: CLI/MCP return `bessie_not_running` for live intents.
- AE6. MCP child: protocol on stdout only; diagnostics on stderr (no stdout log corruption).

### Scope Boundaries

| In | Out |
| --- | --- |
| Intent registry + executor in BessieCore | Full post-V1 feature catalog in one drop |
| App-hosted local socket transport | Network MCP, OAuth, remote agent gateway |
| CLI + MCP stdio + skill skins | GUI automation / Accessibility driving |
| Pilot intents + registration discipline | Replacing `herdr` CLI for non-Bessie operators |
| Confirm gate for destructive | Silent always-confirm or no gate |
| Offline_ok only for pure local recipe files if cheap | Headless durable Bessie session daemon |

### Dependencies

- Existing `HerdrAction` / `HerdrActionClient`, `ConnectionViewModel.perform`, project store/materializer, `BessieShortcutCommand` + palette catalog, shared substrate connection IDs.
- Mac build/test via `./scripts/check.sh` and `./scripts/mac-verify.sh`.

### Sources

- Workstream `DECISIONS.md` 14–16 (this session)
- Occam loop: full parity API; one bus; three thin skins; grows with UI
- `Sources/BessieCore/HerdrActions.swift`, `KeyboardShortcuts.swift`, `BessieApp.swift` `ConnectionViewModel.perform`, `ProductSurfaces.handleShortcut`
- `docs/plans/2026-08-02-v1-shared-substrate.md`
- MCP tools model: discoverable JSON Schema tools, stdio baseline, human-in-loop for risky ops ([MCP tools](https://modelcontextprotocol.io/docs/concepts/tools)); production guidance: bounded context, idempotency/request ids, stdio first, versioned surface

## Planning Contract

### Key Technical Decisions

- KTD1. **Single registry in BessieCore** (`BessieIntent` + catalog). UI shortcut commands, Herdr actions, and Bessie-owned ops map into this catalog; skins never own a second list. (session-settled: user-directed — chosen over divergent CLI/MCP surfaces: one bus, three skins)
- KTD2. **Running BessieApp hosts the bus** over a user-local Unix socket (Application Support path, 0600, single-writer lock). No always-on separate daemon in this plan. (session-settled: user-directed — chosen over headless-first daemon: parity with UI state/connection; honest offline)
- KTD3. **CLI and MCP are socket clients** (plus optional offline_ok local path). MCP = stdio adapter that only translates MCP `tools/*` ↔ bus protocol. Skill = docs generated/hand-maintained from registry metadata, not a fourth command dialect. (session-settled: user-directed — zero divergent logic)
- KTD4. **Pilot intent set first**, architecture enforces growth. Pilot must include: `intents.list`, `app.status`, `connection.status`, `session.projection` (or snapshot projection read), `pane.focus`, `workspace.focus`, one destructive close with confirm, `project.list` / `project.show` (Bessie-owned). Expand by registering existing `HerdrAction` + shortcut commands incrementally after the pipe works.
- KTD5. **Wire format:** versioned NDJSON request/response on the socket (`v:1`, `id`, `intent`, `params`, optional `confirm_token`). Errors: `bessie_not_running`, `unknown_intent`, `invalid_params`, `needs_confirmation`, `confirm_token_invalid`, `herdr_error`, `not_connected`, `unsupported`. Prefer request ids for correlation; avoid inventing a private binary protocol.
- KTD6. **Risk + confirm tokens.** Registry marks risk; executor enforces one-shot confirm tokens for `destructive` (and other gated classes). UI dialogs are one presenter of the same policy outcome. No skin may bypass. (Improves on a bare `--yes` flag: binds confirmation to intent+args hash.)
- KTD7. **Package layout.** Core: registry, schemas, pure decode/encode, offline_ok handlers, client stub, policy/confirm tokens. App: socket server bound to live `ConnectionViewModel` / fleet; feeds the same MainActor projection update path UI observes. New executables: `bessie` CLI and `bessie-mcp` (or `bessie mcp` subcommand)—both depend on Core only for protocol + client. MCP stdout = protocol only; logs on stderr.
- KTD8. **Naming.** Intent names are dotted stable ids (`pane.focus`, `project.list`). Do not invent a durable alternate Herdr operator model. CLI shape: `bessie intents` / `bessie call <id> --json '{…}'` / `bessie call … --confirm <token>` generated from registry.
- KTD9. **Parity gates in `scripts/check.sh`.** Fail if: skin tool list ≠ registry export; registered UI shortcut/command lacks intent mapping; destructive lacks confirm metadata; MCP/CLI special-case handlers appear outside generated/client path.
- KTD10. **Trust boundary.** Local user socket only; no TCP listen in this plan. Document that any local process of the user can call the bus (same class of risk as AppleScript/local automation); optional future token is out of scope unless implementation proves trivial and necessary.
- KTD11. **Static vs effective catalog.** `intents.list` returns effective intents for current connection/app state; static full catalog available for docs/codegen. MCP may advertise `listChanged` when effective set changes.
- KTD12. **Workflow exception (closed list):** Project materialize may be one workflow intent (already multi-step owner in Core). Everything else in pilot is primitive. Terminal input, takeover, secrets: not pilot.

### High-Level Technical Design

```
[Agent]--CLI--> client --\
[Agent]--MCP stdio--> mcp adapter --> client --+--> Unix socket --> BessieApp IntentServer
[Human UI]--> IntentExecutor <// same registry + handlers
                                              |
                                              +--> HerdrActionClient / ProjectStore / Settings
                                              +--> Herdr (live truth)
```

- Registry is pure data + handler keys in Core.
- App registers live handlers at launch (connection-scoped perform, navigation that needs UI selection state where required).
- Intents that need “current UI selection” accept explicit IDs from the agent (agents pass ids; they do not rely on invisible GUI focus unless a read intent exposes it).

### Assumptions

- A1. Bessie will often be running during agent work on the Mac; requiring the app for live intents is acceptable for v1 of this surface.
- A2. SwiftPM can ship additional executable products beside `BessieApp`.
- A3. MCP hosts used by Jordan support stdio servers.
- A4. Pure-Swift Core remains (no Rust required for the bus).

### Implementation Constraints

- Do not terminate Herdr on Bessie quit; bus teardown must not stop pane processes.
- Do not use private Herdr bincode.
- Keep `connection_id` on multi-connection routes.
- Prefer small vertical slice over full HerdrAction enum exposure on day one.
- Avoid new network services and companion-plugin transport hacks.

### Sequencing

1. Registry + schemas + unit tests (Core)
2. Executor protocol + Herdr-backed handlers for pilot + confirm gate
3. Refactor UI pilot paths onto executor
4. App socket server + lifecycle
5. CLI client skin
6. MCP stdio skin (thin)
7. Skill + registry export for docs
8. Parity checks in `check.sh` + Mac live verify

### Research Snapshot

- **Repo:** No agent IPC today. Mutations: `HerdrAction` + `HerdrActionClient.perform` (ordered batch + trailing snapshot). UI hub: `ConnectionViewModel.perform` / `openPane` / `launch` / `openProjectHandoff`. Shortcuts: `BessieShortcutCommand` + `ProductSurfaces.handleShortcut` (mix of Herdr mutate, confirm sheets, editor sheets, pure navigation). Projects: separate `ProjectsViewModel` + store + materializer. Multi-connection: `ConnectionFleetViewModel` — intents must be connection-scoped. Silent disconnect no-op in UI must become explicit `not_connected` for agents. Detail: workstream `orchestration/intent-bus-repo-research.md`.
- **Learnings corpus:** no `docs/solutions/` yet; AGENTS.md + `docs/plans/2026-08-02-v1-shared-substrate.md`.
- **Agent-native:** Required. Primitive intents + closed workflow exception for project materialize; bus-native confirm tokens; human-only OS/secrets/puppeting/takeover; terminal input deferred. Assessment: workstream `inbox/2026-08-02-agent-native-planning-assessment-intent-bus.md` (if present) / delegation summary 2026-08-02.
- **External practices:** One registry / three projections; stdio MCP stdout=protocol; effective catalog; structured errors. Workstream `orchestration/seed/docs/research/2026-08-02-local-mcp-cli-intent-registry-practices.md`. MCP tools model + production guidance cited earlier.

## Implementation Units

### U1. Intent registry and schemas (Core)

**Goal.** Stable catalog type + pilot definitions + JSON Schema export.

**Requirements.** R1, R2, R10 (metadata for skill)

**Files.** `Sources/BessieCore/AgentIntent*.swift` (names flexible); `Tests/BessieCoreTests/…`

**Approach.** Define `BessieIntentID`, risk, owner, params schema (Codable structure sufficient to emit JSON Schema), pilot entries. Pure; no socket.

**Tests.** Round-trip catalog; schema contains required fields; pilot names unique and MCP-safe (`[A-Za-z0-9_.-]`).

**Verify.** `swift test --filter Intent` (or package test subset) via `check.sh` once wired.

### U2. Executor + confirm gate + pilot handlers

**Goal.** Execute pilot intents against injectable ports (Herdr mutation, projection read, project store).

**Requirements.** R6, R7, R8, R11

**Files.** Core executor; adapters later in App; tests with fake `HerdrMutationAPI` / fixtures (existing projection fixtures).

**Approach.** `IntentExecutor.execute(request) -> IntentResult`. Destructive without valid token → `needs_confirmation` with UI-equivalent cascade text + one-shot token. Map `pane.focus` / `workspace.focus` to `HerdrAction`. `project.list/show` via store. `session.projection` from snapshot decode path already used by app. Disconnected → `not_connected`.

**Tests.** Confirm gate + token reuse fail; unknown intent; invalid params; successful focus with fake API; connection_id required when multi-id context demands it.

### U3. UI dispatch through executor (pilot)

**Goal.** Pilot UI actions call executor so human and agent share code.

**Requirements.** R3

**Files.** `ProductSurfaces.swift` / `ConnectionViewModel` / shortcut handling as needed—minimal surface area.

**Approach.** Introduce app-side façade that builds `IntentRequest` from shortcut/button and runs executor; keep non-pilot shortcuts working as today until registered.

**Tests.** App model tests where feasible; avoid full UI snapshot dependency for logic.

### U4. App-hosted local socket server

**Goal.** External clients reach executor while app runs.

**Requirements.** R4, R5, R9

**Files.** App lifecycle (`BessieApp` / root model); Core protocol encode/decode reusable by clients.

**Approach.** On ready connection (or app launch), bind Unix socket; serve NDJSON; tear down on quit without touching Herdr. File permissions 0600. Single instance: replace stale socket if owner dead.

**Tests.** Protocol unit tests in Core; Mac live: start app, `printf`/`bessie` call status.

### U5. CLI skin

**Goal.** `bessie` executable: `intents`, `call`, `status`, `--confirm <token>`.

**Requirements.** R5, R9

**Files.** New target `BessieCLI` (name OK to adjust); help from registry descriptions.

**Approach.** Client-only; argv→JSON and structured JSON stdout for agents. No domain logic.

**Tests.** Arg parse unit tests; integration on Mac against running app.

### U6. MCP stdio skin

**Goal.** MCP server process: `tools/list` / `tools/call` = registry + execute via same client.

**Requirements.** R5

**Files.** New target or `bessie mcp` subcommand; keep adapter thin.

**Approach.** Map each intent to one tool; pass `confirm` in arguments; tool errors as MCP tool execution errors with actionable text. Stdio only.

**Tests.** Fixture stdin/stdout script or unit-level codec tests; Mac smoke with inspector or scripted JSON-RPC if available.

### U7. Skill + parity gates

**Goal.** Agent skill doc + CI/check parity.

**Requirements.** R3, R5, R10

**Files.** Repo `docs/` or `skills/bessie/SKILL.md` (choose one durable place; link from AGENTS.md); `scripts/check.sh` additions; optional export command `bessie intents --json`.

**Approach.** Skill sections: ownership model, transport, discover/call examples, confirm rules, Herdr vs Bessie. Check.sh: registry export equals embedded MCP tool list snapshot or generated file committed.

**Tests.** check.sh fails if intentional drift introduced in a unit test fixture.

### U8. Mac verification slice

**Goal.** Live proof on jordan-macbook path used by repo.

**Requirements.** AE1–AE5

**Files.** `scripts/mac-verify.sh` or sibling script extension—non-destructive where possible; destructive only in isolated Herdr config.

**Approach.** Launch app with test env; CLI list/call focus; quit; assert not_running; confirm gate on a disposable workspace if safe under local herdr config.

## Verification Contract

| Gate | Command / action |
| --- | --- |
| Unit / static | `./scripts/check.sh` (extended with registry/skin parity greps + swift tests) |
| Mac live | `./scripts/mac-verify.sh` (or documented agent-bus subsection) on Apple Silicon Mac mirror |
| Parity | CLI intent names == MCP tools == registry export |
| Safety | Destructive without token fails with cascade text; token succeeds once; reuse fails |
| Fidelity | After agent mutations, ordinary `herdr` still sees same live objects; quitting Bessie does not kill panes |
| MCP hygiene | Stdout protocol-only under smoke test |
| Install | Per AGENTS.md, install packaged app when verification passes unless Jordan says otherwise |

Behavioral skill eval: agent following the skill can list intents and complete AE1–AE3 without inventing `bessie server` or private sockets beyond documented path.

## Definition of Done

**Global**

- [ ] R1–R13 satisfied for pilot set
- [ ] U1–U8 complete with tests/commands above
- [ ] No second session runtime or network control port
- [ ] DECISIONS 14–16 still hold; AGENTS.md notes agent surfaces briefly
- [ ] Abandoned spike code removed
- [ ] Plan not required to implement full HerdrAction enum—in completion report, list registered vs not-yet-registered UI commands

**Per unit**

- U1: catalog tests green
- U2: confirm + execute tests green
- U3: pilot UI path uses executor
- U4: socket live + offline error
- U5: CLI call works on Mac
- U6: MCP list/call matches registry
- U7: skill merged; check.sh parity
- U8: mac-verify evidence captured in goal-progress or report

## System-Wide Impact

- **Agent parity:** primary delivery of this plan
- **Security:** local user-equivalent automation surface; document residual risk
- **Architecture:** pulls UI toward command bus (good pressure against ProductSurfaces god-object growth)
- **V1 sequencing:** foundation can land beside GUI polish; does not unlock Shepherd/MCP marketplace sprawl

## Risks & Dependencies

| Risk | Mitigation |
| --- | --- |
| App must be running frustrates agents | Clear errors; optional later “open -a Bessie” helper (deferred); offline_ok for recipe files |
| UI state (selection) not in Core | Agent passes explicit ids; read intents expose focus |
| MCP Swift ecosystem thin | Hand-rolled stdio JSON-RPC subset for tools only |
| Scope explosion to full action enum | Pilot set + registration backlog; parity check only for registered |
| Confirmation laundering via global --yes | One-shot confirm_token bound to intent+args |
| Terminal input as silent RCE | Not in pilot; separate risk class later |
| Split-brain UI vs bus | U3 rebinds pilot UI; check.sh orphan mapping |
| MCP stdout corruption | stderr logging only; AE6 |
| Multi-instance app | Single socket owner; second instance fails bus bind clearly |

## Open Questions

- Q1. *(deferred, non-blocking)* Auto-launch Bessie from CLI when not running?
- Q2. *(deferred)* Headless same-core host without windows for CI agents?
- Q3. *(deferred)* Per-socket auth token beyond filesystem permissions?

No launch-blocking open questions remain for implementation-ready execution of the pilot architecture.

## Appendix — Pilot intent sketch

| Intent | Owner | Risk | Notes |
| --- | --- | --- | --- |
| `intents.list` | bessie | read | offline via client static catalog OK |
| `app.status` | bessie | read | running, bus version, app version |
| `connection.status` | bessie | read | active connection + connect presentation |
| `session.projection` | herdr | read | via existing snapshot→projection |
| `workspace.focus` | herdr | navigate | HerdrAction |
| `pane.focus` | herdr | navigate | HerdrAction |
| `workspace.close` | herdr | destructive | confirm |
| `project.list` | bessie | read | store |
| `project.show` | bessie | read | store |

Expand after pipe works: remaining `HerdrAction` cases, project materialize/capture, connection switch, attention open, settings reads.
