---
title: "Cost & usage screen — permanently deferred"
type: feat
status: permanently-deferred
date: 2026-08-04
origin: historical direct request — scope usage tracking screen against CodexBar (steipete/CodexBar); superseded by permanent deferral
deepened: 2026-08-04
artifact_contract: ce-unified-plan/v1
research: docs/research/2026-08-04-cost-and-usage-codexbar-scope.md
---

# Cost & usage screen — permanently deferred

> **Product decision (2026-08-04): permanently deferred.** Do not execute this plan, including its local-estimate precursor. It is retained only as research and decision history. Re-entry requires Jordan to explicitly reverse the roadmap decision.

## Difficulty (executive)

| Question | Answer |
| --- | --- |
| How hard is usage tracking **overall**? | **High.** UI is not the feature; honest ingestion, cache, provenance, and non-claims are. |
| How hard is a **fixture-backed screen shell**? | **Low–medium** · **1–2 eng-weeks** for a polished native prototype (not a weekend stub). |
| How hard is the **recommended first credible ship**? | **Medium-high → high** · **7–10 eng-weeks**: Local Estimate Mode for Codex + Claude on this Mac only. |
| How hard are **provider quota meters** (CodexBar live OAuth windows)? | **Very high + ongoing risk** · **+6–10 weeks** after local mode, and only after written source/auth decisions per provider. |
| How hard is the **full mock** (per-agent $, ceilings, forecast, anomaly, CSV, pause)? | **Blocked / cross-repo** · needs typed Herdr/companion telemetry. **~21–34+ eng-weeks** cumulative after contracts exist — low confidence. |
| Fork or vendor **CodexBar**? | **No.** MIT-licensed patterns and selective adaptation OK. Do not import the multi-provider menu-bar product (~260k LOC, 67 providers). |

**Historical recommendation (not planned):**  
The research recommended **Local Estimate Mode** (Codex + Claude, this Mac only, source-labeled, estimated cost only). The permanent deferral supersedes that recommendation. Do not implement provider OAuth quota cards or claim per-agent/workspace attribution without a join ID.

Canonical research (Amp scoping run, CodexBar `@ 5a74688`):  
[`docs/research/2026-08-04-cost-and-usage-codexbar-scope.md`](../research/2026-08-04-cost-and-usage-codexbar-scope.md)

---

## Outcome

A post-V1 **Cost & usage** surface that:

1. Shows **locally tracked** token totals and **API list-rate estimated cost** for Codex and Claude activity visible on the current Mac.
2. Labels every number with **source, confidence, scope, freshness, and pricing coverage**.
3. Never pretends Bessie is the billing authority, never invents zeros for unknown, never silently omits remote Herdr work into a global total.
4. Leaves a clean seam for later provider-reported quota and Herdr-correlated per-agent usage — without baking heuristic joins into v1 of the screen.

---

## What already exists

### Product / design

| Asset | State |
| --- | --- |
| `docs/roadmap/cost-and-usage.md` | Post-V1; first useful slice still wants trusted per-agent ingestion (full mock). Local estimate is a **precursor**, not full graduation of that slice. |
| Design `1x-cost-usage.html` | Later concept: period rail, $, ceiling, forecast, by-agent, by-workspace, CSV, enforcement disclaimer |
| `FEATURE-GAP` U01–U05 | U01 ingestion Upstream/Companion; U02 dashboard after trusted source; U03 ceiling; U04 CSV; U05 anomaly speculative |

### Bessie code (today)

| Seam | Finding |
| --- | --- |
| `ProductDestination` / rail | Easy to add `.usage` or Settings sub-route; Files already flag-gated |
| `AgentProjection` / `HerdrSnapshot` | Topology + agent kind/status only — **no tokens, cost, model, tool calls, durations** |
| `AgentLaunch` | Knows `codex`, `claude`, `amp`, … — allowlist for future provider plane |
| Settings / presentation store | Fine for **display prefs** and opt-in scan toggles; **not** a billing ledger |
| Remote Herdr | Material boundary: local scanners cannot see remote agent logs |

### CodexBar (reference)

| Fact | Detail |
| --- | --- |
| Repo | https://github.com/steipete/CodexBar · inspected `/tmp/CodexBar` @ `5a74688` |
| Scale | ~260k LOC Swift Sources; ~67 provider dirs; Amp provider alone ~1.2k LOC |
| Local cost engine | `CostUsageScanner` ~4.9k LOC — incremental scan, byte budgets, fork/dedupe complexity |
| Live quota | Codex/Claude OAuth-backed consumer endpoints in CodexBar — **not proven stable public APIs** |
| Confidence model | `UsageDataConfidence`: exact / estimated / percentOnly / unknown |
| License | MIT — selective adaptation allowed with attribution; full product fork is wrong shape |

