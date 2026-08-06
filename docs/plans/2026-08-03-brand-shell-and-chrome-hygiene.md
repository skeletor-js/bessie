# Brand shell and chrome hygiene — execution plan (ce-plan)

**Date:** 2026-08-03  
**Status:** Implementation-ready  
**V1 slice:** L  
**Branch:** `feat/v1-l-brand-chrome`  
**Goal-loop ready:** Yes after I lands tokens preferred; can share branch with I if one agent owns both  
**Vision lock:** [`2026-08-02-v1-vision-occam-scope.md`](2026-08-02-v1-vision-occam-scope.md)  
**Product review:** workstream `projects/v1-release/2026-08-03-pre-v1-ui-ux-improvement-plan.md`  
**Live board:** https://skeletorjs.here.now/bessie-pre-v1-ui-review  
**Depends on:** slice I for light/dark palette API (or absorb I token table in this branch if I not merged)  
**Companion patches:** this doc owns visual contracts for Herd, Attention, workspace chrome, onboarding, Trouble; does **not** reopen Occam feature scope  

> **Superseded visual direction (2026-08-04):** `2026-08-04-001-feat-pre-v1-ui-redesign-plan.md` now governs the native floating-card shell and four-step onboarding, and explicitly includes the entity palette and menu-bar companion. Retain this plan only as historical foundation context where the newer plan does not conflict.

---

## Occam essence

**One job:** make the shipped app look and behave like finished cowprint Bessie — quiet chrome, honest empties, real Herdr panes — without new product surfaces.

**Cut everything else:**

| Cut | Why |
| --- | --- |
| Separate plans per OG screen | One visual contract set is enough |
| Menu bar, entity palette, permissions UI, full agent detail | Deferred 2026-08-03. Bounded Zen was subsequently promoted into slice M and remains outside this L plan. |
| Graphical Allow/Deny | No typed Herdr approve RPC — design-only forever until upstream |
| Layout presets / Shepherd broadcast / scrollback search | Deferred |
| Token playground / theme editor | Slice I non-goal |
| Rebuilding Herd Core builders | E already shipped; M removes duplicate Attention and L only restyles/culls chrome |

**Keep (the point):**

1. Pure achromatic light + dark cowprint.  
2. Floating plates with gaps (never full-bleed IDE).  
3. Continuous top bar (not a grey slab).  
4. Sentence case; uppercase only for group labels.  
5. One primary per surface; quiet row actions.  
6. Zero states that say truth + one next step.  
7. Onboarding + Trouble **restyle** (behavior already exists).  
8. Workspace pane titles + quiet chrome.  
9. Herd cards are quiet enough that **needs-you** is the loud signal.

---

## Vision (one paragraph — enough to decide pixels)

Bessie is a **finished Mac client for real Herdr sessions**. Trust comes from quiet, correct chrome and from never faking ownership of the runtime. White ink is reserved for **answer me**; everything else stays dim. Closing the window leaves Herdr running — copy and layout must say so.

---

## 1. Outcome

After L:

1. Light mode is pure greyscale cowprint (not cream/Hearth).  
2. Cowprint prints on light and dark (window ~13%, cards ~5% when enabled).  
3. Main content top bar matches the main plate (no third grey band).  
3a. **Native traffic-light title strip is transparent when windowed** (implemented and captured): stoplights float over desk/cowprint; no solid system-grey/material titlebar bar. Double-click zoom/fullscreen from slice D remains installed.
4. Desk gap between rail and main remains (`cardGap`); pane tiles keep `paneGap`.  
5. Type: sentence case on titles/buttons; tracked uppercase only on group labels.  
6. No shadow elevation on product chrome (hairlines only).  
7. Control noise gone: one white primary per surface; kebab without chevron; one overflow; one follow control; no dual Open-as-primary on every row.  
8. Status words not shouted as badges (no LIVE/LOCAL/ACTIVE uppercase soup).  
9. Pane labels prefer process/cwd/agent over “Untitled pane”.  
10. Empty states: second line is **what to do**, not a repeat of the title.  
11. Onboarding matches design-system structure (steps + survival line), flat cowprint shell.  
12. Trouble uses floating plate + rail layout (not full-bleed single card).  
13. Files: rename/move/trash only when selection exists; no dual-verb jammed labels.  
14. Project launch review includes reverse-line before confirm (“what Herdr will be asked to do”).  
15. Re-capture of the 14 live surfaces passes the brand checklist in §7.

---

## 2. Token table (owns with slice I)

Implement in `BessieDesign.palette(for:)` — **hex intent** (Swift `Color` OK as sRGB):

### Dark cowprint (confirm / keep close to current)

