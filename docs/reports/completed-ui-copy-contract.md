# Completed autonomous UI copy contract

**Status:** Complete. The final static copy guard, isolated Mac verifier, full 40-test suite, package build, eight-surface screenshot review, design snapshot, whitespace check, and process cleanup all passed on 2026-07-31.

**Objective:** Audit every user-visible string in the native Bessie app and replace planning residue, implementation commentary, redundant explanation, and unclear labels with concise, task-oriented product copy.

**Read first:** `AGENTS.md`, `V1-SCOPE.md`, `VISION.md`, `WORKSPACE-INTERACTION-SPEC.md`, the retained desktop UI kit under workstream `source-material/design-system/ui_kits/bessie-desktop/`, and every Swift file in `Sources/BessieApp` that can render text, labels, errors, confirmations, accessibility descriptions, status, or diagnostics.

**Constraints:** Preserve behavior, Herdr ownership, real libghostty rendering, safety consequences, version/capability diagnostics, and the supplied visual system. This is a copy and information-hierarchy pass, not a feature or architecture expansion. Do not hide errors or destructive consequences. Keep technical names only where they help the user diagnose or decide. Prefer short labels, concrete statuses, and direct actions. Avoid tutorial voice, product self-description, architecture narration, fake marketing, placeholder examples, implementation terms, unexplained abbreviations, and text that restates visible controls. Use consistent sentence case and the canonical nouns `workspace`, `tab`, `pane`, `agent`, `Herdr`, and `Bessie`. No new dependencies, commits, pushes, publishing, credentials, or destructive cleanup.

**Validate:** Maintain a complete source inventory of string literals and manually classify every reachable user-facing string. Run `./scripts/check.sh` after each copy checkpoint, then `./scripts/mac-verify.sh` and `git diff --check`. Launch and capture all reachable product surfaces plus connection, empty, confirmation, error, and process-launch states. Inspect screenshots for clipping, density, duplicate explanations, weak information scent, and generic native artifacts.

**Document:** Keep `docs/reports/goal-progress.md`, `docs/reports/mac-v1-alpha.md`, and `README.md` accurate where labels or verification evidence change. Add no ADRs.

**Checkpoints:** Work surface by surface: Connect; shell/navigation/status; The herd; Workspaces; Sessions/workspace and pane chrome; Agent Detail; Attention; New agent/process; Settings; sheets, errors, destructive confirmations, and accessibility labels. Log exact changed files and validation results.

**Reward-hacking guard:** Do not delete, skip, weaken, narrow, or relabel checks to manufacture a pass. Do not remove required diagnostics or safety copy merely because it is technical. Do not replace dynamic truth with polished fixture text.

**Pause and ask if:** A rewrite changes product meaning, removes a required safety consequence, requires a new Herdr capability, or exposes a genuine naming/product decision with materially different behavior. Do not pause for ordinary copy judgment.

**Stop when:** Every reachable static user-facing string has been classified and either kept intentionally, rewritten, or removed; no shipped copy reads like planning notes or implementation explanation; terminology and action labels are consistent; all automated checks pass; the packaged Mac app has been screenshot-reviewed across its surfaces and relevant states; and no test process remains running.
