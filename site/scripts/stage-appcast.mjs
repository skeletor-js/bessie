import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { access, mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { validateAppcast } from '../lib/appcast.mjs';

const siteRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const releaseVerifier = path.resolve(siteRoot, '..', 'scripts', 'release-metadata.py');
const defaultDestination = path.join(siteRoot, 'public', 'appcast.xml');
const defaultReceipt = path.join(siteRoot, '.staged', 'appcast.json');

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function assertPreparedMatch(metadata, result) {
  const latest = result.latest;
  const expected = {
    version: String(metadata.marketing_version),
    build: String(metadata.build_version),
    archiveName: String(metadata.archive_name),
    archiveLength: Number(metadata.archive_length),
    archiveURL: String(metadata.archive_url),
  };
  for (const [key, value] of Object.entries(expected)) {
    if (latest[key] !== value) throw new Error(`Prepared appcast ${key} does not match release.json`);
  }
  if (metadata.feed_url !== 'https://bessie.dev/appcast.xml') {
    throw new Error('Prepared appcast feed URL must be exactly https://bessie.dev/appcast.xml');
  }
  if (metadata.sparkle_signature_verified_during_prepare !== true) {
    throw new Error('Prepared appcast lacks prepare-time Sparkle signature verification evidence');
  }
}

async function atomicWrite(destination, bytes) {
  await mkdir(path.dirname(destination), { recursive: true });
  const temporary = `${destination}.tmp-${process.pid}`;
  try {
    await writeFile(temporary, bytes, { mode: 0o644 });
    await rename(temporary, destination);
  } finally {
    await rm(temporary, { force: true });
  }
}

export async function stagePreparedAppcast({
  preparedDirectory,
  destination = defaultDestination,
  receipt = defaultReceipt,
}) {
  if (!preparedDirectory) throw new Error('A U5 prepared release directory is required');
  const prepared = path.resolve(preparedDirectory);
  execFileSync('python3', [releaseVerifier, 'verify', prepared], { stdio: 'pipe' });

  const metadata = JSON.parse(await readFile(path.join(prepared, 'release.json'), 'utf8'));
  const appcast = await readFile(path.join(prepared, 'appcast.xml'));
  const result = validateAppcast(appcast);
  assertPreparedMatch(metadata, result);
  const appcastSHA256 = sha256(appcast);
  if (appcastSHA256 !== metadata.appcast_sha256) {
    throw new Error('Prepared appcast SHA-256 does not match release.json');
  }

  const stagedReceipt = {
    schema: 1,
    state: 'staged',
    sourceCommit: metadata.source_commit,
    appcastSHA256,
    feedURL: metadata.feed_url,
    version: result.latest.version,
    build: result.latest.build,
    archiveName: result.latest.archiveName,
    archiveLength: result.latest.archiveLength,
    archiveURL: result.latest.archiveURL,
  };
  await atomicWrite(path.resolve(destination), appcast);
  await atomicWrite(path.resolve(receipt), `${JSON.stringify(stagedReceipt, null, 2)}\n`);
  return stagedReceipt;
}

export async function verifyStagedAppcast({
  destination = defaultDestination,
  receipt = defaultReceipt,
} = {}) {
  let appcast;
  let staged;
  try {
    appcast = await readFile(path.resolve(destination));
    staged = JSON.parse(await readFile(path.resolve(receipt), 'utf8'));
  } catch (error) {
    throw new Error(`No verified appcast is staged; run npm run stage:appcast -- PREPARED_DIRECTORY (${error.message})`);
  }
  const result = validateAppcast(appcast);
  if (staged.schema !== 1 || staged.state !== 'staged') throw new Error('Staged appcast receipt is invalid');
  if (sha256(appcast) !== staged.appcastSHA256) throw new Error('Staged appcast SHA-256 changed after validation');
  const expected = {
    version: staged.version,
    build: staged.build,
    archiveName: staged.archiveName,
    archiveLength: staged.archiveLength,
    archiveURL: staged.archiveURL,
  };
  for (const [key, value] of Object.entries(expected)) {
    if (result.latest[key] !== value) throw new Error(`Staged appcast ${key} changed after validation`);
  }
  return staged;
}

async function pathExists(file) {
  try {
    await access(path.resolve(file));
    return true;
  } catch {
    return false;
  }
}

export async function verifyDeployAppcastState({
  destination = defaultDestination,
  receipt = defaultReceipt,
} = {}) {
  const hasAppcast = await pathExists(destination);
  const hasReceipt = await pathExists(receipt);
  if (!hasAppcast && !hasReceipt) return null;
  if (hasAppcast !== hasReceipt) {
    throw new Error('Appcast staging is incomplete; appcast.xml and its staged receipt must both exist or both be absent');
  }
  return verifyStagedAppcast({ destination, receipt });
}

const invokedPath = process.argv[1] ? path.resolve(process.argv[1]) : '';
if (invokedPath === fileURLToPath(import.meta.url)) {
  const [command, argument] = process.argv.slice(2);
  try {
    if (command === 'stage' && argument) {
      const staged = await stagePreparedAppcast({ preparedDirectory: argument });
      console.log(`Staged signed appcast ${staged.version} (${staged.build}) for local/preview packaging.`);
    } else if (command === 'verify-staged' && !argument) {
      const staged = await verifyStagedAppcast();
      console.log(`Verified staged appcast ${staged.version} (${staged.build}).`);
    } else if (command === 'verify-deploy' && !argument) {
      const staged = await verifyDeployAppcastState();
      console.log(staged
        ? `Verified staged appcast ${staged.version} (${staged.build}) for deployment.`
        : 'Verified pre-release deployment with no staged appcast.');
    } else {
      throw new Error('Usage: stage-appcast.mjs stage PREPARED_DIRECTORY | verify-staged | verify-deploy');
    }
  } catch (error) {
    console.error(`Appcast staging: ${error.message}`);
    process.exitCode = 1;
  }
}
