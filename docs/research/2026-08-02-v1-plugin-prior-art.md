# Community Herdr plugin prior art for remaining Bessie V1 features

**Date:** 2026-08-02
**Status:** Research only; product implications, not an implementation plan
**Decision frame:** Map community Herdr plugins to the remaining approved Bessie V1 surfaces without importing plugin architecture or expanding scope.

## Bottom line

The plugin ecosystem validates the jobs Bessie has chosen, but usually not the implementation shape Bessie should use.

- **Strong prior art:** file/diff supervision, attention-first agent lists, menu-bar/push awareness, entity-aware navigation, declarative workspace materialization, and remote connection lifecycle.
- **Weak prior art:** production-quality native macOS window behavior and a coherent native app theme system.
- **Critical boundary:** plugins are terminal programs, web bridges, relays, or external processes. Bessie is a native graphical Herdr client. It should absorb their interaction lessons while continuing to use Herdr's public state/control surfaces, real `GhosttyTerminal` terminal views, native SwiftUI/AppKit UI, and Bessie-owned presentation preferences only.
- **No plugin is a product dependency.** In particular, Projects are already native in Bessie. `herdr-plus` is prior art for recipe ergonomics only.

The Herdr marketplace is an automatic, unreviewed index of repositories carrying the GitHub topic `herdr-plugin`. Popularity is a demand signal, not a security or quality endorsement.

## Feature map

### 1. Production UI/UX cleanup

**Relevant plugins**

