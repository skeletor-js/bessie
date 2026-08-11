import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

import { validateAppcast } from '../lib/appcast.mjs';
import worker from '../worker.js';
import { installer } from '../lib/installer.mjs';
import { stagePreparedAppcast, verifyDeployAppcastState, verifyStagedAppcast } from './stage-appcast.mjs';

const signature = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==';

function signedFeed(item = validItem()) {
  const xml = `<?xml version="1.0" encoding="utf-8"?>\n<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel><title>Bessie</title>${item}</channel></rss>\n`;
  return `${xml}<!-- sparkle-signatures:\nedSignature: ${signature}\nlength: ${Buffer.byteLength(xml)}\n-->\n`;
}

function validItem() {
  return `<item><title>Bessie 1.2.3</title><pubDate>Sun, 09 Aug 2026 00:00:00 +0000</pubDate><sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion><sparkle:releaseNotesLink>https://github.com/skeletor-js/bessie/releases/tag/v1.2.3</sparkle:releaseNotesLink><enclosure url="https://github.com/skeletor-js/bessie/releases/download/v1.2.3/Bessie-1.2.3-10.zip" length="7" type="application/octet-stream" sparkle:version="10" sparkle:shortVersionString="1.2.3" sparkle:edSignature="${signature}" /></item>`;
}

function expectInvalid(label, feed, expected) {
  assert.throws(() => validateAppcast(Buffer.from(feed)), expected, label);
}

function enclosureURL(replacement) {
  return validItem().replace(
    'https://github.com/skeletor-js/bessie/releases/download/v1.2.3/Bessie-1.2.3-10.zip',
    replacement,
  );
}

const validFeed = signedFeed();
assert.deepEqual(validateAppcast(Buffer.from(validFeed)).latest, {
  version: '1.2.3',
  build: '10',
  archiveName: 'Bessie-1.2.3-10.zip',
  archiveLength: 7,
  archiveURL: 'https://github.com/skeletor-js/bessie/releases/download/v1.2.3/Bessie-1.2.3-10.zip',
});
const retainedItem = validItem()
  .replace('<title>Bessie 1.2.3</title>', '')
  .replace('<sparkle:releaseNotesLink>https://github.com/skeletor-js/bessie/releases/tag/v1.2.3</sparkle:releaseNotesLink>', '<description>Retained release notes</description>')
  .replaceAll('1.2.3', '1.2.2')
  .replaceAll('10', '9');
const retainedFeed = validateAppcast(Buffer.from(signedFeed(`${retainedItem}${validItem()}`)));
assert.equal(retainedFeed.items.length, 2);
assert.equal(retainedFeed.latest.build, '10');

expectInvalid('HTML fallback', '<!doctype html><title>Bessie</title>', /HTML|XML/);
expectInvalid('malformed XML', signedFeed(validItem().replace('</item>', '')), /malformed|item/i);
expectInvalid('unmatched XML element', signedFeed(`<broken>${validItem()}`), /malformed/i);
expectInvalid('mismatched release-note tags', signedFeed(validItem().replace('</sparkle:releaseNotesLink>', '</sparkle:fullReleaseNotesLink>')), /malformed/i);
expectInvalid('malformed item attributes', signedFeed(validItem().replace('<item>', '<item broken>')), /malformed/i);
expectInvalid('unsigned feed', validFeed.replace(/<!-- sparkle-signatures:[\s\S]*$/, ''), /signed-feed/);
expectInvalid('private key material', signedFeed(`${validItem()}<!-- -----BEGIN PRIVATE KEY----- -->`), /private-key/);
expectInvalid('HTTP enclosure', signedFeed(enclosureURL('http://github.com/skeletor-js/bessie/releases/download/v1.2.3/Bessie-1.2.3-10.zip')), /immutable GitHub/);
expectInvalid('credential-bearing enclosure', signedFeed(enclosureURL('https://token@github.com/skeletor-js/bessie/releases/download/v1.2.3/Bessie-1.2.3-10.zip')), /credentials|immutable GitHub/);
expectInvalid('wrong archive name', signedFeed(validItem().replace('Bessie-1.2.3-10.zip', 'Bessie-1.2.3-11.zip')), /archive|immutable GitHub/);
expectInvalid('invalid archive length', signedFeed(validItem().replace('length="7"', 'length="0"')), /length/);
expectInvalid('version mismatch', signedFeed(validItem().replace('Bessie 1.2.3</title>', 'Bessie 1.2.4</title>')), /title|version/);
expectInvalid('missing macOS minimum', signedFeed(validItem().replace('<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>', '')), /minimumSystemVersion|minimum macOS/);
expectInvalid('missing enclosure signature', signedFeed(validItem().replace(` sparkle:edSignature="${signature}"`, '')), /archive signature/);
expectInvalid('delta enclosure', signedFeed(validItem().replace('</item>', '<sparkle:deltas><enclosure sparkle:deltaFrom="9" /></sparkle:deltas></item>')), /delta/);
expectInvalid('prerelease channel', signedFeed(validItem().replace('</item>', '<sparkle:channel>beta</sparkle:channel></item>')), /channel|policy/);
expectInvalid('attribute-bearing prerelease channel', signedFeed(validItem().replace('</item>', '<sparkle:channel name="beta">beta</sparkle:channel></item>')), /channel|policy/);
expectInvalid('channel-level delta', signedFeed(`${validItem()}<sparkle:deltas source="fixture" />`), /delta|policy/);
for (const policy of ['channel', 'deltas', 'criticalUpdate']) {
  expectInvalid(
    `alternate-prefix ${policy}`,
    signedFeed(validItem().replace('<item>', `<item xmlns:x="http://www.andymatuschak.org/xml-namespaces/sparkle"><x:${policy}>beta</x:${policy}>`)),
    /canonical root sparkle namespace/,
  );
}
expectInvalid(
  'character-reference Sparkle namespace',
  signedFeed(validItem().replace('<item>', '<item xmlns:x="http://www.andymatuschak.org/xml-namespaces/spark&#108;e"><x:channel>beta</x:channel>')),
  /canonical root sparkle namespace/,
);
expectInvalid('private API URL', signedFeed(enclosureURL('https://api.github.com/repos/skeletor-js/bessie/releases/assets/123')), /immutable GitHub/);
expectInvalid('draft-looking URL', signedFeed(enclosureURL('https://github.com/skeletor-js/bessie/releases/draft/v1.2.3/Bessie-1.2.3-10.zip')), /immutable GitHub/);
expectInvalid('explicit default port', signedFeed(enclosureURL('https://github.com:443/skeletor-js/bessie/releases/download/v1.2.3/Bessie-1.2.3-10.zip')), /immutable GitHub/);
expectInvalid('percent-encoded path', signedFeed(enclosureURL('https://github.com/skeletor-js/bessie/releases/download/v1.2.3/Bessie%2D1.2.3%2D10.zip')), /immutable GitHub/);

