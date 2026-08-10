#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

command -v swift >/dev/null 2>&1 || {
    echo 'Swift is required for hardening probes.' >&2
    exit 2
}

swift test --filter 'PerformanceInstrumentationTests|DiagnosticsHardeningTests|RuntimeSetupTests|BessieProjectTests|PersistenceReconnectTests|BessieConnectionTests|TerminalControllerTests|SurfaceProjectionTests'
python3 scripts/run-hardening-benchmarks.py --format json

cat <<'EOF'
Not proven by this deterministic runner:
- one-window activation and app menu behavior
- packaged cold/warm startup or local/remote terminal latency
- live notification delivery/click routing
- representative local/SSH reconnect, controller takeover, and terminal conformance
EOF
