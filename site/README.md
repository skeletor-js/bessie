# bessie.dev

The Bessie website is a static Cloudflare Workers application with a small `/install` and `/appcast.xml` Worker. React, private design exports, and third-party agent marks are not shipped.

## Serve and check

```sh
cd site
npm ci
npm run check
npm run dev
curl -i http://127.0.0.1:8787/appcast.xml
curl -i http://127.0.0.1:8787/install
```

Wrangler may choose another port when 8787 is occupied. Before release bytes exist, `/install` returns honest shell text that exits nonzero and exact `/appcast.xml` returns `503` plain text with `no-store`; neither endpoint falls through to landing-page HTML.

## Stage a signed appcast

The site does not generate or sign a feed. It consumes a complete output directory from `scripts/release-app.sh prepare`, reruns the secret-free verifier, validates exact release metadata, and copies only the signed appcast into the ignored static-assets staging path:

```sh
cd site
npm run stage:appcast -- /absolute/path/bessie-release-v1.2.3-10
npm run verify:staged-appcast
npm run dev
curl -fsS -D - http://127.0.0.1:8787/appcast.xml -o /tmp/bessie-appcast.xml
```

Generated `public/appcast.xml` and `.staged/appcast.json` are gitignored. Do not hand-create them, stage only an appcast without its complete prepared directory, or put a Sparkle private key in this repository.

The offline verifier checks feed structure, signed-feed trailer metadata, version/build/name/URL consistency, stable-channel/full-archive policy, and exact staged bytes. Installed Bessie remains the cryptographic enforcement point for the feed and enclosure. Publication still requires immutable public release bytes and a successful old-to-new update test.

## Configuration

Edit `public/config.js` for `repoUrl`, `installCmd`, `downloadUrl`, `coldOpen`, `parallax`, `heroInk`, and `cowPx`. With an empty `downloadUrl`, Download links target `#get`. Set it only after a notarized immutable artifact exists.

`wrangler.toml` deliberately omits an account ID and custom-domain route so forks deploy through their authenticated Wrangler account rather than a repository-owned credential or account binding.

## Visual proof

```sh
cd site
npx playwright install chromium # first run only
npm run proof
```

The proof checks 1280- and 1440-pixel widths, horizontal overflow, required sections, browser errors, and reduced-motion behavior. Screenshots go to ignored `site/proof/`. Final typography review should run on macOS because Linux system-font metrics are approximate.

## Deploy

Authenticate to the intended Cloudflare account, review the Worker name in `wrangler.toml`, stage a complete verified appcast when appropriate, then run:

```sh
cd site
npx wrangler whoami
npm run deploy
```

The predeploy gate reruns site and staged-appcast checks. A Workers preview deployment is not production acceptance. Attaching `bessie.dev`, changing DNS, or exposing the production appcast are separate maintainer operations.

Before attaching a custom domain, record existing apex, `www`, MX, TXT, Worker routes, and the rollback deployment. Never replace unrelated DNS records. Publish the appcast only after the GitHub release asset is public, immutable, non-draft, and anonymously byte-verified.

Production verification should include:

```sh
curl -fsS https://bessie.dev/ | grep -F "every agent, one window"
curl -fsSI https://bessie.dev/install
curl -fsS -D - "https://bessie.dev/appcast.xml?release=<build>" -o /tmp/bessie-production-appcast.xml
```

The appcast must remain at the exact HTTPS URL, return XML with `X-Content-Type-Options: nosniff`, and contain the approved signed bytes. Verify every enclosure anonymously against its expected length and checksum, then complete the installed-old-build Sparkle update proof.

## Rollback

Use Cloudflare's deployment rollback to restore the last known-good Worker, then repeat page, install, and appcast checks. Do not mutate immutable release archives. For a bad release, restore the last known-good feed for clients that have not updated and issue a corrected higher build.

## Updating the design

Edit the production files under `public/` directly, keep the change minimal, and rerun `npm run check` and `npm run proof`. Do not add private design exports, canvas runtimes, React bundles, third-party agent marks, or full icon-library selector dumps.
