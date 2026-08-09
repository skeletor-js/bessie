#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

bash -n scripts/check.sh scripts/check-ui-copy.sh scripts/capture-redesign-matrix.sh scripts/dogfood-install-signed.sh scripts/fetch-herdr-runtime.sh scripts/lib/bessie-app-lifecycle.sh scripts/lib/sparkle-packaging.sh scripts/mac-verify.sh scripts/package-app.sh scripts/rebuild-install-catppuccin-themes.sh scripts/rebuild-install-shortcuts.sh scripts/release-app.sh scripts/run-hardening-probes.sh scripts/test-release-app.sh scripts/test-sparkle-packaging.sh scripts/verify-app-install-lifecycle.sh
python3 -c 'import ast, pathlib; ast.parse(pathlib.Path("scripts/release-metadata.py").read_text())'
./scripts/test-sparkle-packaging.sh
./scripts/test-release-app.sh
python3 scripts/check-herdr-runtime.py
python3 scripts/check-intent-parity.py
python3 scripts/check-theme-color-escapes.py
python3 scripts/test-theme-contracts.py
python3 scripts/verify-catppuccin-region-evidence.py --self-test
python3 scripts/run-hardening-benchmarks.py --self-test
python3 - <<'PY'
import plistlib
from pathlib import Path

with Path("scripts/Info.plist.in").open("rb") as handle:
    info = plistlib.load(handle)
assert info.get("NSPrefersDisplaySafeAreaCompatibilityMode") is False, (
    "Bessie must opt out of macOS display-safe-area compatibility mode so "
    "native full screen can use the camera-housing region."
)
assert info.get("CFBundleIdentifier") == "__BESSIE_BUNDLE_IDENTIFIER__", (
    "Info.plist.in must not claim a production or verification notification identity."
)
PY

production_bundle_id=$(BESSIE_PACKAGE_VARIANT=production BESSIE_CODESIGN_IDENTITY=identity-check ./scripts/package-app.sh --print-bundle-identifier)
verify_bundle_id=$(BESSIE_PACKAGE_VARIANT=verify ./scripts/package-app.sh --print-bundle-identifier)
[[ "$production_bundle_id" == dev.bessie.app ]]
[[ "$verify_bundle_id" == dev.bessie.app.verify ]]
[[ "$production_bundle_id" != "$verify_bundle_id" ]]
if BESSIE_PACKAGE_VARIANT=invalid ./scripts/package-app.sh --print-bundle-identifier >/dev/null 2>&1; then
    echo 'package-app.sh accepted an unsupported package variant.' >&2
    exit 1
fi
if BESSIE_PACKAGE_VARIANT=production BESSIE_CODESIGN_IDENTITY=- ./scripts/package-app.sh --print-bundle-identifier >/dev/null 2>&1; then
    echo 'package-app.sh accepted ad-hoc signing for production identity.' >&2
    exit 1
fi
verify_configuration=$(BESSIE_SKIP_INSTALL=1 ./scripts/mac-verify.sh --print-package-configuration)
[[ "$verify_configuration" == $'variant=verify\nbundle_identifier=dev.bessie.app.verify' ]]
production_verify_configuration=$(
    BESSIE_SKIP_INSTALL=0 BESSIE_CODESIGN_IDENTITY=identity-check \
    ./scripts/mac-verify.sh --print-package-configuration
)
[[ "$production_verify_configuration" == $'variant=production\nbundle_identifier=dev.bessie.app' ]]
dogfood_configuration=$(
    BESSIE_CODESIGN_IDENTITY=identity-check ./scripts/dogfood-install-signed.sh --print-package-configuration
)
[[ "$dogfood_configuration" == $'variant=production\nbundle_identifier=dev.bessie.app' ]]
rebuild_configuration=$(
    BESSIE_CODESIGN_IDENTITY=identity-check ./scripts/rebuild-install-shortcuts.sh --print-package-configuration
)
[[ "$rebuild_configuration" == $'variant=production\nbundle_identifier=dev.bessie.app' ]]
theme_configuration=$(
    BESSIE_CODESIGN_IDENTITY=identity-check ./scripts/rebuild-install-catppuccin-themes.sh --print-configuration
)
grep -Fq 'variant=production' <<<"$theme_configuration"
grep -Fq 'bundle_identifier=dev.bessie.app' <<<"$theme_configuration"
grep -Fq 'themes=bessie-dark,bessie-light,catppuccin-latte,catppuccin-frappe,catppuccin-macchiato,catppuccin-mocha' <<<"$theme_configuration"
grep -Fq './scripts/dogfood-install-signed.sh' README.md

