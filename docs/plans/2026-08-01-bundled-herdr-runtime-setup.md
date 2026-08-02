# Bundled Herdr runtime, onboarding, and Trouble

**Date:** 2026-08-01  
**Status:** Complete; Milestones 0–6 implemented and independently verified  
**V1 slice:** 1 after the verified foundation baseline  
**Owner:** Bessie distribution and UI; Herdr remains the runtime  
**First platform:** macOS 14+ on Apple Silicon

## Outcome

A person can download Bessie, open it, and reach a real Herdr terminal without installing Herdr separately, editing shell configuration, or diagnosing executable and socket paths.

The first-run path is:

> Open Bessie → verify the included Herdr runtime → start or reuse Bessie's named Herdr session → create or choose a workspace → open one real terminal.

Existing Herdr users retain an explicit advanced path to select a compatible system or custom runtime. Bessie never replaces or mutates that installation.

## Release-train decision

Treat these roadmap documents as one product release train rather than three independently sequenced features:

1. `docs/roadmap/managed-herdr-runtime-and-setup.md`
2. `docs/roadmap/onboarding-and-zero-states.md`
3. `docs/roadmap/trouble-and-diagnostics.md`

The runtime makes the zero-install path possible. Onboarding exposes it. Trouble makes failures explainable and recoverable. Shipping only one or two of the three would leave an incomplete first-run contract.

## Implementation checkpoint — 2026-08-01

The first bounded loop completed the distribution/provenance and reproducible-artifact substrate:

- pinned and independently verified Herdr `0.7.5` Apple Silicon artifact;
- Apache-2.0 relicensing provenance and bundled notice;
- deterministic fetch, checksum, architecture, version, and drift checks;
- embedding at `Bessie.app/Contents/Resources/Herdr/herdr`;
- nested signing support, package assertions, installation rollback, and live Mac verification.

The completing loop added production bundled runtime selection, persisted bundled/system/custom choices, typed validation and diagnostics, reachable onboarding, Setup Doctor/Trouble, exact failure-specific safe actions, and the no-system-Herdr acceptance path. A selected external runtime never silently falls back to the included runtime.

Jordan completed the Apple Developer agreement and local credential setup. Final notarization submission, stapling, and quarantined release-candidate assessment remain intentionally deferred until the full V1 candidate is feature-complete. This implementation did not submit an intermediate build to Apple.

Milestones 2–6 are complete. Independent verification rebuilt and packaged Bessie, ran 85 Swift tests with zero failures, exercised the bundled/custom/failure matrix, reached and persisted a real first terminal, installed and relaunched `/Applications/Bessie.app`, and confirmed ordinary Herdr `default` remained stopped. Native Projects remains the next separate V1 slice.

## Product decisions

### 1. Bundle the compatible runtime in the app

The first macOS release bundles the exact supported Apple Silicon Herdr executable inside the signed application bundle:

```text
Bessie.app/Contents/Resources/Herdr/herdr
```

For the initial release:

- the runtime version remains pinned to `BessieCompatibility.herdrVersion`;
- the protocol remains pinned to `BessieCompatibility.protocolVersion`;
- acquisition happens during the trusted build/package process, not at first application launch;
- the build verifies the official artifact against a checked-in lock record containing URL, version, architecture, release artifact commit, compatibility/protocol source baseline, relicensing commit, and SHA-256;
- the nested executable and enclosing app are signed and verified together;
- runtime updates ship with Bessie updates;
- rollback means reinstalling or reopening the previous Bessie release, which carries its compatible runtime.

This avoids executing a newly downloaded binary during onboarding and prevents Bessie and Herdr compatibility from drifting independently.

A future downloaded-runtime updater is a separate proposal. Do not build it into this release.

### 2. Bundled is the default; existing installs remain optional

Runtime choices are:

1. **Included with Bessie** — default and always available in a valid release build.
2. **Compatible Herdr on this Mac** — opt-in advanced selection.
3. **Custom executable** — explicit user-selected path for development or advanced use.

Environment overrides remain available for automated verification and development, but they are not ordinary product configuration.

Bessie never silently changes an explicit runtime selection. If a selected external runtime disappears or becomes incompatible, Bessie explains the problem and offers the included runtime; it does not switch while a launch is in progress.

### 3. Share ordinary Herdr configuration; isolate by named session

The included runtime uses the user's ordinary Herdr configuration and state conventions, with `HERDR_SESSION=bessie` selecting Bessie's named session. Bessie does not create a second hidden plugin or agent universe.

Rules:

