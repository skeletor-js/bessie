# Bessie implementation repository

Read this file before changing code.

## Product source of truth

The retained product and technical context lives outside this repository at:

- VPS: `/home/hermes/.hermes/workspace/shared/workstreams/bessie`
- Mac: `/Users/jordanstella/Desktop/Hermes/workstreams/bessie`

For implementation work, read these first:

1. `docs/plans/2026-07-31-bessie-v1.md`
2. `GOAL.md`
3. workstream `V1-SCOPE.md`
4. workstream `WORKSPACE-INTERACTION-SPEC.md`
5. workstream `TERMINAL-BEHAVIOR.md`
6. workstream `HERDR-CAPABILITY-MAP.md`
7. workstream `ARCHITECTURE.md`
8. workstream `FEASIBILITY.md`

Use the design system under workstream `Bessie Design System/` for assets, tokens, and screen intent. Adapt it natively; do not ship the HTML kit inside a web view.

## Non-negotiable constraints

- Bessie is a graphical client for Herdr, never a replacement runtime or fork.
- Herdr owns every workspace, tab, pane, terminal, process, agent, and durable session fact.
- Every visible terminal surface uses libghostty through `GhosttyTerminal`; no terminal imitation or alternate emulator.
- Bessie may persist presentation preferences and last-opened Herdr identifiers only. Those identifiers are hints revalidated against a fresh Herdr snapshot.
- Quitting Bessie must not terminate Herdr or pane processes.
- Use only Herdr's public JSON socket API, CLI wrappers, and public terminal-session bridge. Never copy or depend on Herdr's private bincode client protocol.
- Keep remote sessions, multi-session support, graphical approval inference, worktrees, plugins, generic IDE features, and other post-V1 scope out.
- Do not modify Herdr or libghostty upstream source to make Bessie work.
- Do not publish, push, open a PR, or create a GitHub repository without Jordan's explicit approval.

## V1 implementation decisions

- First target: macOS 14+ on Apple Silicon.
- UI: SwiftUI for app surfaces plus AppKit for window/focus/terminal hosting.
- Terminal dependency: exact `libghostty-spm` `1.3.2` / `GhosttyTerminal` product.
- Herdr compatibility baseline: Herdr `0.7.5`, protocol `17`, source `b4112743cff42452b5d18558bf2d55bbbfff8c69`.
- Start with a narrow pure-Swift `BessieCore` adapter around public Herdr surfaces. Keep protocols and models independent enough to replace the transport with shared Rust later; do not add Rust FFI merely to satisfy the earlier recommendation.
- Bootstrap with `session.snapshot`, subscribe to public events as invalidation hints, and resnapshot. A bounded polling fallback is acceptable for recovery, but not a Bessie-owned source of truth.
- One writable `herdr terminal session control` process per visible pane; feed terminal frames into an `InMemoryTerminalSession`.
- Composite input path: libghostty raw committed input, Herdr `pane.send_keys` for intercepted special keys, and `pane.send_input.text` for paste. Route viewport changes and wheel scrolling to Herdr. Preserve ordering.
- The development build may use a repository-local Herdr runtime/config under `.local/`; never silently install or overwrite a system Herdr installation.

## Repository and Mac paths

- VPS working repository: `/home/hermes/code/bessie`
- Mac test mirror: `/Users/jordanstella/GitHub/bessie`
- Mac SSH target: `jordan-macbook`

The VPS copy is the editing source during this autonomous run. Sync intentionally to the Mac for native builds. Never use `rsync --delete` against a pre-existing destination without first verifying it is the Bessie mirror.

## Required validation

Create repeatable scripts so these are the ordinary checks:

```bash
./scripts/check.sh
./scripts/mac-verify.sh
```

`mac-verify.sh` must sync the source, run Swift tests on the Mac, build/package `dist/Bessie.app`, and run non-destructive live checks against an isolated repository-local Herdr configuration. Do not claim success from compilation alone.

For UI verification, launch the built app on the Mac, capture a screenshot, and inspect it. For terminal verification, assert output/input using live Herdr pane reads or an equivalent observable check.

## Working discipline

- Work in small checkpoints and keep `docs/reports/goal-progress.md` current with changed files and actual command results.
- Add focused tests for model decoding, transport envelopes, layout projection, compatibility checks, and terminal frame sequencing.
- Do not delete, skip, weaken, narrow, or relabel checks to manufacture a pass.
- Avoid speculative abstractions and dependencies. Prefer one honest vertical slice over decorative dead UI.
- Keep the repo uncommitted unless Jordan explicitly asks for commits.
