# Bessie product roadmap

**Execution plans (ce-plan depth):** see `docs/plans/2026-08-01-bessie-v1.md` index.
**Vision/Occam lock:** `docs/plans/2026-08-02-v1-vision-occam-scope.md`
**Shared substrate:** `docs/plans/2026-08-02-v1-shared-substrate.md`
**Brand chrome (L):** `docs/plans/2026-08-03-brand-shell-and-chrome-hygiene.md`
**Hands-on acceptance remediation (M):** `docs/plans/2026-08-03-v1-acceptance-remediation.md`
**Pre-v1 UI redesign amendment:** `docs/plans/2026-08-04-001-feat-pre-v1-ui-redesign-plan.md`

## Current V1 state

D–J and the Agent Intent Bus are integrated on `main` through PR #2. The 2026-08-04 Pre-v1 redesign is the newer release-boundary amendment: native menu-bar Herd and the entity-aware palette are unparked, the four visible states are Needs you / Working / Settled / Unknown, and its shell/onboarding direction supersedes older visual plans. Its U12 matrix and packaged-app gate must pass before K. This is not a V1 release.

## First after V1 launch

| Priority | Item | Plan |
| --- | --- | --- |
| **P0** | **[Bessie iOS control plane](bessie-ios-control-plane.md)** — remote multi-host Herdr client (Mosh + one focused terminal) | [`docs/plans/2026-08-03-bessie-ios-control-plane.md`](../plans/2026-08-03-bessie-ios-control-plane.md) |

Starts only after Mac V1 release (or Jordan early green light). Not part of Mac V1 L/K.

## Deferred / later highlights

Search the Herd · Layout presets · Agent detail · Worktrees · Browser · Shepherd (including later reviewed broadcast) · graphical approve without typed RPC

## Not planned

**Cost and usage is permanently deferred.** Retained documents are decision history, not implementation candidates.

## Roadmap detail docs

Individual `docs/roadmap/*.md` status fields track product status; **implementation detail lives in `docs/plans/2026-08-02-*.md` and `docs/plans/2026-08-03-*.md`.**
