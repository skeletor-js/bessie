# Bessie: Ghostty shortcut parity + terminal/app performance + mouse TUIs

**Date:** 2026-08-03  
**Mode:** Amp high  
**Branch/workdir:** `/home/hermes/code/bessie` on `feat/v1-l-brand-chrome` (dirty tree is intentional current product state — do not wipe WIP)  
**Owner outcome:** Inside Bessie, Jordan can do what he does in native Ghostty on his MacBook — same muscle-memory shortcuts, snappy app, native-feel terminal latency, and mouse-capable TUIs (Hermes, etc.).

## Non-negotiables (from AGENTS.md + workstream)

- Bessie is a graphical Herdr client. Never a competing durable session model.
- Every terminal surface is real libghostty (`libghostty-spm` 1.3.2 / `GhosttyTerminal`).
- Public Herdr JSON + terminal-session bridge only. No private bincode, no forked Herdr/libghostty.
- Events are invalidation hints → resnapshot.
- Do not commit/push/PR/create remote without Jordan.
- VPS edit source: `/home/hermes/code/bessie`. Verify on Mac via `./scripts/mac-verify.sh`, then install to `/Applications/Bessie.app` on `jordan-macbook` and match packaged executable.
- Update `docs/reports/goal-progress.md` with real command results.
- Do not weaken/skip tests to manufacture a pass.

## Product problem (Jordan, 2026-08-03)

1. App still slow; terminals laggy; keyboard shortcuts feel weird.
2. Wants **Ghostty shortcuts**, not Herdr TUI prefix muscle memory forced through Bessie chrome.
3. Terminals must feel as fast as **native Ghostty**.
4. Whole app snappy.
5. Still cannot click/use mouse inside mouse-aware TUIs (e.g. Hermes).
6. Goal: parity with his Ghostty MacBook setup, inside Bessie.

## Authoritative context to read first

1. `AGENTS.md`
2. Workstream (VPS): `/home/hermes/.hermes/workspace/shared/workstreams/bessie/`
   - `TERMINAL-BEHAVIOR.md`
   - `HERDR-CAPABILITY-MAP.md`
   - `WORKSPACE-INTERACTION-SPEC.md`
   - `V1-SCOPE.md`
   - `ARCHITECTURE.md`
3. Repo plan: `docs/plans/2026-08-03-v1-acceptance-remediation.md` (§4 terminal lag, §9 mouse, §11 budgets)
4. Current code:
   - `Sources/BessieCore/KeyboardShortcuts.swift`
   - `Sources/BessieApp/KeyboardShortcutCoordinator.swift`
   - `Sources/BessieApp/TerminalPaneController.swift` (`BessieTerminalView`, `mouse-reporting=false`, mouseDown selection-only)
   - `Sources/BessieCore/TerminalInput.swift`, `HerdrTerminalController.swift`
   - `Sources/BessieCore/PerformanceInstrumentation.swift`
   - `Tests/BessieCoreTests/KeyboardShortcutTests.swift`
   - `Tests/BessieCoreTests/PerformanceInstrumentationTests.swift`

## Jordan's real Ghostty config (Mac) — treat as target feel

Path: `~/Library/Application Support/com.mitchellh.ghostty/config`

Critical custom bind:

```
keybind = cmd+b=text:\x02
```

**Cmd+B must send Ctrl+B (0x02) into the focused terminal** so Herdr's prefix works the way it does in his Ghostty. Bessie currently steals **Cmd+B for the command palette** — that is a primary "shortcuts feel weird" bug.

**Pre-v1 clarification (2026-08-04):** `Cmd+B` remains a one-shot `0x02` terminal binding and empty-selection `Cmd+C` remains a one-shot `0x03` binding. The redesign's no-prefix rule forbids only a Bessie-owned prefix state; it does not remove either direct terminal mapping. The palette uses `Cmd+Shift+P`.

Also set:

- `macos-option-as-alt = left`
- `mouse-hide-while-typing = true`
- Gruvbox colors, font-size 13, font-thicken, padding 4, no blink block cursor, large scrollback, clipboard allow r/w

