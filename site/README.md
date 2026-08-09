# bessie.dev

Production static extraction of the retained oracle in `../docs/research/bessie-landing-source/`. It uses Cloudflare Workers Static Assets plus a small `/install` Worker; React and dc-runtime are not shipped.

## Serve and check

```sh
cd site
npm ci
npm run check
npm run dev
curl -i http://127.0.0.1:8787/appcast.xml
curl -i http://127.0.0.1:8787/install
```

Wrangler may select another port if 8787 is occupied. `/install` intentionally returns honest shell text that exits nonzero because binaries are not published. Until a real U5 artifact is staged, exact `/appcast.xml` returns `503` plain text with `no-store`; it never falls through to landing HTML. `/`, `/install`, static assets, visual proof, and reduced-motion behavior remain independent of the feed.

## Stage a prepared signed appcast

The site does not generate or sign a feed. It consumes the complete output directory from U5 `release-app.sh prepare`, reruns the secret-free U5 verifier, checks the feed structure and exact release metadata, and then copies only the already-signed appcast into the ignored static-assets staging path:

```sh
cd site
npm run stage:appcast -- /absolute/path/bessie-release-v1.2.3-10
npm run verify:staged-appcast
npm run dev
curl -fsS -D - http://127.0.0.1:8787/appcast.xml -o /tmp/bessie-appcast.xml
```

Generated `public/appcast.xml` and its local `.staged/appcast.json` receipt are gitignored. Do not hand-create either file, copy only an appcast without its complete U5 prepared directory, or put a Sparkle private key in this repository. Staging calls the existing offline U5 verifier; it does not invoke Sparkle signing tools, Keychain, Apple, GitHub, or Cloudflare.

The offline verifier proves consistency with the separately trusted `release.json` and requires prepare-time Sparkle verification evidence. It does not independently authenticate that unsigned manifest or reperform Ed25519 verification without the Keychain-backed key. The Worker therefore validates shape, signed-feed trailer metadata, internal version/build/name/URL consistency, stable-channel/full-archive policy, and the exact staged bytes. Installed Bessie remains the cryptographic enforcement point for the signed feed and enclosure. Publication still requires the separate immutable/public GitHub and old-to-new operator gates.

## Configuration

Edit `public/config.js`: `repoUrl`, `installCmd`, `downloadUrl`, `coldOpen`, `parallax`, `heroInk`, and `cowPx`. With an empty `downloadUrl`, every Download CTA links to `#get`. Set it only when a notarized artifact exists. Keep `installCmd` aligned with the deployed origin.

## Visual proof

With the local Worker running:

```sh
npx playwright install chromium # first run only
npm run proof
```

The proof checks 1280 and 1440 widths, horizontal overflow, all required sections, browser errors, and reduced-motion fail-open behavior. Screenshots go to the gitignored `site/proof/` directory. Linux renders system fonts approximately; final pixel review should use the same command on Jordan's Mac, where SF Pro metrics match the oracle.

## Deploy (staging only until launch)

`wrangler.toml` targets Cloudflare account ID `6f03cccab9f19bc53ea7d259167a7024`, Worker name `bessie-dev`, and Workers preview hostname **`bessie-dev.jordanjstella.workers.dev`**. It deliberately contains no custom-domain route. `workers_dev` and preview URLs stay enabled.

Until Jordan explicitly approves launch:

- Before any preview deployment, run `npx wrangler whoami` and stop unless the authenticated account ID is exactly `6f03cccab9f19bc53ea7d259167a7024` and its Workers subdomain produces exactly `bessie-dev.jordanjstella.workers.dev` for this Worker name.
- Stage the complete existing U5 prepared artifact, then run `npm run deploy`. The automatic predeploy gate reruns all checks and refuses if the ignored feed or receipt is absent, invalid, or changed. It never regenerates or re-signs a feed.
- Deploy only to `bessie-dev.jordanjstella.workers.dev`; a successful preview is not production acceptance.
- Do **not** attach `bessie.dev` / `www.bessie.dev`.
- Do **not** mutate DNS.
- Do **not** deploy a landing-only version after appcast publication unless the exact previously approved feed is staged and verified. This prevents an ordinary static-site change from silently removing or changing the machine endpoint.

After an approved preview deployment, verify the exact host with a cache-busting query and reject redirects, HTML, wrong headers, or non-public enclosure bytes. Do not treat a `*.workers.dev` 200 alone as proof that the GitHub release is public, immutable, non-draft, or anonymously downloadable.

When launch is separately approved later, first record the current apex, `www`, MX, TXT, Workers routes, and rollback deployment. Confirm the same account owns the intended `bessie.dev` zone and has the necessary zone/DNS/Workers-route permissions. Stop on any account, zone, hostname, or permission mismatch. Only then attach the apex and approved `www` policy through durable Wrangler configuration or the separately approved Cloudflare route operation. Never replace or remove unrelated DNS, MX, or TXT records. Publish the appcast only after the GitHub release is public, immutable, non-draft, and anonymously byte-verified. Then verify:

```sh
curl -fsS https://bessie.dev/ | rg "every agent, one window"
curl -fsSI https://bessie.dev/install
curl -fsS -D - "https://bessie.dev/appcast.xml?release=<build>" -o /tmp/bessie-production-appcast.xml
```

The production response must remain on `https://bessie.dev/appcast.xml`, return XML with `X-Content-Type-Options: nosniff` and bounded revalidation caching, and contain the exact approved signed bytes. Verify every enclosure anonymously against its expected length and checksum and complete the installed-old-build Sparkle parsing/update proof. If authentication or zone access fails, stop rather than deploying under another account.

### Current deployment status

Deployed on 2026-08-04 to the non-production Workers preview at <https://bessie-dev.jordanjstella.workers.dev> (version `c608d2c0-2e7c-4413-9c20-e43e5b57ac37`). The full browser proof and direct `/install` checks pass there. No custom-domain route or DNS record was created or changed. `bessie.dev` and `www.bessie.dev` do not currently resolve, so the production install command shown in the design will not work until the domain owner deliberately attaches the apex and chooses the `www` policy.

### Rollback

Cloudflare keeps Worker versions. In the Cloudflare dashboard, open **Workers & Pages → bessie-dev → Deployments**, select the last known-good version, and choose **Rollback**. Then repeat the page, `/install`, and exact appcast checks above. If a custom domain is later attached, do not edit its DNS during an application rollback. A bad immutable archive is never replaced in place; restore the last known-good signed feed for clients that have not updated and publish a corrected higher build under the release runbook.

## Updating the oracle

The complete design-canvas export stays in `../docs/research/bessie-landing-source/`; production keeps only the landing DOM, required CSS rules, two WOFF2 fonts, and three agent marks. To update from a new export, retain it in that oracle directory, compare the complete DOM/component/CSS, and rerun the proof before replacing production assets. Do not copy the canvas runtime, React, or the full Phosphor selector catalog into `public/`.
