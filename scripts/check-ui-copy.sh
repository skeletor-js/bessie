#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

copy_sources=(
    Sources/BessieApp
    Sources/BessieCore/ConnectPresentation.swift
    Sources/BessieCore/HerdrModels.swift
    Sources/BessieCore/RuntimeDiscovery.swift
    Sources/BessieCore/SessionProjection.swift
    Sources/BessieCore/SurfaceProjection.swift
)

forbidden_copy=(
    'Save current layout'
    'public client boundary'
    'public JSON socket'
    'PUBLIC HERDR ACTIONS'
    'NO SHADOW SESSION MODEL'
    'Herdr-owned'
    'HERDR STATE'
    'HERDR CLIENT'
    'Authoritative pane state'
    'Bessie does not infer'
    'Bessie is a client'
    'In the background it is just Herdr'
    'Terminal history remains in Herdr'
    'libghostty surfaces'
    'placeholder state'
    'bounded recovery active'
    'opening public json socket'
    'snapshot current'
    'recovery stopped'
    'Save layout unavailable'
    '0.1.0-ALPHA'
    'questionmark.seal'
    'railDestination(.workspace)'
    'Start an agent to add it to the herd.'
    'Send input to this pane'
    'Open a shell or start an agent.'
    'Choose a working directory to get started.'
    'Reduce Motion turns this off.'
    '⌃S N NEW'
    '⌘K PALETTE'
)

for phrase in "${forbidden_copy[@]}"; do
    if grep -RFq -- "$phrase" "${copy_sources[@]}"; then
        printf 'Forbidden product copy found: %s\n' "$phrase" >&2
        grep -RFn -- "$phrase" "${copy_sources[@]}" >&2 || true
        exit 1
    fi
done

required_copy=(
    'How to connect'
    'No agents running'
    'No workspaces yet'
    'No panes in this tab'
    'No agent selected'
    'Pane actions'
    'Action failed'
)

for phrase in "${required_copy[@]}"; do
    if ! grep -RFq -- "$phrase" Sources/BessieApp; then
        printf 'Required product copy missing: %s\n' "$phrase" >&2
        exit 1
    fi
done

printf 'Bessie UI copy checks passed.\n'
