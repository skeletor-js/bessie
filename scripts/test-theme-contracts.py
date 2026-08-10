#!/usr/bin/env python3
"""Independent regression checks for finite Catppuccin audit contracts."""

from __future__ import annotations

import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
EXPECTED_CALLER_FILES = (
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


def load_audit():
    path = ROOT / "scripts/check-theme-color-escapes.py"
    spec = importlib.util.spec_from_file_location("theme_color_audit", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> None:
    audit = load_audit()
    assert audit.CALLER_FILES == EXPECTED_CALLER_FILES, (
        "Catppuccin caller inventory changed. Update the independent contract "
        "only when the reviewed U3 boundary intentionally changes."
    )
    assert len(set(audit.CALLER_FILES)) == len(audit.CALLER_FILES)
    missing = [relative for relative in EXPECTED_CALLER_FILES if not (ROOT / relative).is_file()]
    assert not missing, f"missing audited callers: {missing}"
    audit.self_test()

    acceptance = (ROOT / "scripts/rebuild-install-catppuccin-themes.sh").read_text(encoding="utf-8")
    assert './scripts/rebuild-install-shortcuts.sh --install-only "$mac_dir"' in acceptance
    assert '"method": "pane.send_input"' in acceptance
    assert '"keys": ["Enter"]' in acceptance
    assert "BESSIE_THEME_INPUT_雪豹_🦬_é" in acceptance
    assert "BESSIE_THEME_ANSI_16_牛é🐄" in acceptance
    assert "_bessie_process_matches" in acceptance and "kill -KILL" in acceptance
    assert "--verify-evidence" in acceptance
    assert "verify-catppuccin-region-evidence.py" in acceptance
    integrity_index = acceptance.rindex("real_presentation_after=")
    assert "/usr/bin/open" not in acceptance[integrity_index:], (
        "No app launch may follow the final real-presentation integrity check."
    )
    marker_index = acceptance.index("CATPPUCCIN_ACCEPTANCE_OK")
    assert marker_index < acceptance.index("run_root="), (
        "The only success marker must remain in no-launch evidence-verification mode."
    )
    print(f"Catppuccin theme contract self-tests passed ({len(EXPECTED_CALLER_FILES)} callers).")


if __name__ == "__main__":
    main()