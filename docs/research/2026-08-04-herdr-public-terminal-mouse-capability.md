# Public Herdr terminal mouse capability for native clients

**Status:** Upstream capability proposal; Bessie implementation blocked  
**Audited:** 2026-08-04  
**Runtime:** Herdr 0.8.0, protocol 19  
**Artifact SHA-256:** `d53a9f93fccfdfcc55632927bf51002f5add0aa7990bcdf508ffbd84ac658178`

## Current public gap

Bessie's live spike re-audited the bundled `herdr terminal session control` bridge, the public API schema, the protocol-19 snapshot, and the retained Herdr capability map. The controller publicly supports raw input, resize, vertical scroll/page operations, and release. It does not expose a typed public command or negotiated capability for:

- pointer button down or up;
- drag or pointer motion;
- horizontal wheel input;
- the Herdr-owned terminal application's current mouse-reporting/capture mode.

The full Herdr client has structured mouse input internally, but that is not a public external-client contract. Bessie must not copy the private bincode protocol, infer mouse mode from ANSI output or foreground processes, or ask its local rendering-only libghostty instance to encode mouse escape sequences. Until a public capability lands, Bessie keeps `mouse-reporting=false`, uses pointer gestures for local selection/focus, and routes vertical wheel scrolling through Herdr's existing public `terminal.scroll` command.

## Proposed negotiated capability

Add a versioned terminal-controller capability advertised when control/observe starts, or through an explicit controller handshake:

```json
{
  "type": "terminal.capabilities",
  "mouse_input": {
    "version": 1,
    "buttons": true,
    "motion": true,
    "horizontal_wheel": true,
    "capture_state": true
  }
}
```

Absence means unsupported. Clients must not infer support from the Herdr protocol number alone. Observe-mode clients may receive capture-state updates but must not be allowed to submit pointer input.

## Proposed controller commands

Use cell coordinates because Herdr owns the authoritative grid and terminal modes. Coordinates are zero-based and must be validated against the controller's current grid.

```json
{"cmd":"terminal.mouse","version":1,"kind":"button","button":"left","pressed":true,"column":12,"row":4,"modifiers":["control"]}
{"cmd":"terminal.mouse","version":1,"kind":"motion","column":13,"row":4,"buttons":["left"],"modifiers":[]}
{"cmd":"terminal.mouse","version":1,"kind":"wheel","delta_x":-1,"delta_y":0,"column":13,"row":4,"modifiers":[]}
```

Required fields and behavior:

- `kind`: `button`, `motion`, or `wheel`;
- buttons: `left`, `middle`, `right`, plus numbered extension buttons only when advertised;
- `pressed` for button transitions;
- current `buttons` for drag/motion state;
- signed, bounded wheel deltas for both axes;
- explicit modifiers from a closed set: `shift`, `control`, `alt`, `super`;
- cell `column` and `row`, with no client-generated ANSI bytes;
- one ordered input stream with existing key/text/paste input so pointer and keyboard actions cannot reorder.

Herdr must encode or suppress terminal sequences from its authoritative runtime mode. Unsupported/out-of-grid/malformed events should return a typed controller error rather than closing the stream.

## Authoritative capture-state events

Herdr should publish state whenever the inner application changes mouse reporting:

```json
{
  "type": "terminal.mouse_capture",
  "version": 1,
  "enabled": true,
  "motion": "button",
  "encoding": "sgr",
  "grid_sequence": 481
}
```

`enabled` and `motion` are the client-facing contract. `encoding` is diagnostic only; the client never encodes it. `grid_sequence` binds hit testing to an authoritative viewport generation. A controller reconnect starts with capture unknown/disabled until Herdr sends a fresh state.

## Bessie routing once negotiated

When `mouse_input.version == 1` and authoritative capture is enabled:

1. Convert AppKit positions through libghostty's public cell hit-testing/metrics.
2. Send button, drag, motion, and wheel events through the typed Herdr command.
3. Reserve Shift as the documented host-selection override; Shift-drag stays local and is not also sent to Herdr.
4. Keep pane chrome, split dividers, and out-of-grid events local.
5. Do not also scroll Herdr history when a captured wheel event is submitted.
6. On unknown capability/capture state, fall back to local selection plus existing public vertical scroll, never ANSI guessing.

## Acceptance proof

The capability is not complete until the packaged Bessie app proves on a live Herdr-owned pane:

- click, release, drag, hover/motion, and vertical/horizontal wheel behavior in two mouse-aware TUIs, including Hermes;
- Shift-drag local selection while capture is enabled;
- no duplicate wheel action and no pointer/key input reordering;
- correct behavior after alternate-screen entry/exit, resize, reconnect, observe/control conflict, and explicit takeover;
- malformed/out-of-grid input rejection without process or controller loss;
- quitting Bessie releases only its controller and leaves Herdr and pane processes alive.

No mouse-aware TUI support should be claimed before that proof.