- continue ignoring inherited generic `HERDR_SOCKET_PATH` and `HERDR_SESSION` values that may belong to an unrelated shell;
- honor only Bessie-specific diagnostic overrides during development and tests;
- do not edit Herdr configuration during startup;
- show the effective runtime, session, config root, state root, and socket paths in Trouble;
- if configuration is invalid, report the owning file and Herdr error without rewriting it.

An isolated repository-local configuration remains test-only.

### 4. Ordinary Herdr access remains possible

The running session is still ordinary Herdr. Trouble exposes:

- **Copy attach command** using the selected runtime and `--session bessie` where supported;
- **Reveal included Herdr**;
- **Install command-line launcher…** as an optional, separately approved later milestone if users need a stable shell command.

The first release does not write into `/usr/local/bin`, `/opt/homebrew/bin`, shell profiles, or another package manager's directories.

### 5. Setup Doctor is read-only in the first release

The first Setup Doctor observes and explains. It does not mutate Herdr, shell, Git, SSH, agent, or macOS configuration.

It may offer safe owner-routed actions such as Reveal, Open Settings, Copy command, or Open documentation. Any repair that writes configuration graduates as a separately reviewed milestone with an exact change preview and confirmation.

## Existing substrate

The current app already provides most runtime control primitives:

- `Sources/BessieCore/RuntimeDiscovery.swift`
  - `HerdrRuntime`, `HerdrRuntimeLocator`, `HerdrRuntimeProbe`, and `HerdrServerLauncher`;
- `Sources/BessieCore/ConnectionLifecycle.swift`
  - named-session environment isolation, startup, compatibility checks, bootstrap, reconnect, and connection state;
- `Sources/BessieCore/BessieCompatibility.swift`
  - pinned Herdr version, protocol, source revision, and `bessie` session name;
- `Sources/BessieCore/ConnectPresentation.swift`
  - honest missing, stopped, incompatible, connecting, connected, retrying, and lost states;
- `Sources/BessieApp/BessieSettings.swift`
  - Application Support storage and a basic version surface;
- `Sources/BessieApp/BessieDiagnosticLog.swift`
  - test-oriented state logging;
- `scripts/mac-verify.sh`
  - official artifact URL, pinned checksum, isolated runtime download, startup, live terminal checks, and cleanup;
- `scripts/package-app.sh`
  - release build, app assembly, signing, and signature verification.

The release train should refactor and extend those seams. It must not introduce a second connection stack.

## Architecture

### Runtime identity

Expand the runtime model so the UI can explain selection and provenance:

```swift
public struct HerdrRuntimeDescriptor: Equatable, Sendable {
    public enum Source: String, Codable, Sendable {
        case bundled
        case systemPath
        case custom
        case repositoryLocal
        case explicitOverride
    }

    public let executableURL: URL
    public let source: Source
    public let expectedVersion: String?
    public let expectedProtocol: Int?
    public let expectedSHA256: String?
}
```

Keep test/development sources representable, but hide them from ordinary release UI unless active.

### Persisted selection

Add a small versioned settings document under Application Support:

```text
~/Library/Application Support/Bessie/runtime-selection.json
```

Suggested model:

```swift
enum BessieRuntimeSelection: Codable, Equatable, Sendable {
    case bundled
    case systemPath
    case custom(path: String)
}
```

Do not persist socket paths, process IDs, live session IDs, or compatibility results. Recompute those every launch.

### Resolution order

`BessieRuntimeResolver` resolves one selected runtime, not a winner from an opaque search contest:

1. Bessie-specific test/development override, when present;
2. persisted explicit selection;
3. bundled default.

System discovery feeds the advanced runtime picker and Setup Doctor. It does not silently outrank the bundled runtime.

### Runtime validation

Validation produces typed facts rather than one prose error:

```swift
struct HerdrRuntimeValidation: Equatable, Sendable {
    let executableExists: Bool
    let executableIsRunnable: Bool
    let actualVersion: String?
    let actualProtocol: Int?
    let checksumMatchesBundleLock: Bool?
    let signatureValid: Bool?
    let compatibility: Compatibility
    let failures: [HerdrSetupFinding]
}
```

Checksum and signature checks apply to the included runtime. External runtimes are compatibility-probed but are not expected to match Bessie's bundled checksum.

### Connection state

Preserve `HerdrConnectionState` as the authoritative connection lifecycle, but add enough typed context to distinguish:

- resolving runtime;
- validating executable;
- probing the named session;
- starting Herdr;
- waiting for readiness;
- connecting API socket;
- attaching event subscription;
- opening terminal control;
- connected;
- retrying;
- terminal-controller failure while API remains connected.