| Token | Hex / value |
| --- | --- |
| desk | `#070707` |
| window | `#050505` |
| background (main plate) | `#0E0E0E` |
| rail | `#0A0A0A` |
| panel | `#161616` |
| inset | `#111111` |
| code | `#080808` |
| strong | `#F5F5F5` |
| text | `#B6B6B6` |
| subtle | `#8A8A8A` |
| faint | `#5F5F5F` |
| border | white 10% |
| borderStrong | white 19% |
| accent | `#FFFFFF` |
| accentForeground | `#000000` |
| blocked / err | `#FFFFFF` |
| running | `#9A9A9A` |
| done | `#DCDCDC` |
| idle | `#5F5F5F` |

### Light cowprint (replace warm cream)

| Token | Hex / value |
| --- | --- |
| desk | `#E8E8E8` |
| window | `#F0F0F0` |
| background | `#FAFAFA` |
| rail | `#F5F5F5` |
| panel | `#FFFFFF` |
| inset | `#F0F0F0` |
| code | `#0C0C0C` (terminal plate may stay dark independently) |
| strong | `#0C0C0C` |
| text | `#3A3A3A` |
| subtle | `#5A5A5A` |
| faint | `#8A8A8A` |
| border | black 10% |
| borderStrong | black 18% |
| accent | `#0C0C0C` (primary fill) |
| accentForeground | `#FFFFFF` |
| blocked | `#0C0C0C` |
| running | `#6A6A6A` |
| done | `#2A2A2A` |
| idle | `#8A8A8A` |

### Cowprint texture

| Surface | Dark ink | Light ink |
| --- | --- | --- |
| Window plate | white @ ~3–4% (existing crops OK) | black @ ~13% field / reverse print |
| Cards / panels | white @ ~2–5% | black @ ~5% |

When `cowprintEnabled == false`, solid plate colors only.

### Top bar surface rule

`BessieTopBar` background = **same as main plate** (`background`), not `window`/`rail`/`inset`. Optional bottom hairline `border`. Never a distinct third grey.

### Traffic lights + transparent title strip

- System **colored** traffic lights in AppKit titlebar (not mono greys).
- **Windowed title strip is transparent:** `titlebarAppearsTransparent`, `.fullSizeContentView`, hidden window-toolbar background, adaptive window/desk `backgroundColor`. Desk/cowprint shows through under the lights.
- Floating rail/main cards stay safe-area inset with desk gaps — only the desk plate paints the strip, not a solid system material bar.
- Do not break double-click titlebar zoom/fullscreen (slice D).

### Elevation

No drop shadows on cards, sheets, or Trouble. Border + plate only.

---

## 3. Surface visual contracts

### 3.1 Shell / density

- Keep `cardGap` (default 9) between desk / rail / main.  
- Keep `paneGap` (default 7) between pane tiles.  
- Do not stretch panes to fill window edge-to-edge under the rail.  
- Sheets: flat panel, hairline, sentence-case buttons.

### 3.2 Type and badges

| Element | Case |
| --- | --- |
| Window titles, top bar titles, buttons | Sentence case |
| Group labels in rails/settings sections | Uppercase + tracking OK |
| Filter chips | Sentence or short title — **not** ALL CAPS status |
| Connection facts | Plain sentence or mono detail — **not** LOCAL + Local + INCLUDED |

Remove or demote uppercase status chips: LIVE, LOCAL, INCLUDED, ACTIVE, NO CHANGES FROM GIT HEAD → sentence or mono faint line.

### 3.3 Controls

- **One** filled primary (accent) per surface/sheet.  
- Row “Open” → quiet border/ghost, not second white primary.  
- Overflow = `···` only (no `···∨`).  
- Workspace: single overflow menu (merge Pane actions ∨ + ···).  
- Agent detail: one control for follow-latest vs pin (not both inverted).  
- Sheets: either × **or** Cancel, not both (prefer Cancel + Esc; keep × if sheet standard — pick one pattern app-wide).

### 3.4 Herd (visual only; E logic stays)

- Card: identity, state glyph, location, connection once, optional title.  
- Primary action: quiet Open; Details secondary.  
- Empty: title once; detail = next step (“Open a workspace” / “Start a process” / filter hint).  
- No accent dilution from white Open on every card.

### 3.5 Attention (visual only; E logic stays)

- List: blocked first, then done; age optional if already cheap.  
- **Only action: Open pane.**  
- No Allow/Deny/approve card.  
- Empty: “Nothing needs you” + one line if useful (“Agents will show up here when they wait on you”).

### 3.6 Workspace tiled panes

- Pane chrome title: `label ?? agent ?? title ?? cwd/process-derived ?? "Shell"`.  
- Blocked pane: clear state on tile head (glyph + “needs you”), not only buried menu.  
- Quiet overflow; no dual menus.  
- Preserve gaps; zoom remains product zoom (not Zen).