function assetsReturning(body, contentType = 'application/xml') {
  return {
    fetch: async request => {
      const pathname = new URL(request.url).pathname;
      if (pathname === '/appcast.xml') {
        return new Response(body, { headers: { 'Content-Type': contentType } });
      }
      return new Response('<!doctype html><title>landing</title>', {
        headers: { 'Content-Type': 'text/html; charset=utf-8' },
      });
    },
  };
}

let fetchedAppcastURL = '';
const queryResponse = await worker.fetch(
  new Request('https://bessie.dev/appcast.xml?release=10'),
  {
    ASSETS: {
      fetch: async request => {
        fetchedAppcastURL = request.url;
        return new Response(validFeed, { headers: { 'Content-Type': 'application/xml' } });
      },
    },
  },
);
assert.equal(queryResponse.status, 200);
assert.equal(fetchedAppcastURL, 'https://bessie.dev/appcast.xml');

const validResponse = await worker.fetch(
  new Request('https://bessie.dev/appcast.xml'),
  { ASSETS: assetsReturning(validFeed) },
);
assert.equal(validResponse.status, 200);
assert.match(validResponse.headers.get('content-type') || '', /^application\/xml\b/);
assert.equal(validResponse.headers.get('x-content-type-options'), 'nosniff');
assert.match(validResponse.headers.get('cache-control') || '', /max-age=\d+/);
assert.match(validResponse.headers.get('cache-control') || '', /must-revalidate/);
assert.equal(await validResponse.text(), validFeed);

for (const [label, assets] of [
  ['missing feed SPA fallback', assetsReturning('<!doctype html><title>landing</title>', 'text/html; charset=utf-8')],
  ['wrong asset content type', assetsReturning(validFeed, 'text/html; charset=utf-8')],
  ['invalid feed', assetsReturning('<rss version="2.0"></rss>')],
]) {
  const response = await worker.fetch(new Request('https://bessie.dev/appcast.xml'), { ASSETS: assets });
  assert.ok(response.status >= 400, label);
  assert.doesNotMatch(await response.text(), /<!doctype html|<html/i, label);
}

const headResponse = await worker.fetch(
  new Request('https://bessie.dev/appcast.xml', { method: 'HEAD' }),
  { ASSETS: assetsReturning(validFeed) },
);
assert.equal(headResponse.status, 200);
assert.equal(await headResponse.text(), '');

const postResponse = await worker.fetch(
  new Request('https://bessie.dev/appcast.xml', { method: 'POST' }),
  { ASSETS: assetsReturning(validFeed) },
);
assert.equal(postResponse.status, 405);

