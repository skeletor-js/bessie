#!/usr/bin/env python3
"""Secret-free validation and metadata helpers for Bessie release artifacts."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import plistlib
import re
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import unquote, urlparse

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
SPARKLE = f"{{{SPARKLE_NS}}}"
FEED_URL = "https://bessie.dev/appcast.xml"
MINIMUM_OS = "14.0"
RELEASE_HOST = "github.com"
RELEASE_PREFIX = "/skeletor-js/bessie/releases/download/"
SIGNATURE_MARKER = b"<!-- sparkle-signatures:\n"


def fail(message: str) -> None:
    raise SystemExit(f"Release verification: {message}")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_version(value: str, label: str, minimum_parts: int = 1) -> tuple[int, ...]:
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", value):
        fail(f"{label} must be numeric or dotted-numeric")
    parts = tuple(int(part) for part in value.split("."))
    if len(parts) < minimum_parts:
        fail(f"{label} must contain at least {minimum_parts} numeric components")
    return parts


def version_greater(candidate: str, previous: str) -> bool:
    left = parse_version(candidate, "build version")
    right = parse_version(previous, "previous build version")
    width = max(len(left), len(right))
    return left + (0,) * (width - len(left)) > right + (0,) * (width - len(right))


def version_at_least(candidate: str, previous: str) -> bool:
    left = parse_version(candidate, "marketing version", minimum_parts=3)
    right = parse_version(previous, "previous marketing version", minimum_parts=3)
    width = max(len(left), len(right))
    return left + (0,) * (width - len(left)) >= right + (0,) * (width - len(right))


def validate_version(marketing: str, build: str, tag: str) -> None:
    parse_version(marketing, "marketing version", minimum_parts=3)
    parse_version(build, "build version")
    expected_tag = f"v{marketing}"
    if tag != expected_tag:
        fail(f"tag must be {expected_tag}")


def validate_release_url(url: str, tag: str, archive_name: str) -> None:
    parsed = urlparse(url)
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        fail("archive URL must not contain credentials, query parameters, or fragments")
    expected_path = f"{RELEASE_PREFIX}{tag}/{archive_name}"
    if (
        parsed.scheme != "https"
        or parsed.hostname != RELEASE_HOST
        or parsed.port not in (None, 443)
        or unquote(parsed.path) != expected_path
        or parsed.params
    ):
        fail(
            "archive URL must be the exact immutable GitHub release URL "
            f"https://{RELEASE_HOST}{expected_path}"
        )


def parse_feed(path: Path) -> ET.Element:
    if not path.is_file():
        fail(f"missing appcast: {path}")
    try:
        return ET.fromstring(path.read_bytes())
    except ET.ParseError as error:
        fail(f"appcast is not valid XML: {error}")


def feed_items(root: ET.Element) -> list[ET.Element]:
    if root.tag != "rss" or root.get("version") != "2.0":
        fail("appcast root must be RSS 2.0")
    channel = root.find("channel")
    if channel is None:
        fail("appcast is missing its channel")
    items = channel.findall("item")
    if not items:
        fail("appcast contains no release items")
    return items


def enclosure_for_build(root: ET.Element, build: str) -> tuple[ET.Element, ET.Element]:
    matches: list[tuple[ET.Element, ET.Element]] = []
    for item in feed_items(root):
        enclosure = item.find("enclosure")
        if enclosure is not None and enclosure.get(f"{SPARKLE}version") == build:
            matches.append((item, enclosure))
    if len(matches) != 1:
        fail(f"expected exactly one appcast enclosure for build {build}, found {len(matches)}")
    return matches[0]


def validate_feed_signature_shape(path: Path) -> None:
    data = path.read_bytes()
    marker_offset = data.rfind(SIGNATURE_MARKER)
    if marker_offset < 0:
        fail("appcast is missing Sparkle's signed-feed trailer")
    trailer = data[marker_offset:].decode("utf-8", errors="strict")
    match = re.fullmatch(
        r"<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+/]+={0,2})\nlength: ([0-9]+)\n-->\s*",
        trailer,
    )
    if match is None:
        fail("appcast has a malformed Sparkle signed-feed trailer")
    try:
        decoded = base64.b64decode(match.group(1), validate=True)
    except ValueError:
        fail("appcast feed signature is not canonical base64")
    if len(decoded) != 64 or base64.b64encode(decoded).decode() != match.group(1):
        fail("appcast feed signature must be a canonical 64-byte Ed25519 signature")
    if int(match.group(2)) != marker_offset:
        fail("appcast signed-feed length does not match its signed bytes")


def check_no_deltas(root: ET.Element, directory: Path | None = None) -> None:
    if root.findall(f".//{SPARKLE}deltas"):
        fail("appcast contains forbidden delta enclosures")
    for enclosure in root.findall(".//enclosure"):
        if enclosure.get(f"{SPARKLE}deltaFrom") is not None:
            fail("appcast contains a forbidden delta enclosure")
    if directory is not None:
        for path in directory.rglob("*"):
            if path.is_file() and (path.suffix == ".delta" or "delta" in path.name.lower()):
                fail(f"prepared release contains a forbidden delta file: {path.name}")


def validate_feed_item(item: ET.Element) -> tuple[str, str, str]:
    enclosures = item.findall("enclosure")
    if len(enclosures) != 1:
        fail("every appcast item must contain exactly one full enclosure")
    enclosure = enclosures[0]
    build = enclosure.get(f"{SPARKLE}version", "")
    marketing = enclosure.get(f"{SPARKLE}shortVersionString", "")
    parse_version(build, "appcast build version")
    parse_version(marketing, "appcast marketing version", minimum_parts=3)
    archive_name = f"Bessie-{marketing}-{build}.zip"
    url = enclosure.get("url", "")
    validate_release_url(url, f"v{marketing}", archive_name)
    if enclosure.get("type") != "application/octet-stream":
        fail("appcast enclosure must be a full application/octet-stream archive")
    length = enclosure.get("length", "")
    if not length.isdigit() or int(length) <= 0:
        fail("appcast enclosure length must be a positive integer")
    signature = enclosure.get(f"{SPARKLE}edSignature", "")
    try:
        decoded_signature = base64.b64decode(signature, validate=True)
    except ValueError:
        fail("appcast archive signature is not base64")
    if len(decoded_signature) != 64:
        fail("appcast archive signature must decode to 64 bytes")
    if item.findtext(f"{SPARKLE}minimumSystemVersion") != MINIMUM_OS:
        fail(f"appcast minimum macOS must be {MINIMUM_OS}")
    if item.find("pubDate") is None:
        fail("appcast item is missing publication date")
    if item.find("description") is None and item.find(f"{SPARKLE}releaseNotesLink") is None \
            and item.find(f"{SPARKLE}fullReleaseNotesLink") is None:
        fail("appcast item is missing release notes")
    forbidden_elements = (
        f"{SPARKLE}channel",
        f"{SPARKLE}phasedRolloutInterval",
        f"{SPARKLE}criticalUpdate",
        f"{SPARKLE}informationalUpdate",
    )
    if any(item.find(name) is not None for name in forbidden_elements):
        fail("appcast item contains a forbidden channel, rollout, critical, or informational policy")
    return build, marketing, url


def validate_all_feed_items(root: ET.Element) -> None:
    seen_builds: set[str] = set()
    seen_urls: set[str] = set()
    for item in feed_items(root):
        build, _, url = validate_feed_item(item)
        if build in seen_builds or url in seen_urls:
            fail("appcast contains a duplicate build or enclosure URL")
        seen_builds.add(build)
        seen_urls.add(url)


def compare_retained_items(previous_path: Path, generated_path: Path) -> None:
    previous = parse_feed(previous_path)
    generated = parse_feed(generated_path)
    validate_all_feed_items(previous)
    validate_all_feed_items(generated)
    previous_items = {
        validate_feed_item(item)[0]: validate_feed_item(item)[2]
        for item in feed_items(previous)
    }
    generated_items = {
        validate_feed_item(item)[0]: validate_feed_item(item)[2]
        for item in feed_items(generated)
    }
    for build, url in previous_items.items():
        if generated_items.get(build) != url:
            fail(f"generated appcast dropped or rewrote retained build {build}")


def check_previous(appcast: Path, archive: Path, build: str, tag: str, marketing: str) -> None:
    root = parse_feed(appcast)
    validate_feed_signature_shape(appcast)
    check_no_deltas(root)
    validate_all_feed_items(root)
    items = feed_items(root)
    latest_build: str | None = None
    for item in items:
        enclosure = item.find("enclosure")
        if enclosure is None:
            continue
        previous_build = enclosure.get(f"{SPARKLE}version")
        url = enclosure.get("url", "")
        if f"/download/{tag}/" in url:
            fail(f"tag {tag} already appears in the previous appcast")
        if previous_build is not None and (
            latest_build is None or version_greater(previous_build, latest_build)
        ):
            latest_build = previous_build
    if latest_build is None:
        fail("previous appcast has no versioned full archive")
    if not version_greater(build, latest_build):
        fail(f"build {build} must be strictly greater than previous build {latest_build}")
    latest_item, latest_enclosure = enclosure_for_build(root, latest_build)
    previous_marketing = latest_enclosure.get(f"{SPARKLE}shortVersionString", "")
    if not version_at_least(marketing, previous_marketing):
        fail(f"marketing version {marketing} must not be lower than previous {previous_marketing}")
    expected_archive_name = f"Bessie-{previous_marketing}-{latest_build}.zip"
    if archive.name != expected_archive_name:
        fail(f"previous archive must be named {expected_archive_name}")
    previous_url = latest_enclosure.get("url", "")
    parsed_url = urlparse(previous_url)
    path_parts = parsed_url.path.split("/")
    try:
        previous_tag = path_parts[path_parts.index("download") + 1]
    except (ValueError, IndexError):
        fail("previous archive URL is not an immutable GitHub release URL")
    validate_release_url(previous_url, previous_tag, archive.name)
    del latest_item
    expected_length = latest_enclosure.get("length")
    if not archive.is_file() or expected_length != str(archive.stat().st_size):
        fail("previous archive length does not match the previous appcast")


def check_plist(path: Path, version: str, build: str, public_key: str) -> None:
    try:
        with path.open("rb") as handle:
            info = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as error:
        fail(f"could not parse production Info.plist: {error}")
    expected = {
        "CFBundleIdentifier": "dev.bessie.app",
        "CFBundleShortVersionString": version,
        "CFBundleVersion": build,
        "LSMinimumSystemVersion": MINIMUM_OS,
        "SUFeedURL": FEED_URL,
        "SUPublicEDKey": public_key,
        "SURequireSignedFeed": True,
        "SUVerifyUpdateBeforeExtraction": True,
        "SUSignedFeedFailureExpirationInterval": 0,
        "SUSendProfileInfo": False,
    }
    for key, value in expected.items():
        if info.get(key) != value or type(info.get(key)) is not type(value):
            fail(f"production Info.plist has invalid {key}")
    forbidden = {
        "SUAllowsInsecureUpdates",
        "SUEnableInstallerLauncherService",
        "SUPublicDSAKey",
        "SUPublicDSAKeyFile",
    }
    present = sorted(forbidden.intersection(info))
    if present:
        fail(f"production Info.plist contains deprecated/insecure policy: {', '.join(present)}")


def check_appcast_item(
    item: ET.Element,
    enclosure: ET.Element,
    metadata: dict[str, object],
    archive: Path,
) -> None:
    version = str(metadata["marketing_version"])
    build = str(metadata["build_version"])
    tag = str(metadata["tag"])
    archive_url = str(metadata["archive_url"])
    validate_feed_item(item)
    expected_attributes = {
        f"{SPARKLE}version": build,
        f"{SPARKLE}shortVersionString": version,
        "length": str(archive.stat().st_size),
        "url": archive_url,
        "type": "application/octet-stream",
    }
    enclosure_url = enclosure.get("url", "")
    validate_release_url(enclosure_url, tag, archive.name)
    for key, value in expected_attributes.items():
        if enclosure.get(key) != value:
            fail(f"appcast enclosure has invalid {key}")
    validate_release_url(archive_url, tag, archive.name)
    notes = item.find(f"{SPARKLE}releaseNotesLink")
    if notes is None:
        notes = item.find(f"{SPARKLE}fullReleaseNotesLink")
    expected_notes = f"https://github.com/skeletor-js/bessie/releases/tag/{tag}"
    if notes is None or notes.text != expected_notes:
        fail(f"appcast release notes URL must be {expected_notes}")


def verify_prepared(directory: Path) -> None:
    directory = directory.resolve()
    manifest_path = directory / "release.json"
    try:
        metadata = json.loads(manifest_path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        fail(f"could not read release.json: {error}")
    required = {
        "schema",
        "state",
        "source_commit",
        "tag",
        "marketing_version",
        "build_version",
        "minimum_system_version",
        "feed_url",
        "archive_name",
        "archive_url",
        "archive_length",
        "archive_sha256",
        "appcast_sha256",
        "sparkle_version",
        "sparkle_signature_verified_during_prepare",
        "sparkle_tools_archive_sha256",
        "notarization_submission_id",
        "notarization_archive_sha256",
        "notarization_status",
        "final_archive_extraction_verified",
        "byte_finalization_order",
    }
    missing = sorted(required.difference(metadata))
    if missing:
        fail(f"release.json is missing fields: {', '.join(missing)}")
    if metadata["schema"] != 1 or metadata["state"] != "prepared":
        fail("release.json has an unsupported schema or non-prepared state")
    version = str(metadata["marketing_version"])
    build = str(metadata["build_version"])
    tag = str(metadata["tag"])
    validate_version(version, build, tag)
    if not re.fullmatch(r"[0-9a-f]{40}", str(metadata["source_commit"])):
        fail("source commit must be a full lowercase Git object ID")
    if metadata["minimum_system_version"] != MINIMUM_OS:
        fail(f"release minimum macOS must be {MINIMUM_OS}")
    if metadata["feed_url"] != FEED_URL:
        fail(f"release feed URL must be {FEED_URL}")
    if metadata["sparkle_version"] != "2.9.5":
        fail("release must use Sparkle 2.9.5")
    if metadata["notarization_status"] != "Accepted":
        fail("release notarization status is not Accepted")
    if metadata["final_archive_extraction_verified"] is not True:
        fail("release lacks final archive extraction verification evidence")
    if metadata["sparkle_tools_archive_sha256"] != "34b9b2071f3de0012eca3faa3a9290bb94e62131e9a74f6dc91514a000097a6c":
        fail("release tools do not match the frozen Sparkle 2.9.5 archive")
    if not re.fullmatch(r"[0-9a-f]{64}", str(metadata["notarization_archive_sha256"])):
        fail("notarization archive SHA-256 is invalid")
    evidence = directory / "evidence"
    try:
        submission = json.loads((evidence / "notary-submission.json").read_text())
        notary_log = json.loads((evidence / "notary-log.json").read_text())
    except (OSError, json.JSONDecodeError) as error:
        fail(f"could not read redacted notarization evidence: {error}")
    if submission.get("id") != metadata["notarization_submission_id"] or submission.get("status") != "Accepted":
        fail("notarization submission evidence does not match release.json")
    if (
        notary_log.get("jobId") != metadata["notarization_submission_id"]
        or notary_log.get("status") != "Accepted"
        or notary_log.get("sha256") != metadata["notarization_archive_sha256"]
    ):
        fail("notarization log evidence does not bind the accepted local submission")
    if metadata["sparkle_signature_verified_during_prepare"] is not True:
        fail("release lacks prepare-time Sparkle signature verification evidence")
    expected_order = ["staple", "archive", "extract-verify", "checksum", "appcast-generate-sign", "sparkle-verify"]
    if metadata["byte_finalization_order"] != expected_order:
        fail("release was signed after byte finalization in an invalid order")
    archive_name = str(metadata["archive_name"])
    if Path(archive_name).name != archive_name or archive_name != f"Bessie-{version}-{build}.zip":
        fail("archive name does not match release versions")
    archive = directory / archive_name
    if not archive.is_file():
        fail(f"missing final archive: {archive_name}")
    if archive.stat().st_size != metadata["archive_length"]:
        fail("archive length changed after finalization")
    actual_archive_sha = sha256(archive)
    if actual_archive_sha != metadata["archive_sha256"]:
        fail("archive SHA-256 changed after finalization")
    checksum_path = directory / f"{archive_name}.sha256"
    expected_checksum = f"{actual_archive_sha}  {archive_name}\n"
    if not checksum_path.is_file() or checksum_path.read_text() != expected_checksum:
        fail("archive checksum file is missing or does not match final bytes")
    appcast = directory / "appcast.xml"
    if not appcast.is_file() or sha256(appcast) != metadata["appcast_sha256"]:
        fail("appcast SHA-256 changed after preparation")
    root = parse_feed(appcast)
    check_no_deltas(root, directory)
    validate_all_feed_items(root)
    item, enclosure = enclosure_for_build(root, build)
    check_appcast_item(item, enclosure, metadata, archive)
    validate_feed_signature_shape(appcast)
    print(f"Verified prepared Bessie release {tag} build {build} (secret-free).")


def redact_notary(source: Path, destination: Path) -> None:
    try:
        data = json.loads(source.read_text())
    except (OSError, json.JSONDecodeError) as error:
        fail(f"could not parse notary evidence: {error}")
    allowed = {
        key: data[key]
        for key in ("id", "jobId", "status", "statusSummary", "message", "sha256")
        if key in data
    }
    issues = []
    for issue in data.get("issues", []) if isinstance(data.get("issues"), list) else []:
        if not isinstance(issue, dict):
            continue
        clean = {key: issue[key] for key in ("severity", "code", "message") if key in issue}
        if "path" in issue:
            clean["path"] = Path(str(issue["path"])).name
        issues.append(clean)
    if issues:
        allowed["issues"] = issues
    destination.write_text(json.dumps(allowed, indent=2, sort_keys=True) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    version = sub.add_parser("validate-version")
    version.add_argument("--version", required=True)
    version.add_argument("--build", required=True)
    version.add_argument("--tag", required=True)
    url = sub.add_parser("validate-url")
    url.add_argument("--url", required=True)
    url.add_argument("--tag", required=True)
    url.add_argument("--archive", required=True)
    previous = sub.add_parser("check-previous")
    previous.add_argument("--appcast", type=Path, required=True)
    previous.add_argument("--archive", type=Path, required=True)
    previous.add_argument("--build", required=True)
    previous.add_argument("--tag", required=True)
    previous.add_argument("--version", required=True)
    plist = sub.add_parser("check-plist")
    plist.add_argument("--path", type=Path, required=True)
    plist.add_argument("--version", required=True)
    plist.add_argument("--build", required=True)
    plist.add_argument("--public-key", required=True)
    verify = sub.add_parser("verify")
    verify.add_argument("directory", type=Path)
    redact = sub.add_parser("redact-notary")
    redact.add_argument("--source", type=Path, required=True)
    redact.add_argument("--destination", type=Path, required=True)
    compare = sub.add_parser("compare-retained")
    compare.add_argument("--previous", type=Path, required=True)
    compare.add_argument("--generated", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "validate-version":
        validate_version(args.version, args.build, args.tag)
    elif args.command == "validate-url":
        validate_release_url(args.url, args.tag, args.archive)
    elif args.command == "check-previous":
        check_previous(args.appcast, args.archive, args.build, args.tag, args.version)
    elif args.command == "check-plist":
        check_plist(args.path, args.version, args.build, args.public_key)
    elif args.command == "verify":
        verify_prepared(args.directory)
    elif args.command == "redact-notary":
        redact_notary(args.source, args.destination)
    elif args.command == "compare-retained":
        compare_retained_items(args.previous, args.generated)


if __name__ == "__main__":
    main()
