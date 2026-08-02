# New Agent launch flow

**Status:** Deferred
**Roadmap horizon:** Deferred (2026-08-02)
**Product area:** New Agent
**Implementation approval:** Not granted by this document
**Deferred reason:** Jordan 2026-08-02 — current launch path sufficient for V1.

## Outcome

Make agent launch understandable, configurable, and predictable before Bessie creates panes or starts processes.

## Why this exists

The current sheet covers the essential launch path; the mockup adds integration quality, model, first prompt, placement, permission posture, and an operation preview.

## First useful slice

- Show richer agent cards and arbitrary-command fallback.
- Add model/arguments and an explicit first prompt where supported.
- Choose exact workspace, tab, split target, or reusable empty pane.
- Preview and copy the resulting Herdr operation.

## Possible later scope

- Plan-first prompt modifier.
- Prompt history and attachments.
- Permission posture with explicit owner labels.
- Worktree and remote-runtime targets.

## Sources of truth and dependencies

Herdr catalog and pane actions for the first slice; agent-specific modes, attachments, worktrees, and remotes follow their own contracts.

Bessie must preserve Herdr as the authority for sessions, panes, processes, agents, and durable session state. Any additional owner—filesystem, Git, agent integration, companion plugin, or provider—must be named explicitly in the eventual implementation plan.

## Principal risks

- A generic form can imply cross-agent capabilities that do not exist.
- Permission modes must identify the agent or runtime that actually enforces them.

## Open questions

- Which launch fields should be capability-gated per integration?
- Should first prompt be sent only after an authoritative readiness signal?

## Graduation criteria

Before this idea becomes **Proposed**, validate the first useful slice against the current Herdr contracts, identify local and remote behavior, define failure and empty states, and split any high-risk side effects into separately approved milestones.
