#!/usr/bin/env bash
set -euo pipefail

# Captures the packaged native app. The caller supplies the same isolated Herdr
# environment used by mac-verify; fixtures only select presentation state and
# never stand in for Herdr-owned workspaces, panes, terminals, or processes.
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

app=${BESSIE_CAPTURE_APP:-dist/Bessie.app}
output=${BESSIE_CAPTURE_OUTPUT:-dist/redesign-matrix}
seed=${BESSIE_CAPTURE_SEED:-bessie-pre-v1-u12-v1}
state_log=${BESSIE_STATE_LOG_PATH:?BESSIE_STATE_LOG_PATH is required}
presentation=${BESSIE_PRESENTATION_PATH:?BESSIE_PRESENTATION_PATH is required}
mkdir -p "$output"
manifest="$output/manifest.json"
entries="$output/.manifest-entries.jsonl"
: > "$entries"

[[ -x "$app/Contents/MacOS/BessieApp" ]] || { echo "Packaged Bessie app is missing: $app" >&2; exit 1; }

screen_spec() {
  case "$1" in
    01) echo 'workspace 1180 815 Bessie' ;;
    02) echo 'workspace 1180 815 theme' ;;
    03) echo 'workspace 1180 815 All herds' ;;
    04) echo 'workspace 1180 815 All workspaces' ;;
    05) echo 'projects 1180 815 Projects' ;;
    06) echo 'project-capture 1180 815 Save' ;;
    07) echo 'command-palette 1180 815 sch' ;;
    08) echo 'settings 1180 1720 GENERAL' ;;
    09) echo 'onboarding-splash 1180 560 none' ;;
    10) echo 'onboarding-connect 1180 815 Connect' ;;
    11) echo 'onboarding-how-it-works 1180 815 Herdr' ;;
    12) echo 'onboarding-read-the-rail 1180 815 states' ;;
    13) echo 'onboarding-notifications 1180 815 Notifications' ;;
    14) echo 'zen 1180 720 none' ;;
    15) echo 'menu-bar 900 470 Open' ;;
  esac
}

stop_app() {
  [[ -z ${capture_pid:-} ]] || kill "$capture_pid" 2>/dev/null || true
  [[ -z ${capture_pid:-} ]] || wait "$capture_pid" 2>/dev/null || true
  capture_pid=''
}
trap stop_app EXIT

