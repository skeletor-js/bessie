#!/usr/bin/env python3
"""Reject native theme-role escapes in the U3 caller boundary."""

from __future__ import annotations

import argparse
import re
import sys
import tempfile
from pathlib import Path

CALLER_FILES = (
    "Sources/BessieApp/BessieApp.swift",
    "Sources/BessieApp/BessieCommandPalette.swift",
    "Sources/BessieApp/BessieDesignSystem.swift",
    "Sources/BessieApp/BessieSettings.swift",
    "Sources/BessieApp/FollowFilesSurface.swift",
    "Sources/BessieApp/MarkdownFileEditor.swift",
    "Sources/BessieApp/OnboardingView.swift",
    "Sources/BessieApp/ProductSurfaces.swift",
    "Sources/BessieApp/RuntimeSettingsView.swift",
)

FORBIDDEN = (
    ("broad strong tint", re.compile(r"\.tint\s*\(\s*BessieDesign\.strong\s*\)")),
    ("caller-owned selected opacity", re.compile(r"BessieDesign\.selected\s*\.\s*opacity\s*\(")),
    ("direct red semantic escape", re.compile(r"BessieSemanticColor\s*\.\s*red\b")),
    (
        "direct system semantic color",
        re.compile(
            r"\.(?:foregroundStyle|foregroundColor|fill|stroke|tint)\s*"
            r"\(\s*(?:Color\s*\.\s*|\.)(?:primary|secondary|red|white|black)\s*\)"
        ),
    ),
)

RAW_CALLER_COLOR = re.compile(
    r"(?:Color|NSColor)\s*(?:\(\s*(?:(?:\.\s*(?:sRGB|displayP3)\s*,\s*(?:red|white)\s*:)"
    r"|(?:red|white|nsColor|srgbRed|displayP3Red)\s*:)"
    r"|\.\s*(?:primary|secondary|red|white|black)\b)",
    re.MULTILINE,
)

DESIGN_SYSTEM = "Sources/BessieApp/BessieDesignSystem.swift"

# Raw colors are reviewed only inside the concrete fallback palette builder.
# Exact, unique declaration anchors make this fail closed if the declaration is
# renamed, duplicated, or moved; line numbers are deliberately not trusted.
REVIEWED_RAW_COLOR_SPANS = {
    DESIGN_SYSTEM: (
        (
            "fallback concrete palette definitions",
            "    private static func gray(_ value: UInt8) -> Color {\n",
            "    static let desk = BessieSemanticColor(.desk)\n",
        ),
    ),
}

# Fixed diagnostic colors intentionally do not follow the selected app theme:
# this fallback must remain recognizable when a packaged design asset is absent.
ALLOWLIST = {
    (
        DESIGN_SYSTEM,
        "Rectangle().fill(.red)",
        "direct system semantic color",
    ),
    (
        DESIGN_SYSTEM,
        'Text("!").font(.system(size: max(7, size * 0.7), weight: .bold)).foregroundStyle(.white)',
        "direct system semantic color",
    ),
    (
        "Sources/BessieApp/ProductSurfaces.swift",
        "Color.black.opacity(BessieCommandPalette.scrimOpacity)",
        "raw caller color",
    ),
}


def reviewed_raw_color_spans(relative: str, text: str) -> tuple[list[tuple[int, int]], list[str]]:
    spans: list[tuple[int, int]] = []
    problems: list[str] = []
    for label, start_anchor, end_anchor in REVIEWED_RAW_COLOR_SPANS.get(relative, ()):
        if text.count(start_anchor) != 1 or text.count(end_anchor) != 1:
            problems.append(f"{relative}: reviewed raw-color span anchors invalid: {label}")
            continue
        start = text.index(start_anchor)
        end = text.index(end_anchor)
        if end <= start:
            problems.append(f"{relative}: reviewed raw-color span ordering invalid: {label}")
            continue
        spans.append((start, end))
    return spans, problems


def luminance_mask_spans(text: str) -> list[tuple[int, int]]:
    """Return SwiftUI mask closures where bare white/black encode mask coverage."""
    spans: list[tuple[int, int]] = []
    for match in re.finditer(r"\.mask\s*\{", text):
        depth = 1
        cursor = match.end()
        while cursor < len(text) and depth:
            if text[cursor] == "{":
                depth += 1
            elif text[cursor] == "}":
                depth -= 1
            cursor += 1
        if depth == 0:
            spans.append((match.start(), cursor))
    return spans


def violations(root: Path) -> list[str]:
    problems: list[str] = []
    for relative in CALLER_FILES:
        path = root / relative
        if not path.is_file():
            problems.append(f"{relative}: missing required audit input")
            continue
        text = path.read_text(encoding="utf-8")
        lines = text.splitlines()
        reviewed_spans, span_problems = reviewed_raw_color_spans(relative, text)
        mask_spans = luminance_mask_spans(text)
        problems.extend(span_problems)
        for label, pattern in FORBIDDEN:
            for match in pattern.finditer(text):
                line_number = text.count("\n", 0, match.start()) + 1
                line = lines[line_number - 1].strip()
                if (relative, line, label) not in ALLOWLIST:
                    problems.append(f"{relative}:{line_number}: {label}: {line}")
        # Raw colors are forbidden in every audited file. BessieDesignSystem is
        # exempt only in the exact reviewed palette declaration span above.
        for match in RAW_CALLER_COLOR.finditer(text):
            if any(start <= match.start() and match.end() <= end for start, end in reviewed_spans):
                continue
            # Bare white/black inside a SwiftUI mask are luminance/coverage
            # operators, not rendered theme colors. Qualified expressions such
            # as Color.white.opacity(...) remain audited.
            if (
                re.fullmatch(r"(?:Color|NSColor)\s*\.\s*(?:white|black)", match.group())
                and any(start <= match.start() and match.end() <= end for start, end in mask_spans)
                and not text[match.end():].lstrip().startswith(".")
            ):
                continue
            line_number = text.count("\n", 0, match.start()) + 1
            line = lines[line_number - 1].strip()
            if (relative, line, "raw caller color") not in ALLOWLIST:
                problems.append(f"{relative}:{line_number}: raw caller color: {line}")
    return problems