const rootResponse = await worker.fetch(
  new Request('https://bessie.dev/'),
  { ASSETS: assetsReturning(validFeed) },
);
assert.match(await rootResponse.text(), /landing/);

const installResponse = await worker.fetch(
  new Request('https://bessie.dev/install'),
  { ASSETS: assetsReturning(validFeed) },
);
assert.equal(installResponse.status, 200);
assert.equal(await installResponse.text(), installer);
assert.match(installer, /Bessie-1\.0\.0-15\.zip/);
assert.match(installer, /4875eba124d34d724fc3f899beb1f5e29afe29c37d228d7cb61d72589579e534/);
for (const required of ['codesign --verify --deep --strict', 'xcrun stapler validate', 'spctl --assess --type execute']) {
  assert.match(installer, new RegExp(required.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
}
assert.doesNotMatch(installer, /\bsudo\b/);

const work = await mkdtemp(path.join(os.tmpdir(), 'bessie-site-appcast-'));
try {
  const absentDestination = path.join(work, 'absent-appcast.xml');
  const absentReceipt = path.join(work, 'absent-appcast.json');
  assert.equal(await verifyDeployAppcastState({ destination: absentDestination, receipt: absentReceipt }), null);
  await writeFile(absentDestination, validFeed);
  await assert.rejects(
    () => verifyDeployAppcastState({ destination: absentDestination, receipt: absentReceipt }),
    /incomplete|both/i,
  );
  await rm(absentDestination);

  const prepared = path.join(work, 'prepared');
  const destination = path.join(work, 'public', 'appcast.xml');
  const receipt = path.join(work, '.staged', 'appcast.json');
  await mkdir(path.join(prepared, 'evidence'), { recursive: true });
  await writeFile(path.join(prepared, 'Bessie-1.2.3-10.zip'), 'archive');
  const archive = await readFile(path.join(prepared, 'Bessie-1.2.3-10.zip'));
  const archiveSHA = createHash('sha256').update(archive).digest('hex');
  await writeFile(path.join(prepared, 'Bessie-1.2.3-10.zip.sha256'), `${archiveSHA}  Bessie-1.2.3-10.zip\n`);
  await writeFile(path.join(prepared, 'appcast.xml'), validFeed);
  const appcastSHA = createHash('sha256').update(validFeed).digest('hex');
  const metadata = {
    schema: 1,
    state: 'prepared',
    source_commit: '0123456789abcdef0123456789abcdef01234567',
    tag: 'v1.2.3',
    marketing_version: '1.2.3',
    build_version: '10',
    minimum_system_version: '14.0',
    feed_url: 'https://bessie.dev/appcast.xml',
    archive_name: 'Bessie-1.2.3-10.zip',
    archive_url: 'https://github.com/skeletor-js/bessie/releases/download/v1.2.3/Bessie-1.2.3-10.zip',
    archive_length: archive.length,
    archive_sha256: archiveSHA,
    appcast_sha256: appcastSHA,
    sparkle_version: '2.9.5',
    sparkle_signature_verified_during_prepare: true,
    sparkle_tools_archive_sha256: '34b9b2071f3de0012eca3faa3a9290bb94e62131e9a74f6dc91514a000097a6c',
    notarization_submission_id: 'fixture-submission',
    notarization_archive_sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    notarization_status: 'Accepted',
    final_archive_extraction_verified: true,
    byte_finalization_order: ['staple', 'archive', 'extract-verify', 'checksum', 'appcast-generate-sign', 'sparkle-verify'],
  };
  await writeFile(path.join(prepared, 'release.json'), `${JSON.stringify(metadata, null, 2)}\n`);
  await writeFile(path.join(prepared, 'evidence', 'notary-submission.json'), '{"id":"fixture-submission","status":"Accepted"}\n');
  await writeFile(path.join(prepared, 'evidence', 'notary-log.json'), '{"jobId":"fixture-submission","status":"Accepted","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}\n');

  await stagePreparedAppcast({ preparedDirectory: prepared, destination, receipt });
  assert.equal(await readFile(destination, 'utf8'), validFeed);
  await verifyStagedAppcast({ destination, receipt });
  await verifyDeployAppcastState({ destination, receipt });

  await writeFile(path.join(prepared, 'Bessie-1.2.3-10.zip.sha256'), `${'0'.repeat(64)}  Bessie-1.2.3-10.zip\n`);
  await assert.rejects(
    () => stagePreparedAppcast({ preparedDirectory: prepared, destination: path.join(work, 'rejected.xml'), receipt: path.join(work, 'rejected.json') }),
    /Command failed|verification/i,
  );

  await writeFile(destination, `${validFeed}\n`);
  await assert.rejects(() => verifyStagedAppcast({ destination, receipt }), /SHA-256|changed/);
} finally {
  await rm(work, { recursive: true, force: true });
}

console.log('appcast smoke: ok');