for appearance in dark light; do
  for screen_number in {1..15}; do
    screen=$(printf '%02d' "$screen_number")
    read -r preview width height required_copy <<<"$(screen_spec "$screen")"
    artifact="$output/${screen}-${appearance}.png"
    unset BESSIE_COMMAND_PALETTE_PREVIEW BESSIE_ZEN_AUTOMATION
    case "$screen" in
      07) export BESSIE_COMMAND_PALETTE_PREVIEW=1 ;;
      14) preview=workspace; export BESSIE_ZEN_AUTOMATION=1 ;;
    esac
    snapshot_delay=2
    case "$screen" in 10|11|12|13) snapshot_delay=7 ;; esac
    rail_collapsed=false
    [[ "$screen" != 02 ]] || rail_collapsed=true
    printf '{"preferences":{"appearance":"%s","appIcon":"light","cowprintEnabled":true,"railCollapsed":%s},"first_real_terminal_completion_version":1}\n' "$appearance" "$rail_collapsed" > "$presentation"
    rm -f "$artifact"
    run_token="capture-${screen}-${appearance}-$$"
    open_args=(
      --stdout "${BESSIE_CAPTURE_APP_LOG:-/tmp/bessie-redesign-capture.log}"
      --stderr "${BESSIE_CAPTURE_APP_LOG:-/tmp/bessie-redesign-capture.log}"
      --env "BESSIE_RUN_TOKEN=$run_token"
      --env "BESSIE_STATE_LOG_PATH=$state_log"
      --env "BESSIE_PRESENTATION_PATH=$presentation"
      --env "BESSIE_DESIGN_PREVIEW=$preview"
      --env "BESSIE_DESIGN_ARTBOARD=$screen"
      --env "BESSIE_CAPTURE_FRAME=${width}x${height}"
      --env "BESSIE_CAPTURE_FIXTURE_SEED=$seed"
      --env "BESSIE_WINDOW_SNAPSHOT_DELAY=$snapshot_delay"
      --env "NSDisablePersistentUI=YES"
    )
    [[ "$screen" == 15 ]] || open_args+=(--env "BESSIE_WINDOW_SNAPSHOT_PATH=$artifact")
    [[ "$screen" != 15 ]] || open_args+=(--env "BESSIE_MENU_BAR_SNAPSHOT_PATH=$artifact")
    [[ -z ${HERDR_CONFIG_PATH:-} ]] || open_args+=(--env "HERDR_CONFIG_PATH=$HERDR_CONFIG_PATH")
    [[ -z ${BESSIE_HERDR_SOCKET_PATH:-} ]] || open_args+=(--env "BESSIE_HERDR_SOCKET_PATH=$BESSIE_HERDR_SOCKET_PATH")
    [[ -z ${XDG_CONFIG_HOME:-} ]] || open_args+=(--env "XDG_CONFIG_HOME=$XDG_CONFIG_HOME")
    [[ -z ${XDG_STATE_HOME:-} ]] || open_args+=(--env "XDG_STATE_HOME=$XDG_STATE_HOME")
    [[ -z ${BESSIE_PROJECTS_PATH:-} ]] || open_args+=(--env "BESSIE_PROJECTS_PATH=$BESSIE_PROJECTS_PATH")
    [[ -z ${BESSIE_COMMAND_PALETTE_PREVIEW:-} ]] || open_args+=(--env "BESSIE_COMMAND_PALETTE_PREVIEW=$BESSIE_COMMAND_PALETTE_PREVIEW")
    [[ -z ${BESSIE_ZEN_AUTOMATION:-} ]] || open_args+=(--env "BESSIE_ZEN_AUTOMATION=$BESSIE_ZEN_AUTOMATION")
    open -n "$app" "${open_args[@]}"
    capture_pid=''
    for _ in {1..120}; do
      run_line=$(grep -F "App run=$run_token pid=" "$state_log" | tail -n 1 || true)
      [[ -z "$run_line" ]] || { capture_pid=${run_line##* pid=}; break; }
      sleep .25
    done
    [[ "$capture_pid" =~ ^[0-9]+$ ]] || { echo "Capture app did not launch: $screen $appearance" >&2; exit 1; }
    for _ in {1..120}; do [[ -s "$artifact" ]] && break; kill -0 "$capture_pid" 2>/dev/null || break; sleep .25; done
    [[ -s "$artifact" ]] || { echo "Capture failed: $screen $appearance" >&2; exit 1; }
    pixel_width=$(sips -g pixelWidth "$artifact" | awk '/pixelWidth/ {print $2}')
    pixel_height=$(sips -g pixelHeight "$artifact" | awk '/pixelHeight/ {print $2}')
    scale=$(/usr/bin/python3 - "$width" "$height" "$pixel_width" "$pixel_height" <<'PY'
import sys
width, height, pixels_wide, pixels_high = map(int, sys.argv[1:])
sx, sy = pixels_wide / width, pixels_high / height
if sx != sy or sx not in (1, 2):
    raise SystemExit(f"unexpected capture scale: requested={width}x{height} pixels={pixels_wide}x{pixels_high}")
print(int(sx))
PY
)
    verifier_args=(--minimum-size "$pixel_width,$pixel_height" --exact-size "$pixel_width,$pixel_height")
    [[ "$screen" == 15 ]] || verifier_args+=(--require-opaque true)
    [[ "$required_copy" == none ]] || verifier_args+=(--require-copy "$required_copy")
    [[ "$screen" != 02 ]] || verifier_args+=(--region "16,80,40,$((pixel_height - 150))")
    case "$screen" in
      07|08|09|10|11|12|13|14|15) verifier_args+=(--surface-only true) ;;
      *) verifier_args+=(--max-chroma 8) ;;
    esac
    xcrun swift scripts/verify-design-snapshot.swift "$artifact" "$appearance" "${verifier_args[@]}"
    /usr/bin/python3 - "$entries" "$screen" "$appearance" "$width" "$height" "$scale" "$seed" "$artifact" "$preview" <<'PY'
import json, sys
path, screen, appearance, width, height, scale, seed, artifact, fixture = sys.argv[1:]
with open(path, "a", encoding="utf-8") as f:
    f.write(json.dumps({"screen_id": screen, "appearance": appearance,
      "frame": {"width": int(width), "height": int(height)}, "scale": int(scale),
      "fixture_seed": seed, "fixture": fixture, "artifact_path": artifact,
      "native": True, "full_pixel_equality": False}) + "\n")
PY
    stop_app
  done
done

/usr/bin/python3 - "$entries" "$manifest" <<'PY'
import json, sys
entries = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8")]
expected = {(f"{i:02d}", a) for i in range(1, 16) for a in ("dark", "light")}
actual = {(e["screen_id"], e["appearance"]) for e in entries}
if len(entries) != 30 or actual != expected:
    raise SystemExit(f"incomplete redesign matrix: {len(entries)} entries")
with open(sys.argv[2], "w", encoding="utf-8") as f:
    json.dump({"schema_version": 1, "fixture_seed": entries[0]["fixture_seed"], "artboards": entries}, f, indent=2)
    f.write("\n")
PY
rm -f "$entries"
echo "Captured deterministic native redesign matrix: $manifest"