grep -Fq 'exact: "1.3.2"' Package.swift
grep -Fq '.product(name: "GhosttyTerminal", package: "libghostty-spm")' Package.swift
grep -Fq 'case notChecked' Sources/BessieCore/ConnectPresentation.swift
grep -Fq 'public struct HerdrSessionProjection' Sources/BessieCore/SessionProjection.swift
grep -Fq 'public enum WorkspaceFS' Sources/BessieCore/WorkspaceFS.swift
grep -Fq 'public enum WorkspaceFileOps' Sources/BessieCore/WorkspaceFileOps.swift
grep -Fq 'struct WorkspaceFilesSurface' Sources/BessieApp/WorkspaceFilesSurface.swift
grep -Fq 'struct MarkdownFileEditor' Sources/BessieApp/MarkdownFileEditor.swift
grep -Fq 'testResolveFileRejectsSymlinkEscapeButAllowsContainedSymlink' Tests/BessieCoreTests/WorkspaceFSTests.swift
grep -Fq 'public actor WorkspaceFileWatcher' Sources/BessieCore/FollowWatch.swift
grep -Fq 'public struct GitDiffService' Sources/BessieCore/GitDiffService.swift
grep -Fq 'struct FollowFilesSurface' Sources/BessieApp/FollowFilesSurface.swift
grep -Fq 'Workspace changes observed while watching' Sources/BessieApp/FollowFilesSurface.swift
grep -Fq 'testWatcherSuppressesInitialSnapshotAndReportsAddModifyDelete' Tests/BessieCoreTests/FollowWatchTests.swift
grep -Fq 'testGitHEADPreviewIncludesTrackedModifiedDeletedAndUntrackedFiles' Tests/BessieCoreTests/GitDiffServiceTests.swift
grep -Fq 'testConfigureRestartsTheStretchWhenTheSamePaneChangesDirectory' Tests/BessieAppModelTests/FollowFilesViewModelTests.swift
grep -Fq 'case setSplitRatio' Sources/BessieCore/HerdrActions.swift
grep -Fq 'layout.set_split_ratio' Sources/BessieCore/HerdrActions.swift
grep -Fq 'BessieProductShell(' Sources/BessieApp/BessieApp.swift
grep -Fq 'ConnectionFleetViewModel' Sources/BessieApp/BessieApp.swift
grep -Fq 'Bundle.main.resourceURL?.appendingPathComponent("Herdr/herdr")' Sources/BessieApp/BessieApp.swift
grep -Fq 'struct OnboardingView' Sources/BessieApp/OnboardingView.swift
grep -Fq 'struct TroubleView' Sources/BessieApp/TroubleView.swift
grep -Fq 'struct RuntimeSettingsView' Sources/BessieApp/RuntimeSettingsView.swift
grep -Fq 'runtimeSelection: HerdrRuntimeSelection' Sources/BessieCore/ConnectionLifecycle.swift
grep -Fq 'struct BessieSurfaceProjection' Sources/BessieCore/SurfaceProjection.swift
grep -Fq 'struct HerdSurface' Sources/BessieApp/ProductSurfaces.swift
grep -Fq 'public enum HerdListBuilder' Sources/BessieCore/HerdList.swift
grep -Fq 'case .needsYou: state == .blocked' Sources/BessieCore/HerdList.swift
grep -Fq 'case .done: state == .done' Sources/BessieCore/HerdList.swift
grep -Fq 'case .idle: state == .idle' Sources/BessieCore/HerdList.swift
grep -Fq 'case .unknown: state == .unknown' Sources/BessieCore/HerdList.swift
grep -Fq 'case .done: self = .done' Sources/BessieCore/HerdList.swift
grep -Fq 'case .idle: self = .idle' Sources/BessieCore/HerdList.swift
if grep -Fq 'case settled = "Settled"' Sources/BessieCore/HerdList.swift; then
    echo 'Synthetic user-facing Settled status remains.' >&2
    exit 1
