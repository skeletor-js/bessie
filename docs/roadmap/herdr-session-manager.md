# Herdr session and connection manager

**Status:** Approved
**Roadmap horizon:** V1 (unified Herd labels + settings/onboarding + SSH harden)
**Product area:** Sessions and connections
**Implementation approval:** Granted (Occam-locked 2026-08-02)

## Outcome

Manage local and remote Herdr attachment deliberately while keeping Herdr as the runtime and source of truth.

## Why this exists

The exploration contains a complete session manager with health, compatibility, attachment state, clients, and degraded modes.

## First useful slice

- List named local sessions with runtime facts and topology counts.
- Attach, detach, observe, and open in Herdr where public contracts permit.
- Show capability compatibility and degraded read-only behavior.
- Provide copyable attach commands.

## Possible later scope

- Concurrent clients.
- Multiple runtime endpoints.
- SSH-host connections and reconnect behavior.
- Connection creation, editing, and diagnostics.

## Sources of truth and dependencies

Herdr public discovery and capability contracts; graphical remote sessions need safe forwarding for both required sockets.

Bessie must preserve Herdr as the authority for sessions, panes, processes, agents, and durable session state. Any additional owner—filesystem, Git, agent integration, companion plugin, or provider—must be named explicitly in the eventual implementation plan.

## Principal risks

- Connection settings can affect security and must not store SSH passwords.
- Switching connections must release terminal controllers cleanly without stopping remote work.

## Open questions

- Which portions of the current uncommitted connection work are product-ready?
- Does Herdr need a versioned headless bridge before remote support can ship?

## Graduation criteria

Before this idea becomes **Proposed**, validate the first useful slice against the current Herdr contracts, identify local and remote behavior, define failure and empty states, and split any high-risk side effects into separately approved milestones.
