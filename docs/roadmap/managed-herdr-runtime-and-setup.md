# Managed Herdr runtime and setup

**Status:** Complete  
**Roadmap horizon:** V1  
**Product area:** Installation and first run  
**Implementation approval:** Granted by Jordan on 2026-08-01 through the V1 release decision  

**Implementation checkpoint:** The runtime artifact, production resolver, persisted selection, typed validation, onboarding, diagnostics, Trouble actions, clean-install acceptance, packaging, installation, and relaunch verification are complete. Final Developer ID notarization remains a release-candidate gate rather than part of this roadmap implementation.
**Implementation plan:** [`../plans/2026-08-01-bundled-herdr-runtime-setup.md`](../plans/2026-08-01-bundled-herdr-runtime-setup.md)

## Outcome

A person can download Bessie, open it, and reach a working Herdr terminal without manually installing Herdr, editing shell configuration, or diagnosing executable and socket paths.

Advanced users can continue using their existing Herdr installation and configuration normally.

## Why this exists

Bessie is meant to make a powerful terminal-native system approachable as desktop software. Requiring users to install and configure Herdr separately preserves the hardest part of the terminal-native experience before Bessie can help them.

The current app can locate and validate an installed Herdr runtime. It does not acquire, update, or repair one.

## First useful slice

- Detect existing Herdr installations and show the selected executable, version, protocol, and configuration root.
- Explain incompatibility or missing installation in plain language.
- Use the exact compatible Herdr runtime included inside the signed Bessie application bundle.
- Default to the included runtime while allowing an explicit compatible system/custom selection.
- Start Bessie's named Herdr session with the selected runtime and verify a real terminal opens.
- Provide a Setup Doctor that checks Herdr, shell, Git, SSH, supported agents, and relevant environment conflicts.

## Possible later scope

- Update or roll back the Bessie-managed Herdr runtime.
- Choose between detected and managed runtimes.
- Detect and repair broken agent integrations through their owning installer or configuration path.
- Export a sanitized diagnostic report.
- Support managed runtime acquisition on later Bessie platforms.

## Product boundary

- Herdr remains the runtime and owns all sessions, configuration, panes, processes, and durable state.
- Bessie may install and select a compatible Herdr executable; it must not fork Herdr or create a Bessie-specific runtime.
- Bessie must never silently replace, modify, or take ownership of an existing Herdr installation.
- Installation, updates, configuration changes, and repairs require explicit user approval and must show exactly what will change.
- A Bessie-managed runtime must remain usable through ordinary Herdr commands.

## Relationship to onboarding

[Onboarding and complete zero states](onboarding-and-zero-states.md) owns the guided first-run experience. This plan owns acquiring, selecting, validating, updating, and diagnosing the Herdr runtime that onboarding depends on.

## Sources of truth and dependencies

- Official Herdr release artifacts, checksums, compatibility metadata, and installation behavior.
- Bessie's supported Herdr protocol/version policy.
- The selected Herdr configuration root and public discovery/startup interfaces.
- Platform trust, signing, quarantine, and executable-permission behavior.

## Principal risks

- Accidentally targeting or mutating an unrelated Herdr installation or session.
- Creating two confusing configuration roots with different plugins or agents.
- Supply-chain and update failures.
- A failed update leaving the user unable to start Herdr.
- Claiming an integration is ready when its credentials or owning configuration are not actually valid.

## Resolved first-release decisions

- Bundle the pinned Apple Silicon runtime in `Bessie.app`; do not download executable code during first run.
- Use ordinary Herdr configuration/state conventions and isolate Bessie's work through the named `bessie` session.
- Couple runtime updates and rollback to Bessie app releases for the first version.
- Make Setup Doctor read-only; configuration-writing repairs require separately approved milestones.
- Treat onboarding and Trouble as required parts of the same release train.

## Graduation criteria

Before implementation approval, complete the distribution/signing spike, confirm Herdr redistribution terms, freeze diagnostic redaction rules, and explicitly approve the decisions and milestones in the implementation plan.