Do not collapse all failures into “Herdr unavailable.” Trouble needs the failing stage, owner, safe actions, and underlying error.

### Diagnostic snapshot

Add a sanitized value object assembled from current facts:

```swift
struct BessieDiagnosticSnapshot: Sendable {
    let generatedAt: Date
    let bessieVersion: String
    let macOSVersion: String
    let architecture: String
    let runtime: RuntimeFacts
    let session: SessionFacts
    let connection: ConnectionFacts
    let terminalControllers: [TerminalControllerFacts]
    let setupFindings: [HerdrSetupFinding]
}
```

Redaction rules:

- do not include terminal contents or scrollback;
- do not include environment values, tokens, SSH private paths, or command histories;
- include path names only where necessary to diagnose runtime/config ownership;
- mark every fact as observed, expected, unavailable, or failed;
- never manufacture causal narratives from missing evidence.

## Setup Doctor checks

### Required first-release checks

1. Included Herdr executable exists inside the running Bessie bundle.
2. Included executable checksum matches the lock record.
3. Code signature validation succeeds for the nested executable and app.
4. Selected runtime launches and reports a parseable version/status payload.
5. Herdr version and protocol are compatible with Bessie.
6. Effective config and state roots are readable/creatable by their owner.
7. The `bessie` session socket path is not shadowed by inherited generic overrides.
8. The named server is stopped, starting, running, incompatible, or unreachable.
9. API and terminal-control sockets are independently reachable.
10. Login shell exists.
11. Git is discoverable, reported as optional until a Project or workspace action needs it.
12. Supported agent manifests are shown from Herdr; unavailable binaries remain honest unavailable states.
13. Notification permission is shown as a Bessie/macOS fact, not a Herdr failure.

### Later checks

- SSH connection health after remote graphical sessions are supported;
- plugin-specific health supplied by Herdr;
- writable repair actions;
- update channel and rollback health;
- sanitized diagnostic archive export.

## First-run and zero-state behavior

### First launch

Show onboarding only when Bessie has never completed the first-terminal milestone or when the user explicitly chooses **Run Setup Again**.

Steps:

1. **Bessie includes Herdr** — show exact version and explain that Herdr remains the engine.
2. **Check this Mac** — validate the included runtime and named-session paths.
3. **Start Herdr** — start or reuse only the `bessie` session.
4. **Open a terminal** — focus an existing workspace or create one shell workspace after explicit action.
5. **Four essentials** — show workspace switch, new pane, command palette, and the fact that quitting Bessie leaves work running.

Do not ask users to choose configuration roots or runtime paths during ordinary onboarding.

### Existing Herdr user

An advanced disclosure offers **Use another Herdr runtime…**. It shows every candidate's path, version, protocol, compatibility, and source before selection.

Changing runtime while connected requires confirmation and a clean reconnect. It never stops the old server.

### Zero-state matrix

Implement explicit states for:

- packaged Bessie missing its included runtime — release integrity failure;
- runtime present but not executable;
- invalid signature or checksum;
- incompatible selected external runtime;
- no Herdr session running;
- startup in progress;
- startup failed;
- API socket reachable but terminal-control socket unavailable;
- connected session with no workspace;
- workspace with no usable tab/pane due to external mutation;
- no supported agents installed;
- connection lost while Herdr processes may still be running.

Every state names the owner and offers one safest next action. The universal fallback is to open Trouble, not to guess a repair.

## Trouble destination

Add **Trouble** as a first-class destination reachable from connection banners, Settings, onboarding failures, and the command palette.

### Summary

- overall state: Healthy, Degraded, Disconnected, or Setup required;
- selected runtime and source;
- Herdr version/protocol;
- named session and socket paths;
- API connection health;
- visible terminal-controller counts and failures;
- last successful snapshot time;
- current retry stage.

### Findings

Each finding has:

- severity;
- owning system: Bessie, Herdr, macOS, shell, Git, SSH, or agent integration;
- observed fact;
- expected fact;
- safe actions;
- optional technical detail.

### Actions

First release actions are bounded:

- Retry connection;
- Use included runtime;
- Choose another runtime…;
- Reveal executable;
- Reveal/open Herdr config or log when known;
- Copy attach command;
- Copy sanitized diagnostic report;
- Run Setup Again;
- Open macOS notification settings.

No action stops an unrelated Herdr server, deletes sockets blindly, rewrites config, installs shell tooling, or terminates pane processes.

## Build and supply-chain plan

### Runtime lock

Add `scripts/herdr-runtime-lock.json` containing:

- Herdr version;
- protocol;
- release artifact commit;
- compatibility/protocol source baseline;
- Apache-2.0 relicensing commit;
- platform and architecture;
- official artifact URL;
- SHA-256;
- expected executable version string;
- license/notice metadata required for redistribution.

Seed the first lock from the artifact already exercised by `scripts/mac-verify.sh`:

- URL: `https://github.com/herdrdev/herdr/releases/download/v0.7.5/herdr-macos-aarch64`
- SHA-256: `37350546b0012555943b92eaf962665de4e264395baeb44227b8015e8ff5b0d6`

Milestone 0 must independently reverify those values and redistribution terms before they become release inputs.

`BessieCompatibility` and the lock file must agree. `scripts/check.sh` fails if they drift.

### Acquisition script

Add `scripts/fetch-herdr-runtime.sh`:

1. parse the checked-in lock;
2. reuse a cached artifact only if its checksum matches;
3. download to a temporary path with failure-on-HTTP-error behavior;
4. verify SHA-256 before chmod or copy;
5. verify `herdr --version`;
6. move atomically into the build staging directory;
7. never write to a system Herdr path.

### Packaging

Update `scripts/package-app.sh` to:

1. acquire/verify the pinned runtime;
2. copy it to `Contents/Resources/Herdr/herdr`;
3. set executable permissions;
4. embed required license notices;
5. sign the nested executable before signing the app where release signing requires it;
6. verify the nested executable and enclosing bundle;
7. assert the packaged Bessie executable resolves the bundled path;
8. fail if the runtime is absent, mismatched, writable by group/other, or unsigned under a release-signing build.

Ad hoc development signing remains acceptable for local verification. Public distribution requires Developer ID signing, hardened runtime, notarization, and quarantine/Gatekeeper testing before this release can be called distributable.

## Implementation sequence

### Milestone 0 — Distribution and ownership proof

1. Confirm Herdr's redistribution license and required notices.
2. Verify the official Apple Silicon artifact, checksum, version output, and protocol.
3. Build a throwaway app bundle containing Herdr and exercise nested signing.
4. Test launch from a quarantined copy on a clean macOS user account or equivalent isolated environment.
5. Confirm the bundled runtime can use ordinary Herdr configuration and the named `bessie` session without mutating another session.

**Exit:** no unresolved legal, signing, Gatekeeper, architecture, or configuration-owner blocker remains.

### Milestone 1 — Reproducible bundled artifact

Suggested files:

- `scripts/herdr-runtime-lock.json`
- `scripts/fetch-herdr-runtime.sh`
- `scripts/package-app.sh`
- `scripts/check.sh`
- `Sources/BessieCore/BessieCompatibility.swift`

Implement locked acquisition, package embedding, notices, drift checks, nested signing, and package assertions.

**Exit:** every packaged `Bessie.app` contains the exact verified runtime, and tampering or version drift makes packaging/checks fail.

### Milestone 2 — Runtime resolver and selection

Suggested files:

- `Sources/BessieCore/RuntimeDiscovery.swift`
- `Sources/BessieCore/RuntimeSelection.swift`
- `Sources/BessieCore/RuntimeValidation.swift`
- `Tests/BessieCoreTests/RuntimeDiscoveryTests.swift`
- `Tests/BessieCoreTests/RuntimeSelectionTests.swift`
- `Tests/BessieCoreTests/RuntimeValidationTests.swift`

Add bundled discovery through `Bundle`-supplied paths, persisted selection, explicit external-runtime selection, typed validation, and no-silent-fallback behavior.

Inject the bundled URL into `BessieCore`; do not make the library depend directly on `Bundle.main`.

**Exit:** the resolver deterministically selects and validates bundled, compatible system, custom, test, and missing runtimes.

### Milestone 3 — Lifecycle and diagnostics facts

Suggested files:

- `Sources/BessieCore/ConnectionLifecycle.swift`
- `Sources/BessieCore/SetupDiagnostics.swift`
- `Sources/BessieCore/DiagnosticSnapshot.swift`
- `Sources/BessieApp/BessieDiagnosticLog.swift`
- focused lifecycle and diagnostics tests.

Split runtime resolution, validation, server startup, API connection, and terminal-control health into typed observable stages. Preserve the existing session-isolation and process-survival behavior.

**Exit:** every supported failure is distinguishable without parsing human prose, and reconnect/start behavior remains proven live.

### Milestone 4 — Onboarding and complete zero states

Suggested files:

- `Sources/BessieApp/OnboardingFlow.swift`
- `Sources/BessieApp/SetupPresentation.swift`
- `Sources/BessieCore/OnboardingState.swift`
- `Sources/BessieCore/PresentationPersistence.swift`
- focused app-model tests.

