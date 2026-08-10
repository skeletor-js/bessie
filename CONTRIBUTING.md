# Contributing to Bessie

Thank you for helping make Bessie better.

Bessie is a native macOS client for Herdr. Before proposing implementation work, read [AGENTS.md](AGENTS.md), the [current V1 documentation](docs/README.md), and the [architecture guide](docs/v1/architecture.md).

## Before opening a change

- Keep Bessie a client of Herdr, never a replacement runtime or shadow session database.
- Use only Herdr's public JSON API, CLI surfaces, and terminal-session bridge.
- Keep every visible terminal on `GhosttyTerminal`; do not add terminal imitations or alternate emulators.
- Do not modify Herdr or libghostty upstream source to make Bessie work.
- Until V1 ships, limit changes to demonstrated major defects and work strictly required for the release. Open an issue before proposing broader product scope.
- Never commit credentials, local runtime state, signing material, notarization profiles, or generated release secrets.

For substantial behavior or UI changes, open an issue or discussion before investing in a large patch. Explain the user problem, the Herdr capability involved, and how the change preserves the ownership boundary.

## Development environment

The shipping target is macOS 14 or newer on Apple silicon. Native development requires Swift 6 and the Xcode command-line tools.

```bash
swift package resolve
swift build
swift test
```

Run the repository checks before submitting:

```bash
./scripts/check.sh
```

See [V1 development and verification](docs/v1/development.md) for focused test commands, repository structure, packaging boundaries, intent parity, and Mac verification.

`./scripts/mac-verify.sh` is a broad maintainer release gate, not the default contributor command. It modifies local verification state and may exercise installation paths; do not invoke it casually.

## Changes and tests

- Keep changes narrowly scoped. Avoid drive-by refactors or formatting churn.
- Add focused tests before or with behavior changes.
- Preserve fail-closed validation in compatibility, migration, packaging, update, and destructive-action paths.
- For UI changes, include current macOS screenshots and verify light/dark appearance, Reduce Motion, Increase Contrast, and keyboard accessibility where affected.
- For terminal changes, verify observable output/input against a real isolated Herdr pane in addition to unit coverage.
- Do not weaken, skip, delete, or relabel a failing check to manufacture a pass.

A pull request should state:

1. what changed and why;
2. which ownership/capability boundary it touches;
3. tests and commands actually run;
4. visual or runtime evidence where relevant;
5. known limitations or deferred follow-up.

## Licensing

By contributing, you agree that your contribution is licensed under the repository's [Apache License 2.0](LICENSE). Do not submit code, assets, marks, or generated material that you do not have the right to redistribute. Record third-party provenance and license terms when a contribution introduces or changes bundled material.

For security-sensitive reports, do not open a public issue; follow [SECURITY.md](SECURITY.md).
