# Bessie usage tracking feasibility and scope

**Research date:** 2026-08-04  
**Status:** Research only  
**Decision target:** Whether Bessie should add usage tracking, what a credible first release contains, and what can be adapted from CodexBar  
**Recommended scope:** **Tier 2, Local Estimate Mode, limited to Codex and Claude on the current Mac**

## Executive verdict

Adding a polished usage screen to Bessie is not the difficult part. Bessie already has a native product shell, provider marks, settings persistence, testable view-model patterns, and a clear place for another product surface. The difficult part is obtaining, normalizing, and presenting usage data without making false billing or per-agent attribution claims.

The overall feature is **high difficulty**. The recommended first credible slice is **medium-high to high difficulty**, depending on how much hardened CodexBar scanner code can be adapted under its MIT license.

The evidence supports a split verdict:

1. **UI and navigation:** straightforward, roughly 1 to 2 engineer-weeks for a fixture-backed prototype.
2. **Local token and list-price cost estimates:** feasible, but parser, deduplication, cache, pricing, performance, and provenance work make this a substantial feature.
3. **Provider-reported subscription quota windows:** technically possible for Codex and Claude today, but the inspected CodexBar implementations use OAuth-backed endpoints that should not be treated as stable public contracts. Credential ownership, account isolation, rate limits, endpoint drift, and provider terms make this a separate high-risk milestone.
4. **Trustworthy per-agent and per-workspace usage:** not available from Bessie's current Herdr model. It requires a typed Herdr, agent, or companion telemetry contract that carries a stable correlation identifier. Matching by process name, current working directory, time overlap, or terminal title would be guesswork.
5. **Billed cost:** local logs cannot establish it. They can support an API list-rate estimate. Subscription allowances, discounts, credits, cache semantics, provider-side activity, and missing local logs can make that estimate diverge materially from an invoice or quota.

### Recommendation

Ship **Tier 2: Local Estimate Mode** only if the product is willing to name it honestly. The screen should be called something like **Local usage estimates**, not simply **Billing** or **Spend**.

The MVP should:

- support only Codex and Claude;
- read first-party local session artifacts on the current Mac;
- show today, 7-day, and 30-day tracked token totals;
- show input, output, and cache token categories where the source provides them;
- show API list-rate **estimated cost** only when pricing coverage is known;
- show a provider breakdown and a daily trend;
- show source, scope, freshness, scan coverage, and pricing coverage on every result;
- preserve unknown, partial, unavailable, stale, and permission-denied states instead of turning them into zero;
- use a bounded incremental cache and never rescan an unbounded corpus on the main actor;
- remain read-only with respect to provider credentials and local agent artifacts;
- state **This Mac only** and exclude remote Herdr activity unless a remote telemetry owner is added later.

The MVP should not include:

- provider quota meters;
- billed-spend claims;
- per-agent or per-workspace attribution;
- elapsed-time, blocked-time, or tool-call accounting;
- forecast, anomaly or “waste” hints;
- CSV export;
- menu-bar parity;
- browser-cookie extraction;
- automatic budget enforcement.

This recommendation is useful but narrower than the roadmap's existing “first useful slice,” which asks for trusted per-agent/backend ingestion and agent/workspace breakdowns. Tier 2 would **not** graduate `docs/roadmap/cost-and-usage.md` from Exploring to Proposed by itself. It should be tracked as a precursor with an explicit local-estimate scope.

## Direct answers to the research brief

| Question | Answer |
|---|---|
| How difficult is usage tracking in Bessie? | High overall. A UI prototype is easy; production-quality source ingestion, attribution, privacy, caching, and account isolation are the feature. |
| What can be sourced reliably? | Local Codex and Claude logs can reliably prove that certain locally recorded token events occurred. They cannot prove account completeness, provider quota, or billed spend. Provider responses can report quota windows at fetch time, but the inspected consumer OAuth endpoints are not proven stable public APIs. |
| What must be estimated? | Cost from local tokens, forecast, advisory ceiling consumption, and any mapping from a local provider session to a Herdr agent or workspace without a shared ID. The latter should be treated as unavailable, not displayed as an estimate, in the MVP. |
| Is CodexBar reusable? | Its architecture, models, scanner strategies, cache rules, fixture approach, and some code are reusable. Its full provider registry, browser-cookie matrix, account machinery, menu-bar app, CLI, widget, and web scraping are not appropriate Bessie scope. |
| What should the first credible MVP be? | Tier 2 Local Estimate Mode: Codex plus Claude, local machine only, read-only, source-labeled, bounded, and explicit that cost is an API list-rate estimate. |
| How large is it? | Estimated 7 to 10 engineer-weeks for one senior Swift/macOS engineer, about 4,500 to 8,000 production lines and 5,000 to 10,000 test/fixture lines. This includes scanner hardening and UI, but no provider OAuth or Herdr protocol change. |
| What blocks the complete mockup? | No typed per-agent usage contract, no historical Herdr status duration data, no billing authority, no stable cross-provider source contract, and no remote usage path. |

## Research method and limits

### Sources inspected

The analysis used:

- the current Bessie checkout at `/home/hermes/code/bessie`;
- Bessie's canonical roadmap and current Swift implementation;
- retained Bessie product and design sources under `/home/hermes/.hermes/workspace/shared/workstreams/bessie`;
- the dedicated Cost & usage mockup at `source-material/design-system/screens/1x-cost-usage.html`;
- a fresh shallow clone of public CodexBar at `/tmp/CodexBar`;
- CodexBar's provider, scanner, cache, pricing, refresh, app UI, test, and license sources.

The exact CodexBar revision inspected was:

```text
5a7468826e4f92c07f8decc7cfb8cbd3a6f6c194
2026-08-04T15:35:25-07:00
test: keep widget-snapshot container I/O out of test runs (#2656)
```

Repository: `https://github.com/steipete/CodexBar.git`

### Research safety boundary

- No Bessie source, test, documentation, or project file was edited.
- No Bessie build or test command was run because this was a read-only scope investigation.
- The existing Bessie working tree was already heavily modified and remained untouched.
- No real Codex or Claude credential file was read.
- No Keychain, browser-cookie, provider endpoint, or live account probe was performed.
- Provider behavior is inferred from inspected source and tests, not from a live account validation.

### Terminology used in this report

| Term | Meaning |
|---|---|
| Provider-reported | A value returned by the provider or provider-owned tool for the active account, such as a quota-window percentage. It is not automatically a public or stable API. |
| Locally tracked | A value parsed from first-party local session artifacts. It covers only artifacts visible to the scanner. |
| Estimated cost | Token counts multiplied by a pricing table. It is not an invoice, subscription charge, or proof of the provider's metering. |
| Trusted attribution | A provider or agent event carries a stable identifier that can be joined to a Herdr-owned pane, process, agent, workspace, and connection. |
| Inferred attribution | A join based on path, process name, title, or time overlap. It is ambiguous and should not appear as per-agent truth. |
| Unavailable | The source cannot establish a value. This is distinct from zero. |

## Current Bessie state

### The product already defines the right boundary

Bessie's roadmap says the outcome is to “show trustworthy agent and provider usage context without pretending Bessie is the billing authority.” It also requires provider-reported, estimated, and unavailable values to be labeled distinctly. See:

- `docs/roadmap/cost-and-usage.md:1-21`
- `docs/roadmap/cost-and-usage.md:30-49`

That framing should remain binding. The roadmap is **Exploring**, **Post-V1**, and explicitly says implementation approval is not granted by the document.

