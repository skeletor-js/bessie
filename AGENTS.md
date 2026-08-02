# Bessie implementation repository

Read this file before changing code.

## Product source of truth

The retained product and technical context lives outside this repository at:

- VPS: `/home/hermes/.hermes/workspace/shared/workstreams/bessie`
- Mac: `/Users/jordanstella/Desktop/Hermes/workstreams/bessie`

The exception is the canonical Bessie product roadmap, which lives in this repository under `docs/roadmap/`.

For implementation work, read these first:

1. `docs/plans/2026-08-01-bessie-v1.md`
2. workstream `V1-SCOPE.md`
3. workstream `WORKSPACE-INTERACTION-SPEC.md`
4. workstream `TERMINAL-BEHAVIOR.md`
5. workstream `HERDR-CAPABILITY-MAP.md`
6. workstream `ARCHITECTURE.md`
7. workstream `FEASIBILITY.md`

Use the design system under workstream `source-material/design-system/` for assets, tokens, and screen intent. Adapt it natively; do not ship the HTML kit inside a web view.

## Non-negotiable constraints

- Bessie is a graphical client for Herdr, never a replacement runtime or fork.
- Herdr owns every workspace, tab, pane, terminal, process, agent, and durable session fact. Bessie may own Bessie-native launch recipes that materialize those Herdr objects, but never the live objects themselves.
- Every visible terminal surface uses libghostty through `GhosttyTerminal`; no terminal imitation or alternate emulator.
- Bessie may persist presentation preferences, Bessie-native project recipes, and last-opened Herdr identifiers. Project recipes are launch configuration, never a shadow copy of live Herdr state; persisted Herdr identifiers are hints revalidated against a fresh snapshot.
- Quitting Bessie must not terminate Herdr or pane processes.
- Use only Herdr's public JSON socket API, CLI wrappers, and public terminal-session bridge. Never copy or depend on Herdr's private bincode client protocol.
- Real V1 includes the verified native foundation, the compatible Herdr runtime bundled in the signed app with onboarding/Trouble, and Native Bessie Projects. Keep graphical approval inference, worktrees, generic IDE features, and other unrelated scope out unless a later approved plan explicitly brings one in. Native Bessie Projects do not require Herdr Plus or a companion plugin.
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
- The distributable V1 app includes the exact compatible Apple Silicon Herdr executable as a signed nested resource. Included is the default; compatible system/custom runtimes remain explicit advanced choices.
- Native Project recipes are Bessie-owned versioned launch configuration. Every workspace, tab, pane, terminal, process, and agent they create remains ordinary Herdr-owned live state.

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

After a change passes the required Mac verification, install the newly packaged `dist/Bessie.app` at `/Applications/Bessie.app` on `jordan-macbook`, relaunch it, and verify that the installed executable matches the packaged executable. This is the default completion step for Bessie work unless Jordan explicitly says not to install it.

For UI verification, launch the built app on the Mac, capture a screenshot, and inspect it. For terminal verification, assert output/input using live Herdr pane reads or an equivalent observable check.

## Working discipline

- Work in small checkpoints and keep `docs/reports/goal-progress.md` current with changed files and actual command results.
- Add focused tests for model decoding, transport envelopes, layout projection, compatibility checks, and terminal frame sequencing.
- Do not delete, skip, weaken, narrow, or relabel checks to manufacture a pass.
- Avoid speculative abstractions and dependencies. Prefer one honest vertical slice over decorative dead UI.
- Keep the repo uncommitted unless Jordan explicitly asks for commits.