def self_test() -> None:
    assert FORBIDDEN[0][1].search(".tint(BessieDesign.strong)")
    assert FORBIDDEN[1][1].search("BessieDesign.selected.opacity(0.2)")
    assert FORBIDDEN[3][1].search(".foregroundStyle(.secondary)")
    assert FORBIDDEN[3][1].search(".foregroundStyle(\n    .red\n)")
    assert FORBIDDEN[3][1].search(".tint(Color.red)")
    assert RAW_CALLER_COLOR.search("Color(red: 1, green: 0, blue: 0)")
    assert RAW_CALLER_COLOR.search("Color(\n red: 1,\n green: 0,\n blue: 0\n)")
    assert RAW_CALLER_COLOR.search("Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)")
    assert RAW_CALLER_COLOR.search("Color(\n .displayP3,\n red: 1,\n green: 0,\n blue: 0,\n opacity: 1\n)")
    assert RAW_CALLER_COLOR.search("NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)")
    assert RAW_CALLER_COLOR.search("NSColor(\n displayP3Red: 1,\n green: 0,\n blue: 0,\n alpha: 1\n)")
    assert RAW_CALLER_COLOR.search("Color.red")
    diagnostic = "Rectangle().fill(.red)"
    assert (
        DESIGN_SYSTEM,
        diagnostic,
        "direct system semantic color",
    ) in ALLOWLIST

    # Exercise the full file-walking path with isolated violation fixtures. A
    # regex assertion alone can pass while line reporting, allowlisting, or
    # caller iteration is accidentally broken.
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        for relative in CALLER_FILES:
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            if relative == DESIGN_SYSTEM:
                path.write_text(
                    "enum BessieDesign {\n"
                    "    private static func gray(_ value: UInt8) -> Color {\n"
                    "        Color(.sRGB, white: Double(value) / 255, opacity: 1)\n"
                    "    }\n"
                    "    static func palette() -> Color { Color(red: 1, green: 1, blue: 1) }\n"
                    "    static let desk = BessieSemanticColor(.desk)\n"
                    "}\n",
                    encoding="utf-8",
                )
            else:
                path.write_text("struct SafeFixture {}\n", encoding="utf-8")
        assert violations(root) == []
        fixture = root / CALLER_FILES[0]
        cases = (
            ("struct Fixture { var body: some View { Text(\"x\").tint(BessieDesign.strong) } }\n", "broad strong tint"),
            ("let fill = BessieDesign.selected.opacity(0.2)\n", "caller-owned selected opacity"),
            ("let color = BessieSemanticColor.red\n", "direct red semantic escape"),
            ("Text(\"x\").foregroundStyle(.secondary)\n", "direct system semantic color"),
            ("let color = Color(red: 1, green: 0, blue: 0)\n", "raw caller color"),
            ("let color = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)\n", "raw caller color"),
            ("let color = Color(\n    .displayP3,\n    red: 1,\n    green: 0,\n    blue: 0,\n    opacity: 1\n)\n", "raw caller color"),
            ("let color = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)\n", "raw caller color"),
            ("let color = NSColor(\n    displayP3Red: 1,\n    green: 0,\n    blue: 0,\n    alpha: 1\n)\n", "raw caller color"),
        )
        for source, label in cases:
            fixture.write_text(source, encoding="utf-8")
            found = violations(root)
            assert any(label in problem for problem in found), (label, found)
        fixture.write_text("struct SafeFixture {}\n", encoding="utf-8")

        # The same constructor accepted in the reviewed concrete palette span
        # must fail when it appears in a component/view body.
        design_fixture = root / DESIGN_SYSTEM
        reviewed_source = design_fixture.read_text(encoding="utf-8")
        design_fixture.write_text(
            reviewed_source
            + "struct ComponentFixture: View {\n"
            + "    var body: some View { Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1) }\n"
            + "}\n",
            encoding="utf-8",
        )
        found = violations(root)
        assert any(DESIGN_SYSTEM in problem and "raw caller color" in problem for problem in found), found

        design_fixture.write_text(
            reviewed_source
            + "struct ComponentFixture: View {\n"
            + "    var body: some View { Color.white }\n"
            + "}\n",
            encoding="utf-8",
        )
        found = violations(root)
        assert any(DESIGN_SYSTEM in problem and "raw caller color" in problem for problem in found), found

        # Anchor drift must disable the reviewed palette exemption rather than
        # silently moving it to unrelated declarations.
        design_fixture.write_text(
            reviewed_source.replace("private static func gray", "private static func renamedGray"),
            encoding="utf-8",
        )
        found = violations(root)
        assert any("reviewed raw-color span anchors invalid" in problem for problem in found), found


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    problems = violations(args.root.resolve())
    if problems:
        print("Native theme color escape audit failed:", file=sys.stderr)
        for problem in problems:
            print(f"- {problem}", file=sys.stderr)
        return 1
    print(f"Native theme color escape audit passed ({len(CALLER_FILES)} files).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
