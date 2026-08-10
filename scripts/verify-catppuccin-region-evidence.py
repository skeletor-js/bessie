#!/usr/bin/env python3
"""Create and fail-closed validate Catppuccin region evidence."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import sys
import tempfile
from pathlib import Path
from typing import Any

INTERACTION_REGIONS = (
    ("primary-text", "header / Catppuccin interaction acceptance", "Text primary foreground", "font rasterization and antialiasing may vary"),
    ("secondary-text", "header / deterministic state subtitle", "Subtext hierarchy foreground", "font rasterization and antialiasing may vary"),
    ("hover", "left column / Hover treatment row", "Overlay 2 at 10% over Base", "composited edge antialiasing may vary"),
    ("selected-fill", "left column / Selected + active row interior", "Overlay 2 at 25% over Base", "composited edge antialiasing may vary"),
    ("active-border", "left column / Selected + active row outline", "Lavender active border (bounded Latte derivative permitted)", "one-pixel geometry and display scale may vary"),
    ("panel-elevation", "left column / Native controls and focus group", "Surface 0 elevated panel over Base", "native group-box material may vary without collapsing the surface ladder"),
    ("blue-control", "left column / enabled toggle", "Blue control tint", "macOS may shade the authored tint for control chrome"),
    ("blue-link", "left column / Blue semantic link", "Blue link foreground (bounded Latte derivative permitted)", "underline and hover decoration may vary"),
    ("native-focus", "left column / focused text field outer focus indicator", "native macOS keyboard focus independent of semantic fills", "system focus-ring geometry and strength may vary by macOS"),
    ("rosewater-insertion", "left column / focused text field insertion point", "Rosewater insertion-point tint", "caret blink phase may vary; capture must visibly contain the focused caret"),
    ("diff-hunk", "right column / focused hunk plate", "Peach hunk foreground and Peach at 20% plate", "font rasterization and composited edges may vary"),
    ("diff-added", "right column / added line plate", "Green added foreground and Green at 20% plate", "font rasterization and composited edges may vary"),
    ("diff-removed", "right column / removed line plate", "Red removed foreground and Red at 20% plate", "font rasterization and composited edges may vary"),
    ("destructive", "right column / destructive-error treatment", "Red destructive/error foreground", "SF Symbol rendering may vary"),
)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def expected_entries(capture_dir: Path) -> list[dict[str, object]]:
    entries: list[dict[str, object]] = []
    for flavor in ("latte", "mocha"):
        interaction = capture_dir / f"Bessie-theme-catppuccin-{flavor}-interaction.png"
        menu = capture_dir / f"Bessie-theme-catppuccin-{flavor}-menu-bar.png"
        live = capture_dir / f"Bessie-theme-catppuccin-{flavor}-live.png"
        for region_id, region, treatment, variance in INTERACTION_REGIONS:
            entries.append({
                "id": f"{flavor}.{region_id}",
                "screenshot": interaction.name,
                "screenshot_sha256": digest(interaction),
                "region": region,
                "expected_semantic_treatment": treatment,
                "allowed_platform_variance": variance,
                "pass": False,
                "review_note": "Not reviewed",
            })
        entries.extend((
            {
                "id": f"{flavor}.menu-bar",
                "screenshot": menu.name,
                "screenshot_sha256": digest(menu),
                "region": "complete menu-bar popover",
                "expected_semantic_treatment": "same concrete Catppuccin semantic palette as the main window",
                "allowed_platform_variance": "popover shadow, corner clipping, and menu-bar placement may vary",
                "pass": False,
                "review_note": "Not reviewed",
            },
            {
                "id": f"{flavor}.terminal-seam",
                "screenshot": live.name,
                "screenshot_sha256": digest(live),
                "region": "live workspace terminal/chrome boundary and ANSI marker output",
                "expected_semantic_treatment": "official Ghostty terminal palette beside matching native chrome",
                "allowed_platform_variance": "terminal glyph rasterization and cursor blink phase may vary",
                "pass": False,
                "review_note": "Not reviewed",
            },
        ))
    for flavor in ("latte", "frappe", "macchiato", "mocha"):
        settings = capture_dir / f"Bessie-theme-catppuccin-{flavor}-settings.png"
        entries.extend((
            {
                "id": f"{flavor}.settings-selection",
                "screenshot": settings.name,
                "screenshot_sha256": digest(settings),
                "region": "Appearance picker / selected Catppuccin flavor row and checkmark",
                "expected_semantic_treatment": "selected fill plus non-color selected indication using the concrete flavor",
                "allowed_platform_variance": "checkmark and row geometry may vary by macOS",
                "pass": False,
                "review_note": "Not reviewed",
            },
            {
                "id": f"{flavor}.settings-text",
                "screenshot": settings.name,
                "screenshot_sha256": digest(settings),
                "region": "Appearance picker / primary and secondary labels",
                "expected_semantic_treatment": "readable Text and Subtext hierarchy on the concrete flavor surfaces",
                "allowed_platform_variance": "font rasterization and antialiasing may vary",
                "pass": False,
                "review_note": "Not reviewed",
            },
        ))
        if flavor in ("frappe", "macchiato"):
            live = capture_dir / f"Bessie-theme-catppuccin-{flavor}-live.png"
            entries.append({
                "id": f"{flavor}.terminal-seam",
                "screenshot": live.name,
                "screenshot_sha256": digest(live),
                "region": "live workspace terminal/chrome boundary and ANSI marker output",
                "expected_semantic_treatment": "official Ghostty terminal palette beside matching native chrome",
                "allowed_platform_variance": "terminal glyph rasterization and cursor blink phase may vary",
                "pass": False,
                "review_note": "Not reviewed",
            })
    return entries


def write_template(capture_dir: Path, manifest: Path) -> None:
    entries = expected_entries(capture_dir)
    receipt = json.loads((capture_dir / "acceptance-receipt.json").read_text(encoding="utf-8"))
    identity = {
        "installed_executable": "/Applications/Bessie.app/Contents/MacOS/BessieApp",
        "installed_sha256": receipt["installed_sha256"],
        "installed_herdr_sha256": receipt["installed_herdr_sha256"],
    }
    manifest.write_text(json.dumps({
        "schema_version": 1,
        "review_kind": "human-region-oracle",
        "artifact_identity": identity,
        "regions": entries,
    }, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote fail-closed region evidence template: {manifest}")


CANONICAL_FIELDS = (
    "screenshot",
    "region",
    "expected_semantic_treatment",
    "allowed_platform_variance",
)


def validate(capture_dir: Path, manifest: Path) -> list[str]:
    problems: list[str] = []
    capture_root = capture_dir.resolve()
    try:
        payload = json.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return [f"cannot read manifest: {error}"]
    if not isinstance(payload, dict):
        return ["manifest must be an object"]
    if payload.get("schema_version") != 1:
        problems.append("schema_version must be 1")
    try:
        receipt = json.loads((capture_root / "acceptance-receipt.json").read_text(encoding="utf-8"))
        expected_identity = {
            "installed_executable": "/Applications/Bessie.app/Contents/MacOS/BessieApp",
            "installed_sha256": receipt["installed_sha256"],
            "installed_herdr_sha256": receipt["installed_herdr_sha256"],
        }
        if payload.get("artifact_identity") != expected_identity:
            problems.append("artifact_identity does not match the stopped-app acceptance receipt")
    except (OSError, json.JSONDecodeError, KeyError, TypeError) as error:
        problems.append(f"cannot validate acceptance receipt identity: {error}")
    try:
        canonical_entries = expected_entries(capture_root)
    except OSError as error:
        return problems + [f"cannot build canonical region inventory: {error}"]
    canonical = {str(entry["id"]): entry for entry in canonical_entries}
    regions = payload.get("regions")
    if not isinstance(regions, list):
        return problems + ["regions must be an array"]

    identifiers = [entry.get("id") if isinstance(entry, dict) else None for entry in regions]
    duplicate_ids = sorted({str(item) for item in identifiers if identifiers.count(item) > 1})
    if duplicate_ids:
        problems.append(f"duplicate region IDs: {duplicate_ids}")
    actual_ids = {item for item in identifiers if isinstance(item, str)}
    expected_ids = set(canonical)
    if actual_ids != expected_ids or len(regions) != len(canonical):
        problems.append(
            f"region inventory mismatch: expected={sorted(expected_ids)} "
            f"actual={sorted(set(str(item) for item in identifiers))}"
        )

    for entry in regions:
        if not isinstance(entry, dict):
            problems.append("region entry is not an object")
            continue
        identifier = entry.get("id", "<missing>")
        expected = canonical.get(identifier) if isinstance(identifier, str) else None
        for field in (*CANONICAL_FIELDS, "screenshot_sha256", "pass", "review_note"):
            if field not in entry:
                problems.append(f"{identifier}: missing {field}")
        if expected is not None:
            for field in CANONICAL_FIELDS:
                if entry.get(field) != expected[field]:
                    problems.append(f"{identifier}: {field} does not match canonical metadata")

        screenshot_name = entry.get("screenshot")
        screenshot: Path | None = None
        if (
            not isinstance(screenshot_name, str)
            or not screenshot_name
            or Path(screenshot_name).is_absolute()
            or screenshot_name in {".", ".."}
            or "/" in screenshot_name
            or "\\" in screenshot_name
            or Path(screenshot_name).name != screenshot_name
        ):
            problems.append(f"{identifier}: screenshot must be a simple basename inside capture_dir")
        else:
            candidate = capture_root / screenshot_name
            try:
                resolved = candidate.resolve(strict=True)
            except OSError:
                problems.append(f"{identifier}: missing screenshot {screenshot_name}")
            else:
                if resolved.parent != capture_root or not resolved.is_file():
                    problems.append(f"{identifier}: screenshot resolves outside capture_dir or is not a file")
                else:
                    screenshot = resolved
        if screenshot is not None and entry.get("screenshot_sha256") != digest(screenshot):
            problems.append(f"{identifier}: screenshot digest mismatch")
        if entry.get("pass") is not True:
            problems.append(f"{identifier}: explicit boolean pass=true required (current={entry.get('pass')!r})")
        review_note = entry.get("review_note")
        if (
            not isinstance(review_note, str)
            or not review_note.strip()
            or review_note.strip() == "Not reviewed"
        ):
            problems.append(f"{identifier}: nonempty explicit review_note required")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("capture_dir", type=Path, nargs="?")
    parser.add_argument("manifest", type=Path, nargs="?")
    parser.add_argument("--write-template", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        with tempfile.TemporaryDirectory() as directory:
            capture_dir = Path(directory)
            fixture_bytes: dict[Path, bytes] = {}
            for flavor in ("latte", "mocha"):
                for kind in ("interaction", "menu-bar", "live"):
                    path = capture_dir / f"Bessie-theme-catppuccin-{flavor}-{kind}.png"
                    fixture_bytes[path] = f"fixture-{flavor}-{kind}".encode()
            for flavor in ("latte", "frappe", "macchiato", "mocha"):
                path = capture_dir / f"Bessie-theme-catppuccin-{flavor}-settings.png"
                fixture_bytes[path] = f"fixture-{flavor}-settings".encode()
            for flavor in ("frappe", "macchiato"):
                path = capture_dir / f"Bessie-theme-catppuccin-{flavor}-live.png"
                fixture_bytes[path] = f"fixture-{flavor}-live".encode()
            for path, contents in fixture_bytes.items():
                path.write_bytes(contents)
            receipt_path = capture_dir / "acceptance-receipt.json"
            receipt_payload = {
                "installed_sha256": "fixture-app",
                "installed_herdr_sha256": "fixture-herdr",
            }
            receipt_path.write_text(json.dumps(receipt_payload), encoding="utf-8")
            manifest = capture_dir / "region-evidence.json"
            write_template(capture_dir, manifest)
            pending = validate(capture_dir, manifest)
            assert pending
            assert any("boolean pass=true" in problem for problem in pending)
            assert any("review_note" in problem for problem in pending)
            payload = json.loads(manifest.read_text(encoding="utf-8"))
            for region in payload["regions"]:
                region["pass"] = True
                region["review_note"] = "fixture reviewed"
            reviewed = copy.deepcopy(payload)

            def restore() -> dict[str, Any]:
                for path, contents in fixture_bytes.items():
                    if path.is_symlink():
                        path.unlink()
                    path.write_bytes(contents)
                receipt_path.write_text(json.dumps(receipt_payload), encoding="utf-8")
                candidate = copy.deepcopy(reviewed)
                manifest.write_text(json.dumps(candidate), encoding="utf-8")
                return candidate

            def must_fail(candidate: dict[str, Any], expected_problem: str) -> None:
                manifest.write_text(json.dumps(candidate), encoding="utf-8")
                found = validate(capture_dir, manifest)
                assert any(expected_problem in problem for problem in found), (expected_problem, found)

            restore()
            assert validate(capture_dir, manifest) == []

            candidate = restore()
            first = candidate["regions"][0]
            for region in candidate["regions"]:
                region["screenshot"] = first["screenshot"]
                region["screenshot_sha256"] = first["screenshot_sha256"]
            must_fail(candidate, "screenshot does not match canonical metadata")

            for field in ("region", "expected_semantic_treatment", "allowed_platform_variance"):
                candidate = restore()
                candidate["regions"][0][field] = "mutated"
                must_fail(candidate, f"{field} does not match canonical metadata")

            candidate = restore()
            candidate["regions"][0]["screenshot"] = "/tmp/outside.png"
            must_fail(candidate, "simple basename")

            candidate = restore()
            candidate["regions"][0]["screenshot"] = "../outside.png"
            must_fail(candidate, "simple basename")

            candidate = restore()
            canonical_screenshot = capture_dir / candidate["regions"][0]["screenshot"]
            outside_screenshot = capture_dir.parent / f"{capture_dir.name}-outside.png"
            outside_screenshot.write_bytes(b"outside")
            canonical_screenshot.unlink()
            canonical_screenshot.symlink_to(outside_screenshot)
            must_fail(candidate, "resolves outside capture_dir")
            outside_screenshot.unlink()

            candidate = restore()
            candidate["regions"][-1] = copy.deepcopy(candidate["regions"][0])
            must_fail(candidate, "duplicate region IDs")

            for note_value in (None, "", "Not reviewed"):
                candidate = restore()
                if note_value is None:
                    del candidate["regions"][0]["review_note"]
                else:
                    candidate["regions"][0]["review_note"] = note_value
                must_fail(candidate, "review_note")

            candidate = restore()
            receipt_path.write_text(json.dumps({
                "installed_sha256": "mutated",
                "installed_herdr_sha256": "fixture-herdr",
            }), encoding="utf-8")
            must_fail(candidate, "artifact_identity")

            candidate = restore()
            candidate["regions"][0]["pass"] = 1
            must_fail(candidate, "boolean pass=true")

            restore()
            tampered = capture_dir / "Bessie-theme-catppuccin-latte-live.png"
            tampered.write_bytes(b"tampered")
            assert any("digest mismatch" in problem for problem in validate(capture_dir, manifest))

            restore()
            assert validate(capture_dir, manifest) == []
        print("Catppuccin region evidence self-test passed.")
        return 0
    if args.capture_dir is None or args.manifest is None:
        parser.error("capture_dir and manifest are required unless --self-test is used")
    capture_dir = args.capture_dir.resolve()
    manifest = args.manifest.resolve()
    if args.write_template:
        try:
            write_template(capture_dir, manifest)
        except OSError as error:
            print(f"Cannot create region evidence template: {error}", file=sys.stderr)
            return 1
    problems = validate(capture_dir, manifest)
    if problems:
        print("Catppuccin region evidence is incomplete or failed:", file=sys.stderr)
        for problem in problems:
            print(f"- {problem}", file=sys.stderr)
        return 1
    print(f"Catppuccin region evidence passed ({len(expected_entries(capture_dir))} explicit regions).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