No other custom keybinds — **Ghostty macOS defaults** apply for topology:

| Action | Ghostty macOS default | Current Bessie (wrong where noted) |
| --- | --- | --- |
| New tab | ⌘T | ⌘T OK |
| Close surface/tab | ⌘W | ⌘W → closeTab (OK-ish; verify close-pane vs tab Ghostty semantics) |
| Prev/next tab | ⌘⇧[ / ⌘⇧] | **Bessie uses ⌘[ / ⌘] for tabs — WRONG** |
| Tab 1–8 / last | ⌘1–8 / ⌘9 | ⌘1–9 OK |
| New split right | ⌘D | ⌘D OK |
| New split down | ⌘⇧D | ⌘⇧D OK |
| Focus prev/next split | ⌘[ / ⌘] | **Bessie missing; ⌘[ / ] currently tabs** |
| Focus split dir | ⌘⌥↑↓←→ | Bessie has ⌘⌥ arrows for panes — keep aligned |
| Toggle split zoom | ⌘⇧Enter | Bessie uses bare Enter with ⌘? check — align to ⌘⇧Enter |
| Resize split | ⌘⌃ arrows | Bessie uses ⌘⌃ arrows — verify |
| Equalize splits | ⌘⌃= | Add if missing |
| Command palette | Ghostty has toggle_command_palette (not ⌘B) | **Move palette off ⌘B**. Prefer a non-conflicting bind (e.g. ⌘⇧P or ⌘K if free) + menu item. Document the new palette shortcut. |
| Paste | ⌘V | already routed |
| Copy | ⌘C | selection copy path |

Bessie-only product binds may remain when they do not fight Ghostty defaults:

- ⌘⇧B sidebar (Ghostty unused) — OK
- ⌘, settings — OK (Ghostty opens config; Bessie opens Settings — acceptable product mapping)
- ⌥⌘N next needs-you, ⌘⇧Z zen, ⌥⇧⌘[ / ] agents — OK if documented
- ⌘N new workspace (Ghostty new window) — OK under single-window contract; do not open multi-window

**Principle:** When focused in a terminal, Ghostty-default topology chords perform the equivalent Herdr tab/pane mutations. Non-mapped chords pass through to the PTY/libghostty/Herdr composite input path. Never consume bare Control sequences used by apps (Ctrl+C, Ctrl+R, etc.).

## Workstream A — Shortcut swap (ship)

