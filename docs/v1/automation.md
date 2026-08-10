# CLI, MCP, and the intent bus

Bessie exposes a narrow local automation surface for inspecting and controlling the running app. It is not a second Herdr client, a shell endpoint, or a background daemon.

## How it works

While Bessie runs, it owns an NDJSON request/response socket on the local Mac. The socket is owner-only and protected by a process lock. Both automation executables use that same bus:

- `bessie` is a command-line client.
- `bessie-mcp` is a JSON-RPC MCP server over standard input and output.

The app supplies the effective, versioned intent catalog. Each definition includes its parameter schema, owner (`bessie` or `herdr`), risk (`read`, `navigate`, `mutate`, or `destructive`), live-connection requirement, offline availability, and confirmation contract.

Always discover the effective catalog instead of keeping a second command list:

```bash
bessie intents
```

`bessie intents` asks the running app first. If Bessie is not running, it can return the CLI build's compiled catalog so an integrator can inspect schemas. Every `status` or `call` invocation still requires the app socket. An intent marked `offline_ok` can run without a live Herdr connection; it does not run without Bessie.

## CLI

The complete command shape is:

```text
bessie intents
bessie status
bessie call <intent-id> [--json '<object>'] [--confirm <token>]
```

Examples:

```bash
bessie status
bessie call connection.context --json '{}'
bessie call session.projection --json '{"connection_id":"<connection-id>"}'
bessie call pane.focus --json '{"connection_id":"<connection-id>","pane_id":"<pane-id>"}'
```

`status` is shorthand for `app.status`. `--json` must contain a JSON object. Each invocation writes one JSON result to standard output.

Exit codes:

- `0` — the intent returned a successful result;
- `1` — the intent returned a structured failure;
- `2` — command-line syntax or parameter JSON was invalid;
- `3` — the CLI could not encode its result.

Treat the structured result as authoritative. Do not scrape human-readable diagnostics when a result code and payload are available.

## MCP

Start `bessie-mcp` as a stdio MCP server. Its standard output is protocol-only.

Supported JSON-RPC methods are:

- `initialize`;
- `tools/list` — returns the effective intent catalog as MCP tools;
- `tools/call` — invokes one discovered tool with schema-shaped arguments.

Every MCP tool adds an optional `request_id` correlation field to its input schema. A destructive tool also adds `confirm_token`. Other parameters come directly from the intent definition. Clients should call `tools/list` after startup rather than assuming that a catalog copied from source is the effective runtime catalog.

## Connection and identity scope

Herdr object identifiers are scoped to a Bessie connection. Supply `connection_id` whenever a discovered schema requires it; a pane or workspace ID without its connection is not a globally safe target.

Use `connection.context` to distinguish:

- configured connections;
- enabled or disabled connections;
- the selected connection;
- the default Project target;
- current live/disconnected state.

This read does not enable a connection, retarget a Project, start a remote runtime, or infer a workspace path.

## Pin and snooze concurrency

Pin, unpin, snooze, and wake are Bessie-owned presentation mutations, but they still target an exact live pane incarnation. First call `pane.presentation.list`, then send the fresh values required by the discovered schema:

- `connection_id`;
- `pane_id`;
- `terminal_id`;
- `expected_revision`;
- and, for snooze, a supported `preset`.

Assign a stable correlation ID to each mutation. For CLI calls, pass `--request-id <id>`; for MCP calls, pass the same value as `request_id`. If a mutation times out ambiguously, retry the identical operation once with that same ID so Bessie can replay the original result without applying the transition twice. A revision conflict or terminal-incarnation mismatch instead requires a fresh list and a new operation; never retry it with stale values.

## Destructive confirmation

A destructive call does not execute on its first request. It returns `needs_confirmation`, human-readable cascade text, and a one-shot token bound to the exact intent and arguments.

After presenting and reviewing the impact, repeat the same call with:

```bash
bessie call <intent-id> --json '<same-object>' --confirm '<token>'
```

For MCP, place the token in `confirm_token`. Never reuse a token, alter the confirmed arguments, or pre-approve a destructive operation. For example, closing a Herdr workspace can stop every pane process in that workspace; quitting Bessie is not equivalent and must leave Herdr running.

## Failure handling

Common structured failures include:

- `bessie_not_running` — start the graphical app; there is no `bessie server` daemon;
- `not_connected` — connect the targeted herd before using a live intent;
- invalid parameters — rediscover the schema and correct the request;
- stale revision or pane incarnation — fetch fresh presentation state before retrying;
- `needs_confirmation` — review the cascade and use the returned one-shot token only if approved.

Do not silently retry mutations. Reads may be retried when safe. After an ambiguous mutation timeout, preserve the exact arguments and correlation ID for one replay; for any conflict or changed pane incarnation, fetch fresh state and construct a new operation.

## Safety boundary

The automation surface cannot and must not:

- grant macOS permissions;
- answer Keychain, biometric, signing, or notarization prompts;
- paste secrets;
- inject terminal text or keystrokes;
- take over a terminal controller;
- fabricate graphical Allow/Deny decisions;
- call Herdr's private protocol;
- stop Herdr merely because Bessie quits.

Use only intents returned by the effective catalog. Herdr-owned intents still execute through Herdr's public APIs, and Bessie remains a graphical client rather than a replacement runtime.