The design source reinforces the same constraint. The Cost & usage concept labels itself a later concept, says it “would need: per-agent usage from each backend via Herdr or the companion plugin,” and says “Bessie is not a billing source.” The status line says enforcement belongs to Herdr or the agent while Bessie shows and warns:

- `source-material/design-system/Bessie Screens.html:5373-5379`
- `source-material/design-system/Bessie Screens.html:5582-5585`

### Current data models do not contain usage telemetry

The current Herdr snapshot and Bessie projections expose:

- workspaces, tabs, panes, layouts, and agents;
- focused identifiers;
- pane and terminal identifiers;
- process working directories;
- agent kind, title, semantic status, revision, and launch-pending state.

They do not expose token counts, model usage, cost, quota, billing, request count, tool-call count, start/end time, or historical active/blocked/idle durations:

- `Sources/BessieCore/HerdrModels.swift:40-83`
- `Sources/BessieCore/SessionProjection.swift:3-49`
- `Sources/BessieCore/SessionProjection.swift:128-148`
- `Sources/BessieCore/AgentProjection.swift:45-92`

This means the current Herdr protocol is useful for live identity and topology, but not for usage accounting.

### Existing implementation seams are suitable

The following Bessie seams can support a usage feature without introducing a new framework:

| Seam | Current evidence | Appropriate usage role |
|---|---|---|
| Product destination and sidebar | `Sources/BessieApp/ProductSurfaces.swift:5-40` | Add a usage destination or Settings route; preserve existing shell behavior. |
| Window routing | `Sources/BessieApp/BessieWindowCoordinator.swift` | Focus the existing window and route to the usage surface. |
| Provider visual identity | `Sources/BessieApp/BessieDesignSystem.swift:627+`; visual tests at `Tests/BessieAppModelTests/BessieVisualFoundationTests.swift:43-69` | Reuse provider marks for Codex and Claude rows. |
| Settings model | `Sources/BessieApp/BessieSettings.swift:9-95` | Store display preferences such as selected period, cache-token inclusion, and whether local estimates are enabled. |
| Presentation persistence | `Sources/BessieCore/PresentationPersistence.swift:36-98`, `:100-148` | Store presentation choices only, not accounting truth. |
| Pure view-model testing | `Sources/BessieApp/ProjectsViewModel.swift`; `Tests/BessieAppModelTests/ProjectsViewModelTests.swift` | Keep aggregation and surface states deterministic and injectable. |
| Core test target | `Package.swift:23-46` | Test parsers, models, aggregation, and cache behavior without launching the app. |
| App model test target | `Package.swift:44-47` | Test navigation and surface-state projections. |

The current normally visible product destinations are The herd and Projects. Files is developer-gated. Adding the screen is therefore a product navigation decision, not a technical limitation.

### Persistence boundary

`BessiePreferences` and `BessiePresentationStore` are appropriate for:

- selected time range;
- include/exclude cached input in display;
- whether estimated cost is shown;
- whether local scanning is enabled;
- a future user-entered advisory ceiling.

They are not appropriate for:

- an append-only usage ledger;
- provider billing records;
- an authoritative session history;
- raw credentials;
- raw log records.

Derived counters should live in a separately versioned, rebuildable cache. Cache schema and parser version must be explicit. Changing a display preference must not require rescanning the corpus, matching the useful separation in CodexBar's `CodexLocalProjectUsageProjection` (`Sources/CodexBarCore/CodexLocalProjectUsageProjection.swift:3-15`).

### Remote connections are a material scope boundary

Bessie can connect to remote Herdr sessions. A local scanner on the Mac cannot see remote Codex or Claude logs. Showing a single total across all visible herds would therefore silently omit remote work.

Tier 2 must be labeled **This Mac only** and must not aggregate remote sessions into a misleading global total. Supporting remote usage requires one of:

1. a typed Herdr usage surface that works over Bessie's existing local and SSH connection abstraction;
2. a companion on the remote host that emits a typed usage snapshot;
3. an explicitly approved remote read adapter with the same privacy, cache, and versioning guarantees.

The first option best preserves Bessie's ownership model.

## What the design concept asks for versus what exists

The mockup contains more than one feature. It combines local usage, provider quota, live process context, forecasting, advisory controls, export, and anomaly detection.

| Mockup element | Available now in Bessie/Herdr? | Best source | MVP decision |
|---|---|---|---|
| Today/7-day/30-day input and output tokens | No | Local Codex and Claude session artifacts | Include as locally tracked values. |
| Today estimated cost | No | Local tokens multiplied by versioned pricing | Include, always labeled estimated and coverage-aware. |
| Billed cost | No | Provider billing API or invoice | Unavailable; do not imply it. |
| Provider quota/session/weekly meters | No | Provider-reported usage endpoint or typed provider tool | Tier 3 only. Never infer from local cost. |
| Per-agent token and cost rows | No shared identifier | Typed agent/Herdr telemetry | Defer. Do not join by path or time. |
| Per-workspace totals | No shared identifier | Typed Herdr/agent telemetry | Defer. A local project path is not a Herdr workspace ID. |
| Elapsed or running duration | Current state only, no history | Herdr-owned lifecycle timestamps/events | Defer. App-observed time is incomplete while Bessie is closed. |
| Blocked/idle duration | Current state only, no history | Herdr historical state transitions | Defer. |
| Tool-call count | No | Agent telemetry or local log parsing | Defer; semantics vary by backend. |
| “Re-read the same plan output” hint | No | Content-aware tool event history | Defer; privacy-sensitive and easy to misclassify. |
| Daily ceiling | No, but easy to persist as a preference | User-entered advisory value | Defer from MVP to avoid false precision. Never enforce in Bessie. |
| “Hit ceiling in 52 minutes” forecast | No | Complete, stable history plus defined estimator | Defer until coverage and error behavior are proven. |
| CSV export | No | Normalized aggregate model | Technically easy after the model exists, but defer for privacy and schema stability. |
| Current provider and agent state | Partly | Herdr | May be shown as live context, never as historical usage attribution. |

### U01 through U05 assessment

The retained feature-gap inventory classifies the candidates at `FEATURE-GAP-INVENTORY.md:681-685`.

| Gap | Assessment after this research |
|---|---|
| U01, per-agent/backend usage ingestion | Still Upstream/Companion for trusted attribution. Local provider scanning can establish backend-level local activity but not a durable Herdr agent join. |
| U02, cost and token dashboards | Native-now only after a source contract is defined. A provider-level local estimate dashboard is feasible. The complete per-agent/per-workspace dashboard is blocked on U01. |
| U03, user-defined ceiling and forecast | A ceiling preference is easy; a credible forecast is not. Keep both later so the first release does not decorate partial data with false precision. |
| U04, CSV export | Mechanically straightforward once the normalized schema stabilizes. Defer until privacy fields, unknown representation, and provenance columns are settled. |
| U05, waste/anomaly hints | Remains speculative. It requires content-sensitive telemetry and a defensible definition of waste. Do not ship it in the same program as foundational accounting. |

## CodexBar architecture and relevant lessons

### Scale and methodology

Raw line counts were measured with `find ... -name '*.swift'` and `wc -l` at the exact revision above. These are physical Swift lines, including comments and generated-looking source where present. They are evidence of surface area, not an estimate that Bessie must copy it.

