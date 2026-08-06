# Appearance (themes) — execution plan (ce-plan)

**Date:** 2026-08-02  
**Updated:** 2026-08-03 (achromatic light lock + top bar surface; points at slice L)  
**Status:** Implementation-ready  
**V1 slice:** I  
**Branch:** `feat/v1-i-appearance`  
**Goal-loop ready:** Yes; low coupling; can parallel after D  
**Occam lock:** Dark/Light cowprint, density, cowprint texture **on/off** — no token playground  
**Brand chrome (case, badges, surface restyles):** [`2026-08-03-brand-shell-and-chrome-hygiene.md`](2026-08-03-brand-shell-and-chrome-hygiene.md) (slice L)  
**Jordan lock:** pure achromatic light cowprint (2026-08-03); system traffic lights  

---

## Occam essence

**I only:** switchable Dark/Light cowprint tokens, density metrics, cowprint on/off.  
**Not I:** sentence case, Herd card redesign, onboarding/Trouble layout — that is L.

---

## 1. Outcome

1. User picks **Dark** or **Light** (and **System** if `BessieAppearance` already has it — wire all cases).  
2. App no longer hard-forces `.preferredColorScheme(.dark)` ignoring prefs.  
3. **Density:** Comfortable / Compact adjusts spacing (rail, row height, card gap, topbar).  
4. **Cowprint texture:** on/off (keep intensity/motion prefs if present).  
5. Terminal remains readable; pane chrome follows density; no per-token editor UI.  
6. Light palette is **pure achromatic cowprint** (not warm cream).

---

## 2. Substrate

| Piece | Path |
| --- | --- |
| Prefs | `BessieAppearance`, `BessiePreferences` in `PresentationPersistence.swift` |
| Settings UI | `BessieSettings.swift` |
| Tokens | `BessieDesign` / `BessiePalette` in `BessieDesignSystem.swift` |
| Force dark | `BessieApp` `.preferredColorScheme` |

---

## 3. Architecture

### 3.1 Semantic tokens

Keep `BessiePalette` + `palette(for: ColorScheme)`.

**Canonical hex table:** slice L §2 (single source). Summary:

- **Dark:** existing charcoal ladder (`#0E0E0E` main, white accent) — keep.  
- **Light:** greyscale reverse — main `#FAFAFA`, ink `#0C0C0C`, accent `#0C0C0C` on white fg, **no** warm RGB drift.  
- Replace current light values that use warm cream (`0.975, 0.965, 0.93` etc.).

### 3.2 Top bar surface (I or L — do once)

`BessieTopBar` fill = `background` (main plate), hairline optional. Not `window`/`inset` grey band.  
If I ships first without full L, still land this rule so Light/Dark don’t paint a third slab.

### 3.3 Density

```swift
enum BessieDensity: String, Codable { case comfortable, compact }

struct BessieDensityMetrics {
  var rowHeight: CGFloat
  var cardGap: CGFloat
  var railWidth: CGFloat
  var topbarHeight: CGFloat
  // etc
}
```

Views read `EnvironmentKey` `bessieDensity`. Defaults must preserve **cardGap ≥ 6** and **paneGap ≥ 5** so L’s “no full-bleed” rule holds in Compact.

### 3.4 Cowprint toggle

`preferences.cowprintEnabled: Bool` — texture off → solid plates.  
Light mode cowprint uses **dark ink on paper** at window ~13% / cards ~5%.

### 3.5 preferredColorScheme

Map appearance pref → `.dark` / `.light` / `nil` for system.

### 3.6 Traffic lights

No code to recolor system traffic lights. Mono greys = design canvases only.

---

## 4. Files

- `PresentationPersistence.swift` — density + cowprintEnabled defaults  
- `BessieDesignSystem.swift` — achromatic light palette + TopBar bg + metrics  
- `BessieSettings.swift` — appearance controls  
- `BessieApp.swift` — color scheme binding  
- Product surfaces — environment metrics where hard-coded spacing is worst  
- Tests: decoding defaults for new pref keys  

---

## 5. Milestones

| M | Work |
| --- | --- |
| M1 | Pref fields + settings UI + colorScheme wiring |
| M2 | **Achromatic** light palette across shell (replace cream) |
| M3 | Density environment + key surfaces; gap floors |
| M4 | Cowprint on/off including light inks |
| M5 | TopBar continuous plate; optional screenshots; check.sh |

---

## 6. Acceptance

1. Switching Light/Dark updates chrome without restart.  
2. Light shell shows **no warm hue** on desk/window/background/rail/panel.  
3. Density changes list/card spacing on Herd/Settings.  
4. Compact still shows rail/main gap.  
5. Cowprint off removes texture; on shows print in both themes.  
6. Prefs persist across launch.  
7. No token studio UI.  
8. Top bar not a distinct grey band.  
9. check.sh green.  

---

## 7. Non-goals

- Terminal theme marketplaces, custom hex editors, menu bar icon themes  
- Full brand hygiene (case, badges, onboarding layout) — **slice L**  
- Ember/Hearth warm palette in shipping UI  

---

## 8. Pause

Light palette clashes with libghostty default colors badly → keep terminal independent (dark terminal plate OK inside light shell); document. Do not invent a second product theme.

---

## 9. Parallelism

- Prefer merge D before heavy `BessieApp` edits.  
- L may absorb M2/M5 if one agent owns brand end-to-end — then mark I token acceptance inside L evidence and close I.  
- Do not start Deferred appearance work (icon packs, per-surface themes).