### 3.7 Onboarding restyle

Behavior exists (bundled-runtime train complete). L only:

- Flat cowprint shell; no drop shadow card.  
- Step list structure from OG `1n` where it matches real milestones.  
- Survival copy visible: quitting leaves Herdr running.  
- Light mode uses light cowprint tokens.  
- Primary: one Open/Continue; Skip quiet.

### 3.8 Trouble restyle

- Layout: rail + main plate (or floating card on desk), **not** full-bleed content.  
- Banner: connection/runtime fact + one safe action + link to logs.  
- Always honest about Herdr possibly still running.  
- No mono-painted traffic lights; system titlebar unchanged.

### 3.9 Files / Projects hygiene

- Files: disable rename/move/trash with nothing selected; split or clarify labels (“Rename” / “Move” separate if both exist).  
- Headings weight medium (500), not bold display.  
- Project review sheet: short reverse list of Herdr creates before Confirm.

### 3.10 Palette (commands only)

Visual hygiene only if touched: section labels, row meta. **No** entity index (deferred).

---

## 4. Architecture approach

1. **Tokens first** — fix `BessiePalette` light ladder + cowprint light inks in `BessieDesignSystem.swift` (coordinate with I).  
2. **TopBar** — `BessieTopBar` uses `background` + hairline.  
3. **Shared empty component** — one `ProductEmptyState` API: title, detail (action-oriented), optional single action.  
4. **Copy pass** — sentence case helpers only if needed; prefer direct string fixes + `scripts/check-ui-copy.sh` if present.  
5. **Surface edits** concentrated in `ProductSurfaces.swift`, onboarding/Trouble views, Projects sheets — no new modules unless empty-state extraction is cleaner.  
6. **Snapshot** — reuse design-preview / window snapshot path for 14-surface re-capture.

Do **not** change Herdr protocol, quit survival, or Attention/Herd filter semantics.

---

## 5. Files

| File | Change |
| --- | --- |
| `Sources/BessieApp/BessieDesignSystem.swift` | Light achromatic tokens; top bar; cowprint light; TopBar bg |
| `Sources/BessieApp/ProductSurfaces.swift` | Herd/Workspace/Files chrome + empties + badges; M removes Attention |
| Onboarding / Trouble views (paths as in tree) | Restyle layout + copy |
| `ProjectsSurface.swift` / `ProjectEditorView.swift` | Case, review reverse-line, primary buttons |
| `BessieSettings.swift` | Connection row de-dupe labels if still noisy |
| `PresentationPersistence` | only if cowprint light needs a pref (prefer none) |
| `docs/plans/2026-08-02-design-system-customization.md` | Token table pointer |
| `scripts/check.sh` / `check-ui-copy.sh` | Case/badge guards if cheap |
| Evidence §11 | Fill on Mac |

---

## 6. Milestones

### M0 — Inventory map (half day)

List each brand violation → file/symbol. No drive-by refactors.

### M1 — Tokens + top bar + gaps

Light achromatic palette live; cowprint on light; TopBar continuous; gap constants respected on shell.

**DoD:** Light + Dark screenshots of Herd shell; no cream; content top bar not third grey; **windowed** traffic-light strip transparent over desk/cowprint (not solid grey).

### M2 — Type, badges, controls

Sentence case pass; badge cull; control dedupe on Herd, Workspaces list, Workspace, Projects, Settings.

**DoD:** No LIVE/LOCAL shout on primary paths; one primary per surface sample.

### M3 — Empties + Files + Project review

Empty matrix; files selection gating; project reverse-line.

### M4 — Onboarding + Trouble restyle

Plate layouts; survival copy; light-safe.

### M5 — Workspace pane chrome

Titles, blocked head, single overflow.

### M6 — Re-capture + brand checklist

14 surfaces; board or local HTML update optional; check.sh green.

---

## 7. Brand acceptance checklist (release gate for L)

- [x] Light: no warm hue on shell plates  
- [x] Light + dark: cowprint when enabled  
- [x] Top bar continuous with main plate  
- [x] Gaps visible rail↔main and pane↔pane  
- [x] No card drop shadows  
- [x] System traffic lights  
- [x] Sentence case on buttons/titles  
- [x] Uppercase only group labels  
- [x] One primary per surface (sampled: Herd, Projects, sheets)  
- [x] Kebab without chevron  
- [x] Single workspace overflow  
- [x] No dual follow/pin  
- [x] Connection not labeled three ways  
- [x] No Untitled pane when process/cwd known  
- [x] Empties: non-repeating detail line  
- [x] Trouble not full-bleed  
- [x] Onboarding flat + survival line  
- [x] Files actions gated on selection  
- [x] Project review reverse-line  
- [x] No graphical Allow/Deny  
- [x] No Zen / menu bar / entity palette / permissions UI  