| CodexBar scope | Swift files/lines observed |
|---|---:|
| `Sources/CodexBarCore` | 542 files / 153,760 lines |
| `Sources/CodexBar` | 423 files / 87,604 lines |
| `Sources/CodexBarCLI` | 36 files / 13,535 lines |
| `Sources/CodexBarWidget` | 6 files / 2,965 lines |
| Adaptive refresh/replay modules | 14 files / 1,611 lines |
| All production `Sources/**/*.swift` | 259,660 lines |
| All Swift tests under `Tests` and `TestsLinux` | 269,982 lines |

A focused reference set was also measured:

| Focused reference group | Physical Swift lines |
|---|---:|
| Provider-neutral usage/cost models, fetch plans, descriptors | 3,294 |
| Codex and Claude OAuth/descriptor/source-planner files | 2,968 |
| Local cost fetcher, scanner, Claude scanner, cache helpers, cache, pricing | 10,165 |
| Spend pane, refresh coordinator, adaptive refresh core | 985 |
| **Focused production reference total** | **17,412** |

A filename-filtered set of relevant Swift tests contained 72 files and 38,943 lines:

- CostUsage: 23 files / 18,534 lines;
- CodexOAuth: 5 files / 1,638 lines;
- ClaudeOAuth and ClaudeSourcePlanner: 29 files / 11,963 lines;
- SpendDashboard: 9 files / 5,702 lines;
- ProviderRefresh and AdaptiveRefresh: 6 files / 1,106 lines.

This focused set still overstates Bessie's recommended MVP because it includes advanced fork handling, account selection, provider fallbacks, pricing refresh, dashboard behavior, and production incidents that Bessie can initially avoid. It also demonstrates why a “read a few JSONL files and draw a chart” estimate would be wrong.

### Major layers

CodexBar's package structure separates:

- `CodexBarCore`: provider-neutral models, provider strategies, transports, credential/cookie handling, local scanners, pricing, and caches;
- `CodexBar`: menu-bar and Settings UI, scheduling, account state, diagnostics, notifications, and presentation;
- `CodexBarCLI`: command-line access;
- `CodexBarWidget`: widget projection;
- adaptive refresh and replay tooling;
- helper executables for Claude web/watchdog behavior.

See `/tmp/CodexBar/Package.swift:21-206`.

The Bessie MVP should copy the separation of pure normalization from app presentation, not the product breadth.

### Provider-neutral model lessons

Useful CodexBar model choices include:

1. **Raw provider values are preserved.** `RateWindow.usedPercent` is intentionally not globally normalized, and display projections clamp separately (`UsageFetcher.swift:3-6`).
2. **Synthetic and unknown windows are explicit.** A synthesized placeholder is not allowed to masquerade as a real zero (`UsageFetcher.swift:13-21`).
3. **Knownness is separate from numeric value.** `NamedRateWindow.usageKnown` prevents a reset-only window from appearing exhausted (`UsageFetcher.swift:98-139`).
4. **Freshness is part of the model.** `UsageSnapshot.updatedAt` and cost snapshot timestamps support stale-state presentation (`UsageFetcher.swift:143-184`; `ProviderCostSnapshot.swift:3-40`).
5. **Local estimates are named as estimates.** `CostUsageSessionBreakdown` says it is distinct from account billing or quota (`CostUsageModels.swift:25-27`).
6. **Completeness can be represented.** Local snapshots include history coverage, optional values, currency, metered versus estimated cost, account-scope fingerprint, daily values, projects, sessions, and update time (`CostUsageModels.swift:65-123`).
7. **Confidence is typed.** CodexBar uses exact, estimated, percent-only, and unknown confidence states (`ProviderIdentitySnapshot.swift:41-46`).
8. **Source is retained.** Fetch results include source label, strategy ID, strategy kind, diagnostic, and transient credential-owner evidence (`ProviderFetchPlan.swift:102-153`).

Bessie should use a smaller model, but it should retain these semantics.

### Local scanner lessons

CodexBar's local scanner is not a naive directory walk:

- Codex roots include `$CODEX_HOME/sessions` or `~/.codex/sessions` plus sibling `archived_sessions` (`CostUsageScanner.swift:1777-1802`).
- Claude roots include configured Claude roots, `~/.config/claude/projects`, the normal config root's `projects`, and Claude Desktop roots (`CostUsageScanner+Claude.swift:27-63`).
- Codex records carry input, cached input, output, reasoning, event identity, pricing coverage, and optional session/project metadata (`CostUsageScanner.swift:209-255`).
- Claude parsing reads assistant usage records with input, cache creation, cache reads, output, timestamps, model, request/message/session IDs, and sidechain/path roles (`CostUsageScanner+Claude.swift:136-244`).
- Claude streaming chunks can share IDs, so the final cumulative chunk wins rather than every chunk being added (`CostUsageScanner+Claude.swift:236-243`).
- Codex cumulative totals, forks, archived sessions, interleaved lineages, and re-emitted totals need containment and deduplication logic (`CostUsageScanner.swift:384-540`).
- Scanning is resumable and bounded by file bytes, per-refresh bytes, optional wall-clock duration, and cancellation (`CostUsageScanner.swift:46-183`).
- The app uses a 2-second automatic Codex scan slice and a dedicated executor because large corpora can take minutes (`CostUsageFetcher.swift:30-37`, `:487-503`).
- Cache payloads carry parser/producer version, scan window, time zone, pricing key, file state, catch-up progress, and previous stale report (`CostUsageCache.swift:27-177`).
- Incompatible parser caches are not reused as current truth; the previous report may be shown explicitly as stale while rebuilding (`CostUsageCache.swift:59-86`).

These are reusable engineering principles even if Bessie implements fewer record shapes.

### Refresh and stale-state lessons

CodexBar separates provider refresh from local token scans:

- provider refreshes coalesce and use generations so canceled/replaced work cannot publish stale results (`ProviderRefreshCoordinator.swift:23-95`);
- automatic local token scans have a minimum 5-minute TTL (`UsageStore.swift:423-447`);
- adaptive provider refresh ranges from 2 minutes after recent interaction to 30 minutes while constrained or long-idle (`AdaptiveRefreshPolicyCore.swift:53-101`);
- a provider snapshot with a current error is considered stale, and retry is required when stale or unsatisfied (`UsageStore.swift:626-640`);
- UI shows Refreshing, last-updated text, Not fetched yet, source errors, explicit stale-data labels, and partial/unavailable model history (`MenuCardView.swift:1131-1149`; `PreferencesSpendDashboardPane.swift:186-195`, `:389-402`, `:509-525`).

Bessie does not need adaptive policy in Tier 2. A smaller safe policy is:

- load cache immediately;
- run a bounded scan when the usage screen opens if the cache is older than 5 minutes;
- provide manual Refresh;
- coalesce duplicate requests;
- cancel on source/scope change;
- keep old data visible with a stale label when refresh fails;
- never block the main actor on file traversal.

### Honest UI language worth adapting

CodexBar uses language such as:

- “Local estimated cost history across supported providers.”
- “Local estimated history”
- “Estimated spend”
- “Tracked tokens”
- “Spend unavailable”
- “Model breakdown unavailable”
- “No local cost history yet”
- “Estimated from local Codex logs for the selected account.”

See `PreferencesSpendDashboardPane.swift:130-157`, `:259-283`, `:389-449`, and `:470-555`.

That language is more trustworthy than the unqualified dollar totals in the concept mockup.

## Provider-by-provider source assessment

### Reliability scale

