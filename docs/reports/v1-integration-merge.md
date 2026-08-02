# V1 integration merge

**Branch:** `feat/v1-integration`  
**Tip:** see `git rev-parse HEAD`  
**Date:** 2026-08-02  
**Location:** `/home/hermes/code/bessie-wt/integration`

## Merged slices (order)

1. D production polish
2. E herd + attention
3. I appearance
4. F0 workspace FS
5. F1 follow files
6. F2 media/markdown
7. G notification polish
8. J connection UX

## Conflict resolutions

- ProductSurfaces: kept E routed types + I density + F1 follow workbench state
- WorkspaceFS: F0 hardened `resolveContainedPath` + F1 `resolvePath`/`relativePath` APIs
- BessieApp: kept D/I appearance + G notifications + J fleet start/health + E attentionAgents
- goal-progress / check.sh: unioned where needed

## Verification

- `./scripts/check.sh` passed on VPS (static only; no Swift)
- **Not** run: `mac-verify.sh`, notarization, full hands-on
- **Not** pushed

## Next

1. Mac: checkout this branch / mirror, `./scripts/mac-verify.sh`
2. Hands-on: ⌘Q, Needs-you filter, Follow, Files, remote label, appearance
3. Only then consider merge to main + K gate
