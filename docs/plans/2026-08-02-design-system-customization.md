# Appearance (themes) — execution plan (ce-plan)

**Date:** 2026-08-02
**Status:** Implementation-ready
**V1 slice:** I
**Branch:** `feat/v1-i-appearance`
**Goal-loop ready:** Yes; low coupling; can parallel after D
**Occam lock:** Dark/Light cowprint, density, cowprint texture **on/off** — no token playground

## 1. Outcome

1. User picks **Dark** or **Light** (and optional System if already in `BessieAppearance` — wire all enum cases that exist).
2. App no longer hard-forces `.preferredColorScheme(.dark)` ignoring prefs.
3. **Density:** Comfortable / Compact adjusts spacing constants (rail padding, row height, card gap, topbar).
4. **Cowprint texture:** on/off (and keep existing intensity/motion prefs if present).
5. Terminal remains readable; pane chrome follows density; no per-token editor UI.

## 2. Substrate

| Piece | Path |
| --- | --- |
| Prefs | `BessieAppearance`, `BessiePreferences` in `PresentationPersistence.swift` |
| Settings UI | `BessieSettings.swift` |
| Tokens | `BessieDesign` hard-coded dark |
| Force dark | `BessieApp` `.preferredColorScheme(.dark)` |

## 3. Architecture

### 3.1 Semantic tokens

```swift
enum BessieDesign {
  // Replace static lets with functions or computed from palette:
  static func palette(for scheme: ColorScheme) -> BessiePalette
}

struct BessiePalette {
  let window, panel, text, strong, border, ...
}
```

Light palette: warm off-white desk / dark ink text per brand (cowprint identity) — not pure system gray only.

### 3.2 Density

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

Views read metrics from EnvironmentKey `bessieDensity`.

### 3.3 Cowprint toggle

`preferences.cowprintEnabled: Bool` — `BessieCowprintTexture` returns plain base color when off.

### 3.4 preferredColorScheme

Map appearance pref → `.dark` / `.light` / nil for system.

## 4. Files

- `PresentationPersistence.swift` — density + cowprintEnabled fields with defaults
- `BessieDesignSystem.swift` — palettes + metrics
- `BessieSettings.swift` — controls
- `BessieApp.swift` — color scheme binding
- Product surfaces — use environment metrics where hard-coded spacing is worst
- Tests: decoding defaults for new pref keys

## 5. Milestones

M1 Pref fields + settings UI + colorScheme wiring
M2 Light palette applied across shell (not every pixel perfect)
M3 Density environment + key surfaces
M4 Cowprint on/off
M5 Visual verify dark/light screenshots optional; check.sh

## 6. Acceptance

1. Switching Light/Dark updates chrome without restart.
2. Density changes list/card spacing on Herd/Attention/Settings.
3. Cowprint off removes texture.
4. Prefs persist across launch.
5. No token studio UI.
6. check.sh green.

## 7. Non-goals

Terminal theme marketplaces, custom hex editors, menu bar icon themes.

## 8. Pause

Light palette clashes with libghostty default colors badly → document and keep terminal independent with minimal chrome-only light mode if needed.