**Borrow:** descriptor/strategy thinking, confidence + provenance labels, bounded incremental scan, stale-first refresh, fixture-heavy tests, honest empty/partial language.  
**Do not borrow:** 67-provider registry, browser-cookie matrix, menu-bar/widget product, account-switcher machinery as Bessie core.

---

## Scope tiers

Aligned with Amp research naming (preferred). Prior draft that led with “provider meters first” is **superseded** — OAuth quota is Tier 3 here, not the fast follow.

### Tier 1 — UI-only prototype (Low–medium · 1–2 weeks)

- Route + native surface + period controls + summary/provider/chart chrome.
- All empty / partial / stale / permission / error fixtures.
- Feature-flagged (`BessieFeature.costAndUsage`); developer-only.
- **Must not ship synthetic numbers as real.**

### Tier 2 — Local Estimate Mode **(recommended fast follow · 7–10 weeks)**

- Codex + Claude only.
- Read first-party **local** session artifacts on the **current Mac**.
- Today / 7-day / 30-day tracked tokens (input / output / cache where present).
- API list-rate **estimated cost** only when pricing table covers the model.
- Provider breakdown + daily trend.
- Every result shows: source, scope (**This Mac only**), freshness, scan coverage, pricing coverage.
- Bounded incremental cache; no main-actor corpus walk; opt-in/out + clear-cache.
- Read-only w.r.t. credentials and agent artifacts.

**Explicit non-goals for Tier 2:**
- provider quota meters
- billed-spend claims
- per-agent / per-workspace attribution
- elapsed / blocked / tool-call accounting
- forecast, anomaly, CSV
- menu-bar parity
- browser-cookie extraction
- automatic budget enforcement
- Amp (or other) providers until local Codex/Claude quality is real
- remote Herdr activity in the totals

### Tier 3 — Provider-connected quota (Very high · +6–10 weeks)

- Codex/Claude provider-reported windows only after written answers to: documented endpoint? credential owner? account identity? rate limits? schema drift? quota vs credits vs billed?
- If the only path is cookie scrape / private UI — **stop at Tier 2**.

### Tier 4 — Trusted per-agent/workspace + full concept (Blocked · cross-repo)

- Requires versioned telemetry with stable correlation IDs into Herdr panes/workspaces/connections.
- Then: by-agent rows, by-workspace tables, remote-aware totals, advisory ceilings, forecast, CSV, maybe anomaly later.
- **Never fake Tier 4 by splitting provider or local totals across panes.**

---

## Key Technical Decisions

The decisions below describe the abandoned implementation shape. They are not active implementation authority while the permanent deferral stands.

### KTD-1 — Local Estimate Mode is the first credible ship

**Decision:** Fast follow = Tier 2 local Codex/Claude estimates, not live OAuth quota cards and not mock-complete by-agent spend.

**Why:** Local logs can prove *some* recorded token events occurred. They cannot prove account completeness, quota, or invoices — and that honesty matches Bessie’s roadmap boundary. OAuth consumer endpoints in CodexBar are high drift/terms risk for a first cut.

### KTD-2 — Two future data planes, never unlabeled merge

| Plane | Answers | Fast follow? |
| --- | --- | --- |
| **Local tracked / estimated** | Tokens (and list-rate $) from session artifacts on this Mac | **Yes (Tier 2)** |
| **Provider-reported** | Plan/quota windows for an account | Tier 3 only |
| **Session-attributed** | This Herdr agent/workspace spent X | Tier 4 only |

### KTD-3 — Borrow CodexBar; do not vendor the app

**Decision:** Bessie-owned `BessieCore` usage module. Optional selective MIT adaptation of scanner/cache ideas after M0 license/fixture gate. No SPM dependency on full CodexBar.

### KTD-4 — Feature-flagged, post-V1 only

**Decision:** `BessieFeature.costAndUsage` via `BESSIE_DEVELOPER_FEATURES` until product graduation. Outside Mac V1 acceptance.

### KTD-5 — Presentation store holds prefs only

**Decision:** Preferences: period, show estimated cost, include cache tokens, scan enabled, custom roots (later).  
Derived counters live in a **separately versioned rebuildable cache**. Not an append-only ledger; not credentials.

### KTD-6 — Design mock is aspirational acceptance, not Tier 2 acceptance

**Decision:** `1x-cost-usage.html` guides density and disclaimer language. Tier 2 acceptance is honest local estimates — not ceiling enforcement or six agent meters.

### KTD-7 — Screen naming

