# Agent detail and prompt composer

**Status:** Exploring  
**Roadmap horizon:** Post-V1  
**Product area:** Agent detail  
**Implementation approval:** Not granted by this document

## Outcome

Turn Agent detail into the primary place to watch, understand, and steer one agent without replacing its real terminal.

## Why this exists

The current detail view exposes the terminal and basic input, while the high-fidelity screen adds follow controls, composition modes, history, trace, and provenance.

## First useful slice

- Add follow-output and jump-to-bottom controls.
- Add copy-selection or copy-visible-buffer behavior.
- Add typed interrupt when supported.
- Improve the prompt composer with explicit Send now and Raw keys modes plus local prompt history.

## Possible later scope

- Queued prompts and queue visibility.
- Turn history and trace timeline.
- Identity/state provenance and backend metadata.
- Attachments and links into workspace files or changes.

## Sources of truth and dependencies

Current terminal and pane contracts support the first slice; queue, turn, trace, and provenance features require Herdr, agent, or companion contracts.

Bessie must preserve Herdr as the authority for sessions, panes, processes, agents, and durable session state. Any additional owner—filesystem, Git, agent integration, companion plugin, or provider—must be named explicitly in the eventual implementation plan.

## Principal risks

- A graphical composer must not obscure whether text is a prompt or literal terminal input.
- Trace and attribution must not be inferred from terminal prose.

## Open questions

- Should the work panel be shared with Workspace Files or remain agent-specific?
- What is the minimum typed queue contract worth requesting upstream?

## Graduation criteria

Before this idea becomes **Proposed**, validate the first useful slice against the current Herdr contracts, identify local and remote behavior, define failure and empty states, and split any high-risk side effects into separately approved milestones.