| Grade | Meaning |
|---|---|
| A | Documented, versioned, provider-supported contract with defined auth and semantics. |
| B | First-party local artifact or tool output with useful stable fields, but incomplete account coverage or weaker compatibility guarantees. |
| C | Provider-reported value from an undocumented or private endpoint. Likely accurate at fetch time, but operationally fragile. |
| D | UI/browser scrape or heuristic inference. Brittle, privacy-sensitive, and unsuitable as a foundational contract. |
| Unavailable | The source cannot establish the value. |

No inspected consumer subscription source was proven Grade A.

### Source matrix

| Provider/source | What it can establish | What it cannot establish | Grade | MVP |
|---|---|---|---|---|
| Codex local session and archived JSONL | Locally recorded input/cache/output/reasoning events, model where present, local dates, session metadata, sometimes project path | Complete account usage, subscription quota, invoice, activity on other machines, clean Herdr agent mapping | B for local events; estimate for cost | Include |
| Claude local project/session JSONL | Locally recorded assistant usage, input/cache creation/cache read/output, model, timestamps, some session/message/request IDs | Complete account usage, subscription quota, invoice, other machines, Herdr agent mapping | B for local events; estimate for cost | Include |
| Codex OAuth usage | Provider-reported primary/secondary/additional rate windows, credits and some limit data | Stable public contract, billed local-session attribution | C | Tier 3 only |
| Claude OAuth usage | Provider-reported 5-hour, weekly/scoped windows and optional extra usage | Stable public contract, local session attribution, guaranteed availability | C | Tier 3 only |
| Codex or Claude CLI scraping/RPC | Sometimes account usage and identity using provider-owned tools | Cross-version stability, prompt-free behavior, complete fields | B/C depending on documented command; requires a separate contract study | Do not use as Tier 2 foundation |
| Browser cookies and dashboard scraping | Potential account dashboard values | Stable shape, low-friction permission model, safe account ownership | D | Reject for Bessie MVP |
| Herdr current snapshot | Pane/process/agent/workspace identity and live semantic state | Usage, historical state duration, token/cost/quota | A for topology, unavailable for accounting | Use only for live context |
| CWD/title/time-overlap join | A possible guess about where activity happened | Unique agent/workspace attribution | D | Reject |

### Codex live quota path

CodexBar's OAuth fetcher resolves a ChatGPT backend URL and uses:

- `/wham/usage` or `/api/codex/usage`;
- `Authorization: Bearer ...`;
- optional `ChatGPT-Account-Id`;
- a 30-second GET.

See `Providers/Codex/CodexOAuth/CodexOAuthUsageFetcher.swift:343-378`.

The parser handles primary and secondary windows, additional rate limits, credits, and flexible spend-control fields. It intentionally tolerates partial decode failures (`:6-47`, `:116-178`, `:180-230`). That tolerance is evidence that provider shapes change.

CodexBar loads CLI-owned OAuth material from a Codex `auth.json`, may refresh tokens, and may save the refreshed material (`CodexProviderDescriptor.swift:166-196`; `CodexOAuthCredentials.swift:55-187`). Bessie should not silently take ownership of or rewrite another tool's credentials. A future provider-connected tier needs an explicit credential-owner decision and account-scope tests before implementation.

### Claude live quota path

CodexBar's Claude OAuth fetcher uses:

- `https://api.anthropic.com/api/oauth/usage`;
- `Authorization: Bearer ...`;
- `anthropic-beta: oauth-2025-04-20`;
- a Claude Code user agent;
- explicit 401, 403, 429, retry-after, decode, cancellation, and network handling.

See `Providers/Claude/ClaudeOAuth/ClaudeOAuthUsageFetcher.swift:60-127`.

The response includes five-hour, seven-day, scoped weekly, optional extra usage, and newer dynamic limit entries (`:268-413`). The endpoint's beta header and evolving response shapes are strong reasons not to make it the first Bessie foundation.

CodexBar's Claude source planner supports OAuth, CLI, web, and API paths with explicit availability and fallback order (`ClaudeSourcePlanner.swift:3-116`, `:169-234`). Its provider descriptor also enforces a useful authority boundary: a selected account with missing or malformed credentials must not fall through to an ambient account and be mislabeled (`ClaudeProviderDescriptor.swift:50-66`). Bessie should adapt that principle if it ever adds multiple accounts.

### Cost semantics

For both providers, local cost is calculated from token categories and model pricing. It is not a provider charge.

Reasons for divergence include:

- subscription plans that do not bill each local token at API list rate;
- provider discounts, credits, promotions, and enterprise agreements;
- unsupported or renamed models;
- incomplete cache-read/cache-write semantics;
- provider-side tool calls or inference absent from local files;
- local artifacts deleted, truncated, disabled, or stored on another machine;
- duplicated cumulative records, forks, retries, and sidechains;
- pricing changing during the selected period;
- provider rounding and tiered pricing;
- activity from web, API, mobile, or other clients under the same account.

The UI must therefore say **Estimated at API list rates from local logs** and expose unknown pricing coverage. If some models are unpriced, the total must be marked partial. It must not silently sum only known models and present the result as complete.

## Why per-agent attribution is not ready

### The missing join

Herdr owns stable live identifiers such as:

- connection ID;
- workspace ID;
- tab ID;
- pane ID;
- terminal ID;
- process/agent identity.

Local Codex and Claude artifacts may contain:

- provider session ID;
- request, message, or turn IDs;
- timestamp;
- model;
- working directory or project path;
- provider-specific fork/subagent metadata.

No current field proves that provider session `S` belongs to Herdr pane `P` in workspace `W` on connection `C`.

### Why heuristics are not acceptable

| Heuristic | Failure mode |
|---|---|
| Working directory match | Multiple agents can share a repository; cwd changes; remote paths differ; a provider project is not a Herdr workspace. |
| Process name | Every Codex or Claude process looks similar and processes can fork. |
| Start-time overlap | Concurrent agents and resumed sessions create ambiguous matches. Bessie may not be running at launch. |
| Terminal title or label | User-editable and not stable. |
| Most recently focused pane | Focus is unrelated to provider usage. |
| Bessie launch recipe | Covers only Bessie-launched recipes and still needs the provider to carry a correlation ID into its telemetry. Existing Herdr objects cannot be excluded. |

### Required future contract

A trustworthy future path should emit a typed usage event or snapshot with:

- schema and producer version;
- source/provider;
- account-scope discriminator that is safe to persist;
- provider session/request/turn identifier;
- Herdr connection/workspace/tab/pane/terminal/process identifiers or a stable launch correlation ID;
- event timestamp and local time-zone handling;
- model and token categories;
- whether values are cumulative or delta;
- cost, if provider-reported, including currency and billing period;
- provenance and confidence;
- correction/deduplication identity;
- completeness and finalization state.

Herdr should remain the authority for the live object identifiers. The provider or companion should remain the authority for the usage event. Bessie should normalize and present the join, not become a second session owner.

## Proposed Bessie data model

The model should be smaller than CodexBar's but should encode truth status directly.

### Core types

Suggested conceptual types, not an implementation prescription:

```text
UsageProvider             codex | claude
UsageScope                localMachine | connection | workspace | agent | account
UsagePeriod               start, end, calendar/time zone
UsageTokenCounts          input?, cachedInput?, cacheCreation?, output?, reasoning?, total?
UsageCost                 amount?, currency, basis, pricingCoverage
UsageProvenance           sourceKind, sourceLabel, producerVersion, scopeDescription
UsageFreshness            observedAt, scannedAt, staleReason?
UsageCompleteness         complete | partial(reasons) | unavailable(reason)
UsageEstimate             provider, period, tokens, cost, provenance, freshness, completeness
UsageDashboardSnapshot    estimates, errorsBySource, scanProgress, generatedAt
```

