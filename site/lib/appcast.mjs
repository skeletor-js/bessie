import { XMLParser, XMLValidator } from 'fast-xml-parser';

const SPARKLE_NAMESPACE = 'http://www.andymatuschak.org/xml-namespaces/sparkle';
const SIGNATURE_MARKER = '<!-- sparkle-signatures:\n';
const SIGNATURE_PATTERN = /^<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+/]+={0,2})\nlength: ([0-9]+)\n-->\s*$/;
const VERSION_PATTERN = /^[0-9]+(?:\.[0-9]+)*$/;
const RELEASE_PREFIX = '/skeletor-js/bessie/releases/download/';

function invalid(message) {
  throw new Error(`Invalid appcast: ${message}`);
}

function decodeSignature(value, label) {
  let binary;
  try {
    binary = atob(value);
  } catch {
    invalid(`${label} is not canonical base64`);
  }
  if (binary.length !== 64) invalid(`${label} must decode to 64 bytes`);
  let canonical = '';
  for (let index = 0; index < binary.length; index += 1) {
    canonical += binary[index];
  }
  if (btoa(canonical) !== value) invalid(`${label} is not canonical base64`);
}

function oneText(value, name, label) {
  if (typeof value !== 'string' || !value.trim()) invalid(`${label} must contain exactly one ${name}`);
  return value.trim();
}

function optionalText(value, name, label) {
  return value === undefined ? '' : oneText(value, name, label);
}

function compareVersions(left, right) {
  const leftParts = left.split('.').map(Number);
  const rightParts = right.split('.').map(Number);
  const width = Math.max(leftParts.length, rightParts.length);
  for (let index = 0; index < width; index += 1) {
    const difference = (leftParts[index] || 0) - (rightParts[index] || 0);
    if (difference) return difference;
  }
  return 0;
}

function hasForbiddenPolicy(value) {
  if (!value || typeof value !== 'object') return false;
  for (const [key, child] of Object.entries(value)) {
    if (['sparkle:deltas', 'sparkle:channel', 'sparkle:phasedRolloutInterval', 'sparkle:criticalUpdate', 'sparkle:informationalUpdate'].includes(key)) {
      return true;
    }
    if (hasForbiddenPolicy(child)) return true;
  }
  return false;
}

function hasUnsupportedSparkleNamespace(value, allowCanonicalRoot = false) {
  if (!value || typeof value !== 'object') return false;
  for (const [key, child] of Object.entries(value)) {
    if (key === '@_xmlns' || key.startsWith('@_xmlns:')) {
      if (typeof child !== 'string' || child.includes('&')) return true;
      if (child === SPARKLE_NAMESPACE && !(allowCanonicalRoot && key === '@_xmlns:sparkle')) return true;
    }
    if (child && typeof child === 'object' && hasUnsupportedSparkleNamespace(child, false)) return true;
  }
  return false;
}

function validateItem(item, index) {
  const label = `item ${index + 1}`;
  if (!item || typeof item !== 'object') invalid(`${label} is malformed`);
  if (hasForbiddenPolicy(item)) invalid(`${label} contains forbidden delta, channel, or rollout policy`);

  oneText(item.pubDate, 'pubDate', label);
  const minimum = oneText(item['sparkle:minimumSystemVersion'], 'sparkle:minimumSystemVersion', label);
  if (minimum !== '14.0') invalid(`${label} minimum macOS must be 14.0`);

  const enclosures = Array.isArray(item.enclosure) ? item.enclosure : [];
  if (enclosures.length !== 1 || !enclosures[0] || typeof enclosures[0] !== 'object') invalid(`${label} must contain exactly one full enclosure`);
  const enclosure = enclosures[0];
  const enclosureBuild = optionalText(enclosure['@_sparkle:version'], 'enclosure sparkle:version', label);
  const itemBuild = optionalText(item['sparkle:version'], 'sparkle:version', label);
  const enclosureVersion = optionalText(enclosure['@_sparkle:shortVersionString'], 'enclosure sparkle:shortVersionString', label);
  const itemVersion = optionalText(item['sparkle:shortVersionString'], 'sparkle:shortVersionString', label);
  if (enclosureBuild && itemBuild && enclosureBuild !== itemBuild) invalid(`${label} build versions disagree`);
  if (enclosureVersion && itemVersion && enclosureVersion !== itemVersion) invalid(`${label} marketing versions disagree`);
  const build = enclosureBuild || itemBuild;
  const version = enclosureVersion || itemVersion;
  if (!VERSION_PATTERN.test(build)) invalid(`${label} build version must be numeric or dotted-numeric`);
  if (!VERSION_PATTERN.test(version) || version.split('.').length < 3) {
    invalid(`${label} marketing version must contain at least three numeric components`);
  }
  if (enclosure['@_type'] !== 'application/octet-stream') {
    invalid(`${label} enclosure must be a full application/octet-stream archive`);
  }
  const length = enclosure['@_length'] || '';
  if (!/^[1-9][0-9]*$/.test(length)) invalid(`${label} enclosure length must be a positive integer`);
  decodeSignature(enclosure['@_sparkle:edSignature'] || '', `${label} archive signature`);
  if (enclosure['@_sparkle:deltaFrom'] !== undefined) invalid(`${label} contains a forbidden delta enclosure`);

  const archiveName = `Bessie-${version}-${build}.zip`;
  const archiveURL = enclosure['@_url'] || '';
  try {
    new URL(archiveURL);
  } catch {
    invalid(`${label} enclosure URL is malformed`);
  }
  const expectedPath = `${RELEASE_PREFIX}v${version}/${archiveName}`;
  if (archiveURL !== `https://github.com${expectedPath}`) {
    invalid(`${label} enclosure must use the exact immutable GitHub release URL for ${archiveName} without credentials`);
  }

  if (item.title !== undefined) {
    const title = oneText(item.title, 'title', label);
    if (title !== version && title !== `Bessie ${version}`) invalid(`${label} title does not match its marketing version`);
  }
  const notes = item['sparkle:releaseNotesLink'] ?? item['sparkle:fullReleaseNotesLink'];
  if (notes !== undefined) {
    if (oneText(notes, 'release notes link', label) !== `https://github.com/skeletor-js/bessie/releases/tag/v${version}`) {
      invalid(`${label} release notes URL does not match its marketing version`);
    }
  } else if (item.description === undefined) {
    invalid(`${label} is missing release notes`);
  }

  return {
    version,
    build,
    archiveName,
    archiveLength: Number(length),
    archiveURL,
  };
}

