---
name: operating-bessie
description: Operates a running Bessie app through its discoverable local intent bus using the bessie CLI or bessie-mcp. Use when an agent needs to inspect or control Bessie and Herdr-backed objects without GUI automation or terminal injection.
---

# Operating Bessie

Bessie is a graphical Herdr client. Herdr remains the source of truth and owns every live workspace, tab, pane, terminal, process, agent, and durable session fact. Bessie owns presentation preferences and Bessie Project launch recipes, not shadow live state. Quitting Bessie must leave Herdr and pane processes running.

## Discover, then call

The local Unix socket exists only while the Bessie app is running. There is no `bessie server` command or shadow daemon. Discover the effective catalog and schemas every time instead of relying on a copied command list:

```sh
bessie intents
bessie call <intent-id> --json '{"connection_id":"<id>","other_param":"<value>"}'
```

Use the returned schema exactly. Supply `connection_id` whenever an intent addresses Herdr-owned IDs; IDs are scoped to that connection.

Pane pin and snooze operations are Bessie-owned presentation mutations. Read `pane.presentation.list`, then send the exact fresh `connection_id`, `pane_id`, `terminal_id`, and `expected_revision`. Assign a stable correlation ID with CLI `--request-id <id>` or MCP `request_id`, and preserve it when retrying an identical ambiguous timeout. A revision conflict or incarnation mismatch requires a fresh list and a new ID; never extend a snooze by rebuilding a stale retry.

Use the catalog's read-only connection-context capability when you need to distinguish configured, enabled, selected/default, and currently connected herds. It can report disabled or disconnected definitions, but it cannot enable, retarget, start, or infer paths for them.

For MCP clients, launch `bessie-mcp` over stdio, call MCP `tools/list` for the effective catalog, then `tools/call` with the selected tool name and schema-shaped arguments. MCP stdout is protocol-only.

## Confirmation and failures

Destructive calls first return `needs_confirmation` with human-readable cascade text and a one-shot `confirm_token` bound to the exact intent and arguments. Review the impact, then repeat the same call with CLI `--confirm <token>` or MCP argument `confirm_token`. Never reuse, alter, or pre-approve tokens.

If Bessie is not running, live operations fail with `bessie_not_running`; start the app rather than inventing a daemon. A disconnected Herdr connection returns `not_connected`. Only catalog-marked `offline_ok` Bessie-owned reads may work without the app. Treat structured errors as authoritative and do not silently retry mutations.

## Boundaries

Do not attempt OS permission sheets, Keychain or biometric prompts, signing/notarization identity entry, secret/API-key paste, GUI puppeting, terminal-controller takeover, stopping Herdr as a synonym for quitting Bessie, or fabricated Allow/Deny actions. Never inject terminal keystrokes or text through this surface. Use only discovered intents through CLI or MCP; do not call private sockets or Herdr protocols.