---

## 8. Acceptance criteria

1. §7 checklist green on re-capture.  
2. Slice I acceptance still holds (theme switch, density, cowprint toggle).  
3. Herd Open pane behavior remains correct; M folds needs-you routing into Herd.  
4. Quit still does not stop Herdr (D).  
5. `./scripts/check.sh` green.  
6. No Deferred features introduced.

---

## 9. Non-goals

- Zen mode  
- Menu-bar status item  
- Entity-aware palette  
- Permissions inventory  
- Agent detail trace/diff/provenance overhaul  
- Graphical approval / typed allow-once  
- Layout presets, Shepherd broadcast, search-the-herd  
- General code editor  
- Warm “paper” alternate palette in shipping UI  

---

## 10. Parallelism

| Slice | Relation |
| --- | --- |
| I Appearance | **Merge or co-own tokens** — L requires light ladder; prefer I first or one branch |
| D Production polish | Independent; L does not redo quit/zoom |
| E Herd baseline | Done for initial logic; M removes duplicate Attention; L visual only — coordinate `ProductSurfaces` ownership |
| J Connection UX | Labels may overlap; take J’s connection label helper, don’t fork |
| F* Files | L only gating/labels; F owns viewer features |
| K Hardening | After L visual gate preferred |

**Worktree:** solo brand branch; do not pair with F file editing.

---

## 11. Evidence log (fill during execution)

| Milestone | Evidence | Date |
| --- | --- | --- |
| M1 tokens + shell | Achromatic §2 ladder implemented. Light mode uses a real black RGBA tile generated from the cowprint alpha mask; dark retains original white artwork. Root cowprint ignores safe areas. Window toolbar background is hidden; AppKit uses transparent titlebar/full-size content and adaptive desk backing. `dist/Bessie-herd-light.png`, `dist/Bessie-workspace-light.png`, and `dist/Bessie-titlebar-windowed.png` confirm visible cowprint and cowprint beneath native traffic lights. | 2026-08-03 |
| M2 chrome cull | Sentence-case actions, restrained counts/status, connection-label de-duplication, quiet row actions, one workspace overflow, and one Follow Files control implemented. UI-copy check passed. | 2026-08-03 |
| M3 empties / Files / Projects | Honest action-oriented empties implemented; Files clears stale selections and separately gates rename, move, and trash; launch review lists the exact Herdr create sequence before confirmation. | 2026-08-03 |
| M4 onboarding/Trouble | Flat rail/content-plate layouts implemented with Herdr-survival copy and no product-card shadow. Four runtime failure captures plus `dist/Bessie-onboarding.png` passed the Mac verifier. | 2026-08-03 |
| M5 workspace chrome | Pane titles derive from label/agent/title/CWD/process before `Shell`; needs-you state is visible; pane actions use quiet single-locus overflow. Projection test added; light workspace capture confirms readable terminals and pane gaps. | 2026-08-03 |
| M6 capture + install | Historical pre-remediation capture matrix included Herd and the now-removed Attention surface plus Workspaces, Workspace, Agent detail, process sheet, Projects, Files, Settings, project sheets, Onboarding, Trouble variants, explicit light surfaces, and windowed titlebar. Packaged app installed and relaunched; packaged/installed SHA-256 both `89396ef50b2fdebc5080e2b1e738d122e2d4c6724ddafa7d16e466377d1407fb`; `cmp=passed`. | 2026-08-03 |
| check.sh / Mac | VPS `./scripts/check.sh` exit 0. Final `./scripts/mac-verify.sh` exit 0: 227 XCTest cases and 21 intent/CLI tests passed with zero failures; live Herdr/libghostty, quit survival, package/sign, screenshots, install, identity, and relaunch passed. | 2026-08-03 |

---

## 12. Pause conditions

Stop and ask Jordan if:

1. Light cowprint makes libghostty unreadable and terminal cannot stay independent.  
2. Titlebar/TopBar structure cannot be continuous without multi-day window rewrite.  
3. Scope pressure to unpark Zen / menu bar / approve card / entity palette.  
4. Product wants Needs-you filter semantics changed (belongs to E, not L).

---

## 13. Implementation order (agent)

```text
1. Branch feat/v1-l-brand-chrome (or feat/v1-i-appearance if absorbing tokens)
2. M0 inventory
3. M1 tokens + TopBar + gaps
4. M2 type/badges/controls
5. M3 empties/files/projects
6. M4 onboarding/Trouble
7. M5 workspace chrome
8. M6 recapture + checklist + check.sh
9. Stop — do not start Deferred work
```

---

## 14. Done means

L is done when §7 is evidenced and the app is visually shippable as cowprint Bessie — not when a subset of strings were renamed.