`UsageCost.basis` should be one of:

- `providerReported`;
- `apiListRateEstimate`;
- `userDeclaredBudget`;
- `unavailable`.

Do not represent these as one unqualified `Double`.

### Unknown-value rules

1. Unknown is `nil` or a typed unavailable state, never numeric zero.
2. A missing provider result does not erase another provider's valid data.
3. Partial cost is not a complete total. Show known amount plus an explicit unpriced token/model count.
4. Display clamping must not alter raw provider values.
5. A stale last-known snapshot remains visible with its timestamp and failure reason.
6. A scope change invalidates publication from in-flight work.
7. Account/scope changes invalidate incompatible cache entries.
8. Time-zone changes invalidate day buckets or trigger deterministic rebucketing.

### Cache design

Tier 2 needs a rebuildable derived cache, not an event ledger.

Minimum cache metadata:

- cache schema version;
- parser/producer version;
- source roots and scope fingerprint;
- local calendar time zone;
- pricing-table version/fingerprint;
- per-file path fingerprint, size, modification time, parsed offset, and completion state;
- deduplication checkpoints needed by each parser;
- aggregate daily/provider token counters;
- cost coverage and unknown model counters;
- last successful scan time;
- bounded scan progress;
- optional prior snapshot explicitly marked stale during rebuild.

Persist only what is required to avoid rescanning. Do not persist prompt text, tool output, raw credentials, browser cookies, or full raw log records. Project paths should be omitted from the default aggregate cache unless project-level display is later approved.

### Ownership placement

| Layer | Responsibility |
|---|---|
| `BessieCore` | Provider-neutral models, source protocols, parsers, deduplication, aggregation, pricing calculations, cache schema, deterministic time-window logic. |
| `BessieApp` | macOS source-root discovery, file-permission UX, refresh coordination, cancellation, Settings integration, SwiftUI surface, app/window routing. |
| Herdr | Live workspace/tab/pane/process/agent identity and future correlation contract. |
| Provider/agent artifacts | Raw token event ownership. |
| Provider API | Any future provider-reported quota or spend ownership. |

## Recommended MVP product surface

### Information architecture

Use a dedicated **Usage** route reachable from Settings or the main sidebar, but do not make it a menu-bar dashboard in the first release.

The smallest shell change is a Settings entry because:

- scanning and privacy choices are configuration-adjacent;
- the current design breadcrumb already says Settings / Cost & usage;
- the feature is post-V1 and local-only;
- it avoids making incomplete estimates a primary navigation promise.

If product chooses a top-level destination, the same view model can be routed through `ProductDestination`; the data architecture does not change.

### MVP layout

1. **Header**
   - Local usage estimates
   - scope badge: This Mac only
   - selected range: Today / 7 days / 30 days
   - Refresh button
   - last successful scan and scan status

2. **Summary cards**
   - tracked tokens;
   - estimated API list-rate cost;
   - pricing coverage, for example “98% of tracked tokens priced”;
   - source coverage, for example “Codex and Claude local logs.”

3. **Provider rows**
   - Codex and Claude marks;
   - input/output/cache totals;
   - estimated cost;
   - source path category, not the full sensitive path;
   - complete/partial/unavailable status;
   - last observed activity.

4. **Daily chart**
   - tracked tokens by provider;
   - optional estimated cost toggle;
   - gaps remain gaps rather than interpolated zeros.

5. **Provenance panel**
   - “Estimated at API list rates from local provider logs. Not an invoice or provider quota.”
   - local-only and remote-exclusion statement;
   - unpriced models or partial-source warnings;
   - link to clear the derived cache.

### Required screen states

| State | Required behavior |
|---|---|
| Never scanned | Explain sources and offer Enable local estimates. No zero dashboard. |
| No logs found | Name which provider roots were checked, without exposing full paths in shared screenshots. |
| One provider available | Show it; mark the other unavailable independently. |
| Permission denied | Explain that Bessie could not read the local source and offer a retry or explicit folder selection if approved. |
| Scan in progress, no cache | Show progress and no fabricated totals. |
| Scan in progress, stale cache | Keep old totals visible with stale timestamp and progress. |
| Partial bounded scan | Show partial/catching-up state and do not claim selected-period completeness. |
| Corrupt/truncated records | Continue valid records, count ignored records, and show partial diagnostics. |
| Unknown model price | Show tracked tokens, partial estimated cost, and unpriced token/model count. |
| Time-zone change | Rebuild day buckets; show stale data until complete. |
| Source root/account changed | Do not publish results from the old scope. Rebuild an isolated cache. |
| Remote Herdr activity visible | State that remote activity is not included. Never fold it into a complete global label. |
| Refresh failure | Retain last-known result, mark stale, show source-specific error and Retry. |

### Accessibility and privacy

- Every color/status treatment needs a text label.
- Charts need summary accessibility values and provider/day labels.
- Dollar amounts need “estimated” in visible or accessibility text, not only a tooltip.
- Source paths and account identifiers should be redacted in shareable diagnostics.
- Hide-personal-information mode should cover provider identity, project paths, and account labels.
- Do not add export or share until the redaction and schema behavior is tested.

## Concrete Bessie integration path

This is an integration map, not authorization to implement.

### BessieCore

Add the smallest coherent usage domain:

1. normalized usage/provenance/completeness models;
2. pure daily-window aggregation;
3. model pricing lookup with explicit unknown coverage;
4. Codex and Claude local parsers;
5. scanner cache and bounded-progress state;
6. source protocol that allows fixture and app implementations;
7. deterministic tests for decode, deduplication, aggregation, time zones, and cache invalidation.

Do not put SwiftUI, AppKit, Keychain, browser cookies, or provider account UI in this layer.

### BessieApp

Integrate through existing patterns:

- add the route in `ProductSurfaces.swift` or the Settings navigation;
- route window focus through `BessieWindowCoordinator.swift`;
- reuse `BessieProviderMark`;
- add a `UsageViewModel` with injected source and clock;
- keep file scanning off the main actor;
- store only display/scanning preferences through `BessieSettingsModel`;
- show source-specific errors without collapsing the whole dashboard;
- add visual/presentation tests alongside `BessieVisualFoundationTests`;
- add view-model state tests alongside the existing app-model patterns.

No new package dependency is required for Tier 2. Foundation file and JSON handling are sufficient. If the implementation needs SQLite for scale, decide that after fixture benchmarks rather than adding it speculatively.

### Menu bar

Defer usage from `BessieMenuBarPopover.swift`. Bessie's menu bar currently serves agent attention and navigation. Adding cost polling there would:

- increase background work;
- create another refresh consumer;
- require compact stale/partial semantics;
- imply stronger completeness than a local-only estimate deserves.

The full usage screen should establish reliability first.

## Scope tiers and estimates

### Estimation basis

Estimates assume:

- one senior Swift/macOS engineer;
- current Bessie architecture remains intact;
- no direct Herdr or provider source modification in Tiers 1 through 3;
- implementation includes focused unit tests, fixtures, packaged Mac verification, and UI screenshot review;
- no commit, release, provider legal review, or external security audit time;
- production LOC includes models, parsers, cache, coordination, and UI;
- test LOC includes Swift tests and owned text/JSON fixtures, but not copied production corpora;
- ranges are physical lines and are directional, not targets.

### Tier 1: UI-only prototype

