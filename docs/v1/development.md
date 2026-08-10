# Developing Bessie V1

This is the contributor guide for the current V1 codebase. Read [`AGENTS.md`](../../AGENTS.md) before changing code; its ownership, validation, and release-safety rules are mandatory.

## Repository layout

| Path | Purpose |
| --- | --- |
| `Package.swift` | Swift 6 package manifest and exact dependency pins |
| `Sources/BessieCore/` | Pure-Swift Herdr adapters, models, transports, Projects, persistence, terminal sequencing, connection/runtime, and intent contracts |
| `Sources/BessieApp/` | Native SwiftUI/AppKit app, libghostty hosting, settings, onboarding/Trouble, Projects UI, notifications, and Sparkle coordination |
| `Sources/BessieCLI/` | `bessie` command-line client for the running app's intent socket |
| `Sources/BessieMCP/` | stdio MCP adapter over the same live intent catalog |
| `Sources/BessieMigrationTool/` | stopped-app configuration/project migration operator |
| `Tests/BessieCoreTests/` | transport, projection, terminal, Projects, persistence, security, and optional live-Herdr tests |
| `Tests/BessieAppModelTests/` | app/view-model, responder, notification, update, theme, and integration-model tests |
| `Tests/BessieCLITests/`, `Tests/BessieMCPTests/`, `Tests/BessieMigrationToolTests/` | executable-surface contract tests |
| `scripts/` | ordinary checks, Mac verification, packaging, install lifecycle, runtime lock/fetch, and release tooling |
| `docs/v1/` | concise current V1 architecture and contributor documentation |
| `docs/releases/` | signing, notarization, update, and publication runbook |
| `site/` | bessie.dev site source, separate from the native app |
| `.local/`, `.build/`, `dist/` | ignored local runtime/state, Swift build output, and packaged artifacts |

The Swift package produces the `BessieCore` library plus `BessieApp`, `bessie`, `bessie-mcp`, and `BessieMigrationTool` executables.

## Prerequisites

The shipping target and native test environment are:

- Apple Silicon Mac;
- macOS 14 or newer;
- Xcode command-line tools with Swift 6 (`xcode-select` must point at the intended Xcode);
- network access for SwiftPM dependency resolution when artifacts are not already cached;
- the exact SwiftPM dependencies from `Package.swift`: `libghostty-spm` `1.3.2` and Sparkle `2.9.5`.

Tests that exercise live sessions additionally need the repository-pinned arm64 Herdr `0.8.0`, protocol `19`. Use `scripts/herdr-runtime-lock.json` as the artifact identity. `./scripts/fetch-herdr-runtime.sh` installs only into the repository's `.local/` development area; do not replace a system Herdr executable.

The ordinary repository check also uses standard shell/Python tools and media utilities referenced by `scripts/check.sh` (including `ffprobe` for the packaged cold-open asset). The Linux/VPS checkout can run static and fixture checks, but it cannot establish native AppKit, Metal/libghostty, signing, installation, or responder behavior.

## Source of truth

Use sources in this order when they disagree:

1. [`AGENTS.md`](../../AGENTS.md) for repository rules and fixed V1 constraints.
2. This directory's [`architecture.md`](architecture.md) for the implemented V1 component and ownership model.
3. Current code, tests, package/runtime lockfiles, and release runbooks for executable details.
4. [`features.md`](features.md), [`getting-started.md`](getting-started.md), and [`automation.md`](automation.md) for current public behavior.

## Ordinary checks

Run this from the repository root for every change:

```bash
./scripts/check.sh
```

It checks shell/Python syntax, package/runtime locks, packaging and release fixtures, identity boundaries, intent/theme/design contracts, and repository invariants. If Swift is available it also validates the package manifest; on the VPS it reports that native compilation belongs on the Mac.

For changed files, also run whitespace/error checking before handoff:

```bash
git diff --check -- path/to/changed-file …
```

Documentation-only work does not require manufacturing a Mac app run, but it still requires `./scripts/check.sh` and `git diff --check`. Never weaken or skip a check to obtain a pass.

## Native and focused Mac tests

Run native Swift tests on the Apple Silicon Mac checkout:

```bash
xcrun swift test
```

That is the ordinary complete native suite. The current established baseline is 733 XCTest tests with 6 intentional skips and 0 failures, plus 21 Swift Testing tests passing. Five skips are isolated live-Herdr tests gated by environment; one is a headless responder case. Treat these numbers as a known baseline, not a reason to ignore new tests or unexpected skips.

During implementation, prefer the smallest relevant suite first, then expand. SwiftPM supports test-case filters, for example:

```bash
xcrun swift test --filter BessieProjectMaterializationTests
xcrun swift test --filter TerminalControllerTests
xcrun swift test --filter SettingsAndNotificationsTests
```

Choose filters that match the files and behavior changed. For UI/app behavior, a compile or model test alone is insufficient: launch the built or packaged app, exercise the changed flow, capture a screenshot when visual output changed, and inspect an observable live result. For terminal behavior, verify round-trip output/input through a Herdr-owned pane rather than only a standalone libghostty fixture. For focus, IME, menu, notification, update, and installation behavior, use the relevant native environment and lifecycle test.

`./scripts/mac-verify.sh` is a broad maintainer release gate. It performs live automation, packages, and may install; it is not a shortcut for focused feature validation. Use direct `xcrun swift test --filter …` and a narrowly isolated live check for ordinary development.

When release work passes focused Mac validation, follow `AGENTS.md` and the release runbook for packaging, installation, relaunch, and installed executable identity. Documentation-only changes do not imply a new app artifact.

## Testing philosophy

Tests should prove ownership boundaries and observable behavior, not implementation decoration.

