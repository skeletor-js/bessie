# Worktrees and branches

**Status:** Deferred  
**Roadmap horizon:** Parked; not sequenced for near-term post-V1  
**Product area:** Repository workflow  
**Implementation approval:** Not granted by this document  
**Deferred on:** 2026-08-01  
**Reason:** Jordan does not use worktrees and does not want a worktree product investment now. Community plugin demand remains real but is not a Bessie priority until Follow files, menu-bar/push, and in-app browser are decided and the core GUI remains excellent.

## Outcome (retained for when unparked)

Make parallel agent work visible and easy to open as ordinary Herdr workspaces.

## Why this existed

The designs connect worktrees, branch state, changed-file counts, agents, and workspace creation without claiming Bessie owns Git. Herdr plugins (worktrunk, sessionizer, herdr-plus layouts) show external demand.

## First useful slice (if unparked)

- Inventory the primary checkout and worktrees.
- Show clean/dirty/untracked, ahead/behind, last commit, and changed-file rollups.
- Open an existing worktree as a Herdr workspace.
- Show agents and states associated with each worktree when reliable.

## Possible later scope

- Create and remove worktrees through observable operations.
- Start a shell, agent, or recipe in a worktree.
- Compare against a selected base branch.
- Detect concurrent file overlap.

## Sources of truth and dependencies

Git and filesystem facts, Herdr workspace actions, and companion metadata for enrichment.

Bessie must preserve Herdr as the authority for sessions, panes, processes, agents, and durable session state. Any additional owner—filesystem, Git, agent integration, companion plugin, or provider—must be named explicitly in the eventual implementation plan.

## Principal risks

- Create/remove are side effects and must remain distinct from passive inventory.
- Branch or agent association can be ambiguous across nested repositories.
- Building this early pulls focus from higher-delight supervision features.

## Open questions

- Should Git mutations run in a visible Herdr pane or a typed companion contract?
- What confirmation is required before worktree removal?

## Re-entry criteria

Move back to **Exploring** or **Proposed** only when:

1. Jordan explicitly unparks worktrees; and
2. Follow files (or equivalent review) is shipped or consciously deprioritized; and
3. A real multi-checkout pain shows up in Bessie usage, not only in plugin star counts.

## Graduation criteria

Before this idea becomes **Proposed** again, validate the first useful slice against the current Herdr contracts, identify local and remote behavior, define failure and empty states, and split any high-risk side effects into separately approved milestones.
