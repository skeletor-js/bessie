# Bessie landing design oracle

Source design canvas ingested 2026-08-04 from Mac path:

`workstreams/bessie/inbox/Bessie Landing.html`

## Production plan

Implementation plan: [`../../plans/2026-08-04-002-feat-bessie-dev-landing-page-plan.md`](../../plans/2026-08-04-002-feat-bessie-dev-landing-page-plan.md)

Production code belongs in repo `site/` (created during plan execution), not here.

## Key extracted files

| File | Use |
|---|---|
| `Bessie Landing.html` | Original design-canvas bundle (do not ship) |
| `landing-dom.html` | Page structure and copy |
| `landing-component.js` | Cold-open cowprint, scroll motion, clipboard, links |
| `all.css` | Design-system + icon CSS to prune |
| `dc-props.json` | Canvas tweak defaults |
| Fonts / SVGs / PNG | Asset inputs for subsetting |

## Notes

- Title: **Bessie — every agent, one window**
- Dark-only Coals marketing page
- Install string in the design defaults to `bessie.sh`; production plan standardizes on `bessie.dev/install`
- Syncthing inbox should not remain the only copy of the multi-MB HTML