fi
grep -Fq '.sendBytes(Data([0x02]))' Sources/BessieCore/KeyboardShortcuts.swift
grep -Fq 'builder.withCustom("macos-option-as-alt", "left")' Sources/BessieApp/TerminalPaneController.swift
grep -Fq '.keyboardShortcut("p", modifiers: [.command, .shift])' Sources/BessieApp/BessieApp.swift
if grep -Fq '.keyboardShortcut("b", modifiers: .command)' Sources/BessieApp/BessieApp.swift; then
    echo 'Cmd+B must remain terminal input; command palette cannot claim it.' >&2
    exit 1
fi
grep -Fq 'public var requiresUserAction: Bool { self == .blocked }' Sources/BessieCore/SurfaceProjection.swift
test ! -e Sources/BessieCore/AttentionList.swift
test ! -e Tests/BessieCoreTests/AttentionListTests.swift
if grep -Fq 'case attention' Sources/BessieApp/ProductSurfaces.swift \
    || grep -Fq 'struct AttentionSurface' Sources/BessieApp/ProductSurfaces.swift \
    || grep -Fq 'AttentionListBuilder' Sources/BessieApp/ProductSurfaces.swift; then
    echo 'Standalone Attention navigation or surface remains.' >&2
    exit 1
fi
grep -Fq 'public struct ConnectionDisplayLabel' Sources/BessieCore/ConnectionDisplay.swift
grep -Fq 'struct AgentDetailSurface' Sources/BessieApp/ProductSurfaces.swift
grep -Fq 'struct NewProcessSheet' Sources/BessieApp/ProductSurfaces.swift
grep -Fq 'public struct AgentCatalog' Sources/BessieCore/AgentLaunch.swift
grep -Fq 'case agentStart' Sources/BessieCore/HerdrActions.swift
grep -Fq 'BESSIE_PROCESS_LIVE_AUTOMATION' Sources/BessieApp/ProductSurfaces.swift
grep -Fq 'struct BessieWindowSnapshotProbe' Sources/BessieApp/BessieSettings.swift
test -s Sources/BessieApp/Resources/CowMark.svg
test -s Sources/BessieApp/Resources/BessieLogo.svg
test -s Sources/BessieApp/Resources/CowprintTile.png
test -s scripts/verify-design-snapshot.swift
test -x scripts/capture-redesign-matrix.sh
test -s scripts/lib/bessie-app-lifecycle.sh
test -s scripts/verify-app-install-lifecycle.sh
grep -Fq 'bessie_terminate_installation_owners' scripts/mac-verify.sh
grep -Fq 'bessie_terminate_installation_owners' scripts/rebuild-install-shortcuts.sh
grep -Fq 'for screen_number in {1..15}' scripts/capture-redesign-matrix.sh
grep -Fq "screen=\$(printf '%02d' \"\$screen_number\")" scripts/capture-redesign-matrix.sh
grep -Fq 'len(entries) != 30' scripts/capture-redesign-matrix.sh
agent_assets=(
    AgentClaude AgentCodex AgentGrok AgentAmp AgentGeneric
    AgentHermes AgentGemini AgentOpenCode AgentCopilot
    AgentPi AgentOmp AgentCursor AgentDevin AgentAgy
    AgentCline AgentMastraCode AgentKimi AgentKiro AgentDroid
    AgentKilo AgentQodercli AgentMaki AgentOpenClaw
)
for asset in "${agent_assets[@]}"; do
    path="Sources/BessieApp/Resources/${asset}.svg"
    test -s "$path"
    grep -Fq '<svg' "$path"
    grep -Fq '<title>' "$path"
    grep -Eq '<(path|circle|rect|polygon|image)[ >]' "$path"
