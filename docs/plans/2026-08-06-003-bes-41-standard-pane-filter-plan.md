# BES-41 — Standard pane filtering for “All Workspaces” and “All Tabs”

**Date:** 2026-08-06
**Issue:** BES-41
**Status:** Ready for implementation

## Objective

Make **All Workspaces** and **All Tabs** ordinary scope selections in the same sidebar + panes-view interaction used for a specific workspace or tab. The All choices broaden which Herdr-owned panes are included; they must not create an overview mode, render a grid/stack of live terminal layouts, start extra terminal surfaces, or rearrange Herdr state.

## Current-state finding

The dirty branch already contains a provisional aggregate implementation in `Sources/BessieApp/ProductSurfaces.swift`:

- `WorkspaceScopeProjection` expands a scope into one `WorkspaceScopeGroup` per tab/layout.
- `WorkspaceSurface` switches to a `ScrollView` of `AggregatePaneGroup` values when `workspaceScope` is non-nil.
- Each `AggregatePaneGroup` renders a `ProductPaneLayout`, which materializes many small live terminal surfaces.

That is exactly the behavior BES-41 rejects. Preserve the unrelated command-palette and other pre-existing dirty work; do not reset or rewrite the checkout.

## Implementation

1. **Model All as filter breadth, not presentation mode.**
   - Keep connection/workspace/tab-qualified pane identities so duplicate Herdr IDs remain safe.
   - Derive the pane rows/targets matching these scopes: one tab, all tabs in the selected workspace, or all workspaces in the selected connection.
   - Do not derive or render one terminal layout per matching tab.

2. **Use the standard sidebar and panes selection path.**
   - Route individual workspace/tab choices and All choices through one selection/filter reducer.
   - The hierarchy labels, selected-state styling, pane count, and mutation availability must reflect the active scope consistently.
   - Switching scopes should preserve the normal selected-pane fallback: retain a still-visible selected pane; otherwise choose the normal focused/first matching pane without mutating Herdr layout.

3. **Render matching panes in the existing panes view.**
   - Remove/bypass `AggregatePaneGroup` and the aggregate `ScrollView` of `ProductPaneLayout` terminal grids.
   - Show the matching pane entries through the ordinary panes view/filter UI. Opening one pane should follow the existing routed-pane path and display only the normal selected terminal surface/layout.
   - Merely choosing All Workspaces or All Tabs must not instantiate, prewarm, duplicate, focus, resize, or rearrange every matching terminal.

4. **Keep Herdr ownership and connection routing intact.**
   - Filter only fresh authoritative snapshots.
   - Keep connection-qualified routes and use existing `openRoutedPane` behavior when the user chooses a pane.
   - No new persistence of live workspace/tab/pane state.

5. **Focused coverage only.**
   - Add or adjust focused model tests proving individual vs All Workspace/All Tabs membership, order, duplicate-ID connection scoping, selected-pane retention/fallback, and that All selection maps to filtering rather than aggregate terminal presentation.
   - Do not run broad test suites. Run only the smallest relevant Swift test filters or compile checks needed to catch obvious breakage.

6. **Mac package and install.**
   - Sync the dirty working tree intentionally to `/Users/jordanstella/GitHub/bessie` on `jordan-macbook` without `--delete` and without clobbering unrelated work.
   - Build/package `dist/Bessie.app`, install it as `/Applications/Bessie.app`, relaunch it, and verify the installed executable hash matches the packaged executable.
   - Jordan will perform hands-on UI acceptance, so do not spend time on a large test matrix or screenshot QA.

7. **Record evidence.**
   - Update `docs/reports/goal-progress.md` with changed files and actual focused build/install/hash results.
   - Leave the repository uncommitted; do not push or open a PR.

## Acceptance checklist

- Individual workspace and All Workspaces use the same filter/selection machinery.
- Individual tab and All Tabs use the same filter/selection machinery.
- The sidebar consistently displays the selected scope and matching pane count.
- The ordinary panes view contains all and only panes in scope.
- All selection alone creates/opens no terminal and renders no terminal-tile overview.
- Switching scopes retains a valid selected pane or uses the standard fallback.
- Focused tests/compile checks pass.
- The latest packaged app is installed and relaunched on Jordan’s Mac with matching executable hashes.