- [AltanS/collie](https://github.com/AltanS/collie) has the broadest end-user polish: explicit loading/offline states, reconnect behavior, diagnostics, deep links, settings, light/dark appearance, push preferences, and mobile-first interaction design.
- [dcolinmorgan/herdr-remote (Herdi)](https://github.com/dcolinmorgan/herdr-remote) is direct native-macOS prior art for a menu-bar utility and ambient agent status.
- [smarzban/herdr-file-viewer](https://github.com/smarzban/herdr-file-viewer), [persiyanov/herdr-reviewr](https://github.com/persiyanov/herdr-reviewr), and [thanhdat77/herdr-navigator](https://github.com/thanhdat77/herdr-navigator) show careful empty/error states, keyboard discoverability, stale-result handling, and bounded degradation, but only inside TUIs.

**Steal / learn**

- Make degraded and disconnected states actionable rather than blank: name the failed connection or capability, retain unaffected content, and provide a diagnostic route.
- Preserve user work across recoverable failures. Reviewr keeps unsent comments after a failed send and flags stale comments instead of dropping them; file-viewer discards stale asynchronous renders rather than replacing a newer selection.
- Use progressive disclosure for uncommon actions. Collie uses contextual/long-press pane management; Navigator keeps source filters and advanced actions available without crowding the default list.
- Treat lifecycle, notification policy, stale builds, and reconnect behavior as product UI, not engineering-only states.

**Ignore / do not copy**

- Do not copy terminal-drawn chrome, web/PWA layout conventions, popup-pane lifecycle, or keyboard routing workarounds into the native app.
- Do not imitate or parse a terminal into an alternate UI. Collie's text mirror and prompt-pattern controls solve a phone-web constraint; Bessie's visible terminals remain real libghostty surfaces.
- Do not infer that plugin polish covers macOS conventions. None of these sources meaningfully validates Bessie's required `⌘Q`, app menu, title-bar double-click, first-responder, full-screen, VoiceOver, or standard window behavior.

**Bessie product boundary**

This is mostly greenfield native-app work. Use the plugins as evidence for resilient states and interaction economy, not as UI architecture. Bessie owns app/window lifecycle and presentation; quitting Bessie must release its controllers without stopping Herdr or pane processes.

### 2. Richer Herd dashboard

**Relevant plugins**

- [Collie](https://github.com/AltanS/collie) is the strongest dashboard precedent: agents needing attention float above spaces/workspaces, while working and idle agents collapse into lower-priority sections.
- [Herdi](https://github.com/dcolinmorgan/herdr-remote) adds a global "Needs you" section, workspace drill-down, pane/tab counts, activity timelines, and compact menu-bar/notch summaries.
- [Herdr Navigator](https://github.com/thanhdat77/herdr-navigator) demonstrates dense entity rows with agent state, workspace, cwd, pane/tab/session identifiers, aliases, current/previous markers, and reuse-first navigation.
- [herdr-file-viewer](https://github.com/smarzban/herdr-file-viewer) overlays active-agent status onto worktrees, useful evidence for a restrained workspace/agent context badge.

**Steal / learn**

- Organize by operational priority before topology: "Needs you" first, then ready/done-unseen if Bessie adopts that presentation concept, then working and idle.
- Make every card or row answer three questions quickly: what state is it in, where is it, and what is the safest next action?
- Keep workspace grouping and direct agent navigation available without burying urgent agents inside workspace cards.
- Show connection/degraded state per affected session or host. One unreachable source should not make the whole Herd look offline.
- Use compact metadata that Herdr actually owns: agent label/type, state, workspace/tab/pane, age only when its timestamp source is explicit, and exact open-to-pane routing.

**Ignore / do not copy**

- Do not copy Collie's parsed terminal mirror, transcript adapters, or client-inferred prompt controls into Herd cards.
- Do not infer per-agent file authorship, progress percentages, or completion from Git polling, terminal prose, or snippets.
- Do not turn the dashboard into a second terminal, timeline product, token-spend dashboard, or generic process monitor.
- Do not let client-local seen state masquerade as Herdr truth. If shipped, label and treat it as Bessie presentation state.

**Bessie product boundary**

Herdr snapshot/events remain authoritative for agents, panes, workspaces, and semantic state. Bessie may own filters, sort order, density, and local seen/dismiss presentation. The universal action remains **Open pane**; richer actions appear only where a typed Herdr contract supports them.

### 3. Attention queue

**Relevant plugins**

- [Collie](https://github.com/AltanS/collie) provides the clearest attention hierarchy: "Needs you," "Ready · unseen," grouped lower-priority state, snooze/DND, and a visible state transition after sending input.
- [Herdi](https://github.com/dcolinmorgan/herdr-remote) hoists blocked agents globally and offers output/reply/approval paths from notifications and remote clients.
- [cobanov/herdr-ntfysh](https://github.com/cobanov/herdr-ntfysh) is strong notification-pipeline prior art: actionable-state defaults, per-pane deduplication, persisted debounce state, test/doctor actions, secret redaction, and notifier failure isolation.
- [herdr-reviewr](https://github.com/persiyanov/herdr-reviewr) contributes stale-comment and failed-send behavior relevant to preserving attention work in progress.

**Steal / learn**

- Separate authoritative state from queue presentation. Herdr says an agent is blocked/done; Bessie may say an item is seen, snoozed, dismissed, or locally resolved.
- Prioritize exact location and fallback action: agent, workspace/tab/pane, age if known, and **Open pane**.
- Deduplicate by pane and event kind, retract or stop repeating an item when the underlying state clears, and avoid stale bursts after reconnect.
- For any send-like action, distinguish "Herdr accepted input" from "the target actually changed state." Collie's two-stage feedback is the right trust model.
- Preserve drafts and queue state on transient failure; resnapshot before retrying an ambiguous mutation.

**Ignore / do not copy**

- Do not copy screen-text parsing, numbered-option detection, one-tap approvals, or reply buttons as proof that a generic graphical approval contract exists.
- Do not treat `working → idle` as durable completion without validating the exact Herdr baseline and product semantics.
- Do not persist a shadow event history or claim cross-client resolution consistency for Bessie-local state.
- Do not let notification or queue failures affect Herdr execution.

**Bessie product boundary**

V1 can provide Open/Resolved/All presentation, seen/dismiss/snooze, keyboard routing, and zoom-to-real-terminal around authoritative Herdr state. Without a typed upstream action payload, the safe action is **Open pane**, not guessed Allow/Deny/Approve controls.

### 4. Follow files

**Relevant plugins**

- [smarzban/herdr-file-viewer](https://github.com/smarzban/herdr-file-viewer) is the strongest read-only repository-view precedent: Git status in the tree, changed-file navigation, automatic diff/source/rendered mode, baseline switching, `path:line` handoff, and hardened untrusted-repository reads.
- [persiyanov/herdr-reviewr](https://github.com/persiyanov/herdr-reviewr) adds changed-files versus all-files views, last-turn diffs, hunk navigation, stale annotations, and explicit acknowledgment that polling conflates multiple agents and human edits.
- [dwarvesf/herdr-quicklook](https://github.com/dwarvesf/herdr-quicklook) is the clearest file-reference precedent: resolve visible `path:line` tokens against the producing pane's cwd/worktree, preserve the line across preview/viewer/editor handoffs, and surface agent-turn suggestions without stealing focus.

**Steal / learn**

- Keep the surface diff-first with a named baseline, a recency-ordered touched/changed list, Follow on/off, and Pin to stop selection thrash.
- Use a typed internal target: Herdr workspace/pane identity, canonical local root, root-relative path, and optional source line/range.
- Treat file detection and path resolution separately. Cheap candidate observation may trigger a refresh; canonical root containment and file existence decide what can open.
- Drop stale preview results with a generation/sequence check when the selected path changes during rendering.
- Prefer passive cues over focus stealing. Quick Look recommends notification rather than auto-preview on completion.
- Adopt file-viewer's hostile-content posture: root containment, bounded reads/diffs, timeouts, hardened Git calls, no repo-controlled diff/textconv/hooks, and no untrusted terminal control sequences.

**Ignore / do not copy**

- Do not copy Reviewr's polling-based "last turn" as authoritative attribution. Its own README documents missed turns and conflation across agents and human edits.
- Do not scrape arbitrary scrollback or use fuzzy bare filenames to claim the current edit target.
- Do not drive another UI by sending its keybindings. Quick Look documents this as a brittle workaround for file-viewer's missing goto-file API.
- Do not add PR review, annotations, staging, commit, worktrees, rich media preview, or external-renderer breadth to the V1 Follow slice.

**Bessie product boundary**

For V1, Follow is a local, read-only, transient projection over a resolvable workspace root, filesystem observation, and Git status/diff. Wording must remain "workspace/session changes observed while this agent was working" unless Herdr or an integration supplies authoritative path events. Remote Follow stays unavailable until a versioned file transport exists.

### 5. In-app file viewer/editor

**Relevant plugins**

- [herdr-file-viewer](https://github.com/smarzban/herdr-file-viewer) supplies the best tree/content model, Git-aware default views, fuzzy open, in-file navigation, binary/large-file handling, and external editor/OS handoff.
- [herdr-reviewr](https://github.com/persiyanov/herdr-reviewr) demonstrates shared navigation across Changes, All files, and PR projections, plus stale-state handling and bounded file budgets.
- [herdr-quicklook](https://github.com/dwarvesf/herdr-quicklook) demonstrates a useful escalation ladder: lightweight preview → persistent viewer at the same path/line → external editor.

**Steal / learn**

- Share canonical root/path identity with Follow files so selecting a touched file and browsing the tree land on the same file.
- Put Git status in the tree, make changed text default to diff, and preserve an explicit source path/line when switching views.
- Keep rendered rows distinct from source rows. Rendered Markdown and diffs must not pretend to have source-line coordinates without a valid mapping.
- Bound file size, line count, diff output, and asynchronous work; identify binary, missing, permission-denied, unsupported encoding, and stale-on-disk states explicitly.
- Preserve a lightweight handoff to the system editor/Finder and a fast route back to the exact Herdr pane.

**Ignore / do not copy**

- None of the inspected plugins implements native in-app file editing. File-viewer and Reviewr are read-only; Quick Look launches an external editor. Do not present them as precedent for safe writes.
- Do not import terminal renderers (`bat`, `delta`, `glow`, `less`), TUI navigation, arbitrary archive/database/media preview, PR review, or plugin-pane management into V1.
- Do not let a workspace-scoped file surface become a machine-wide Finder or full IDE.

**Bessie product boundary**

Bessie may browse and read real local files under the selected workspace root and make one explicit single-file save. The native editor needs its own write contract: dirty state, encoding/newline preservation, atomic replacement where appropriate, symlink/root checks, external-change detection, conflict presentation, and failure recovery. No autosave-only behavior, language server, multi-file refactor, Git write, or shell-scraped remote bridge.

### 6. Menu-bar Herd + Mac push

**Relevant plugins**

- [Herdi](https://github.com/dcolinmorgan/herdr-remote) is direct prior art: a macOS 14+ menu-bar app, compact agent list, ambient notch panel, blocked/done notifications, workspace drill-down, and exact output/reply entry points.
- [herdr-ntfysh](https://github.com/cobanov/herdr-ntfysh) provides the cleanest notification correctness model: blocked/done defaults, per-pane dedup window, defensive event parsing, diagnostics, secret redaction, and fail-open event hooks.
- [Collie](https://github.com/AltanS/collie) adds batched blocked notifications, Web Push policy, snooze/DND, and deep-linked mobile attention.

**Steal / learn**

- Keep the menu-bar surface glanceable: connection health, blocked count, at most a handful of urgent agents, Open pane/Open Bessie, Quiet, Settings, and Quit.
- Use the same urgency ordering and identity as the in-window Herd/attention queue.
- Deduplicate by pane and transition, collapse stale offline notifications, and stop alerting when the underlying blocked state clears.
- Build a visible test/repair path for notification authorization and policy rather than silently failing.
- Deep-link every row/banner to the exact Herdr pane, including cold-start revalidation of saved identifiers.

**Ignore / do not copy**

- Do not build a phone PWA, Telegram bot, Cloudflare relay, ntfy dependency, notch overlay, or remote web shell as part of this slice.
- Do not expose prompt text or terminal snippets in banners by default; they may contain secrets.
- Do not add generic approve/reply controls without typed actions and stale-state protection.
- Do not imply that quitting the menu-bar app stops Herdr.

**Bessie product boundary**

This is native macOS ambient supervision for Bessie's active connection, not a second attention system or remote product. macOS owns authorization/delivery; Bessie owns quiet policy and deep links; Herdr owns agent/pane state. Menu-bar-only lifecycle must preserve Herdr and release Bessie's terminal controllers cleanly.

### 7. Layout presets/navigation

**Relevant plugins**

- [yuk1ty/herdr-spreader](https://github.com/yuk1ty/herdr-spreader) is the strongest layout execution precedent: declarative workspace/tab/pane hierarchy, split ratios, deterministic focus, strict parsing, dry-run output, and a pure plan executed through public Herdr CLI operations using returned IDs.
- [Herdr Navigator](https://github.com/thanhdat77/herdr-navigator) provides cross-workspace jump, reuse-first opening, current/previous Jump Back, source filters, direct agent focus, and persistent side-navigation patterns.
- [cloudmanic/herdr-plus](https://github.com/cloudmanic/herdr-plus) provides project grouping, ordered tabs/panes, startup commands, and one shared path for interactive versus named project opening.
- [JanTvrdik/herdr-command-palette](https://github.com/JanTvrdik/herdr-command-palette) contributes invocation-context preservation, but is more relevant to feature 8.

**Steal / learn**

- Apply layout through ordinary Herdr topology/resize operations and reconcile from a fresh snapshot; use only IDs returned by Herdr.
- Make focus outcome deterministic and preserve current focus when a preset has no explicit target.
- Preview or clearly name the operation before any recipe-like materialization. Spreader's pure plan/dry-run separation is good architecture evidence.
- Add fast direct pane selection, pane-number hints, and current/previous navigation without requiring users to understand IDs.
- Reuse an existing live entity before creating anything new.

**Ignore / do not copy**

- Do not bring Spreader's YAML DSL, arbitrary startup-command orchestration, worktree automation, or multi-workspace materializer into the simple V1 **Even** and **Main + stack** layout-presets slice.
- Do not persist private split ratios or a shadow layout model after applying a preset.
- Do not depend on Herdr Plus. Its worktree layouts and Quick Actions are separate scope.
- Do not copy TUI overlays or shell command construction where Bessie has typed Herdr calls.

**Bessie product boundary**

Simple layout presets mutate the current Herdr-owned tab geometry and then resnapshot. Bessie owns only preset names and presentation. **Projects already exist natively in Bessie** as Bessie-owned versioned launch recipes that materialize ordinary Herdr objects; `herdr-plus` and Spreader are prior art, not storage, runtime, or dependencies.

### 8. Entity-aware command palette

**Relevant plugins**

- [Herdr Navigator](https://github.com/thanhdat77/herdr-navigator) is the strongest prior art: one fuzzy index across agents, workspaces, projects, sessions, remotes, directories, and actions, with typed rows and entity-specific dispatch.
- [herdr-command-palette](https://github.com/JanTvrdik/herdr-command-palette) dynamically lists every installed plugin action, preserves the originating cwd, hides its recursive open action, and invokes the selected stable action ID.
- [herdr-plus](https://github.com/cloudmanic/herdr-plus) demonstrates grouped project results and context-aware global/repo-local Quick Actions.

**Steal / learn**

- Keep results typed. A row should identify whether it is an agent, pane, tab, workspace, attention item, command, or plugin action; show state/location and exactly what Enter will do.
- Rank urgent live entities and exact command matches without collapsing navigation and execution into an undifferentiated list.
- Preserve invocation context: active connection/session, workspace, tab, pane, cwd, and selection when supported.
- Populate plugin actions from Herdr metadata rather than hard-coding them; suppress unavailable, recursive, or context-inapplicable actions.
- Reuse/focus existing entities before offering creation.

**Ignore / do not copy**

- Do not use `fzf`, a temporary overlay pane, shell scripts, or local parsing of external plugin config as Bessie's palette architecture.
- Do not expose every plugin action without grouping, applicability, descriptions, and destructive-action treatment.
- Do not import Navigator's directories, zoxide, remotes, Herdr Plus templates, or generic integration command protocol into the first V1 slice.
- Do not let context-safe typed actions bypass the same confirmations used elsewhere.

**Bessie product boundary**

The first slice indexes Bessie's current Herdr projection: agents, panes, tabs, workspaces, attention items, and commands. Herdr owns entity identity and plugin action metadata; Bessie owns ranking, query state, and native presentation. Broader file/plan/worktree search is not implied.

### 9. Themes

**Relevant plugins**

- [Collie](https://github.com/AltanS/collie) has System/Light/Dark application appearance, but its light terminal mirror uses an approximation because emitted ANSI colors are not re-themed by Herdr.
- [Herdr Navigator](https://github.com/thanhdat77/herdr-navigator) reads a Herdr theme name, maps supported names to its own palette, applies custom overrides, and explicitly calls this "practical theme inheritance, not native palette access."
- [herdr-reviewr](https://github.com/persiyanov/herdr-reviewr) offers named TUI palettes and a terminal-following palette.

**Steal / learn**

- Offer a few coherent appearance choices, including System-following behavior, rather than raw token editing.
- Treat contrast, focus, agent state, diff colors, density, pane borders/gaps, and Reduce Motion as one tested system.
- Keep app appearance and terminal appearance conceptually separate. A user-selected Bessie theme must not silently rewrite bytes or ANSI semantics from the real terminal.
- Make ownership explicit when a setting belongs to Bessie versus Herdr or the terminal.

**Ignore / do not copy**

- Do not copy local mappings from Herdr theme names, ANSI inversion, terminal-mirror recoloring, or ad hoc plugin palettes as Bessie's design system.
- Do not promise exact Herdr theme parity from a plugin workaround; Navigator documents that plugin v1 does not expose the active palette directly.
- Do not turn Settings into arbitrary color/shape/elevation token editing or allow combinations the product cannot test.

**Bessie product boundary**

Prior art is weak. Bessie's source of truth is its retained native design system, adapted into a small set of Bessie-owned theme/density/chrome preferences. Every visible terminal remains a real `GhosttyTerminal`; terminal palette behavior follows the supported terminal/Herdr configuration rather than a Bessie-drawn imitation.

### 10. Session/connection manager, including remote

**Relevant plugins**

- [nikok6/herdr-mirror](https://github.com/nikok6/herdr-mirror) is the strongest remote lifecycle prior art: named SSH/container hosts, compatibility status, reconnect behavior, independent long-lived pane streams, watch-versus-control, explicit control release, dormant-versus-unreachable states, and distinct close/restore/pause/resume/teardown semantics.
- [Collie](https://github.com/AltanS/collie) demonstrates multiple named local Herdr sessions behind one selector, per-session reachability, and the correct `session.snapshot` → `events.subscribe` invalidation → resnapshot model.
- [Herdi](https://github.com/dcolinmorgan/herdr-remote) demonstrates remote relay authentication, secret-file permissions, WebSocket clients, audit logging, and tunnel-based access.
- [Herdr Navigator](https://github.com/thanhdat77/herdr-navigator) demonstrates unified session/server/remote discovery and dispatch, but not the underlying connection safety model.

**Steal / learn**

- Present a connection as a named endpoint with explicit local/remote type, session, health, Herdr/protocol compatibility, capabilities, latency/reconnect state, and copyable attach command.
- Distinguish dormant, unreachable, authentication failed, incompatible, reconnecting, observing, controlling, and controller-conflict states.
- Keep the control plane separate from one terminal stream/controller per visible pane. A busy pane must not starve the rest of the session projection.
- Make **detach**, **release control**, **close remote pane/workspace**, and **stop/forget connection** separate actions with unambiguous consequences.
- Default to preserving remote work when Bessie disconnects or quits. Require explicit confirmation before takeover or remote termination.
- Revalidate all persisted IDs and capabilities against a fresh snapshot after attach/reconnect.

**Ignore / do not copy**

- Do not mirror remote objects into synthetic local Herdr workspaces as Bessie's model. That is herdr-mirror's plugin technique; Bessie should present the connected Herdr session directly.
- Do not create a Bessie relay service, custom remote port, Cloudflare tunnel, web dashboard, or private-protocol dependency.
- Do not silently escalate from observe to control, infer mouse mode from foreground process, or inherit destructive "closing the mirror closes the remote" defaults.
- Do not store SSH passwords or make insecure TLS/host-key bypass an easy path.
- Do not claim remote file browsing/editing merely because terminal control works; file transport is a separate capability.

**Bessie product boundary**

Bessie is an attach/detach client, never the owner of Herdr lifecycle or remote live state. Local discovery and health should use public Herdr contracts. Remote attach should follow the approved SSH architecture and must provide safe forwarding for the required public control/event and terminal-session surfaces; it must not use Herdr's private bincode protocol. Capability gaps remain visible and can degrade to observe/read-only rather than being papered over.

## Deferred item

**Search the Herd:** no strong prior art / deferred. File finders, Navigator, and command palettes search their own bounded domains; none establishes a trustworthy, versioned cross-pane scrollback index with exact jump semantics and an acceptable secret-retention model. Do not pull search back into V1 through this research.

## Cross-cutting rules to carry forward

1. **Herdr owns live session facts.** Use `session.snapshot` as the projection source, events as invalidation hints, and resnapshot on reconnect or ambiguity.
2. **The filesystem and Git own file facts.** They do not prove agent authorship. Repository reads must assume hostile content and enforce root, subprocess, escape-sequence, and resource boundaries.
3. **Bessie owns presentation only where appropriate.** Filters, sorting, pinned selection, seen/dismiss/snooze, recents, quiet policy, and appearance may be Bessie state if labeled and disposable.
4. **Every terminal remains real.** Plugin TUIs and web mirrors are interaction evidence, never alternatives to `GhosttyTerminal`.
5. **Acknowledge is not outcome.** After a mutation, reconcile from Herdr state. Preserve drafts and avoid blind retries after ambiguous connection loss.
6. **No inferred approvals.** Blocked state guarantees Open pane, not a safe graphical answer.
7. **Disconnect is not terminate.** Bessie quit, detach, controller release, remote object close, and Herdr server stop must stay distinct.

## Sources inspected

Primary discovery sources:

- [Herdr plugin marketplace](https://herdr.dev/plugins/) — live page inspected 2026-08-02; automatic and unreviewed.
- [GitHub topic: `herdr-plugin`](https://github.com/topics/herdr-plugin) — inspected 2026-08-02.
- [Herdr plugin documentation](https://herdr.dev/docs/plugins/) — host/API and trust boundary.

Repository source snapshot (README plus `ARCHITECTURE.md`, security, and API notes where present):

| Repository | Revision inspected | Principal evidence |
| --- | --- | --- |
| [smarzban/herdr-file-viewer](https://github.com/smarzban/herdr-file-viewer) | [`fa1946a`](https://github.com/smarzban/herdr-file-viewer/commit/fa1946a04dd58ba9b3db2eda0125b6055fb604da) | [README](https://github.com/smarzban/herdr-file-viewer/blob/fa1946a04dd58ba9b3db2eda0125b6055fb604da/README.md), [architecture](https://github.com/smarzban/herdr-file-viewer/blob/fa1946a04dd58ba9b3db2eda0125b6055fb604da/ARCHITECTURE.md), [security](https://github.com/smarzban/herdr-file-viewer/blob/fa1946a04dd58ba9b3db2eda0125b6055fb604da/SECURITY.md) |
| [persiyanov/herdr-reviewr](https://github.com/persiyanov/herdr-reviewr) | [`42ccaaa`](https://github.com/persiyanov/herdr-reviewr/commit/42ccaaa72176937181c82a91484f97466fb5ed59) | [README](https://github.com/persiyanov/herdr-reviewr/blob/42ccaaa72176937181c82a91484f97466fb5ed59/README.md), [Herdr API notes](https://github.com/persiyanov/herdr-reviewr/blob/42ccaaa72176937181c82a91484f97466fb5ed59/docs/herdr-api-notes.md), [security](https://github.com/persiyanov/herdr-reviewr/blob/42ccaaa72176937181c82a91484f97466fb5ed59/SECURITY.md) |
| [dwarvesf/herdr-quicklook](https://github.com/dwarvesf/herdr-quicklook) | [`0cfc08b`](https://github.com/dwarvesf/herdr-quicklook/commit/0cfc08bc375c2f62789e3b8e2c207a824ac12e17) | [README](https://github.com/dwarvesf/herdr-quicklook/blob/0cfc08bc375c2f62789e3b8e2c207a824ac12e17/README.md) |
| [dcolinmorgan/herdr-remote](https://github.com/dcolinmorgan/herdr-remote) | [`975be27`](https://github.com/dcolinmorgan/herdr-remote/commit/975be271a6dee550f6a6850cf0512a39964f7f49) | [README](https://github.com/dcolinmorgan/herdr-remote/blob/975be271a6dee550f6a6850cf0512a39964f7f49/README.md) |
| [AltanS/collie](https://github.com/AltanS/collie) | [`0cbf583`](https://github.com/AltanS/collie/commit/0cbf5834f4d9a97d1fb5032bba1b69ca23c77d60) | [README](https://github.com/AltanS/collie/blob/0cbf5834f4d9a97d1fb5032bba1b69ca23c77d60/README.md), [architecture](https://github.com/AltanS/collie/blob/0cbf5834f4d9a97d1fb5032bba1b69ca23c77d60/ARCHITECTURE.md), [Herdr API notes](https://github.com/AltanS/collie/blob/0cbf5834f4d9a97d1fb5032bba1b69ca23c77d60/HERDR_API.md) |
| [nikok6/herdr-mirror](https://github.com/nikok6/herdr-mirror) | [`a569217`](https://github.com/nikok6/herdr-mirror/commit/a569217ae59166470aa6a1fc0bbca2dea196af64) | [README](https://github.com/nikok6/herdr-mirror/blob/a569217ae59166470aa6a1fc0bbca2dea196af64/README.md) |
| [thanhdat77/herdr-navigator](https://github.com/thanhdat77/herdr-navigator) | [`745019e`](https://github.com/thanhdat77/herdr-navigator/commit/745019ebdc38f9752629c93d2ca56d1ce638cf98) | [README](https://github.com/thanhdat77/herdr-navigator/blob/745019ebdc38f9752629c93d2ca56d1ce638cf98/README.md), [architecture](https://github.com/thanhdat77/herdr-navigator/blob/745019ebdc38f9752629c93d2ca56d1ce638cf98/docs/architecture.md), [security](https://github.com/thanhdat77/herdr-navigator/blob/745019ebdc38f9752629c93d2ca56d1ce638cf98/SECURITY.md) |
| [JanTvrdik/herdr-command-palette](https://github.com/JanTvrdik/herdr-command-palette) | [`eab9400`](https://github.com/JanTvrdik/herdr-command-palette/commit/eab940018c2135ac23718efa11e23e9dddcd2a75) | [README](https://github.com/JanTvrdik/herdr-command-palette/blob/eab940018c2135ac23718efa11e23e9dddcd2a75/README.md) |
| [yuk1ty/herdr-spreader](https://github.com/yuk1ty/herdr-spreader) | [`5f76bc9`](https://github.com/yuk1ty/herdr-spreader/commit/5f76bc9eab02296e88d2707fa4c1cf0d8eabdb80) | [README](https://github.com/yuk1ty/herdr-spreader/blob/5f76bc9eab02296e88d2707fa4c1cf0d8eabdb80/README.md), [architecture](https://github.com/yuk1ty/herdr-spreader/blob/5f76bc9eab02296e88d2707fa4c1cf0d8eabdb80/ARCHITECTURE.md) |
| [cloudmanic/herdr-plus](https://github.com/cloudmanic/herdr-plus) | [`a9aca9d`](https://github.com/cloudmanic/herdr-plus/commit/a9aca9da3ca6d7406f3d878a1df1c1b9775e2723) | [README](https://github.com/cloudmanic/herdr-plus/blob/a9aca9da3ca6d7406f3d878a1df1c1b9775e2723/README.md) |
| [cobanov/herdr-ntfysh](https://github.com/cobanov/herdr-ntfysh) | [`f074624`](https://github.com/cobanov/herdr-ntfysh/commit/f07462439b7dde0ac08ffe90d30661520037d561) | [README](https://github.com/cobanov/herdr-ntfysh/blob/f07462439b7dde0ac08ffe90d30661520037d561/README.md), [architecture](https://github.com/cobanov/herdr-ntfysh/blob/f07462439b7dde0ac08ffe90d30661520037d561/ARCHITECTURE.md) |

Bessie scope/boundary sources used for synthesis:

- [`docs/plans/2026-08-01-bessie-v1.md`](../plans/2026-08-01-bessie-v1.md)
- [`docs/roadmap/`](../roadmap/README.md), especially the ten corresponding component plans
- Workstream `V1-SCOPE.md`, `HERDR-CAPABILITY-MAP.md`, `WORKSPACE-INTERACTION-SPEC.md`, `TERMINAL-BEHAVIOR.md`, `ARCHITECTURE.md`, and `FEASIBILITY.md`

This document records interaction and architecture lessons only. It does not approve new dependencies, plugin integrations, scope additions, or implementation work.