1. Rebuild `BessieKeyboardShortcutRouter` bindings to Ghostty macOS defaults + Jordan `cmd+b → \x02`.
2. Implement terminal-targeted raw byte/path for `cmd+b` (send Ctrl+B via existing composite input, not as app command).
3. Retarget command palette off ⌘B; update palette chrome glyph, tests, menus, any copy.
4. ⌘[ / ⌘] = previous/next **pane** (Herdr focus neighbor / cycle), not tabs.
5. ⌘⇧[ / ⌘⇧] = previous/next **tab**.
6. Zoom = ⌘⇧Enter → `toggleZoom` / pane.zoom.
7. Add equalize if Herdr public API supports it; otherwise omit honestly (do not fake).
8. Update `KeyboardShortcutTests` exhaustively; keep system passthrough ⌘Q/H/M/`` ` ``.
9. Sheets still own their keys; non-matching still pass to terminal.
10. Option-as-Alt left behavior: ensure Option+letter produces Meta/Alt for terminal apps the way Ghostty `macos-option-as-alt=left` does (verify current path; fix if broken).

## Workstream B — Performance (ship against budgets)

Baselines + optimize. Budgets from acceptance plan §11 (local Herdr):

| Measure | Target |
| --- | --- |
| Printable key → visible echo | p50 ≤ 25 ms; p95 ≤ 50 ms; p99 ≤ 100 ms |
| Frame receive → libghostty feed | p95 ≤ 8 ms |
| Sustained output | no input freeze > 100 ms |
| Resize storm | final grid ≤ 250 ms after drag end |
| First window content cold | p95 ≤ 0.75 s |
| Warm reattach usable shell | p95 ≤ 1.5 s |
| Cold bundled Herdr usable shell | p95 ≤ 3.0 s |

Investigate and fix real hot paths (measure first):

- `GhosttyPaneSurface` / `updateNSView` redundant `fitToSize` / resize loops
- Per-frame `@Published` / SwiftUI invalidation / main-actor churn
- Terminal controller lifecycle (create only visible panes; reuse)
- Frame batching into `InMemoryTerminalSession` without reordering bytes
- Diagnostic logging in hot path
- Cowprint/shell work competing with terminal frame times (animation already constrained — ensure no full-window CPU path)
- Input path: AppKit event → enqueue → Herdr write latency; remove avoidable hops/locks
- Snapshot/event storm coalescing that starves input

Use existing `BessiePerformanceRecorder` / export path. Add tests where pure logic is touched. Capture packaged-app measurements on Mac in progress report. Remote SSH latency reported separately (do not hide RTT).

## Workstream C — Mouse in TUIs (blocker-aware)

**Status today:**

- `BessieTerminalView` sets `mouse-reporting=false`, uses mouse for focus + local selection only.
- Public Herdr 0.8.0 / protocol 19 schema has **no** mouse methods (`pane.send_*` only keys/text/input). Terminal-session NDJSON exposes wheel scroll; full mouse is private client `InputEvents` / `MouseCapture` territory.
- Acceptance plan §9: typed negotiated public mouse capability is a V1 release blocker; **no ANSI guessing, no private protocol copy**.

Required approach:

1. **Spike M0 (do first, time-box):** Re-audit live Herdr 0.8.0 terminal-session control protocol and any newer public surface for mouse/button/motion/capture-state. Dump schema + any terminal control command variants from the bundled Mac Herdr binary and docs. Search herdr source/release notes if available.
2. If a public capability exists or can be added via ordinary public methods without private bincode: implement Bessie adapter + capability negotiation + Shift-for-local-selection + live tests (Hermes TUI + one other mouse TUI if available).
3. If still gap-only:  
   - Implement everything possible on Bessie side without lying (selection, wheel routing correctness, honest capability UX when capture unsupported).  
   - Write a crisp upstream Herdr proposal/spec in `docs/research/` for public mouse events (capability version, cell coords, buttons, mods, motion, wheel, capture state, host-selection modifier).  
   - Wire Bessie behind a feature/capability flag so the moment bundled Herdr gains it, routing lights up.  
   - Do **not** claim mouse works until live proof.
4. Never enable local libghostty mouse-reporting that encodes sequences client-side while Herdr owns the PTY modes — that desyncs mode state (see TERMINAL-BEHAVIOR.md).

## Validation (mandatory)

On VPS:

```bash
./scripts/check.sh
```

On Mac (`jordan-macbook`):

```bash
./scripts/mac-verify.sh
```

Then install packaged app to `/Applications/Bessie.app`, relaunch, `cmp`/SHA match packaged executable.

Live manual/automation checks:

1. In a shell pane: type speed feels native; `cat` large output stays responsive.
2. ⌘B inserts Herdr prefix behavior (Ctrl+B) — **not** palette.
3. Palette opens on the new bind; searchable commands still work.
4. ⌘D / ⌘⇧D splits; ⌘[ / ⌘] moves pane focus; ⌘⇧[ / ⌘⇧] tabs; ⌘1–9 tabs; ⌘⇧Enter zoom.
5. Ctrl+C / normal terminal control sequences untouched.
6. Mouse: if capability landed, click works in Hermes TUI; Shift-drag still selects text. If not, document honest limitation + upstream note — do not fake.
7. Screenshots of workspace + palette shortcut chrome if UI strings changed.

## Delivery format

1. Implement in the existing dirty tree carefully (do not discard unrelated WIP). Prefer small coherent diffs for shortcuts vs perf vs mouse.
2. Keep `docs/reports/goal-progress.md` current with files changed and real command output.
3. End with a concise status: done / blocked (mouse upstream?) / remaining risks.
4. Do not commit unless asked.

## Out of scope

- Generic IDE features, iOS control plane, publishing GitHub remote
- Replacing Herdr keybind model inside Herdr itself
- Private protocol hacks for mouse