**Purpose:** Validate information hierarchy and native visual treatment with synthetic fixtures.

| Dimension | Estimate |
|---|---|
| Difficulty | Low to medium |
| Effort | 1 to 2 engineer-weeks |
| Production code | 500 to 900 lines |
| Tests | 400 to 800 lines |
| External dependencies | None |
| User value | Low; must remain developer-only |

Includes:

- route/surface;
- time-range controls;
- summary/provider/chart components;
- all empty, partial, stale, and error fixtures;
- accessibility and design tests.

Excludes every real data source. This is not a credible public feature and must not ship with synthetic numbers.

### Tier 2: Local Estimate Mode, recommended MVP

**Purpose:** Provide honest local token and API list-rate estimates for Codex and Claude.

| Dimension | Estimate |
|---|---|
| Difficulty | Medium-high to high |
| Effort | 7 to 10 engineer-weeks |
| Production code | 4,500 to 8,000 lines |
| Tests and fixtures | 5,000 to 10,000 lines |
| External dependencies | None required; optional adaptation of MIT-licensed CodexBar code |
| Ongoing maintenance | Parser and pricing updates as local formats/models change |

Includes:

- Tier 1 UI;
- default/local configured roots for Codex and Claude;
- streaming JSONL parsing;
- cumulative/streaming deduplication needed by supported fixture shapes;
- archived-session handling;
- bounded incremental scanning and cancellation;
- parser/pricing/cache versioning;
- time-zone-aware today/7/30 aggregation;
- partial pricing and unpriced-model accounting;
- stale-cache rebuild behavior;
- local-only and source-provenance UX;
- cache clear and scanning opt-in/out;
- isolated Mac live checks against synthetic homes.

Explicit limitations:

- current Mac only;
- ambient/default local source scope only unless custom roots are explicitly added;
- no account-wide completeness;
- no provider quota;
- no invoice semantics;
- no per-agent/workspace mapping;
- no remote activity.

The lower end assumes selective adaptation of proven scanner/cache patterns under CodexBar's MIT license. A from-scratch implementation that reaches equivalent edge-case quality is more likely to land at or above the upper end.

### Tier 3: Provider-connected production mode

**Purpose:** Add provider-reported Codex and Claude quota windows and optional provider-reported spend where a defensible contract exists.

| Dimension | Estimate |
|---|---|
| Difficulty | Very high, with ongoing operational risk |
| Increment beyond Tier 2 | 6 to 10 engineer-weeks |
| Cumulative effort | 13 to 20 engineer-weeks |
| Additional production code | 3,000 to 6,000 lines |
| Additional tests/fixtures | 4,000 to 8,000 lines |
| External dependencies | Provider auth/endpoint contracts, security and terms review |

Includes:

- separate provider-reported quota models;
- source/account selection and isolation;
- read-only credential discovery or a Bessie-owned OAuth flow;
- token refresh ownership decision;
- 401/403/429/retry-after handling;
- source fallbacks only when account ownership is provable;
- account-scoped cache and publication guards;
- offline/stale last-known provider data;
- mocked transport contract suites and opt-in manual acceptance tests.

This tier should not begin until each provider has a written source decision:

1. Is the endpoint documented and permitted for this use?
2. Who owns credentials and refresh?
3. How is account identity proven?
4. What is the rate-limit policy?
5. What happens when the response shape changes?
6. Which values are quota, prepaid credits, extra usage, or billed spend?

If the only available answer is browser-cookie extraction or private UI scraping, Bessie should stop at Tier 2.

### Tier 4: Trusted per-agent/workspace usage and complete concept

**Purpose:** Satisfy the current roadmap's trusted per-agent/backend and workspace breakdown requirements, then consider ceiling, forecast, export, and context.

| Dimension | Estimate |
|---|---|
| Difficulty | Very high and cross-repository |
| Increment beyond Tier 3 | At least 8 to 14 engineer-weeks after a contract is agreed |
| Cumulative effort | Roughly 21 to 34+ engineer-weeks |
| Additional code | 3,000 to 7,000+ lines across Bessie, Herdr, and/or companion/provider adapters |
| Estimate confidence | Low until the upstream contract owner and provider instrumentation are known |

Includes:

- versioned telemetry/correlation contract;
- local and remote support through Herdr connections;
- lifecycle timestamps and historical state changes;
- correction and deduplication semantics;
- per-agent/workspace aggregation;
- only then, advisory ceiling and forecast;
- export after schema/privacy stabilization;
- anomaly hints only as a separately reviewed feature.

This tier cannot be estimated confidently from Bessie alone. It requires upstream design and implementation evidence.

## Recommended Tier 2 milestone plan

### M0: Contract and corpus gate, 3 to 5 days

- approve the local-only estimate framing;
- define visible labels and unknown/partial semantics;
- define cache retention and clear behavior;
- assemble sanitized Codex and Claude fixtures covering supported formats;
- decide whether MIT-licensed CodexBar code will be adapted or only used as a reference;
- benchmark fixture corpus size and set scanner budgets.

**Stop condition:** If the team cannot own representative sanitized fixtures or cannot state what “tracked” excludes, do not build the dashboard.

### M1: Core model and aggregation, about 1 week

- implement normalized models;
- implement period and time-zone aggregation;
- implement pricing basis and partial coverage;
- test unknowns, local-day boundaries, and deterministic summaries.

### M2: Codex local source, 2 to 3 weeks

- discover standard/configured roots and archives;
- stream supported token records;
- handle cumulative records, duplicates, archives, and supported fork shapes;
- implement bounded/resumable scanning and cache invalidation;
- test corrupt, truncated, growing, archived, and replaced files.

### M3: Claude local source, 1.5 to 2 weeks

- discover standard/configured/Desktop roots;
- parse assistant usage and cache categories;
- deduplicate cumulative streaming chunks;
- handle subagent/sidechain records explicitly;
- test malformed records, unknown models, duplicate roots, and partial pricing.

### M4: Refresh/cache coordination, about 1 week

- load stale cache first;
- coalesce refresh requests;
- cancel and generation-guard scope changes;
- expose bounded catch-up progress;
- implement clear-cache and parser-version rebuild;
- verify no scanning on the main actor.

### M5: Native surface and navigation, 1 to 1.5 weeks

- implement Settings or product route;
- add summary, provider rows, daily chart, provenance, and all states;
- reuse provider marks and native design system;
- add accessibility and pure view-model tests.

### M6: Hardening and packaged verification, 1 to 1.5 weeks

- run `./scripts/check.sh`;
- run `./scripts/mac-verify.sh` with isolated synthetic provider homes;
- verify app packaging/install according to Bessie's normal completion rules;
- capture and inspect screenshots for empty, partial, populated, stale, and permission states;
- verify scanner output against hand-calculated fixtures;
- profile large synthetic corpora and cancellation;
- verify the app never reads real credentials in local-estimate mode;
- verify remote sessions are visibly excluded.

Some milestones can overlap, producing the 7 to 10 week total rather than a strict sum.

## Test and validation plan

### Core model tests

- optional versus zero token fields;
- raw versus display-clamped percentages for future live data;
- provider-reported versus estimated cost basis;
- complete, partial, stale, and unavailable projections;
- local calendar day boundaries, daylight-saving changes, and time-zone changes;
- 1/7/30-day inclusive ranges;
- unknown currency and pricing coverage;
- source/account/scope change invalidation.

### Codex scanner fixtures

