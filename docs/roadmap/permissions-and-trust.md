# Permissions and trust

**Status:** Exploring  
**Roadmap horizon:** Post-V1  
**Product area:** Trust and safety  
**Implementation approval:** Not granted by this document

## Outcome

Make agent, Herdr, macOS, and companion permission rules legible and editable through their actual owners.

## Why this exists

The design presents scoped rules, launch posture, ownership, usage, revocation, and links back to originating approvals.

## First useful slice

- Define a typed read-only permission inventory with owner and scope.
- Group rules by workspace and global scope.
- Show age, source, and whether Bessie can mutate each rule.
- Open the actual owner configuration.

## Possible later scope

- Default launch posture.
- Rule-use counts and audit links.
- Typed revoke or edit actions.
- Session-rule notices linked to approvals.

## Sources of truth and dependencies

Upstream agent/Herdr permission contracts; Bessie cannot reconstruct this safely from terminal output.

Bessie must preserve Herdr as the authority for sessions, panes, processes, agents, and durable session state. Any additional owner—filesystem, Git, agent integration, companion plugin, or provider—must be named explicitly in the eventual implementation plan.

## Principal risks

- Observed rules can be mistaken for enforced policy.
- Revocation may break active agent work and must name the actual owner.

## Open questions

- Is a read-only inventory valuable before mutation exists?
- Which ownership categories must be standardized upstream?

## Graduation criteria

Before this idea becomes **Proposed**, validate the first useful slice against the current Herdr contracts, identify local and remote behavior, define failure and empty states, and split any high-risk side effects into separately approved milestones.