**Decision:** Prefer product copy like **Local usage estimates** (or Cost & usage with a permanent subtitle *Local estimates · this Mac*). Avoid “Billing” / “Spend” as the primary title.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ BessieApp                                                   │
│  ProductDestination.usage → CostUsageSurface                │
│  CostUsageViewModel (@MainActor) — publishes snapshots only │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│ BessieCore / Usage                                          │
│  UsageSummarySnapshot (period, tokens, est. cost, provenance)│
│  UsageScanCoordinator (coalesce, cancel, generation guards) │
│  CodexLocalUsageSource / ClaudeLocalUsageSource             │
│  UsagePricingTable (versioned)                              │
│  UsageDerivedCache (parser+pricing schema versions)         │
│  (later) ProviderQuotaSource · SessionUsageJoin             │
└─────────────────────────────────────────────────────────────┘
        │ read-only FS                         │ future
        ▼                                      ▼
 ~/.codex / Claude local roots          Provider APIs / Herdr events
```

**Rules:**
- No terminal scraping of agent panes for token lines.
- No main-actor file traversal.
- Failures are card/state level, not shell crashes.
- Remote connections: excluded from Tier 2 totals; UI says so.
- Unknown ≠ zero.

---

## Implementation Units

### U0. Contract + corpus gate (M0 · 3–5 days)

**Goal:** Lock labels, unknown semantics, cache retention, fixture corpus, MIT adapt-vs-rewrite decision, scanner budgets.

**Stop if:** Cannot own sanitized fixtures or cannot state what “tracked” excludes.

**Deliverable:** short decision note in plan or research appendix; fixture tree under `Tests/.../Fixtures/usage/`.

### U1. Core models + period aggregation (M1 · ~1 week)

**Files (indicative):**
- `Sources/BessieCore/Usage/UsageModels.swift`
- `Sources/BessieCore/Usage/UsageAggregation.swift`
- `Sources/BessieCore/Usage/UsagePricing.swift`
- Core tests for TZ day boundaries, unknowns, partial pricing

**Sketch:**
```swift
public enum UsageValueConfidence: String, Codable, Sendable {
    case exact, estimated, percentOnly, unknown
}
public struct UsageTokenTotals: Codable, Equatable, Sendable {
    public var input: Int?
    public var output: Int?
    public var cacheRead: Int?
    public var cacheWrite: Int?
}
public struct UsagePeriodSummary: Codable, Equatable, Sendable {
    public var period: UsagePeriod          // today | days7 | days30
    public var tokens: UsageTokenTotals
    public var estimatedCostUSD: Decimal?   // nil if coverage incomplete
    public var pricingCoverage: Double      // 0...1 of tokens priced
    public var scope: UsageScope            // thisMac
    public var sources: [UsageSourceID]     // codexLocal, claudeLocal
    public var scannedThrough: Date?
    public var stale: Bool
    public var incompleteReasons: [String]
}
```

### U2. Codex local source (M2 · 2–3 weeks)

- Discover standard/configured roots + archives.
- Stream supported token records; cumulative/dupe/fork containment.
- Bounded/resumable scan + cache invalidation.
- Tests: corrupt, truncated, growing, archived, replaced files.

### U3. Claude local source (M3 · 1.5–2 weeks)

- Standard/configured/Desktop roots.
- Assistant usage + cache categories; streaming chunk dedupe.
- Explicit subagent/sidechain policy (include with label or exclude — decide in U0).
- Tests: malformed, unknown models, duplicate roots, partial pricing.

### U4. Scan coordinator + cache (M4 · ~1 week)

- Stale-first publish; coalesce refresh; cancel on scope change.
- Parser/pricing version rebuild; clear-cache.
- Progress for bounded catch-up; never block UI thread.

### U5. Native surface + navigation (M5 · 1–1.5 weeks)

- Flag + destination (rail or Settings — product choice in U0).
- Summary, provider rows, daily chart, provenance strip.
- All required states (empty, scanning, partial, stale, permission-denied, no roots).
- Reuse `BessieProviderMark` / design system.
- Pure ViewModel tests + accessibility.

### U6. Hardening + Mac verification (M6 · 1–1.5 weeks)

- `./scripts/check.sh`
- `./scripts/mac-verify.sh` with **isolated synthetic provider homes**
- Screenshot matrix: empty/partial/populated/stale/permission
- Hand-calc fixture audit; large corpus profile + cancel

### U7. Docs / roadmap honesty

- Keep roadmap outcome language.
- Document Tier 2 as **local-estimate precursor**; full U01–U02 agent/workspace slice remains future.
- Link this plan + research from `docs/roadmap/cost-and-usage.md`.

### U8. (Later plan) Provider quota Tier 3

Separate plan only after per-provider source decision checklist passes.

### U9. (Blocked) Herdr usage correlation contract

Upstream — Bessie consumes; does not invent heuristic joins.

---

## Mock → tier mapping

| Mock element | Tier |
| --- | --- |
| Screen chrome, period control, disclaimer | 1–2 |
| Total tokens (local tracked) | 2 |
| Total $ (list-rate estimate) | 2 |
| Provider breakdown (Codex/Claude local) | 2 |
| Provider plan % meters | 3 |
| By agent / by workspace | 4 |
| Ceiling / forecast / CSV / anomaly / pause | 4–5 after 4 |

---

## Risks

| Risk | Mitigation |
| --- | --- |
| Users treat estimates as invoices | Title + permanent provenance; never “Spend” alone |
| Incomplete local roots → silent undercount | “Tracked on this Mac” + incompleteReasons; never fill zeros |
| Remote herds omitted | Explicit exclusion; future Herdr path only |
| Scanner CPU / huge histories | Byte/time budgets, newest-first, resume, cancel |
| Privacy (paths/titles in logs) | Read tokens/metadata only; no cloud upload; opt-out |
| Pricing table drift | Versioned table; unpriced bucket; no fake $ |
| OAuth endpoint churn if rushed into Tier 3 | Gate Tier 3 on written contracts |
| Scope creep to CodexBar product | Hard allowlist: Codex+Claude local only |

**Open questions for Jordan (U0):**
1. Rail destination vs Settings subsection?
2. MIT adapt selective CodexBar scanner code vs clean-room rewrite?
3. Subagent/sidechain tokens: include labeled vs exclude?
4. Is 7–10 weeks still “fast follow,” or do you want Tier 1 developer prototype only until after more V1 polish?

---

## Test strategy

- **Unit:** models, aggregation TZ edges, pricing coverage, cache version rebuild, coordinator generation guards.
- **Fixtures:** sanitized Codex/Claude JSONL shapes (streaming, cumulative, archive, fork/sidechain).
- **Mac:** synthetic `HOME` trees; permission-denied; stale cache; cancel mid-scan.
- **Forbidden in CI:** live provider OAuth; reading the operator’s real credential files.

---

## Effort summary

| Package | Effort | Notes |
| --- | --- | --- |
| Tier 1 UI prototype | 1–2 weeks | Fixture only |
| Tier 2 Local Estimate Mode | **7–10 weeks** | Recommended ship |
| Tier 3 Provider quota | +6–10 weeks | After auth/contract gates |
| Tier 4 Per-agent + mock complete | +8–14 weeks after upstream contract | Cross-repo; low confidence |
| Full cumulative | ~21–34+ weeks | Not a fast follow |

Lower Tier 2 bound assumes selective MIT adaptation of proven CodexBar scanner/cache patterns. Clean-room parity trends to the upper bound.

---

## System-Wide Impact

- **Interaction graph:** Navigation → CostUsageSurface → ScanCoordinator → local FS sources. No Herdr mutations in Tier 1–2.
- **Error propagation:** Surface states only; optional Trouble breadcrumb if scan repeatedly fails.
- **State lifecycle:** Stale-first; atomic cache replace; generation-guarded refresh; terminate mid-scan safe.
- **API surface delta:** Internal Core types only until Tier 4.
- **Unchanged invariants:** Herdr owns sessions; terminals stay real; Bessie is not billing authority; closing Bessie does not alter provider accounts or local logs.

---

## Implementation Todos

- [ ] U0 Contract + corpus gate
- [ ] U1 Core models + aggregation + pricing
- [ ] U2 Codex local source
- [ ] U3 Claude local source
- [ ] U4 Scan coordinator + derived cache
- [ ] U5 Native surface + flag + navigation
- [ ] U6 Hardening + mac-verify synthetic homes
- [ ] U7 Roadmap/docs honesty pass
- [ ] (Later) U8 Provider quota plan
- [ ] (Blocked) U9 Herdr usage correlation proposal

---

## References

- Research (Amp): [`docs/research/2026-08-04-cost-and-usage-codexbar-scope.md`](../research/2026-08-04-cost-and-usage-codexbar-scope.md)
- Roadmap: [`docs/roadmap/cost-and-usage.md`](../roadmap/cost-and-usage.md)
- Workstream `FEATURE-GAP-INVENTORY.md` §1x U01–U05
- Design: workstream `source-material/design-system/screens/1x-cost-usage.html`
- CodexBar: https://github.com/steipete/CodexBar (local `/tmp/CodexBar`)
