# Cross-agent Plans

**Status:** Exploring  
**Roadmap horizon:** Post-V1  
**Product area:** Coordination  
**Implementation approval:** Not granted by this document

## Outcome

See normalized work in progress across agents and detect collisions without creating a generic task-management system.

## Why this exists

The mockup aggregates todos, progress, stalls, and file overlap and offers direct routing back to each pane.

## First useful slice

- Define a normalized, capability-gated plan item contract.
- Group plan items by agent and workspace.
- Show done, in-flight, queued, and stalled states.
- Open or nudge the owning pane.

## Possible later scope

- Group by file touched.
- Detect same-file overlap.
- Move, drop, or reassign tasks where agent integrations support it.
- Suggest worktree splits for conflicts.

## Sources of truth and dependencies

Typed agent plan data through Herdr; companion support for overlap detection.

Bessie must preserve Herdr as the authority for sessions, panes, processes, agents, and durable session state. Any additional owner—filesystem, Git, agent integration, companion plugin, or provider—must be named explicitly in the eventual implementation plan.

## Principal risks

- Inferring todos from prose would be unreliable.
- Task mutation may be agent-specific and can conflict with the agent's own planner.

## Open questions

- Is read-only aggregation valuable enough before mutation exists?
- How much coordination belongs in Bessie versus the agent or repository workflow?

## Graduation criteria

Before this idea becomes **Proposed**, validate the first useful slice against the current Herdr contracts, identify local and remote behavior, define failure and empty states, and split any high-risk side effects into separately approved milestones.
