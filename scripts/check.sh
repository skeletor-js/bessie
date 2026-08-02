#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

bash -n scripts/check.sh scripts/check-ui-copy.sh scripts/fetch-herdr-runtime.sh scripts/mac-verify.sh scripts/package-app.sh
python3 scripts/check-herdr-runtime.py

grep -Fq 'exact: "1.3.2"' Package.swift
grep -Fq '.product(name: "GhosttyTerminal", package: "libghostty-spm")' Package.swift
grep -Fq 'case notChecked' Sources/BessieCore/ConnectPresentation.swift
grep -Fq 'public struct HerdrSessionProjection' Sources/BessieCore/SessionProjection.swift
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
grep -Fq 'struct AttentionSurface' Sources/BessieApp/ProductSurfaces.swift
grep -Fq 'struct HerdSurface' Sources/BessieApp/ProductSurfaces.swift
grep -Fq 'public enum HerdListBuilder' Sources/BessieCore/HerdList.swift
grep -Fq 'case .needsYou: state == .blocked' Sources/BessieCore/HerdList.swift
grep -Fq 'public enum AttentionListBuilder' Sources/BessieCore/AttentionList.swift
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
grep -Fq 'struct BessieCowprintTexture' Sources/BessieApp/BessieDesignSystem.swift
grep -Fq 'Bundle.main.url(forResource: name' Sources/BessieApp/BessieDesignSystem.swift
grep -Fq '?? Bundle.module.url(forResource: name' Sources/BessieApp/BessieDesignSystem.swift
grep -Fq 'BessieLogoMark(width: 19)' Sources/BessieApp/BessieDesignSystem.swift
grep -Fq 'static let railWidth: CGFloat = 244' Sources/BessieApp/BessieDesignSystem.swift
grep -Fq 'static let topbarHeight: CGFloat = 46' Sources/BessieApp/BessieDesignSystem.swift
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
