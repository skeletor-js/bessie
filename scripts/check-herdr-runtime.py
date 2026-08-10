#!/usr/bin/env python3
import hashlib
import json
import pathlib
import re

repo = pathlib.Path(__file__).resolve().parent.parent
lock_path = repo / "scripts/herdr-runtime-lock.json"
lock = json.loads(lock_path.read_text())

expected = {
    "version": "0.8.0",
    "protocol": 19,
    "release_artifact_commit": "346411fa21afd297f5ed3b3fa56f9e3fbf7654b7",
    "compatibility_source_baseline": "346411fa21afd297f5ed3b3fa56f9e3fbf7654b7",
    "apache_relicensing_commit": "cd5ea1be0e69ed49b6f32f7ed5b333f6c8526874",
    "platform": "macOS",
    "architecture": "arm64",
    "url": "https://github.com/herdrdev/herdr/releases/download/v0.8.0/herdr-macos-aarch64",
    "sha256": "d53a9f93fccfdfcc55632927bf51002f5add0aa7990bcdf508ffbd84ac658178",
    "expected_version_output": "herdr 0.8.0",
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
    "source_path": "Sources/BessieApp/Resources/Herdr-LICENSE.txt",
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
