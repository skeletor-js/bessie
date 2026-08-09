# Bessie release preparation and verification

This runbook covers the BES-3 U5 boundary: create signed, notarized, stapled, immutable local release bytes and a staged signed appcast. It does not publish a GitHub release, upload an asset, deploy Cloudflare, change repository visibility, install Bessie, or update the production feed.

## Boundaries

- `./scripts/release-app.sh prepare ...` is credentialed and macOS-only. Run it on Jordan's trusted Mac after separate authorization. It reads a Developer ID identity, a named `notarytool` Keychain profile, and Sparkle's Keychain-backed Ed25519 key. It never publishes.
- `./scripts/release-app.sh verify PREPARED_DIRECTORY` is offline and secret-free. Against a separately trusted `release.json`, it checks internal consistency: final archive SHA-256 and length, checksum file, exact version/build/tag and URLs, minimum macOS, full-archive-only feed structure, signature metadata, signed-feed trailer shape/length, and the recorded preparation sequence.
- `./scripts/release-app.sh publish PREPARED_DIRECTORY` intentionally verifies and then refuses. GitHub draft upload, immutable-release publication, anonymous asset verification, and appcast deployment belong to later operator-approved U8 work. The appcast remains the final client-exposure step.

Ordinary `./scripts/check.sh` runs fixture tests and the secret-free verifier. It does not query Keychain, inspect identities, contact Apple, sign production code, or submit notarization work.

## One-time trusted-Mac setup

Use only Sparkle 2.9.5's official tools. Release preparation freshly downloads the official SwiftPM distribution, verifies the frozen SHA-256 `34b9b2071f3de0012eca3faa3a9290bb94e62131e9a74f6dc91514a000097a6c`, extracts it to private temporary storage, and executes its `bin` tools. Generate or inspect the public key through the Keychain-backed account:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account <account>
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account <account> -p
```

The first command may create the private key in the login Keychain. The second prints only the public key. Record and approve the SHA-256 of the decoded 32-byte public key out of band. Never export the private key into this repository or pass it in an argument. Do not use deprecated `-s`, private-key environment variables, DSA tooling, custom crypto, or the removed binary-distribution CLI.

Create the Apple notary profile separately with `xcrun notarytool store-credentials`. The release script accepts only its profile name and tests usability with `notarytool history`; it never accepts Apple credentials directly.

## Prepare a release

Preparation fails closed unless all of these are true:

1. The source checkout is clean, `HEAD` is the explicitly approved full commit, and `v<marketing-version>` resolves to that commit.
2. Marketing/build versions are numeric, the tag is exactly `v<marketing-version>`, and the build is strictly newer than the staged/deployed appcast.
3. Unless `--initial-release` is explicit, the signed previous appcast and its latest archive are present, length-consistent, and cryptographically verified through Sparkle. The prior feed seeds generation, but only the new archive is placed in the generation directory so the old immutable URL cannot be rewritten under the new tag.
4. The archive URL is exactly `https://github.com/skeletor-js/bessie/releases/download/<tag>/<archive>` with no credentials, query, fragment, redirect host, or temporary token. The feed URL is exactly `https://bessie.dev/appcast.xml`.
5. The selected Developer ID Application identity/team, notary Keychain profile, and Sparkle Keychain account are usable. The Sparkle public key must match the separately approved SHA-256.
6. Release notes are an existing HTML file. The app and appcast minimum system version remain exactly macOS 14.0.

Example for a non-initial release, with only non-secret values on the command line:

```bash
./scripts/release-app.sh prepare \
  --version 1.0.1 \
  --build 101 \
  --tag v1.0.1 \
  --approved-source-commit "$(git rev-parse HEAD)" \
  --identity 'Developer ID Application: <approved identity> (<TEAMID>)' \
  --team-id '<TEAMID>' \
  --notary-profile '<keychain profile name>' \
  --sparkle-account '<keychain account>' \
  --approved-key-sha256 '<approved public-key sha256>' \
  --feed-url 'https://bessie.dev/appcast.xml' \
  --archive-url 'https://github.com/skeletor-js/bessie/releases/download/v1.0.1/Bessie-1.0.1-101.zip' \
  --release-notes /absolute/path/release-notes-1.0.1.html \
  --previous-appcast /absolute/path/current-appcast.xml \
  --previous-archive /absolute/path/Bessie-1.0.0-100.zip \
  --output /absolute/path/bessie-release-v1.0.1-101
```

Preparation performs this order:

1. package and explicitly verify nested Developer ID code;
2. make a notarization ZIP and run `xcrun notarytool submit --wait`;
3. retain only redacted submission/log evidence and require `Accepted`;
4. staple and validate `Bessie.app`, assess it with `spctl`, then reverify code;
5. seal the stapled app tree and recreate the downloadable ZIP with `ditto -c -k --sequesterRsrc --keepParent`;
6. extract that final ZIP into private scratch and rerun strict code-sign, staple, Gatekeeper, identity/team, plist, version, and minimum-OS checks;
7. compute final archive length and SHA-256, and reject any app mutation;
8. run Sparkle 2.9.5 `generate_appcast --maximum-deltas 0 --maximum-versions 0` against those final bytes, preserving every prior immutable item and URL;
9. reject dropped/rewritten prior items and delta files/enclosures, verify archive and signed appcast with `sign_update --verify`, recheck the archive hash, write evidence, and run the offline verifier.

The output directory is deliberately outside the repository and contains the final ZIP, checksum, signed staged appcast, release notes, `release.json`, `release-evidence.md`, and redacted notarization evidence. No private material or environment dump is retained.

## Verify from fresh scratch

Copy the complete prepared directory without changing its contents, then run:

```bash
./scripts/release-app.sh verify /path/to/copied-prepared-directory
```

This proves the copied archive and appcast remain internally consistent with the supplied `release.json`. The manifest must come through a separately trusted handoff; it is not itself signed. The offline check does not independently establish archive/feed signature authenticity, notarization, stapling, Developer ID identity, execution order, or manifest provenance. Sparkle 2.9.5's supported `sign_update --verify` derives its public key from the selected Keychain private key, so cryptographic archive/feed verification runs during `prepare`. The same prepare also validates the notary log's job ID/status/submission-archive SHA-256 and an extracted copy of the final ZIP. Bessie does not implement custom Ed25519 verification.

## R31 release evidence

`release-evidence.md` is generated with these fields. Deferred publication/runtime fields must remain marked deferred until observed, never inferred:

- source commit and tag;
- app marketing/build versions;
- Sparkle version;
- bundled Herdr lock/version/protocol;
- archive and executable SHA-256;
- Developer ID identity and team;
- notarization submission ID and status;
- appcast URL, signature evidence, and prepared SHA-256;
- GitHub release URL and immutable/public asset result;
- Cloudflare deployment/version and exact production-feed result;
- real old-to-new update result;
- installed executable identity;
- Herdr process/pane survival and post-relaunch terminal I/O result.

The first Sparkle-enabled public build still requires one manual install for users of pre-Sparkle Bessie. Rollback never mutates an immutable archive or downgrades an installation: remove the bad feed item for users who have not installed it, retain published bytes, and issue a corrected higher build.
