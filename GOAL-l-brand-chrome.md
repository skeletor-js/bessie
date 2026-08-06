# Goal: V1 slice L — Brand shell and chrome hygiene

**Status:** Active  
**Owner:** Amp (medium) via Hermes  
**Branch:** `feat/v1-l-brand-chrome`  
**Plan:** `docs/plans/2026-08-03-brand-shell-and-chrome-hygiene.md`

## Goal contract (paste into /goal or amp -x)

**Objective:** Make Bessie look like finished cowprint Bessie: pure achromatic light, continuous top bar, quiet chrome, honest empties, onboarding/Trouble restyle, workspace pane chrome — without new product surfaces or Deferred features.

**Read first:**
- `docs/plans/2026-08-03-brand-shell-and-chrome-hygiene.md` (source of truth for L)
- `docs/plans/2026-08-02-design-system-customization.md` (I token ownership; absorb remaining cream→achromatic if still warm)
- `AGENTS.md`
- `Sources/BessieApp/BessieDesignSystem.swift`
- `Sources/BessieApp/ProductSurfaces.swift`
- `Sources/BessieApp/OnboardingView.swift`
- `Sources/BessieApp/TroubleView.swift`
- `Sources/BessieApp/WorkspaceFilesSurface.swift`
- `Sources/BessieApp/ProjectsSurface.swift` / `ProjectEditorView.swift`
- Workstream review (optional): `/home/hermes/.hermes/workspace/shared/workstreams/bessie/projects/v1-release/2026-08-03-pre-v1-ui-ux-improvement-plan.md`

**Constraints:**
- Branch: stay on `feat/v1-l-brand-chrome` (create if missing).
- No new product features: no Zen, menu-bar item, entity palette, permissions UI, full agent detail overhaul, graphical Allow/Deny, layout presets, Search the Herd.
- Do not change Herd/Attention filter/builder semantics (E is done); visual/chrome only.
- Do not stop Herdr on quit; do not change survival rule.
- No commit, push, PR, notarize, publish, or ship without explicit Jordan/Hermes approval.
- No new dependencies.
- Do not weaken, skip, delete, or relabel tests/checks to force a pass.
- Prefer small checkpoints; update `docs/reports/goal-progress.md` with files changed and real command output.
- Append evidence to the plan §11 when milestones complete.
- VPS edit path: `/home/hermes/code/bessie`. Mac verify via `./scripts/mac-verify.sh` and `jordan-macbook` per AGENTS.md. Never `rsync --delete` blindly.

**Validate after each meaningful checkpoint:**
1. `./scripts/check.sh` on VPS
2. After UI-substantial work: `./scripts/mac-verify.sh` on Mac path
3. Prefer design-preview / window snapshot for brand checklist spots when tooling allows
4. Install packaged app to `/Applications/Bessie.app` only after mac-verify passes (AGENTS default)

**Document:** Update plan evidence §11 and `docs/reports/goal-progress.md`. Do not invent ADRs.

**Checkpoints (plan order):**
1. M0 inventory (violation → file)
2. M1 tokens + TopBar continuous + gaps (replace warm cream light)
3. M2 type/case/badges/control quieting
4. M3 empties + Files gating + project review reverse-line
5. M4 onboarding + Trouble restyle
6. M5 workspace pane chrome
7. M6 re-check + brand checklist notes + check.sh green

**Reward-hacking guard:** Do not delete, skip, weaken, narrow, or relabel tests/checks to make the goal pass.

**Pause and ask if:**
- Titlebar/TopBar continuous plate needs multi-day window rewrite
- Light shell makes terminal unreadable and no independent terminal plate works
- Scope pressure to unpark Deferred features
- Mac SSH/mac-verify unavailable after repeated attempts
- Product decision needed beyond the locked plan

**Stop when:**
- Plan §7 brand checklist is addressed in code to the extent verifiable without Jordan eyeballing every pixel
- `./scripts/check.sh` passes
- Mac verify run attempted with evidence in goal-progress (pass or documented blocker)
- Progress log lists remaining manual-only items honestly
- OR blocked on pause condition above

## Non-goals

Graphical approve card, Zen, menu bar, entity palette, permissions inventory, warm Hearth light palette.
