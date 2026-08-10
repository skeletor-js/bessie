# Bessie contributor contract

Read this file before changing code.

## Source of truth

Current public documentation lives in:

1. `README.md`
2. `docs/v1/features.md`
3. `docs/v1/getting-started.md`
4. `docs/v1/architecture.md`
5. `docs/v1/development.md`
6. `docs/v1/automation.md`
7. `docs/releases/README.md`

Source, tests, package lockfiles, and runtime lockfiles are authoritative when prose drifts.

## Non-negotiable architecture

- Bessie is a graphical client for Herdr, never a replacement runtime or fork.
- Herdr owns every workspace, tab, pane, terminal, process, agent, and durable session fact. Bessie may own versioned launch recipes that materialize Herdr objects, but never the live objects themselves.
- Every visible terminal uses libghostty through `GhosttyTerminal`; do not add a terminal imitation or alternate emulator.
- Bessie may persist presentation preferences, project recipes, and last-opened Herdr identifiers. Persisted Herdr identifiers are hints that must be revalidated against a fresh snapshot.
- Quitting Bessie must not terminate Herdr or pane processes.
- Use only Herdr's public JSON socket API, CLI wrappers, and public terminal-session bridge. Never copy or depend on Herdr's private bincode protocol.
- Do not modify Herdr or libghostty upstream source to make Bessie work.
- Keep graphical approval inference, worktrees, generic IDE features, and unrelated product expansion out of the V1 codebase.

## Compatibility baseline

- Target: macOS 14+ on Apple Silicon.
- UI: SwiftUI product surfaces with AppKit window, focus, and terminal hosting.
- Terminal: exact `libghostty-spm` `1.3.2` / `GhosttyTerminal` product.
- Herdr: `0.8.0`, protocol `19`, source `346411fa21afd297f5ed3b3fa56f9e3fbf7654b7`.
- Bootstrap with `session.snapshot`; public events are invalidation hints followed by a fresh snapshot.
- One writable `herdr terminal session control` process serves each visible pane.
- Input is composite: libghostty raw committed input, public Herdr key operations for intercepted special keys, and public Herdr text input for paste. Preserve ordering.
- Development may use repository-local runtime/config state under ignored `.local/`; never overwrite a system Herdr installation.
- Distribution bundles the compatible Herdr executable as a signed nested resource.

## V1 freeze

The Mac V1 source is feature-frozen. Before the V1 release, accept only:

- fixes for demonstrated major defects; or
- changes strictly required to build, sign, notarize, package, document, or distribute the release.

Do not merge cleanup, refactors, speculative abstractions, or nice-to-have features during the freeze.

## Validation

Run the ordinary repository checks:

```bash
./scripts/check.sh
```

Native behavior must also be exercised on macOS. Use focused Swift tests for changed behavior and verify observable terminal input/output against a real isolated Herdr pane. For release candidates, follow `docs/releases/README.md` and `scripts/mac-verify.sh`.

Do not delete, skip, weaken, narrow, or relabel a check to manufacture a pass. Compilation alone is not acceptance for UI, terminal, lifecycle, packaging, or update behavior.

## Working discipline

- Match existing Swift and shell conventions.
- Add focused tests for model decoding, transport envelopes, state transitions, layout projection, compatibility checks, and terminal frame/input sequencing.
- Keep dependencies and abstractions narrow.
- Never commit credentials, signing material, notarization profiles, local runtime state, build products, or generated release secrets.
- Do not publish releases, change repository visibility, deploy the site, or modify distribution channels as part of an ordinary code change.

## Agent surfaces

Use [`.agents/skills/operating-bessie/SKILL.md`](.agents/skills/operating-bessie/SKILL.md) for Bessie's CLI and MCP intent surfaces. It preserves Herdr ownership and requires runtime capability discovery instead of a second hard-coded command catalog.
