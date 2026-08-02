#!/usr/bin/env python3
import hashlib
import json
import pathlib
import re

repo = pathlib.Path(__file__).resolve().parent.parent
lock_path = repo / "scripts/herdr-runtime-lock.json"
lock = json.loads(lock_path.read_text())

expected = {
    "version": "0.7.5",
    "protocol": 17,
    "release_artifact_commit": "ef4c23f5775bb8cfec05f05d0844226ff959a07a",
    "compatibility_source_baseline": "b4112743cff42452b5d18558bf2d55bbbfff8c69",
    "apache_relicensing_commit": "cd5ea1be0e69ed49b6f32f7ed5b333f6c8526874",
    "platform": "macOS",
    "architecture": "arm64",
    "url": "https://github.com/herdrdev/herdr/releases/download/v0.7.5/herdr-macos-aarch64",
    "sha256": "37350546b0012555943b92eaf962665de4e264395baeb44227b8015e8ff5b0d6",
    "expected_version_output": "herdr 0.7.5",
}
for key, value in expected.items():
    if lock.get(key) != value:
        raise SystemExit(f"runtime lock {key} drifted: {lock.get(key)!r}")

compatibility = (repo / "Sources/BessieCore/BessieCompatibility.swift").read_text()
swift_expectations = {
    "herdrVersion": lock["version"],
    "protocolVersion": str(lock["protocol"]),
    "herdrSourceRevision": lock["compatibility_source_baseline"],
}
for name, value in swift_expectations.items():
    pattern = rf"public static let {name} = \"?{re.escape(value)}\"?"
    if not re.search(pattern, compatibility):
        raise SystemExit(f"BessieCompatibility.{name} does not match the runtime lock")

notice = lock.get("notice", {})
required_notice = {
    "license": "Apache-2.0",
    "source_path": "docs/research/herdr-apache-2.0-license.txt",
    "bundle_path": "Contents/Resources/Herdr/LICENSE",
    "source_url": "https://raw.githubusercontent.com/herdrdev/herdr/cd5ea1be0e69ed49b6f32f7ed5b333f6c8526874/LICENSE",
    "relicense_commit_url": "https://github.com/herdrdev/herdr/commit/cd5ea1be0e69ed49b6f32f7ed5b333f6c8526874",
}
for key, value in required_notice.items():
    if notice.get(key) != value:
        raise SystemExit(f"runtime notice {key} drifted: {notice.get(key)!r}")

notice_path = repo / notice["source_path"]
try:
    notice_bytes = notice_path.read_bytes()
except OSError:
    raise SystemExit(f"required Herdr notice is missing: {notice_path}")
notice_sha = hashlib.sha256(notice_bytes).hexdigest()
if notice_sha != "c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4":
    raise SystemExit(f"Herdr Apache license text drifted: {notice_sha}")

package_script = (repo / "scripts/package-app.sh").read_text()
for required in (
    "fetch-herdr-runtime.sh",
    "Contents/Resources/Herdr/herdr",
    "notice_bundle_path",
    "codesign --verify --deep --strict",
):
    if required not in package_script:
        raise SystemExit(f"package-app.sh is missing runtime expectation: {required}")

print("Herdr runtime lock, compatibility, notice, and packaging checks passed.")