done
# Mastra must remain true vector (no PNG-in-SVG regression).
if grep -Eq 'data:image|<image[ >]' Sources/BessieApp/Resources/AgentMastraCode.svg; then
    echo 'AgentMastraCode.svg must be vector paths, not an embedded raster.' >&2
    exit 1
fi
grep -Fq 'AgentPi' Sources/BessieApp/BessieDesignSystem.swift
grep -Fq 'AgentOpenClaw' Sources/BessieApp/BessieDesignSystem.swift
grep -Fq 'case "qodercli"' Sources/BessieCore/AgentLaunch.swift
test -s Sources/BessieApp/Resources/ATTRIBUTION.md
test -s Sources/BessieApp/CatppuccinPalette.swift
test -x scripts/check-theme-color-escapes.py
test -x scripts/rebuild-install-catppuccin-themes.sh
grep -Fq 'Catppuccin palette v1.8.0' Sources/BessieApp/Resources/ATTRIBUTION.md
grep -Fq 'a310b246a3cfcdadb6f5b174d879743e084e87ea' Sources/BessieApp/Resources/ATTRIBUTION.md
grep -Fq '5a58926563ddacbde4a12b4a347464c2c6945393' Sources/BessieApp/Resources/ATTRIBUTION.md
grep -Fq 'Copyright (c) 2021 Catppuccin' Sources/BessieApp/Resources/ATTRIBUTION.md
grep -Fq 'do not endorse Bessie' Sources/BessieApp/Resources/ATTRIBUTION.md
grep -Fq 'madeofbees' Sources/BessieApp/Resources/ATTRIBUTION.md
for asset_id in \
    d4fadd6a-e121-4ced-85ae-4023a3f84a7f \
    a4d7865e-8453-4e93-9207-659294800903 \
    6e6995e3-9398-4b45-8fbb-441934ad34a1 \
    33f2f2a8-be73-4be4-b812-b7eb69a35fbb; do
    grep -Fq "$asset_id" Sources/BessieApp/Resources/ATTRIBUTION.md
done
video='Sources/BessieApp/Resources/bessie-cold-open.mp4'
test -s "$video" || { echo 'Missing packaged U8 cold-open video.' >&2; exit 1; }
[[ $(shasum -a 256 "$video" | awk '{print $1}') == 'f68f09d8b31cd6b5af0483c50fb79dd33fbe619a358c81c8438d04ab9f67b871' ]] \
    || { echo 'Packaged cold-open video does not match the normalized corrected asset.' >&2; exit 1; }
ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height -of csv=p=0 "$video" \
    | grep -qx 'h264,1920,1080' || { echo 'Cold-open video must be H.264 1920x1080.' >&2; exit 1; }
grep -Fq 'initiallyShowsColdOpen: !Self.isOnboardingStepArtboard' Sources/BessieApp/BessieApp.swift
grep -Fq 'playsVideo: playsColdOpenVideo' Sources/BessieApp/BessieApp.swift
grep -Fq 'return !settings.onboarding.completed' Sources/BessieApp/BessieApp.swift
grep -Fq '.AVPlayerItemDidPlayToEndTime' Sources/BessieApp/ColdOpenSplashView.swift
grep -Fq '.AVPlayerItemFailedToPlayToEndTime' Sources/BessieApp/ColdOpenSplashView.swift
grep -Fq 'let safetyDelay = isPlaying ? 15.0 : 0' Sources/BessieApp/ColdOpenSplashView.swift
grep -Fq 'guard playsVideo,' Sources/BessieApp/ColdOpenSplashView.swift
grep -Fq 'player.playImmediately(atRate: 1)' Sources/BessieApp/ColdOpenSplashView.swift
grep -Fq 'struct BessieWindowRoot<Content: View>' Sources/BessieApp/BessieDesignSystem.swift
grep -Fq 'struct BessieCowprintBackdrop: View' Sources/BessieApp/BessieDesignSystem.swift
grep -Fq 'static let darkInkOpacity = 0.11' Sources/BessieApp/BessieDesignSystem.swift
grep -Fq 'static let lightInkOpacity = 0.16' Sources/BessieApp/BessieDesignSystem.swift
grep -Fq '@Environment(\.accessibilityReduceTransparency)' Sources/BessieApp/BessieDesignSystem.swift
grep -Fq 'RoundedRectangle(cornerRadius: radius).fill(base)' Sources/BessieApp/BessieDesignSystem.swift
[[ $(rg -c 'BessieCowprintBackdrop\(enabled:' Sources/BessieApp | awk -F: '{ total += $2 } END { print total + 0 }') == 1 ]]
[[ $(rg -c 'BessieWindowRoot \{' Sources/BessieApp/BessieApp.swift) == 2 ]]
if rg -n 'BessieCowprintTexture|BessieCowCrop|BessieCowprintMotion|phaseOverride|intensityScale|cowPrintIntensity|cowPrintMotion|BessieWindowDrawabilityReader' Sources; then
    echo 'Dead or user-configurable cowprint motion/contrast machinery remains.' >&2
    exit 1
