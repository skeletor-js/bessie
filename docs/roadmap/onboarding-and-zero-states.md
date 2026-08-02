# Onboarding and complete zero states

**Status:** Approved  
**Roadmap horizon:** V1  
**Product area:** First run and recovery  
**Implementation approval:** Granted by Jordan on 2026-08-01 through the V1 release decision  
**Release train:** [`../plans/2026-08-01-bundled-herdr-runtime-setup.md`](../plans/2026-08-01-bundled-herdr-runtime-setup.md)

## Outcome

Help a new or disconnected user reach one working Herdr terminal without understanding Bessie's architecture first.

## Why this exists

Connection and empty states exist, but the exploration defines a guided first run and a complete topology-aware recovery matrix.

## First useful slice

- Detect and validate Herdr with path, version, and capability facts.
- Choose or create a workspace and open one shell.
- Teach the four essential focus/navigation controls.
- Explain that closing Bessie leaves Herdr and its processes running.

## Possible later scope

- No-session, no-workspace, no-tab, no-pane, and no-agent states.
- Capability-aware one-action recovery.
- Integration setup handoffs.
- Remote-unreachable behavior after remote connections ship.

## Sources of truth and dependencies

Current discovery, startup, workspace, and pane actions; remote and integration setup depend on their owning features.

Bessie must preserve Herdr as the authority for sessions, panes, processes, agents, and durable session state. Any additional owner—filesystem, Git, agent integration, companion plugin, or provider—must be named explicitly in the eventual implementation plan.

## Principal risks

- A wizard can become a brittle alternate settings UI.
- Automatic recovery must not mutate unrelated Herdr sessions.

## Open questions

- When should onboarding reappear after first run?
- What is the shortest honest path for users who only want a terminal?

## Graduation criteria

Before this idea becomes **Proposed**, validate the first useful slice against the current Herdr contracts, identify local and remote behavior, define failure and empty states, and split any high-risk side effects into separately approved milestones.
