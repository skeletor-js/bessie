# Bessie product roadmap

This folder holds Bessie's product roadmap. The bundled-runtime release train and Native Bessie Projects are now part of real V1; the remaining items are directional candidates, not promises or an implementation backlog.

## Governing boundary

Every roadmap item must strengthen Bessie as the graphical client for Herdr:

- Herdr remains the engine and authority for sessions, workspaces, tabs, panes, terminals, processes, agents, and durable session state.
- Every terminal remains a real libghostty surface attached to a Herdr-owned pane.
- Bessie may own ordinary desktop presentation state and operate on workspace files, but it must not invent a second session model or replace Herdr with a generic IDE shell.
- Features that can act through Herdr should do so. Filesystem or Git behavior must name its actual owner and remain observable.
- Local-first plans must describe what degrades or remains unavailable for remote Herdr sessions.

## Status vocabulary

- **Exploring** — the problem and boundary are being shaped.
- **Proposed** — coherent enough to estimate and sequence, but not approved for implementation.
- **Approved** — Jordan has explicitly approved implementation.
- **In progress** — implementation has started.
- **Shipped** — verified in a released build.
- **Deferred** — intentionally parked, with the reason recorded.
- **Superseded** — replaced by a materially different product decision; retained only for decision history.

## V1 implementation sequence

The current `0.1.0-rc.3` candidate is the foundation preview. Real V1 adds, in order:

1. **Bundled Herdr runtime + onboarding + Trouble** — one release train that makes Bessie self-contained, understandable, and recoverable.
2. **Native Bessie Projects** — reusable graphical launch recipes that materialize ordinary Herdr state.
3. **Integrated clean-machine V1 hardening** — signing, notarization, installation, relaunch, real terminal, Project, process-survival, ordinary-Herdr attach, and controlled-failure verification.

Everything else remains behind V1 unless Jordan explicitly changes the release contract.

## Plans