Implement the five-step first-run path, Run Setup Again, existing-user runtime selection, first-terminal completion marker, and zero-state matrix.

**Exit:** a clean macOS user can open Bessie and reach one real terminal without installing Herdr or opening Terminal.app.

### Milestone 5 — Trouble and runtime settings

Suggested files:

- `Sources/BessieApp/TroubleView.swift`
- `Sources/BessieApp/BessieSettings.swift`
- `Sources/BessieCore/SetupDiagnostics.swift`
- `Sources/BessieCore/DiagnosticRedaction.swift`

Add runtime selection, diagnostic summary/findings, safe actions, and sanitized report copy. Replace hard-coded Settings version text with observed runtime facts.

**Exit:** runtime, connection, and terminal-control failures route to one trustworthy surface with a safe next action.

### Milestone 6 — Full release verification

Extend `scripts/mac-verify.sh` to test:

1. packaged app uses its included runtime with no system `herdr` on PATH;
2. included checksum, version, and signature are correct;
3. Bessie starts/reuses only the named `bessie` session;
4. an unrelated default Herdr session remains untouched;
5. a compatible external runtime can be selected explicitly;
6. an incompatible external runtime is rejected without silent fallback;
7. corrupt/missing included runtime produces release-integrity Trouble state;
8. onboarding reaches a real libghostty shell;
9. API and terminal-controller failures are distinguished;
10. sanitized diagnostics omit injected secret environment values and terminal text;
11. quitting/reopening Bessie leaves Herdr panes and processes alive;
12. the installed `/Applications/Bessie.app` executable and bundled Herdr binary match the packaged artifacts.

Capture and inspect screenshots for first run, setup success, incompatibility, startup failure, Trouble healthy/degraded states, and runtime selection.

**Exit:** checks, native tests, live isolated Herdr tests, packaging, installation, relaunch, signature verification, process survival, and visual review all pass.

## Test matrix

### Unit

- bundled path resolution;
- persisted runtime selection migration and corruption fallback;
- explicit runtime never silently replaced;
- compatibility facts and source labels;
- lock/compatibility drift;
- lifecycle state transitions and cancellation;
- diagnostic finding ownership and severity;
- deterministic redaction;
- onboarding completion/re-entry rules;
- zero-state action mapping.

### Integration

- fake runtime version/status outputs;
- missing/non-executable/tampered bundled binary;
- stopped/starting/ready/start-failed server;
- API socket works while terminal-control socket fails;
- generic Herdr environment overrides are ignored;
- Bessie-specific overrides remain available for tests;
- runtime switch disconnects/reconnects without stopping the previous server.

### Live macOS

- no Herdr installed;
- compatible Herdr already installed;
- incompatible external Herdr selected;
- existing unrelated default session running;
- invalid Herdr config;
- app quit/reopen;
- app bundle move after first launch;
- Gatekeeper/quarantine path before public distribution.

## Acceptance criteria

- A release build contains the exact compatible Herdr runtime declared by the lock record.
- A new user reaches a real Herdr/libghostty terminal without separately installing Herdr or using Terminal.app.
- Bessie defaults to the included runtime and allows an explicit compatible external selection.
- Bessie never overwrites, upgrades, stops, or reconfigures an existing Herdr installation or unrelated session.
- Runtime updates are coupled to Bessie releases in this version.
- Bessie's `bessie` session remains ordinary Herdr state and survives app quit/reopen.
- Setup Doctor is read-only and distinguishes facts from guesses.
- Trouble distinguishes runtime, API connection, and terminal-controller failures.
- Diagnostic copy excludes terminal content, secrets, and raw environment values.
- The included executable and enclosing application pass the required signature, checksum, packaging, install, and live tests.
- The default Herdr session remains untouched throughout verification.

## Explicit non-goals

- Runtime download or self-update from inside Bessie
- Silent runtime switching
- Editing or repairing Herdr configuration
- Installing shell-profile or package-manager entries
- Stopping an external Herdr server during runtime changes
- Managing multiple local runtime endpoints simultaneously
- Remote graphical Herdr acquisition
- Plugin marketplace or credential setup
- Inferring agent health from terminal prose
- Including terminal contents in diagnostics
- App Store distribution before sandbox and entitlement decisions are separately resolved

## Approval gate

Before implementation begins, Jordan should explicitly approve:

1. bundled runtime as the default acquisition model;
2. ordinary shared Herdr configuration plus named-session isolation;
3. Bessie-coupled runtime updates rather than an in-app updater;
4. read-only Setup Doctor scope;
5. the release train ordering ahead of Native Bessie Projects.
