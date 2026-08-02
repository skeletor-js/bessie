# Production UI/UX cleanup

**Status:** Approved
**Roadmap horizon:** V1
**Product area:** App shell, windowing, menus, chrome hygiene
**Implementation approval:** Granted by Jordan on 2026-08-02 as part of the expanded V1 release contract

## Outcome

Make Bessie behave like a normal production Mac app: standard window and quit interactions work, focus and shortcut ownership are predictable, and leftover prototype chrome is gone.

## Why this exists

Foundation preview still has desktop-polish gaps that break trust before feature depth matters—for example **⌘Q not quitting cleanly** (key routing / first-responder hijack) and missing ordinary title-bar behaviors such as **double-click to zoom/fullscreen**. Production readiness also means deleting unused or confusing UI rather than shipping every exploration surface.

## Product boundary (V1)

### In scope

- **Quit:** ⌘Q and app menu Quit always terminate Bessie cleanly without being swallowed by terminal/webview/first-responder paths; Herdr and pane processes keep running (survival rule unchanged).
- **Window chrome:** double-click title bar uses standard macOS zoom/fullscreen behavior consistent with system preference; traffic lights and full-screen transitions behave like a normal document/app window.
- **Shortcut ownership:** document which shortcuts the terminal may consume vs which the app shell always owns; fix known hijacks.
- **Chrome audit:** remove or hide unneeded prototype controls, dead navigation, placeholder panels, and exploratory UI that is not part of the V1 product surfaces.
- **Empty/error/loading consistency:** shared patterns so leftover half-states do not feel like a demo.
- **Accessibility basics:** VoiceOver labels on primary chrome; keyboard path to quit and main destinations.

### Out of scope

- Full design-token playground (see design-system customization / themes for intentional appearance prefs).
- New product surfaces not already on the V1 list.
- Changing Herdr lifecycle on quit.

## First useful milestones

1. Reproduce and fix ⌘Q / Quit menu path with and without terminal focus.
2. Title-bar double-click zoom/fullscreen + standard window behaviors.
3. App-shell vs terminal key-routing matrix for reserved shortcuts.
4. Chrome cull pass against V1 destinations only.
5. Smoke checklist on clean install build.

## Acceptance criteria

1. With focus in a live libghostty pane, ⌘Q quits Bessie; Herdr session/processes remain.
2. Double-click title bar zooms or full-screens per macOS expectation.
3. No obvious prototype-only chrome remains on primary V1 paths (Herd, workspace, Projects, Follow files, files, attention, settings, Trouble, menu bar).
4. Quit from Dock / app menu matches ⌘Q behavior.

## Unresolved decisions

- Whether “fullscreen” means macOS native full screen vs zoom-to-fill (follow system title-bar double-click preference when possible).
- Exact reserved shortcut list beyond ⌘Q / standard app menu items.
