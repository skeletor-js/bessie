# Security policy

## Supported versions

Bessie supports the latest published version, currently `1.0.0`. Older candidates, verification bundles, and development builds may be used to reproduce an issue but are not maintained public releases.

## Report a vulnerability privately

Please do **not** open a public GitHub issue for a suspected vulnerability.

Use GitHub's private vulnerability-reporting flow for [`skeletor-js/bessie`](https://github.com/skeletor-js/bessie/security/advisories/new). If that flow is unavailable, email [hello@bessie.dev](mailto:hello@bessie.dev) and ask for a secure reporting channel without including exploit details in the first message.

Include, when safe:

- the affected Bessie version/build and macOS version;
- whether the issue involves local or SSH-connected Herdr;
- reproduction steps and the expected versus observed behavior;
- security impact and any known preconditions;
- logs or screenshots with credentials, hostnames, tokens, paths, and personal data removed;
- whether the issue has been disclosed anywhere else.

Do not send private keys, passwords, signing/notarization material, Sparkle private keys, full environment files, or live user data.

## Scope

Security-sensitive areas include:

- command or input injection across local and SSH connection boundaries;
- path traversal, symlink escape, or unsafe file operations;
- unauthorized terminal takeover or destructive Herdr mutations;
- intent-bus confirmation bypass or unauthorized local socket access;
- update signature, archive identity, notarization, or appcast failures;
- credential or secret persistence/logging;
- migration rollback, ownership-marker, or configuration-integrity failures;
- bundled runtime or dependency supply-chain issues.

Herdr vulnerabilities that reproduce independently of Bessie should also be reported to the Herdr project through its preferred private channel. Bessie-specific reports should still explain the Herdr version and public surface involved.

## Disclosure

The maintainers will validate reports, coordinate remediation, and credit reporters who want attribution when it is safe to do so. Please allow a reasonable remediation window before public disclosure and coordinate disclosure timing for issues that affect users or upstream projects.