| Plan | Status | Product outcome |
| --- | --- | --- |
| [Follow files and agent changes](follow-files-and-agent-changes.md) | Proposed | While an agent works, auto-preview the file it is touching, show the diff, and flip through paths touched in that stretch. |
| [Workspace files, review, and lightweight editing](workspace-files-review-and-editing.md) | Proposed | Broader program: workspace tree, full diff review, and bounded edits. Follow files is the preferred first product slice. |
| [Menu-bar Herd and Mac push](menu-bar-herd.md) | Proposed | Keep the herd visible and actionable from the macOS menu bar with polished push routing; no phone PWA. |
| [In-app browser (URL preview)](in-app-browser.md) | Proposed | Open localhost and docs in a human WKWebView-style preview beside real terminals—not a CDP agent browser. |
| [Managed Herdr runtime and setup](managed-herdr-runtime-and-setup.md) | In progress | Download Bessie and reach a working Herdr terminal using the compatible runtime included in the signed app. |
| [Native Bessie Projects](native-bessie-projects.md) | In progress | Open a reusable project recipe as ordinary Herdr workspaces, tabs, panes, and shell commands without creating shadow runtime state. |
| [Richer Herd dashboard](richer-herd-dashboard.md) | Exploring | Make the Herd the fastest place to understand every agent and take the next safe action. |
| [Agent detail and prompt composer](agent-detail-and-prompt-composer.md) | Exploring | Turn Agent detail into the primary place to watch, understand, and steer one agent without replacing its real terminal. |
| [Attention queue and resolution](attention-queue-and-resolution.md) | Exploring | Make attention items triageable and resolvable while preserving the real terminal as the universal fallback. |
| [Trouble and diagnostics](trouble-and-diagnostics.md) | Approved | Give users one trustworthy place to understand connection, runtime, controller, and pane failures. |
| [Onboarding and complete zero states](onboarding-and-zero-states.md) | Approved | Help a new or disconnected user reach one working Herdr terminal without understanding Bessie's architecture first. |
| [New Agent launch flow](new-agent-launch-flow.md) | Exploring | Make agent launch understandable, configurable, and predictable before Bessie creates panes or starts processes. |
| [Zen mode](zen-mode.md) | Exploring | Offer a nearly chrome-free real terminal while preserving awareness of the rest of the herd. |
| [Richer workspace overview](workspace-overview.md) | Exploring | Make workspaces legible as live Herdr environments rather than only names and topology counts. |
| [Layout presets and workspace navigation](layout-presets-and-navigation.md) | Exploring | Make common pane arrangements and cross-workspace movement faster without introducing a shadow layout model. |
| [Herdr session and connection manager](herdr-session-manager.md) | Exploring | Manage local and remote Herdr attachment deliberately while keeping Herdr as the runtime and source of truth. |
| [Workspace recipes](workspace-recipes.md) | Superseded | Replaced by Native Bessie Projects; retained only for decision history. |
| [Worktrees and branches](worktrees-and-branches.md) | Deferred | Parked: not a current user need; do not sequence ahead of Follow files, menu bar, or in-app browser. |
| [Entity-aware command palette](entity-aware-command-palette.md) | Exploring | Turn the existing palette into a universal navigator for live Bessie and Herdr entities. |
| [Search the Herd](search-the-herd.md) | Exploring | Find relevant terminal, file, plan, and prompt context across the current Herdr session and jump to the exact source. |
| [Activity timeline](activity-timeline.md) | Exploring | Explain what happened across the herd while the user was away and route them to the next useful action. |
| [Cross-agent Plans](cross-agent-plans.md) | Exploring | See normalized work in progress across agents and detect collisions without creating a generic task-management system. |
| [Broadcast](broadcast.md) | Exploring | Send one reviewed prompt or key operation to a deliberate set of real Herdr panes. |
| [Shepherd](shepherd.md) | Proposed | Invoke-only Shepherd corner chat: OpenAI/xAI BYOK → immediate **new** agent dispatch (default kind + spawn location); Open pane; no status/existing-target/alerts in v1. |
| [Agent integrations and identity](agent-integrations-and-identity.md) | Exploring | Explain how Herdr recognizes each agent, which features are trustworthy, and how to repair degraded integrations. |
| [Herdr plugins](herdr-plugins.md) | Exploring | Show which Herdr plugins are installed and how their capabilities map into Bessie without hosting a second plugin system. |
| [Permissions and trust](permissions-and-trust.md) | Exploring | Make agent, Herdr, macOS, and companion permission rules legible and editable through their actual owners. |
| [Cost and usage](cost-and-usage.md) | Exploring | Show trustworthy agent and provider usage context without pretending Bessie is the billing authority. |
| [Design-system capabilities and customization](design-system-and-customization.md) | Exploring | Expose the useful parts of Bessie's design system as coherent native preferences without turning Settings into a token playground. |
| [Review and land](review-and-land.md) | Exploring | Support a bounded path from reviewed workspace changes to an explicitly owned delivery action, if that proves better than a visible Herdr pane or external Git tool. |

### Post-V1 priority bets (2026-08-01)

After V1 (bundled runtime + Projects) lands, the product-directed post-V1 bets from plugin research and Jordan review are:

1. **Follow files and agent changes** — live touch list + diff-first preview while agents work.
2. **Menu-bar Herd + Mac push** — ambient supervision; no phone PWA (native iOS later).
3. **In-app browser (URL preview)** — human localhost/docs preview, not CDP automation.

Projects remains V1. Worktrees remain deferred. Palette, multi-machine, and in-app digests/approve paths are treated as already covered enough not to lead the next wave.

**Shepherd** ([`shepherd.md`](shepherd.md)) is a **Proposed** post-V1 capability (invoke-only herd dispatch + status). It is not sequenced ahead of the three bets above unless Jordan explicitly reprioritizes.

## How roadmap plans graduate

Before implementation, a plan should have:

1. an explicit user problem and product boundary;
2. independently valuable milestones rather than one giant feature;
3. identified sources of truth and side-effect owners;
4. local and remote behavior;
5. acceptance criteria and failure states;
6. unresolved decisions called out rather than silently guessed;
7. explicit implementation approval.

Approved implementation plans belong in the Bessie repository under `docs/plans/`. Roadmap documents stay here as the product-level record and should name the repository plan when one exists.