- normal session with deltas;
- cumulative totals only;
- last plus total records;
- repeated cumulative records;
- growing file resumed from offset;
- file replacement/truncation;
- archived session;
- parent/child fork;
- interleaved lineage drop;
- cached-input and reasoning fields;
- unknown model;
- malformed/truncated JSONL;
- large line and large file;
- cancellation and per-refresh budget;
- changed parser and pricing fingerprints.

### Claude scanner fixtures

- standard assistant usage event;
- cache creation, one-hour cache creation, cache read, input, and output;
- repeated streaming chunks with the same message/request ID;
- old records without IDs;
- subagent and sidechain records;
- duplicate roots;
- Claude Desktop location;
- configured root;
- unknown model and partial pricing;
- malformed/truncated records;
- growing file and cancellation.

### Cache tests

- atomic save and corrupt-cache recovery;
- schema/producer incompatibility;
- source-root fingerprint changes;
- time-zone invalidation;
- pricing-version changes;
- stale previous snapshot during rebuild;
- no raw content or credential material in serialized cache;
- file-permission expectations;
- clear-cache behavior.

### App model and UI tests

- navigation to Usage;
- one provider does not block another;
- every required state in the matrix;
- source and freshness always visible;
- “estimated” always visible with dollar values;
- no zero shown for unknown;
- remote-exclusion warning;
- reduce motion/transparency and increased contrast behavior;
- VoiceOver summaries for chart and provider rows;
- personal-info redaction.

### Live packaged checks

Live checks should use temporary isolated `CODEX_HOME`, Claude config roots, and owned fixture files. They should not inspect Jordan's live accounts. Assert:

- the packaged app discovers the isolated roots;
- manual refresh produces hand-calculated totals;
- a changed fixture increment updates once, not twice;
- stale cache appears after induced parser/source failure;
- refresh remains responsive during a large scan;
- remote Herdr items do not change local usage totals;
- the installed executable matches the packaged executable under Bessie's normal validation workflow.

Provider-connected live acceptance, if Tier 3 is later approved, should use separately authorized test accounts and must not run in ordinary CI.

## Security, privacy, and product risks

### Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Local estimate is read as billed spend | High | High | Put “estimated at API list rates from local logs” beside every cost summary; never title it Billing. |
| Missing activity appears as zero | High | High | Typed unavailable/partial states; no default zero; visible source scope. |
| Double counting cumulative/forked events | Medium-high | High | Fixture-backed deduplication, stable event keys, cumulative containment, cache checkpoints. |
| Parser drift after provider update | Medium | High | Producer version, fixture corpus, stale rebuild, per-source failure, fast disable switch. |
| Unknown pricing understates cost | High over time | Medium-high | Pricing fingerprint, partial coverage, unpriced token/model count, no complete total. |
| Cross-account cache publication | Medium | High | Account/scope discriminator, generation guard, isolated cache key, no ambient fallback for selected accounts. |
| Live endpoint or OAuth behavior changes | High for undocumented sources | High | Keep out of MVP; require provider-specific contract and kill switch in Tier 3. |
| Bessie rewrites tool-owned credentials | Medium if copied from CodexBar | High | Tier 2 reads no credentials; Tier 3 must designate owner and avoid silent mutation. |
| Prompt/tool content leaks into cache or diagnostics | Medium | High | Streaming field extraction, aggregate-only cache, sanitization tests, no raw records. |
| Project path leaks | Medium | Medium-high | No project breakdown in MVP; redact diagnostics and personal-info mode. |
| Remote work is omitted from a global total | High | High | “This Mac only,” separate remote unavailable state, no complete all-herds label. |
| Large corpus stalls app | Medium-high | High | Dedicated executor, wall-clock and byte budgets, incremental cache, cancellation, progress. |
| Time-zone/day rebucketing changes totals | Medium | Medium | Store time zone, invalidate/rebuild deterministically, label selected period. |
| Forecast creates false urgency | High | Medium-high | Defer until coverage and confidence rules are approved. |
| Anomaly hints misjudge user behavior | High | High | Keep U05 separate and speculative. |

### Credential policy

Tier 2 should not read or write OAuth tokens. It only reads session artifacts.

Tier 3 must choose one explicit model per provider:

1. **Tool-owned credentials, read-only:** Bessie reads a documented token surface but never refreshes or rewrites it. Failure asks the user to authenticate in the provider tool.
2. **Bessie-owned OAuth:** Bessie stores and refreshes its own token in Keychain with a provider-approved flow.
3. **Provider API key:** only where an official usage API and scopes exist.

Do not combine these silently. Do not fall back from a selected account to ambient credentials. Never persist raw token material in usage snapshots, logs, diagnostics, or exported data.

### Local artifact policy

- Parse only fields needed for counts and source identity.
- Do not load whole corpora into memory.
- Do not persist prompts, responses, command text, or tool output.
- Keep derived cache file permissions private.
- Give the user a clear-cache action.
- Disable scanning by default if product/legal review concludes local logs are unexpectedly sensitive.
- State exactly which roots and machines are covered.

## What to adapt from CodexBar

### Adapt directly or closely

- provider-neutral snapshots with source, freshness, confidence, and completeness;
- distinct provider-reported and locally estimated values;
- raw-value preservation and display-only clamping;
- explicit synthetic/missing/unknown states;
- bounded incremental JSONL scanning;
- cache producer/pricing/source fingerprints;
- stale previous snapshot during rebuild;
- cumulative and streaming deduplication techniques;
- account/scope publication guards;
- pure aggregation with fixture-heavy tests;
- visible local-estimate and partial-coverage language;
- independent errors by source.

### Use only as a reference

- the complete Codex fork/interleaving machinery until Bessie's fixture corpus proves each branch is needed;
- Models.dev dynamic pricing refresh;
- multi-account promotion/reconciliation;
- adaptive background polling;
- provider source fallback trees;
- share/export presentation;
- project-level Codex sidecar indexing.

### Do not bring into the MVP

- full multi-provider registry;
- browser-cookie extraction or web dashboard scraping;
- Keychain migration and broad credential-account machinery;
- CLI, widget, and menu-bar parity;
- provider helper executables;
- broad provider-specific settings;
- anomaly, notification, predictive pace, or quota hook systems;
- billing-like dashboards without provenance.

## License and reuse

CodexBar is MIT licensed at the inspected revision:

```text
MIT License
Copyright (c) 2026 Peter Steinberger
```

The license permits use, copy, modification, merge, publication, distribution, sublicensing, and sale. It requires the copyright notice and permission notice to be included in all copies or substantial portions. It disclaims warranty.

Implications for Bessie:

- Architectural ideas and independently implemented patterns can be used normally.
- If Bessie copies or substantially adapts scanner, cache, parser, or model code, preserve the MIT notice in Bessie's source/distribution attribution in a form consistent with the license.
- Track copied/adapted files so future maintainers know their provenance.
- Do not assume that third-party pricing data, fixtures, provider assets, or dependencies embedded in the broader CodexBar repository inherit MIT treatment without checking their own notices.
- Prefer a small auditable adaptation over adding the full CodexBar package as a dependency. Bessie does not need CodexBar's app, widget, CLI, cookies, or provider registry.

Source: `/tmp/CodexBar/LICENSE`.

## Open decisions before implementation

### Product decisions

1. Is a **This Mac only, local estimate** useful enough without per-agent attribution?
2. Should the visible title be Local usage estimates, Usage, or Cost & usage?
3. Should the surface live in Settings first or primary navigation?
4. Is scanning opt-in or on by default after disclosure?
5. Are today/7/30 sufficient, or is month-to-date required?
6. Should cached input be included in the primary token total, and how is that explained?
7. Is API list-rate cost useful for subscription users, or should cost default off while tokens remain on?
8. How long should the derived cache be retained?