- Unit-test decoding, envelopes, protocol/version checks, path and schema validation, projection/layout derivation, persistence normalization, action parameters, intent risks, and terminal frame sequencing.
- Test race and recovery paths: buffered bootstrap events, reconnect, stale snapshots, sequence gaps, ambiguous mutation outcomes, stale Project writes, stale notification routes, and controller conflicts.
- Keep network/process/filesystem seams injectable where that makes deterministic tests possible, while retaining focused integration coverage for the real adapters.
- Verify Herdr mutations by response plus a fresh snapshot. Do not assert that an optimistic local model became truth.
- Terminal support requires the same public control/API path used in the product. A standalone parser or renderer success is necessary but not sufficient.
- UI work needs native evidence: responder behavior, screenshots, accessibility/interaction where relevant, and observable effects in Herdr.
- Security tests should include malformed/untrusted input, symlink/path escapes, file permissions, socket ownership, unsafe SSH values, and stale one-shot confirmation tokens.
- Do not delete, skip, relabel, narrow, or loosen tests to hide a regression. Every unexpected skip or environment gate should be explained.

## Safe live-Herdr testing

Live tests can create workspaces, panes, processes, terminal controllers, and SSH forwards. Isolate and label everything they own.

1. Use the repository-local runtime and create config, XDG state, logs, sockets, Projects, and presentation files under `.local/` or a unique temporary directory.
2. Use a unique named Herdr session and explicit Bessie-scoped environment variables. Never rely on an inherited generic `HERDR_SOCKET_PATH`.
3. Before starting a server, prove that the socket/state belongs to the test. Refuse to reuse, stop, or overwrite an unrelated server or the user's default session.
4. Prefer read-only `session.snapshot`, `pane.read`, or `herdr terminal session observe` while diagnosing. Open a writable controller only for a pane the test created.
5. Never pass terminal `--takeover` during automation unless the test specifically covers a user-confirmed takeover against test-owned controllers.
6. Use unique workspace/pane labels and record created IDs. Cleanup only those exact objects, processes, sockets, and temporary directories.
7. After app/controller teardown, verify the Herdr-owned pane process is still alive when persistence is under test. Stopping Bessie is not permission to stop Herdr.
8. For SSH, use an explicit known host alias, strict host-key checking, private stream-local forwards, and a test-owned remote session/folder. Never expose Herdr on TCP or modify remote shell/Herdr configuration as a convenience.
9. If a mutation response is lost, resnapshot before retrying. Do not create duplicate workspaces or issue speculative destructive cleanup.
10. Keep live tests opt-in and environment-gated in the ordinary suite unless they can be made hermetic, fast, and non-destructive.

Never use a person's active Herdr pane as test input, and never send commands into a live pane merely because its ID appears in a snapshot.

## Packaging boundaries

`swift build` and `swift test` exercise SwiftPM products; they do not create a distributable app or prove signing/runtime nesting.

- `scripts/package-app.sh` assembles `dist/Bessie.app`, embeds frameworks/resources and the locked Herdr runtime, and applies the selected development/verification/production identity rules.
- Packaged applications carry Bessie's Apache-2.0 license at `Contents/Resources/Bessie-LICENSE.txt`, the bundled Herdr license under `Contents/Resources/Herdr/`, and the resource attribution file. Packaging and install checks fail if those copies are missing or drifted.
- Verification packages use `dev.bessie.app.verify` and cannot be treated as production install candidates.
- Production packaging requires a stable approved signing identity; ad-hoc signing must not claim `dev.bessie.app`.
- Install helpers modify `/Applications/Bessie.app` and interact with LaunchServices. Run them only as part of the authorized Mac validation flow, and verify that the installed executable matches the packaged executable.
- Runtime fetching, app packaging, install verification, and update/release preparation are separate stages. Passing one does not imply the others.

Do not hand-edit packaged output in `dist/` or commit build artifacts. Fix the source, lock, template, or packaging script and regenerate.

## Release-tooling boundary

Release operations are not ordinary contributor validation. `docs/releases/README.md` is the runbook.

- `./scripts/check.sh` runs secret-free release fixtures and offline consistency tests only.
- `./scripts/release-app.sh prepare …` is credentialed, macOS-only, and requires separate authorization. It uses a Developer ID identity, Apple notarization profile, and Sparkle Keychain key.
- `release-app.sh verify` checks a prepared directory offline; it does not establish publication or operator approval.
- The repository's publish subcommand intentionally refuses. GitHub release publication, asset upload, Cloudflare/appcast deployment, production-feed changes, and update rollout remain separate operator-approved actions.
- Never put signing, notarization, Sparkle private-key, or Apple credentials in the repository, command history, environment captures, fixtures, or logs.

A successful build/package is not a release. A notarized prepared archive is not published. A staged appcast is not the production feed.

V1 is a direct Developer ID distribution, not a Mac App Store submission. Approved release bytes are intended for `bessie.dev`, an immutable GitHub release, and command-line installation through a verified Homebrew cask and/or `curl` installer. Every channel must resolve to the same notarized archive and published checksum rather than rebuilding channel-specific app bundles.

## Change discipline and handoff

- Keep changes scoped and inspect the pre-existing working tree before editing. Do not overwrite another contributor's files.
- Update or add focused tests with behavior changes and report actual command output, including skips and environment limitations.
- Keep durable current docs concise and source-grounded.
- Keep commits scoped and use the repository's conventional commit style.
- Pull requests should target the current default branch and include the evidence requested in `CONTRIBUTING.md`.
- Publishing an artifact, deploying a feed/site, changing repository visibility, or running credentialed release preparation remains a maintainer-only operation.

A contributor handoff should state what changed, files touched, exact checks run and their real results, focused/live evidence, known skips or blockers, and whether any app was packaged or installed.