fi
if rg -n 'Cowprint contrast|Cowprint motion|BessieSettingRow\(label: "Contrast"' Sources/BessieApp; then
    echo 'Removed cowprint controls remain exposed.' >&2
    exit 1
fi
grep -Fq 'Bundle.main.url(forResource: name' Sources/BessieApp/BessieDesignSystem.swift
grep -Fq '?? Bundle.module.url(forResource: name' Sources/BessieApp/BessieDesignSystem.swift
grep -Fq 'BessieLogoMark(width: 26)' Sources/BessieApp/ProductSurfaces.swift
grep -Fq '.renderingMode(.template)' Sources/BessieApp/BessieDesignSystem.swift
grep -Fq 'static let surfaceRadius: CGFloat' Sources/BessieApp/BessieDesignSystem.swift
grep -Fq 'static let popoverInnerRadius: CGFloat' Sources/BessieApp/BessieDesignSystem.swift
grep -Fq 'static let railWidth: CGFloat = 244' Sources/BessieApp/BessieDesignSystem.swift
grep -Fq 'static let collapsedRailWidth: CGFloat = 52' Sources/BessieApp/BessieDesignSystem.swift
grep -Fq 'static let topbarHeight: CGFloat = 46' Sources/BessieApp/BessieDesignSystem.swift
grep -Fq 'static let cardGap: CGFloat = 9' Sources/BessieApp/BessieDesignSystem.swift
grep -Fq 'static let paneGap: CGFloat = 7' Sources/BessieApp/BessieDesignSystem.swift
grep -Fq 'static let motionFastDuration: TimeInterval = 0.16' Sources/BessieApp/BessieDesignSystem.swift
grep -Fq 'static let motionExplanatoryDuration: TimeInterval = 0.20' Sources/BessieApp/BessieDesignSystem.swift
grep -Fq 'static let motionStrongEaseOut = Animation.timingCurve(0.23, 1, 0.32, 1, duration: motionFastDuration)' Sources/BessieApp/BessieDesignSystem.swift
grep -Fq 'static let motionExplanatoryEaseOut = Animation.timingCurve(0.23, 1, 0.32, 1, duration: motionExplanatoryDuration)' Sources/BessieApp/BessieDesignSystem.swift
grep -Fq 'struct BessieOnboardingSurface: View' Sources/BessieApp/BessieDesignSystem.swift
test -s docs/reports/mac-v1-alpha.md
grep -Fq './scripts/mac-verify.sh' README.md
grep -Fq '/Users/jordanstella/GitHub/bessie/dist/Bessie.app' docs/reports/mac-v1-alpha.md

./scripts/check-ui-copy.sh

if command -v swift >/dev/null 2>&1; then
    swift package dump-package >/dev/null
else
    echo "Swift is unavailable on this VPS; native compilation runs in scripts/mac-verify.sh."
fi

echo "Bessie static checks passed."