### Source decisions

1. Which sanitized Codex and Claude versions/shapes define initial compatibility?
2. Are custom `CODEX_HOME` and Claude config roots in MVP?
3. Are Claude Desktop sessions in MVP?
4. How are multiple accounts or homes represented without reading credentials?
5. Is project-path metadata excluded entirely from the first cache?
6. What corpus size and scan latency are acceptable?

### Future provider decisions

1. Are the Codex and Claude OAuth usage endpoints approved and stable enough for Bessie?
2. Does provider policy permit third-party use with CLI-owned credentials?
3. Will Bessie own OAuth, or remain read-only?
4. Which provider values are quota, credits, extra usage, prepaid balance, or spend?
5. What account identity can be retained without exposing personal information?

### Upstream decisions

1. Does Herdr want to own a generic usage event contract, or only carry correlation IDs?
2. Which provider/agent component owns token events?
3. How does the same contract work for SSH remote connections?
4. How are corrections, forks, retries, and session resumes represented?
5. Are historical active/blocked/idle transitions in scope for Herdr?

## Go/no-go criteria

### Proceed with Tier 2 when

- the local-estimate framing is explicitly approved;
- representative sanitized fixtures are owned by the project;
- source and pricing coverage can be shown honestly;
- scanning can be bounded and canceled;
- the cache contains no raw content or credentials;
- remote omission is clear;
- tests prove no double publication on scope change;
- the product accepts that per-agent/workspace rows remain absent.

### Do not proceed with Tier 2 when

- the product requires invoice accuracy;
- the screen must show all visible local and remote agents as complete;
- estimates cannot be visibly labeled;
- implementation depends on browser cookies or silently modifying provider auth;
- no stable fixture corpus can be maintained;
- unknown pricing would be hidden rather than surfaced.

### Proceed to Tier 3 only when

- each provider source has a written auth, terms, identity, rate-limit, and failure contract;
- account-scoped cache/publication tests exist;
- the endpoint can be disabled independently;
- the UI keeps provider-reported quota separate from local estimate cost;
- security review approves credential ownership.

### Proceed to Tier 4 only when

- a typed correlation/usage contract exists across local and remote Herdr connections;
- at least Codex and Claude can emit stable provider-session correlation;
- historical lifecycle semantics are defined;
- per-agent totals can be validated against source fixtures without CWD/time heuristics.

## Final recommendation

**Do not implement the complete Cost & usage mockup now.** It combines several data products that current Bessie and Herdr contracts cannot support honestly.

Approve a separate post-V1 precursor only if the local-estimate product is valuable on its own:

> **Tier 2, Local Estimate Mode:** Codex and Claude, current Mac only, read-only local artifacts, today/7/30 tracked tokens, API list-rate estimated cost, daily/provider breakdown, bounded cache, and explicit provenance/partial/stale states.

Treat provider quota as Tier 3 and trusted per-agent/workspace usage as Tier 4. Do not let the easy UI work pull undocumented OAuth, browser cookies, billing claims, or heuristic attribution into the MVP.

## Evidence index

### Bessie repository

- `AGENTS.md`
- `docs/plans/2026-08-01-bessie-v1.md`
- `docs/roadmap/cost-and-usage.md:1-49`
- `Sources/BessieApp/ProductSurfaces.swift:5-40`
- `Sources/BessieApp/BessieSettings.swift:9-95`, `:253-259`
- `Sources/BessieApp/BessieDesignSystem.swift:627+`
- `Sources/BessieApp/BessieWindowCoordinator.swift`
- `Sources/BessieApp/BessieMenuBarPopover.swift`
- `Sources/BessieCore/HerdrModels.swift:40-83`
- `Sources/BessieCore/SessionProjection.swift:3-49`, `:128-148`
- `Sources/BessieCore/AgentProjection.swift:45-92`
- `Sources/BessieCore/PresentationPersistence.swift:36-148`
- `Sources/BessieCore/KeyboardShortcuts.swift:35-67`, `:259-300`
- `Tests/BessieAppModelTests/ProjectsViewModelTests.swift`
- `Tests/BessieAppModelTests/BessieVisualFoundationTests.swift:43-100`
- `Package.swift:23-55`

### Retained Bessie workstream

- `/home/hermes/.hermes/workspace/shared/workstreams/bessie/V1-SCOPE.md`
- `/home/hermes/.hermes/workspace/shared/workstreams/bessie/ARCHITECTURE.md`
- `/home/hermes/.hermes/workspace/shared/workstreams/bessie/FEASIBILITY.md`
- `/home/hermes/.hermes/workspace/shared/workstreams/bessie/HERDR-CAPABILITY-MAP.md`
- `/home/hermes/.hermes/workspace/shared/workstreams/bessie/FEATURE-GAP-INVENTORY.md:677-685`
- `/home/hermes/.hermes/workspace/shared/workstreams/bessie/source-material/design-system/screens/1x-cost-usage.html`
- `/home/hermes/.hermes/workspace/shared/workstreams/bessie/source-material/design-system/Bessie Screens.html:5373-5585`

### CodexBar exact revision

- `/tmp/CodexBar/Package.swift:21-206`
- `/tmp/CodexBar/LICENSE`
- `Sources/CodexBarCore/UsageFetcher.swift:3-21`, `:98-184`
- `Sources/CodexBarCore/ProviderIdentitySnapshot.swift:41-46`
- `Sources/CodexBarCore/ProviderCostSnapshot.swift:3-40`
- `Sources/CodexBarCore/CostUsageModels.swift:25-123`
- `Sources/CodexBarCore/CostUsageFetcher.swift:30-37`, `:352-470`, `:487-580`
- `Sources/CodexBarCore/CodexLocalProjectUsageProjection.swift:3-49`
- `Sources/CodexBarCore/Providers/ProviderFetchPlan.swift:102-177`, `:195-295`
- `Sources/CodexBarCore/Providers/ProviderDescriptor.swift:103-138`
- `Sources/CodexBarCore/Providers/Codex/CodexProviderDescriptor.swift:40-105`, `:166-280`
- `Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthUsageFetcher.swift:6-47`, `:116-178`, `:320-378`
- `Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthCredentials.swift:55-187`
- `Sources/CodexBarCore/Providers/Claude/ClaudeSourcePlanner.swift:3-116`, `:169-234`
- `Sources/CodexBarCore/Providers/Claude/ClaudeProviderDescriptor.swift:50-107`, `:134-207`
- `Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthUsageFetcher.swift:60-127`, `:268-413`
- `Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner.swift:46-183`, `:209-255`, `:384-540`, `:1777-1802`
- `Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner+Claude.swift:27-63`, `:136-267`
- `Sources/CodexBarCore/Vendored/CostUsage/CostUsageCache.swift:27-177`
- `Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift`
- `Sources/CodexBar/ProviderRefreshCoordinator.swift:23-95`
- `Sources/AdaptiveRefreshCore/AdaptiveRefreshPolicyCore.swift:53-101`
- `Sources/CodexBar/UsageStore.swift:423-447`, `:626-640`
- `Sources/CodexBar/MenuCardView.swift:1131-1149`
- `Sources/CodexBar/PreferencesSpendDashboardPane.swift:130-157`, `:186-195`, `:259-330`, `:389-449`, `:470-637`