export function validateAppcast(bytes) {
  const data = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  if (!data.length || data.length > 1024 * 1024) invalid('feed must be between 1 byte and 1 MiB');
  let text;
  try {
    text = new TextDecoder('utf-8', { fatal: true }).decode(data);
  } catch {
    invalid('feed is not valid UTF-8 XML');
  }
  if (/<!doctype\s+html|<html(?:\s|>)/i.test(text)) invalid('HTML fallback is not XML');
  if (/<!DOCTYPE|<!ENTITY|-----BEGIN [A-Z ]*PRIVATE KEY-----|sparkle[_-]?private[_-]?key/i.test(text)) {
    invalid('feed contains forbidden declarations or private-key material');
  }

  const markerIndex = text.lastIndexOf(SIGNATURE_MARKER);
  if (markerIndex < 0) invalid("feed is missing Sparkle's signed-feed trailer");
  const trailerMatch = SIGNATURE_PATTERN.exec(text.slice(markerIndex));
  if (!trailerMatch) invalid("feed has a malformed Sparkle signed-feed trailer");
  decodeSignature(trailerMatch[1], 'signed-feed signature');
  const signedBytes = new TextEncoder().encode(text.slice(0, markerIndex)).byteLength;
  if (Number(trailerMatch[2]) !== signedBytes) invalid('signed-feed length does not match its signed bytes');

  const xml = text.slice(0, markerIndex).trim();
  const validation = XMLValidator.validate(xml, { allowBooleanAttributes: false });
  if (validation !== true) invalid(`feed is malformed RSS XML: ${validation.err.msg}`);
  const parser = new XMLParser({
    ignoreAttributes: false,
    attributeNamePrefix: '@_',
    parseAttributeValue: false,
    parseTagValue: false,
    processEntities: false,
    trimValues: true,
    isArray: (name, path) => path === 'rss.channel.item' || path.endsWith('.item.enclosure'),
  });
  const document = parser.parse(xml);
  const rss = document?.rss;
  if (!rss || typeof rss !== 'object' || rss['@_version'] !== '2.0' || rss['@_xmlns:sparkle'] !== SPARKLE_NAMESPACE) {
    invalid('feed must be Sparkle RSS 2.0');
  }
  if (hasUnsupportedSparkleNamespace(rss, true)) {
    invalid('feed must use only the canonical root sparkle namespace declaration');
  }
  if (!rss.channel || typeof rss.channel !== 'object' || Array.isArray(rss.channel)) invalid('feed is missing or has a malformed channel');
  if (hasForbiddenPolicy(rss.channel)) invalid('feed contains forbidden delta, channel, or rollout policy');
  const parsedItems = Array.isArray(rss.channel.item) ? rss.channel.item : [];
  if (!parsedItems.length) invalid('feed has missing or malformed release items');
  const items = parsedItems.map(validateItem);
  const builds = new Set();
  const urls = new Set();
  for (const item of items) {
    if (builds.has(item.build) || urls.has(item.archiveURL)) invalid('feed contains a duplicate build or enclosure URL');
    builds.add(item.build);
    urls.add(item.archiveURL);
  }
  const latest = items.reduce((candidate, item) => compareVersions(item.build, candidate.build) > 0 ? item : candidate);
  return { items, latest };
}
