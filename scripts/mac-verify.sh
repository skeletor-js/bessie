#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mac_host=${BESSIE_MAC_HOST:-}
mac_dir=${BESSIE_MAC_DIR:-}
agent_kind=${BESSIE_AGENT_KIND:-codex}
codesign_identity=${BESSIE_CODESIGN_IDENTITY:--}
skip_install=${BESSIE_SKIP_INSTALL:-0}
mirror_marker=${BESSIE_MIRROR_MARKER:-source=$repo_root}
verification_lock=/tmp/bessie-mac-verify.lock
ssh_options=(-o StrictHostKeyChecking=yes)

case "$agent_kind" in
    pi|claude|codex|gemini|amp|grok|hermes) ;;
    *) echo "Refusing unsupported live verification agent: $agent_kind" >&2; exit 1 ;;
esac

case "$skip_install" in
    0|1) ;;
    *) echo "BESSIE_SKIP_INSTALL must be 0 or 1." >&2; exit 1 ;;
esac

if [[ ${1:-} == --print-package-configuration && $# == 1 ]]; then
    if [[ "$skip_install" == 1 ]]; then
        package_variant=verify
    else
        package_variant=production
    fi
    package_bundle_identifier=$(
        BESSIE_PACKAGE_VARIANT="$package_variant" \
        BESSIE_CODESIGN_IDENTITY="$codesign_identity" \
        "$repo_root/scripts/package-app.sh" --print-bundle-identifier
    )
    printf 'variant=%s\nbundle_identifier=%s\n' "$package_variant" "$package_bundle_identifier"
    exit 0
fi
if [[ $# -ne 0 ]]; then
    echo "Usage: $0 [--print-package-configuration]" >&2
    exit 1
fi

[[ -n "$mac_host" ]] || {
    echo "Set BESSIE_MAC_HOST to an SSH host for the verification Mac." >&2
    exit 1
}
case "$mac_dir" in
    /*) ;;
    *) echo "Set BESSIE_MAC_DIR to an absolute mirror path on the verification Mac." >&2; exit 1 ;;
esac
[[ "$mac_dir" != / ]] || {
    echo "Refusing to use the filesystem root as a Mac mirror." >&2
    exit 1
}

if ! ssh "${ssh_options[@]}" "$mac_host" mkdir "$verification_lock"; then
    echo "Another Bessie Mac verification is already running: $verification_lock" >&2
    exit 1
fi
trap 'ssh -o StrictHostKeyChecking=yes "$mac_host" rmdir "$verification_lock" 2>/dev/null || true' EXIT

ssh "${ssh_options[@]}" "$mac_host" bash -s -- "$mac_dir" "$mirror_marker" <<'REMOTE'
set -euo pipefail
mac_dir=$1
trap 'echo "mac-verify failed at line $LINENO: $BASH_COMMAND" >&2' ERR
mirror_marker=$2

if [[ -e "$mac_dir" && ! -d "$mac_dir" ]]; then
    echo "Mac mirror path is not a directory: $mac_dir" >&2
    exit 1
fi

if [[ ! -d "$mac_dir" ]]; then
    mkdir -p "$mac_dir"
fi

if [[ -f "$mac_dir/.bessie-mirror" ]]; then
    [[ $(<"$mac_dir/.bessie-mirror") == "$mirror_marker" ]] || {
        echo "Mac mirror marker does not match the VPS source." >&2
        exit 1
    }
elif [[ -n $(find "$mac_dir" -mindepth 1 -maxdepth 1 -print -quit) ]]; then
    echo "Refusing to sync into a non-empty, unmarked Mac directory: $mac_dir" >&2
    exit 1
else
    printf '%s\n' "$mirror_marker" > "$mac_dir/.bessie-mirror"
fi
REMOTE

rsync -az \
    -e 'ssh -o StrictHostKeyChecking=yes' \
    --exclude='.git' \
    --exclude='.build/' \
    --exclude='.swiftpm/' \
    --exclude='.local/' \
    --exclude='dist/' \
    "$repo_root/" "$mac_host:$mac_dir/"

ssh "${ssh_options[@]}" "$mac_host" bash -s -- "$mac_dir" "$agent_kind" "$codesign_identity" "$skip_install" <<'REMOTE'
set -euo pipefail
trap 'status=$?; trap - ERR; echo "Mac verification failed at remote line $LINENO (exit $status)." >&2; exit $status' ERR
mac_dir=$1
requested_agent_kind=$2
codesign_identity=$3
skip_install=$4
export BESSIE_CODESIGN_IDENTITY="$codesign_identity"
if [[ "$skip_install" == 1 ]]; then
    package_variant=verify
    export BESSIE_PACKAGE_VARIANT=verify
else
    package_variant=production
    if [[ "$codesign_identity" == - ]]; then
        echo "mac-verify installation requires a stable BESSIE_CODESIGN_IDENTITY; use BESSIE_SKIP_INSTALL=1 for ad-hoc verification." >&2
        exit 1
    fi
    export BESSIE_PACKAGE_VARIANT=production
fi
logical_mac_dir=${mac_dir%/}
mac_dir=$(cd "$mac_dir" && pwd -P)
cd "$mac_dir"
source "$mac_dir/scripts/lib/bessie-app-lifecycle.sh"
package_bundle_identifier=$(./scripts/package-app.sh --print-bundle-identifier)

login_path=$(zsh -lic 'printf "%s\n" "$PATH"' 2>/dev/null | tail -n 1)
[[ -n "$login_path" ]] || { echo "Could not resolve the Mac login PATH." >&2; exit 1; }
PATH=$login_path
export PATH
requested_agent_path=$(command -v "$requested_agent_kind" || true)
[[ -n "$requested_agent_path" && -x "$requested_agent_path" ]] || {
    echo "Requested agent is unavailable on the Mac login PATH: $requested_agent_kind" >&2
    exit 1
}

runtime_lock="$mac_dir/scripts/herdr-runtime-lock.json"
IFS=$'\t' read -r herdr_sha256 herdr_architecture herdr_expected_version herdr_protocol < <(
    /usr/bin/python3 -c 'import json, sys; lock = json.load(open(sys.argv[1])); print(*(lock[key] for key in ("sha256", "architecture", "expected_version_output", "protocol")), sep="\t")' "$runtime_lock"
)
herdr_dir="$mac_dir/.local/herdr"
herdr_bin="$herdr_dir/herdr"
herdr_socket="$herdr_dir/runtime/herdr.sock"
herdr_config="$herdr_dir/config.toml"
herdr_xdg_config="$herdr_dir/xdg-config/verify-$$"
herdr_xdg_state="$herdr_dir/xdg-state/verify-$$"
herdr_log="$herdr_dir/runtime/server.log"
state_log="$herdr_dir/runtime/bessie-state.log"
app_log="$herdr_dir/runtime/bessie-app.log"
intent_socket="$herdr_dir/runtime/bessie-intent-verify-$$.sock"
presentation_path="$herdr_dir/runtime/bessie-presentation-$$.json"
performance_evidence_path="$herdr_dir/runtime/bessie-performance-$$.json"
performance_report_path="$herdr_dir/runtime/bessie-performance-$$.txt"
terminal_performance_evidence_path="$herdr_dir/runtime/bessie-terminal-performance-$$.json"
pane_switch_performance_evidence_path="$herdr_dir/runtime/bessie-pane-switch-performance-$$.json"
terminal_performance_resources_path="$herdr_dir/runtime/bessie-terminal-resources-$$.json"
terminal_performance_report_path="$herdr_dir/runtime/bessie-terminal-performance-$$.txt"
terminal_performance_profile_path="$herdr_dir/runtime/bessie-terminal-profile-$$.txt"
startup_evidence_dir="$herdr_dir/runtime/bessie-startup-evidence-$$"
startup_samples_path="$herdr_dir/runtime/bessie-startup-samples-$$.json"
startup_report_path="$herdr_dir/runtime/bessie-startup-performance-$$.txt"
pane_read_error_path="$herdr_dir/runtime/bessie-pane-read-$$.stderr"
projects_root="$herdr_dir/runtime/projects-$$"
snapshot_path="$mac_dir/dist/Bessie-window.png"
autostart_root="/tmp/bessie-autostart-verify-$$"
autostart_xdg_config="$autostart_root/xdg-config"
autostart_xdg_state="$autostart_root/xdg-state"
autostart_state_log="$autostart_root/bessie-state.log"
autostart_app_log="$autostart_root/bessie-app.log"
autostart_presentation_path="$autostart_root/bessie-presentation.json"
autostart_snapshot_path="$mac_dir/dist/Bessie-onboarding.png"
herdr_pid=''
app_pid=''
installed_pid=''
installed_app=/Applications/Bessie.app
installed_executable="$installed_app/Contents/MacOS/BessieApp"
installed_menu_snapshot="$mac_dir/dist/Bessie-menu-bar-installed.png"
install_stage="/Applications/.Bessie.app.install-$$"
install_backup="/tmp/Bessie.app.backup-$$"
install_candidate_active=false
leave_installed_app_running=false
runtime_case_pid=''
runtime_case_root=''
runtime_case_herdr=''
missing_bundle_case=''
corrupt_bundle_case=''
performance_profile_pid=''
launch_counter=0
cli_workspace_id=''
process_automation=0
process_agent_kind=''
terminal_automation=1
terminal_performance_probe=0
terminal_performance_pane_id=''
pane_switch_performance_probe=0
startup_performance_probe=0
startup_performance_scenario=warm
setup_automation=0
snapshot_trigger=live-two-pane
autostart_snapshot_trigger=''
autostart_design_preview=herd
design_preview=''
fullscreen_snapshot=0
theme_capture_dir=''

launch_app() {
    local app_bundle="$mac_dir/dist/Bessie.app"
    local app_executable="$app_bundle/Contents/MacOS/BessieApp"
    launch_counter=$((launch_counter + 1))
    local run_token="verify-$$-$launch_counter"
    local open_args=(
        --stdout "$app_log"
        --stderr "$app_log"
        --env "BESSIE_REPOSITORY_ROOT=$mac_dir"
        --env "HERDR_CONFIG_PATH=$herdr_config"
        --env "BESSIE_HERDR_SOCKET_PATH=$herdr_socket"
        --env "XDG_CONFIG_HOME=$herdr_xdg_config"
        --env "XDG_STATE_HOME=$herdr_xdg_state"
        --env "PATH=$PATH"
        --env "BESSIE_STATE_LOG_PATH=$state_log"
        --env "BESSIE_RUN_TOKEN=$run_token"
        --env "BESSIE_INTENT_SOCKET_PATH=$intent_socket"
        --env "BESSIE_PRESENTATION_PATH=$presentation_path"
        --env "BESSIE_PERFORMANCE_EVIDENCE_PATH=$performance_evidence_path"
        --env "BESSIE_PERFORMANCE_EVIDENCE_KIND=packaged_local_measurement"
        --env "BESSIE_PERFORMANCE_STARTUP_SCENARIO=$startup_performance_scenario"
        --env "BESSIE_STARTUP_PERFORMANCE_PROBE=$startup_performance_probe"
        --env "BESSIE_PROJECTS_PATH=$projects_root"
        --env "BESSIE_DEVELOPER_FEATURES=fileBrowserEditor,followFiles"
        --env "NSDisablePersistentUI=YES"
        --env "BESSIE_TERMINAL_LIVE_AUTOMATION=$terminal_automation"
        --env "BESSIE_TERMINAL_PERFORMANCE_PROBE=$terminal_performance_probe"
        --env "BESSIE_TERMINAL_PERFORMANCE_PANE_ID=$terminal_performance_pane_id"
        --env "BESSIE_PANE_SWITCH_PERFORMANCE_PROBE=$pane_switch_performance_probe"
        --env "BESSIE_WINDOW_SNAPSHOT_PATH=$snapshot_path"
        --env "BESSIE_PROCESS_LIVE_AUTOMATION=$process_automation"
        --env "BESSIE_PROCESS_AGENT_KIND=$process_agent_kind"
        --env "BESSIE_PROCESS_CWD=$mac_dir"
    )
    [[ -z "$snapshot_trigger" ]] || open_args+=(--env "BESSIE_WINDOW_SNAPSHOT_TRIGGER=$snapshot_trigger")
    [[ -z "$design_preview" ]] || open_args+=(--env "BESSIE_DESIGN_PREVIEW=$design_preview")
    [[ -z "$theme_capture_dir" ]] || open_args+=(--env "BESSIE_THEME_LIVE_CAPTURE_DIR=$theme_capture_dir")
    [[ "$fullscreen_snapshot" != 1 ]] || open_args+=(--env "BESSIE_FULLSCREEN_SNAPSHOT=1")
    open -n "$app_bundle" "${open_args[@]}"
    for _ in {1..40}; do
        local run_line
        run_line=$(grep -F "App run=$run_token pid=" "$state_log" | tail -n 1 || true)
        if [[ -n "$run_line" ]]; then
            app_pid=${run_line##* pid=}
            [[ "$app_pid" =~ ^[0-9]+$ ]] || { echo "Bessie reported an invalid process ID." >&2; return 1; }
            local executable
            executable=$(ps -p "$app_pid" -o command=)
            [[ "$executable" == "$app_executable" ]] || { echo "Bessie launch token resolved to an unexpected process: $executable" >&2; return 1; }
            return
        fi
        sleep 0.25
    done
    echo "Bessie did not launch through LaunchServices." >&2
    return 1
}

launch_autostart_app() {
    local app_bundle="$mac_dir/dist/Bessie.app"
    local app_executable="$app_bundle/Contents/MacOS/BessieApp"
    launch_counter=$((launch_counter + 1))
    local run_token="verify-autostart-$$-$launch_counter"
    open -n "$app_bundle" \
        --stdout "$autostart_app_log" \
        --stderr "$autostart_app_log" \
        --env "BESSIE_REPOSITORY_ROOT=$mac_dir" \
        --env "HERDR_SOCKET_PATH=$herdr_socket" \
        --env "HERDR_SESSION=default" \
        --env "XDG_CONFIG_HOME=$autostart_xdg_config" \
        --env "XDG_STATE_HOME=$autostart_xdg_state" \
        --env "PATH=/usr/bin:/bin" \
        --env "BESSIE_STATE_LOG_PATH=$autostart_state_log" \
        --env "BESSIE_RUN_TOKEN=$run_token" \
        --env "BESSIE_INTENT_SOCKET_PATH=$intent_socket" \
        --env "BESSIE_PRESENTATION_PATH=$autostart_presentation_path" \
        --env "BESSIE_PERFORMANCE_EVIDENCE_PATH=$performance_evidence_path" \
        --env "BESSIE_PERFORMANCE_EVIDENCE_KIND=packaged_local_measurement" \
        --env "BESSIE_PERFORMANCE_STARTUP_SCENARIO=$startup_performance_scenario" \
        --env "BESSIE_STARTUP_PERFORMANCE_PROBE=$startup_performance_probe" \
        --env "NSDisablePersistentUI=YES" \
        --env "BESSIE_SETUP_AUTOMATION=$setup_automation" \
        --env "BESSIE_DESIGN_PREVIEW=$autostart_design_preview" \
        --env "BESSIE_WINDOW_SNAPSHOT_TRIGGER=$autostart_snapshot_trigger" \
        --env "BESSIE_WINDOW_SNAPSHOT_PATH=$autostart_snapshot_path" \
        --env "BESSIE_WINDOW_SNAPSHOT_DELAY=2" \
        --env "BESSIE_TERMINAL_LIVE_AUTOMATION=0" \
        --env "BESSIE_PROCESS_LIVE_AUTOMATION=0"
    for _ in {1..40}; do
        local run_line
        run_line=$(grep -F "App run=$run_token pid=" "$autostart_state_log" | tail -n 1 || true)
        if [[ -n "$run_line" ]]; then
            app_pid=${run_line##* pid=}
            [[ "$app_pid" =~ ^[0-9]+$ ]] || { echo "Autostart Bessie reported an invalid process ID." >&2; return 1; }
            local executable
            executable=$(ps -p "$app_pid" -o command=)
            [[ "$executable" == "$app_executable" ]] || { echo "Autostart token resolved to an unexpected process: $executable" >&2; return 1; }
            return
        fi
        sleep 0.25
    done
    echo "Autostart Bessie did not launch through LaunchServices." >&2
    return 1
}

stop_app() {
    [[ -n "$app_pid" ]] || return 0
    if ! kill -0 "$app_pid" 2>/dev/null; then
        wait "$app_pid" 2>/dev/null || true
        app_pid=''
        return 0
    fi
    local executable
    executable=$(ps -p "$app_pid" -o command=)
    case "$executable" in
        "$mac_dir"/dist/Bessie.app/Contents/MacOS/BessieApp*) ;;
        *) echo "Refusing to stop unexpected app process: $executable" >&2; return 1 ;;
    esac
    kill "$app_pid"
    for _ in {1..40}; do
        ! kill -0 "$app_pid" 2>/dev/null && break
        sleep 0.25
    done
    if kill -0 "$app_pid" 2>/dev/null; then
        echo "Bessie did not exit within 10 seconds after controller release." >&2
        return 1
    fi
    wait "$app_pid" 2>/dev/null || true
    app_pid=''
}

startup_evidence_ready() {
    local evidence_path=$1
    [[ -s "$evidence_path" ]] || return 1
    /usr/bin/python3 - "$evidence_path" <<'PY'
import json
import sys

try:
    payload = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)
milestones = payload.get("milestones", [])
names = {mark.get("milestone") for mark in milestones}
required = {"process_start", "first_window_content", "connection_start", "first_complete_frame"}
spans = [
    span for span in payload.get("spans", [])
    if span.get("start_milestone") == "startup_main_thread_probe_scheduled"
    and span.get("end_milestone") == "startup_main_thread_probe_completed"
    and isinstance(span.get("duration_ms"), (int, float))
]
raise SystemExit(0 if required.issubset(names) and len(spans) >= 25 else 1)
PY
}

capture_design_surface() {
    local name=$1
    local preview=$2
    local verify_shell=${3:-true}
    local appearance=${4:-dark}
    local fullscreen=${5:-false}
    local output="$mac_dir/dist/Bessie-$name.png"
    stop_app
    # Keep removed keys here deliberately: every native visual capture also
    # proves old presentation files still decode after contrast/motion removal.
    printf '{"preferences":{"appearance":"%s","appIcon":"light","cowprintEnabled":true,"cowPrintIntensity":0.05,"cowPrintMotion":false},"first_real_terminal_completion_version":1}\n' \
        "$appearance" > "$presentation_path"
    rm -f "$output"
    snapshot_path=$output
    snapshot_trigger=''
    design_preview=$preview
    [[ "$fullscreen" == true ]] && fullscreen_snapshot=1 || fullscreen_snapshot=0
    launch_app
    for _ in {1..80}; do
        [[ -s "$output" ]] && break
        kill -0 "$app_pid" 2>/dev/null || { cat "$app_log" >&2; return 1; }
        sleep 0.25
    done
    [[ -s "$output" ]] || {
        echo "Design snapshot was not written: $output" >&2
        tail -n 80 "$app_log" >&2 || true
        return 1
    }
    file "$output" | grep -Fq 'PNG image data' || {
        echo "Design snapshot is not a PNG: $output" >&2
        return 1
    }
    [[ $(stat -f %z "$output") -gt 15000 ]] || {
        echo "Design snapshot is unexpectedly small: $output" >&2
        return 1
    }
    if [[ "$verify_shell" == true ]]; then
        xcrun swift scripts/verify-design-snapshot.swift "$output" "$appearance"
    fi
    grep -Fq "Window snapshot path=$output" "$state_log" || {
        echo "Design snapshot was not acknowledged in the app state log: $output" >&2
        tail -n 80 "$state_log" >&2 || true
        return 1
    }
    fullscreen_snapshot=0
}

capture_live_theme_matrix() {
    stop_app
    printf '%s\n' '{"preferences":{"appearance":"dark","appIcon":"light","cowprintEnabled":true},"first_real_terminal_completion_version":1}' > "$presentation_path"
    theme_capture_dir="$mac_dir/dist"
    local names=(bessie-dark bessie-light catppuccin-latte catppuccin-frappe catppuccin-macchiato catppuccin-mocha)
    local schemes=(dark light light dark dark dark)
    for name in "${names[@]}"; do
        rm -f "$theme_capture_dir/Bessie-theme-$name-live.png"
    done
    snapshot_trigger=disabled
    design_preview=workspace
    terminal_automation=0
    launch_app
    for _ in {1..160}; do
        grep -Fq 'Theme live capture complete themes=6 controller_identity=stable' "$state_log" && break
        kill -0 "$app_pid" 2>/dev/null || { cat "$app_log" >&2; return 1; }
        sleep 0.25
    done
    grep -Fq 'Theme live capture complete themes=6 controller_identity=stable' "$state_log"
    ! grep -Fq 'Theme live capture failed' "$state_log"
    for index in "${!names[@]}"; do
        local output="$theme_capture_dir/Bessie-theme-${names[$index]}-live.png"
        [[ -s "$output" ]]
        file "$output" | grep -Fq 'PNG image data'
        [[ $(stat -f %z "$output") -gt 20000 ]]
        xcrun swift scripts/verify-design-snapshot.swift "$output" "${schemes[$index]}" --surface-only true
        grep -Fq "Window snapshot path=$output" "$state_log"
    done
    local observed
    observed=$(read_pane_recent "$cli_pane_id")
    grep -Fq 'BESSIE_THEME_ANSI_16_牛é🐄' <<<"$observed"
    theme_capture_dir=''
    terminal_automation=1
    design_preview=''
}

intent_cli() {
    BESSIE_INTENT_SOCKET_PATH="$intent_socket" "$mac_dir/.build/debug/bessie" "$@"
}

read_pane_recent() {
    local pane_id=$1
    local output=''
    for _ in {1..20}; do
        if output=$(XDG_CONFIG_HOME="$herdr_xdg_config" XDG_STATE_HOME="$herdr_xdg_state" \
            HERDR_CONFIG_PATH="$herdr_config" HERDR_SOCKET_PATH="$herdr_socket" \
            "$herdr_bin" pane read "$pane_id" --source recent --lines 200 \
            2>"$pane_read_error_path"); then
            printf '%s\n' "$output"
            return 0
        fi
        sleep 0.1
    done
    echo "Could not read live Herdr pane after retries: $pane_id" >&2
    cat "$pane_read_error_path" >&2
    return 1
}

assert_intent_ok() {
    /usr/bin/python3 -c '
import json, sys
result = json.load(sys.stdin)
if result.get("ok") is not True:
    raise SystemExit(f"intent failed: {result}")
'
}

assert_herdr_focus() {
    local expected_workspace=$1
    local expected_pane=$2
    /usr/bin/python3 -c '
import json, sys
snapshot = json.load(sys.stdin)
workspace, pane = sys.argv[1:3]
session = snapshot.get("result", {}).get("snapshot", {})
actual = (session.get("focused_workspace_id"), session.get("focused_pane_id"))
if actual != (workspace, pane):
    raise SystemExit(f"Herdr focus mismatch: workspace={actual[0]!r}, pane={actual[1]!r}")
' "$expected_workspace" "$expected_pane"
}

verify_runtime_failure_case() {
    local name=$1
    local app_bundle=$2
    local expected_finding=$3
    local selection_json=${4:-}
    local expected_source=$5
    local expected_path=$6
    local root="/tmp/bessie-runtime-$name-verify-$$"
    local state="$root/state.log"
    local log="$root/app.log"
    local presentation="$root/presentation.json"
    local screenshot="$mac_dir/dist/Bessie-trouble-$name.png"
    local token="verify-runtime-$name-$$"
    local case_pid=''
    runtime_case_root=$root
    mkdir -p "$root/xdg-config" "$root/xdg-state"
    printf '%s\n' '{"preferences":{},"first_real_terminal_completion_version":1}' > "$presentation"
    if [[ -n "$selection_json" ]]; then
        printf '%s\n' "$selection_json" > "$root/runtime-selection.json"
    fi
    : > "$state"
    : > "$log"
    rm -f "$screenshot"
    open -n "$app_bundle" \
        --stdout "$log" --stderr "$log" \
        --env "PATH=/usr/bin:/bin" \
        --env "XDG_CONFIG_HOME=$root/xdg-config" \
        --env "XDG_STATE_HOME=$root/xdg-state" \
        --env "BESSIE_STATE_LOG_PATH=$state" \
        --env "BESSIE_RUN_TOKEN=$token" \
        --env "BESSIE_INTENT_SOCKET_PATH=$intent_socket" \
        --env "BESSIE_PRESENTATION_PATH=$presentation" \
        --env "NSDisablePersistentUI=YES" \
        --env "BESSIE_WINDOW_SNAPSHOT_PATH=$screenshot" \
        --env "BESSIE_WINDOW_SNAPSHOT_DELAY=1"
    for _ in {1..80}; do
        line=$(grep -F "App run=$token pid=" "$state" | tail -n 1 || true)
        [[ -z "$line" ]] || { case_pid=${line##* pid=}; break; }
        sleep 0.25
    done
    if [[ ! "$case_pid" =~ ^[0-9]+$ ]]; then
        cat "$log" >&2
        echo "Runtime failure case $name did not report a process ID." >&2
        return 1
    fi
    runtime_case_pid=$case_pid
    for _ in {1..80}; do
        grep -Fq "source=$expected_source path=$expected_path finding=$expected_finding" "$state" && break
        kill -0 "$case_pid"
        sleep 0.25
    done
    grep -Fq "source=$expected_source path=$expected_path finding=$expected_finding" "$state"
    for _ in {1..40}; do
        [[ -s "$screenshot" ]] && break
        sleep 0.25
    done
    [[ -s "$screenshot" ]]
    file "$screenshot" | grep -Fq 'PNG image data'
    [[ $(stat -f %z "$screenshot") -gt 20000 ]]
    kill "$case_pid"
    for _ in {1..40}; do
        ! kill -0 "$case_pid" 2>/dev/null && break
        sleep 0.25
    done
    ! kill -0 "$case_pid" 2>/dev/null
    ! pgrep -f "^$app_bundle/Contents/Resources/Herdr/herdr server" >/dev/null
    find "$root" -depth -delete
    runtime_case_pid=''
    runtime_case_root=''
}

verify_external_runtime_success_case() {
    local app_bundle=$1
    local external_runtime=$2
    local root="/tmp/bessie-runtime-compatible-external-verify-$$"
    local state="$root/state.log"
    local log="$root/app.log"
    local presentation="$root/presentation.json"
    local token="verify-runtime-compatible-external-$$"
    local case_pid=''
    runtime_case_root=$root
    runtime_case_herdr=$external_runtime
    mkdir -p "$root/xdg-config" "$root/xdg-state"
    printf '%s\n' '{"preferences":{"startupBehavior":"lastWorkspace"},"first_real_terminal_completion_version":1}' > "$presentation"
    printf '{"version":1,"kind":"custom","path":"%s"}\n' "$external_runtime" > "$root/runtime-selection.json"
    : > "$state"
    : > "$log"
    open -n "$app_bundle" \
        --stdout "$log" --stderr "$log" \
        --env "PATH=/usr/bin:/bin" \
        --env "XDG_CONFIG_HOME=$root/xdg-config" \
        --env "XDG_STATE_HOME=$root/xdg-state" \
        --env "BESSIE_STATE_LOG_PATH=$state" \
        --env "BESSIE_RUN_TOKEN=$token" \
        --env "BESSIE_INTENT_SOCKET_PATH=$intent_socket" \
        --env "BESSIE_PRESENTATION_PATH=$presentation" \
        --env "NSDisablePersistentUI=YES" \
        --env "BESSIE_TERMINAL_LIVE_AUTOMATION=0" \
        --env "BESSIE_PROCESS_LIVE_AUTOMATION=0"
    for _ in {1..80}; do
        line=$(grep -F "App run=$token pid=" "$state" | tail -n 1 || true)
        [[ -z "$line" ]] || { case_pid=${line##* pid=}; break; }
        sleep 0.25
    done
    if [[ ! "$case_pid" =~ ^[0-9]+$ ]]; then
        cat "$log" >&2
        echo "Compatible external runtime case did not report a process ID." >&2
        return 1
    fi
    runtime_case_pid=$case_pid
    for _ in {1..120}; do
        grep -Fq "Runtime stage=workspaceReady source=custom path=$external_runtime finding=none api=true" "$state" && break
        kill -0 "$case_pid"
        sleep 0.25
    done
    grep -Fq "Runtime stage=workspaceReady source=custom path=$external_runtime finding=none api=true" "$state"
    kill "$case_pid"
    for _ in {1..40}; do
        ! kill -0 "$case_pid" 2>/dev/null && break
        sleep 0.25
    done
    ! kill -0 "$case_pid" 2>/dev/null
    external_status=$(XDG_CONFIG_HOME="$root/xdg-config" XDG_STATE_HOME="$root/xdg-state" \
        HERDR_SESSION=bessie "$external_runtime" status server --json)
    grep -Fq '"running":true' <<<"$external_status"
    grep -Fq '"session":"bessie"' <<<"$external_status"
    XDG_CONFIG_HOME="$root/xdg-config" XDG_STATE_HOME="$root/xdg-state" \
        HERDR_SESSION=bessie "$external_runtime" server stop >/dev/null
    find "$root" -depth -delete
    runtime_case_pid=''
    runtime_case_root=''
    runtime_case_herdr=''
}

cleanup() {
    cleanup_status=$?
    if [[ -n "$performance_profile_pid" ]] && kill -0 "$performance_profile_pid" 2>/dev/null; then
        kill "$performance_profile_pid" 2>/dev/null || true
        wait "$performance_profile_pid" 2>/dev/null || true
    fi
    stop_app || true
    if [[ -n "$runtime_case_pid" ]] && kill -0 "$runtime_case_pid" 2>/dev/null; then
        kill "$runtime_case_pid" 2>/dev/null || true
    fi
    if [[ -n "$runtime_case_herdr" && -x "$runtime_case_herdr" && -d "$runtime_case_root/xdg-config" ]]; then
        XDG_CONFIG_HOME="$runtime_case_root/xdg-config" XDG_STATE_HOME="$runtime_case_root/xdg-state" \
            HERDR_SESSION=bessie "$runtime_case_herdr" server stop >/dev/null 2>&1 || true
    fi
    [[ -z "$runtime_case_root" ]] || find "$runtime_case_root" -depth -delete 2>/dev/null || true
    [[ -z "$missing_bundle_case" ]] || find "$missing_bundle_case" -depth -delete 2>/dev/null || true
    [[ -z "$corrupt_bundle_case" ]] || find "$corrupt_bundle_case" -depth -delete 2>/dev/null || true
    if [[ -n "$installed_pid" ]] && kill -0 "$installed_pid" 2>/dev/null \
        && { [[ "$cleanup_status" -ne 0 ]] || [[ "$leave_installed_app_running" != true ]]; }; then
        cleanup_installed_executable=$(ps -p "$installed_pid" -o command= 2>/dev/null || true)
        if [[ "$cleanup_installed_executable" == /Applications/Bessie.app/Contents/MacOS/BessieApp ]]; then
            kill "$installed_pid"
            wait "$installed_pid" 2>/dev/null || true
        else
            echo "Refusing to stop unexpected installed-app process: $cleanup_installed_executable" >&2
        fi
    fi
    if [[ "$cleanup_status" -ne 0 && "$install_candidate_active" == true ]]; then
        find "$installed_app" -depth -delete 2>/dev/null || true
        if [[ -e "$install_backup" ]]; then
            mv "$install_backup" "$installed_app"
        fi
    fi
    if [[ -x "$herdr_bin" && -d "$autostart_xdg_config" ]]; then
        XDG_CONFIG_HOME="$autostart_xdg_config" XDG_STATE_HOME="$autostart_xdg_state" \
        HERDR_SESSION=bessie "$herdr_bin" server stop >/dev/null 2>&1 || true
    fi
    if [[ -n "$cli_workspace_id" && -S "$herdr_socket" ]]; then
        XDG_CONFIG_HOME="$herdr_xdg_config" XDG_STATE_HOME="$herdr_xdg_state" \
        HERDR_CONFIG_PATH="$herdr_config" HERDR_SOCKET_PATH="$herdr_socket" \
            "$herdr_bin" workspace close "$cli_workspace_id" >/dev/null 2>&1 || true
    fi
    if [[ -n "$herdr_pid" ]] && kill -0 "$herdr_pid" 2>/dev/null; then
        executable=$(ps -p "$herdr_pid" -o command=)
        case "$executable" in
            "$herdr_bin"\ server*) kill "$herdr_pid"; wait "$herdr_pid" 2>/dev/null || true ;;
            *) echo "Refusing to stop unexpected Herdr process: $executable" >&2 ;;
        esac
    fi
    if ! pgrep -f "^$herdr_bin server" >/dev/null; then
        rm -f "$herdr_socket" "$herdr_dir/runtime/herdr-client.sock"
    fi
    rm -f "$intent_socket" "$intent_socket.lock"
    rm -f "$presentation_path"
    [[ ! -e "$projects_root" ]] || find "$projects_root" -depth -delete
}
trap cleanup EXIT

./scripts/check.sh
bash ./scripts/verify-app-install-lifecycle.sh

mkdir -p "$herdr_dir/runtime" "$herdr_xdg_config" "$herdr_xdg_state"
# rsync preserves source mtimes, so a pre-existing Mac release build can look
# newer than changed source. Clean before packaging so the app under live test
# is built from the exact mirrored source rather than stale SwiftPM products.
xcrun swift package clean
./scripts/package-app.sh
packaged_bundle_identifier=$(plutil -extract CFBundleIdentifier raw dist/Bessie.app/Contents/Info.plist)
if [[ "$packaged_bundle_identifier" != "$package_bundle_identifier" ]]; then
    echo "Packaged bundle identifier mismatch: expected $package_bundle_identifier, got $packaged_bundle_identifier" >&2
    exit 1
fi

packaged_runtime="$mac_dir/dist/Bessie.app/Contents/Resources/Herdr/herdr"
packaged_license="$mac_dir/dist/Bessie.app/Contents/Resources/Herdr/LICENSE"
packaged_lock="$mac_dir/dist/Bessie.app/Contents/Resources/Herdr/runtime-lock.json"
packaged_bessie_license="$mac_dir/dist/Bessie.app/Contents/Resources/Bessie-LICENSE.txt"
test -x "$packaged_runtime"
test -s "$packaged_license"
test -s "$packaged_lock"
test -s "$packaged_bessie_license"
if [[ "$codesign_identity" == - ]]; then
    [[ $(shasum -a 256 "$packaged_runtime" | awk '{print $1}') == "$herdr_sha256" ]]
else
    codesign -dv --verbose=4 "$packaged_runtime" 2>&1 | grep -Fq "$codesign_identity"
fi
[[ $(lipo -archs "$packaged_runtime") == "$herdr_architecture" ]]
[[ $("$packaged_runtime" --version) == "$herdr_expected_version" ]]
[[ $(( $(stat -f %Lp "$packaged_runtime") & 022 )) == 0 ]]
cmp Sources/BessieApp/Resources/Herdr-LICENSE.txt "$packaged_license"
cmp LICENSE "$packaged_bessie_license"
cmp scripts/herdr-runtime-lock.json "$packaged_lock"
codesign --verify --strict "$packaged_runtime"
codesign --verify --deep --strict dist/Bessie.app

# Product-level failure routing must distinguish a broken app bundle from an
# explicitly missing external runtime without launching the included fallback.
missing_bundle_case="/private/tmp/Bessie-missing-runtime-$$.app"
corrupt_bundle_case="/private/tmp/Bessie-corrupt-runtime-$$.app"
ditto dist/Bessie.app "$missing_bundle_case"
rm "$missing_bundle_case/Contents/Resources/Herdr/herdr"
codesign --force --sign - "$missing_bundle_case"
verify_runtime_failure_case missing-bundled "$missing_bundle_case" bundledIntegrity '' bundled \
    "$missing_bundle_case/Contents/Resources/Herdr/herdr"
find "$missing_bundle_case" -depth -delete

ditto dist/Bessie.app "$corrupt_bundle_case"
rm "$corrupt_bundle_case/Contents/Resources/Herdr/herdr"
/bin/cp /usr/bin/true "$corrupt_bundle_case/Contents/Resources/Herdr/herdr"
codesign --force --sign - "$corrupt_bundle_case"
verify_runtime_failure_case corrupt-bundled "$corrupt_bundle_case" bundledIntegrity '' bundled \
    "$corrupt_bundle_case/Contents/Resources/Herdr/herdr"
find "$corrupt_bundle_case" -depth -delete

verify_runtime_failure_case missing-external "$mac_dir/dist/Bessie.app" externalMissing \
    '{"version":1,"kind":"custom","path":"/definitely/missing/bessie-herdr"}' custom \
    /definitely/missing/bessie-herdr
verify_runtime_failure_case incompatible-external "$mac_dir/dist/Bessie.app" incompatible \
    '{"version":1,"kind":"custom","path":"/usr/bin/true"}' custom /usr/bin/true
verify_external_runtime_success_case "$mac_dir/dist/Bessie.app" "$packaged_runtime"

# All live checks below exercise the executable from inside the packaged app.
herdr_bin="$packaged_runtime"
system_default_before=$(HERDR_SESSION=default "$herdr_bin" status server --json 2>&1 || true)

if pgrep -f "^$herdr_bin server" >/dev/null; then
    echo "Refusing to reuse or stop an existing repository-local Herdr server." >&2
    exit 1
fi

find "$herdr_dir/runtime" -maxdepth 1 -type s \( -name 'herdr.sock' -o -name 'herdr-client.sock' \) -delete
: > "$herdr_config"
XDG_CONFIG_HOME="$herdr_xdg_config" XDG_STATE_HOME="$herdr_xdg_state" \
HERDR_CONFIG_PATH="$herdr_config" HERDR_SOCKET_PATH="$herdr_socket" \
    "$herdr_bin" server >"$herdr_log" 2>&1 &
herdr_pid=$!

for _ in {1..40}; do
    [[ -S "$herdr_socket" ]] && break
    kill -0 "$herdr_pid" 2>/dev/null || { cat "$herdr_log" >&2; exit 1; }
    sleep 0.25
done
[[ -S "$herdr_socket" ]] || { echo "Isolated Herdr socket did not appear." >&2; exit 1; }
grep -Fq "logs: $herdr_xdg_config/herdr/herdr-server.log" "$herdr_log"
if grep -Fq "$HOME/.config/herdr" "$herdr_log"; then
    echo "Isolated Herdr reported a global config/log path." >&2
    exit 1
fi

status_json=$(XDG_CONFIG_HOME="$herdr_xdg_config" XDG_STATE_HOME="$herdr_xdg_state" \
    HERDR_CONFIG_PATH="$herdr_config" HERDR_SOCKET_PATH="$herdr_socket" \
    "$herdr_bin" status server --json)
grep -Fq '"running":true' <<<"$status_json"
/usr/bin/python3 -c 'import json, sys; status = json.load(sys.stdin); expected = int(sys.argv[1]); actual = status.get("protocol"); raise SystemExit(0 if actual == expected else f"Herdr protocol mismatch: {actual!r}")' "$herdr_protocol" <<<"$status_json"

# Rebuild the test products independently from the packaged release artifact.
xcrun swift package clean
XDG_CONFIG_HOME="$herdr_xdg_config" XDG_STATE_HOME="$herdr_xdg_state" \
    BESSIE_LIVE_HERDR_SOCKET="$herdr_socket" BESSIE_LIVE_RUN_ID="verify-$$" xcrun swift test
xcrun swift build --product bessie
xcrun swift build --product bessie-mcp
test -x .build/debug/bessie
test -x .build/debug/bessie-mcp

test -x dist/Bessie.app/Contents/MacOS/BessieApp
test -x dist/Bessie.app/Contents/Resources/Herdr/herdr
test -s dist/Bessie.app/Contents/Resources/Herdr/LICENSE
test -s dist/Bessie.app/Contents/Resources/Bessie-LICENSE.txt
[[ $(shasum -a 256 dist/Bessie.app/Contents/Resources/libghostty-spm-LICENSE.txt | awk '{print $1}') == 1f4b38df6a142e678a85d84c3a7ec4d1db328a556483241df714156134e81615 ]]
[[ $(shasum -a 256 dist/Bessie.app/Contents/Resources/Ghostty-LICENSE.txt | awk '{print $1}') == 386211873e5b7a02f663ae4d7adf96285999f91608f8f9f31fecfd0f4095e6f1 ]]
[[ $(shasum -a 256 dist/Bessie.app/Contents/Resources/Sparkle-LICENSE.txt | awk '{print $1}') == 389a4e4e9a32f059775b13a06e25a591445ba229d2838d26dd3e7c0c45127cfe ]]
test -s dist/Bessie.app/Contents/Resources/BessieDark.icns
test -s dist/Bessie.app/Contents/Resources/BessieLight.icns
attribution_path=dist/Bessie.app/Contents/Resources/ATTRIBUTION.md
[[ -s "$attribution_path" ]]
grep -Fq '5a58926563ddacbde4a12b4a347464c2c6945393' "$attribution_path"
grep -Fq 'Copyright (c) 2021 Catppuccin' "$attribution_path"
[[ $(plutil -extract CFBundleIconFile raw dist/Bessie.app/Contents/Info.plist) == BessieDark.icns ]]
[[ $(plutil -extract CFBundleShortVersionString raw dist/Bessie.app/Contents/Info.plist) == 0.1.0 ]]
[[ $(plutil -extract CFBundleVersion raw dist/Bessie.app/Contents/Info.plist) == 3 ]]
plutil -lint dist/Bessie.app/Contents/Info.plist
otool -L dist/Bessie.app/Contents/MacOS/BessieApp > "$herdr_dir/runtime/bessie-otool.txt"
nm -gU dist/Bessie.app/Contents/MacOS/BessieApp > "$herdr_dir/runtime/bessie-symbols.txt"
grep -Fq '/Metal.framework/' "$herdr_dir/runtime/bessie-otool.txt"
grep -Fq 'GhosttyTerminal03AppB4View' "$herdr_dir/runtime/bessie-symbols.txt"
controller_bin="$logical_mac_dir/dist/Bessie.app/Contents/Resources/Herdr/herdr"
[[ $(cd "$(dirname "$controller_bin")" && pwd -P)/herdr == "$packaged_runtime" ]]

: > "$state_log"
: > "$app_log"
# This phase verifies the live workspace shell. Keep onboarding completed in
# the isolated presentation fixture so the two-pane snapshot cannot capture
# the onboarding window instead of the Herdr-owned terminal topology.
printf '%s\n' '{"preferences":{"appearance":"dark","appIcon":"light"},"first_real_terminal_completion_version":1}' > "$presentation_path"
rm -f "$snapshot_path"
launch_app

for _ in {1..40}; do
    grep -Fq 'Connected' "$state_log" && break
    kill -0 "$app_pid" 2>/dev/null || { cat "$app_log" >&2; exit 1; }
    sleep 0.25
done

grep -Fq 'Connecting' "$state_log"
grep -Fq 'Connected' "$state_log"
grep -Fq 'App icon=light' "$state_log"

# Mutate through the public Herdr CLI and prove the already-running app converges from events + snapshot.
cli_label="bessie-m3-cli-$$"
cli_renamed_label="bessie-m3-cli-renamed-$$"
cli_created=$(XDG_CONFIG_HOME="$herdr_xdg_config" XDG_STATE_HOME="$herdr_xdg_state" \
    HERDR_CONFIG_PATH="$herdr_config" HERDR_SOCKET_PATH="$herdr_socket" \
    "$herdr_bin" workspace create --label "$cli_label" --focus)
cli_workspace_id=$(sed -n 's/.*"workspace_id":"\([^"]*\)".*/\1/p' <<<"$cli_created" | head -n 1)
cli_pane_id=$(sed -n 's/.*"pane_id":"\([^"]*\)".*/\1/p' <<<"$cli_created" | head -n 1)
[[ -n "$cli_workspace_id" ]] || { echo "Could not read CLI-created workspace id: $cli_created" >&2; exit 1; }
[[ -n "$cli_pane_id" ]] || { echo "Could not read CLI-created pane id: $cli_created" >&2; exit 1; }
for _ in {1..40}; do
    grep -Fq "Snapshot workspace_labels=$cli_label" "$state_log" && break
    sleep 0.25
done
grep -Fq "Snapshot workspace_labels=$cli_label" "$state_log"

XDG_CONFIG_HOME="$herdr_xdg_config" XDG_STATE_HOME="$herdr_xdg_state" \
HERDR_CONFIG_PATH="$herdr_config" HERDR_SOCKET_PATH="$herdr_socket" \
    "$herdr_bin" workspace rename "$cli_workspace_id" "$cli_renamed_label" >/dev/null
for _ in {1..40}; do
    grep -Fq "Snapshot workspace_labels=$cli_renamed_label" "$state_log" && break
    sleep 0.25
done
grep -Fq "Snapshot workspace_labels=$cli_renamed_label" "$state_log"

# The connected app must host a real libghostty surface and drive the first Herdr-owned pane.
for _ in {1..80}; do
    grep -Fq "Terminal pane=$cli_pane_id viewport raw=true paste=true" "$state_log" && break
    kill -0 "$app_pid" 2>/dev/null || { cat "$app_log" >&2; exit 1; }
    sleep 0.25
done
grep -Fq "Terminal pane=$cli_pane_id input=raw_unicode,special_enter,paste" "$state_log"
grep -Fq "Terminal pane=$cli_pane_id viewport raw=true paste=true" "$state_log"
for _ in {1..40}; do
    grep -Fq "Terminal pane=$cli_pane_id input=shortcut_cmd_b_control_b value=true" "$state_log" && break
    sleep 0.25
done
grep -Fq "Terminal pane=$cli_pane_id input=shortcut_cmd_b_control_b value=true" "$state_log"
for _ in {1..40}; do
    grep -Fq "Terminal pane=$cli_pane_id input=scroll" "$state_log" && break
    sleep 0.25
done
grep -Fq "Terminal pane=$cli_pane_id input=scroll" "$state_log"
grep -Eq "Terminal pane=$cli_pane_id state=ready_[0-9]+x[0-9]+_seq_[0-9]+_full_true" "$state_log"

# Split through the public CLI; the running app must add one, and only one, controller for the new visible pane.
split_created=$(XDG_CONFIG_HOME="$herdr_xdg_config" XDG_STATE_HOME="$herdr_xdg_state" \
    HERDR_CONFIG_PATH="$herdr_config" HERDR_SOCKET_PATH="$herdr_socket" \
    "$herdr_bin" pane split "$cli_pane_id" --direction right --ratio 0.5 --focus)
split_pane_id=$(sed -n 's/.*"pane_id":"\([^"]*\)".*/\1/p' <<<"$split_created" | head -n 1)
[[ -n "$split_pane_id" && "$split_pane_id" != "$cli_pane_id" ]] || { echo "Could not read split pane id: $split_created" >&2; exit 1; }
for _ in {1..80}; do
    grep -Fq "Terminal pane=$split_pane_id viewport raw=true paste=true" "$state_log" && break
    kill -0 "$app_pid" 2>/dev/null || { cat "$app_log" >&2; exit 1; }
    sleep 0.25
done
grep -Fq "Terminal pane=$split_pane_id viewport raw=true paste=true" "$state_log"
for _ in {1..40}; do
    grep -Fq "Terminal pane=$split_pane_id input=shortcut_cmd_b_control_b value=true" "$state_log" && break
    sleep 0.25
done
grep -Fq "Terminal pane=$split_pane_id input=shortcut_cmd_b_control_b value=true" "$state_log"
# Foundation Process children are not guaranteed to remain direct children of
# the packaged app on every macOS release. The verifier-owned runtime path is
# unique, so scope controller assertions to that exact executable instead.
controller_count=0
for _ in {1..40}; do
    controller_count=$({ pgrep -f "^$controller_bin terminal session control" || true; } | wc -l | tr -d ' ')
    [[ "$controller_count" == 2 ]] && break
    sleep 0.25
done
if [[ "$controller_count" != 2 ]]; then
    echo "Expected two packaged terminal controllers, found $controller_count for $controller_bin." >&2
    pgrep -alf 'terminal session control' >&2 || true
    exit 1
fi

# Validate the packaged app's opt-in payload-free performance evidence. The
# evaluator intentionally exits nonzero for incomplete evidence, so capture and
# assert that status rather than letting `set -e` misclassify it as a harness
# failure. Live percentile collection remains a separate release blocker.
for _ in {1..40}; do
    [[ -s "$performance_evidence_path" ]] && \
        /usr/bin/python3 -m json.tool "$performance_evidence_path" >/dev/null 2>&1 && break
    sleep 0.25
done
[[ -s "$performance_evidence_path" ]]
performance_status=0
/usr/bin/python3 scripts/run-hardening-benchmarks.py \
    --app-evidence "$performance_evidence_path" > "$performance_report_path" || performance_status=$?
[[ "$performance_status" == 1 ]]
grep -Fq 'evidence_kind: packaged_local_measurement' "$performance_report_path"
grep -Fq 'simulation_is_not_live_measurement: false' "$performance_report_path"
grep -Fq 'UNAVAILABLE printable_key_to_visible_echo_p95 observed=unavailable' "$performance_report_path"
grep -Fq 'overall: INCOMPLETE' "$performance_report_path"

# Exercise the verifier-owned agent bus while the packaged app and isolated
# Herdr server are live (AE1-AE3 and AE6).
for _ in {1..40}; do
    [[ -S "$intent_socket" && $(stat -f %Lp "$intent_socket") == 600 ]] && break
    kill -0 "$app_pid" 2>/dev/null || { cat "$app_log" >&2; exit 1; }
    sleep 0.25
done
[[ -S "$intent_socket" ]]
[[ $(stat -f %Lp "$intent_socket") == 600 ]]

intent_names_json=$(intent_cli intents)
/usr/bin/python3 -c '
import json, sys
result = json.load(sys.stdin)
expected = {
    "intents.list", "app.status", "connection.status", "connection.context",
    "session.projection", "pane.focus", "pane.presentation.list", "pane.pin",
    "pane.unpin", "pane.snooze", "pane.wake", "workspace.focus",
    "workspace.close", "project.list", "project.show",
}
actual = {intent["id"] for intent in result.get("value", {}).get("intents", [])}
if result.get("ok") is not True or actual != expected:
    raise SystemExit(f"CLI intent catalog mismatch: {sorted(actual)}")
' <<<"$intent_names_json"

intent_cli status | assert_intent_ok
connection_status=$(intent_cli call connection.status --json '{"connection_id":"local-bessie"}')
/usr/bin/python3 -c 'import json, sys; value=json.load(sys.stdin).get("value", {}); raise SystemExit(0 if value == {"connected": True, "connection_id": "local-bessie"} else f"bad connection status: {value}")' <<<"$connection_status"
projection_json=$(intent_cli call session.projection --json '{"connection_id":"local-bessie"}')
/usr/bin/python3 -c 'import json, sys; value=json.load(sys.stdin).get("value", {}); raise SystemExit(0 if value.get("connection_id") == "local-bessie" and value.get("workspaces") else f"bad projection: {value}")' <<<"$projection_json"
cli_terminal_id=$(/usr/bin/python3 -c 'import json, sys; value=json.load(sys.stdin)["value"]; target=sys.argv[1]; print(next(pane["terminal_id"] for pane in value["panes"] if pane["pane_id"] == target))' "$cli_pane_id" <<<"$projection_json")
presentation_list=$(intent_cli call pane.presentation.list --json '{"connection_id":"local-bessie"}')
presentation_revision=$(/usr/bin/python3 -c 'import json, sys; print(json.load(sys.stdin)["value"]["revision"])' <<<"$presentation_list")
pin_result=$(intent_cli call pane.pin --json "{\"connection_id\":\"local-bessie\",\"pane_id\":\"$cli_pane_id\",\"terminal_id\":\"$cli_terminal_id\",\"expected_revision\":$presentation_revision}")
/usr/bin/python3 -c 'import json, sys; value=json.load(sys.stdin)["value"]; raise SystemExit(0 if value["pinned"] is True and value["revision"] == int(sys.argv[1]) + 1 else f"bad pin result: {value}")' "$presentation_revision" <<<"$pin_result"
presentation_revision=$((presentation_revision + 1))
snooze_result=$(intent_cli call pane.snooze --json "{\"connection_id\":\"local-bessie\",\"pane_id\":\"$cli_pane_id\",\"terminal_id\":\"$cli_terminal_id\",\"expected_revision\":$presentation_revision,\"preset\":\"one_hour\"}")
/usr/bin/python3 -c 'import json, sys; value=json.load(sys.stdin)["value"]; raise SystemExit(0 if value["pinned"] is True and value["snooze"] == "one_hour" and value["wake_at"] else f"bad snooze result: {value}")' <<<"$snooze_result"
presentation_revision=$((presentation_revision + 1))
intent_cli call project.list | assert_intent_ok
intent_cli call workspace.focus --json "{\"connection_id\":\"local-bessie\",\"workspace_id\":\"$cli_workspace_id\"}" | assert_intent_ok
intent_cli call pane.focus --json "{\"connection_id\":\"local-bessie\",\"pane_id\":\"$cli_pane_id\"}" | assert_intent_ok
focused_snapshot=$(printf '%s\n' '{"id":"mac-agent-bus-focus","method":"session.snapshot","params":{}}' | nc -U "$herdr_socket")
assert_herdr_focus "$cli_workspace_id" "$cli_pane_id" <<<"$focused_snapshot"

mcp_stdout="$herdr_dir/runtime/bessie-mcp-$$.stdout"
mcp_stderr="$herdr_dir/runtime/bessie-mcp-$$.stderr"
printf '%s\n' \
    '{"jsonrpc":"2.0","id":"init","method":"initialize","params":{"protocolVersion":"2024-11-05"}}' \
    '{"jsonrpc":"2.0","id":"list","method":"tools/list","params":{}}' \
    "{\"jsonrpc\":\"2.0\",\"id\":\"call\",\"method\":\"tools/call\",\"params\":{\"name\":\"pane.wake\",\"arguments\":{\"connection_id\":\"local-bessie\",\"pane_id\":\"$cli_pane_id\",\"terminal_id\":\"$cli_terminal_id\",\"expected_revision\":$presentation_revision}}}" \
    | BESSIE_INTENT_SOCKET_PATH="$intent_socket" "$mac_dir/.build/debug/bessie-mcp" >"$mcp_stdout" 2>"$mcp_stderr"
[[ ! -s "$mcp_stderr" ]]
/usr/bin/python3 -c '
import json, sys
cli = json.loads(sys.argv[1])
expected = {intent["id"] for intent in cli["value"]["intents"]}
with open(sys.argv[2], encoding="utf-8") as stream:
    lines = stream.readlines()
if len(lines) != 3:
    raise SystemExit(f"MCP emitted {len(lines)} stdout lines, expected 3")
initialize, listed, called = map(json.loads, lines)
actual = {tool["name"] for tool in listed["result"]["tools"]}
if initialize["result"]["serverInfo"]["name"] != "bessie-mcp" or actual != expected:
    raise SystemExit(f"MCP catalog mismatch: {sorted(actual)}")
intent_result = json.loads(called["result"]["content"][0]["text"])
if called["result"]["isError"] or not intent_result.get("ok"):
    raise SystemExit(f"MCP call failed: {called}")
' "$intent_names_json" "$mcp_stdout"
presentation_revision=$((presentation_revision + 1))
intent_cli call pane.unpin --json "{\"connection_id\":\"local-bessie\",\"pane_id\":\"$cli_pane_id\",\"terminal_id\":\"$cli_terminal_id\",\"expected_revision\":$presentation_revision}" | assert_intent_ok

# Capture the actual AppKit window without Screen Recording permission and validate a usable PNG artifact.
for _ in {1..40}; do
    [[ -s "$snapshot_path" ]] && break
    sleep 0.25
done
[[ -s "$snapshot_path" ]]
file "$snapshot_path" | grep -Fq 'PNG image data'
snapshot_width=$(sips -g pixelWidth "$snapshot_path" | awk '/pixelWidth/ {print $2}')
snapshot_height=$(sips -g pixelHeight "$snapshot_path" | awk '/pixelHeight/ {print $2}')
[[ "$snapshot_width" -ge 760 && "$snapshot_height" -ge 520 ]]
[[ $(stat -f %z "$snapshot_path") -gt 20000 ]]
xcrun swift scripts/verify-design-snapshot.swift "$snapshot_path"
grep -Fq "Window snapshot path=$snapshot_path" "$state_log"

first_token=${cli_pane_id//:/_}
second_token=${split_pane_id//:/_}
first_read=$(read_pane_recent "$cli_pane_id")
second_read=$(read_pane_recent "$split_pane_id")
grep -Fq "RAW_${first_token}_牛é🐄" <<<"$first_read"
grep -Fq "PASTE_$first_token" <<<"$first_read"
grep -Fq "RAW_${second_token}_牛é🐄" <<<"$second_read"
grep -Fq "PASTE_$second_token" <<<"$second_read"

# Emit all 16 ANSI background slots through Herdr's public mode-aware input API,
# then prove every concrete coordinated theme in the same live workspace. Each
# relaunch reuses the Herdr-owned panes and terminal output; only Bessie-owned
# presentation selection changes.
ansi_request=$(BESSIE_ANSI_PANE_ID="$cli_pane_id" /usr/bin/python3 - <<'PY' | nc -U "$herdr_socket"
import json, os
blocks = "\\033[3J\\033[H\\033[2JBessie ANSI 00-15: "
blocks += "".join(f"\\033[{40 + index}m {index:02d} " for index in range(8))
blocks += "\\033[0m\\n"
blocks += "".join(f"\\033[{100 + index}m {index + 8:02d} " for index in range(8))
command = "printf '" + blocks + "\\033[0m\\nBESSIE_THEME_ANSI_16_牛é🐄\\n'"
print(json.dumps({
    "id": "mac-theme-ansi",
    "method": "pane.send_input",
    "params": {"pane_id": os.environ["BESSIE_ANSI_PANE_ID"], "text": command, "keys": ["Enter"]},
}))
PY
)
grep -Fq '"type":"ok"' <<<"$ansi_request"
for _ in {1..40}; do
    ansi_read=$(read_pane_recent "$cli_pane_id")
    grep -Fq 'BESSIE_THEME_ANSI_16_牛é🐄' <<<"$ansi_read" && break
    sleep 0.25
done
grep -Fq 'BESSIE_THEME_ANSI_16_牛é🐄' <<<"$ansi_read"

capture_live_theme_matrix

# Continue lifecycle/recovery checks from a fresh Bessie Dark attachment.
stop_app
printf '%s\n' '{"preferences":{"appearance":"dark","appIcon":"light"},"first_real_terminal_completion_version":1}' > "$presentation_path"
snapshot_path="$mac_dir/dist/Bessie-window.png"
snapshot_trigger=disabled
terminal_automation=0
ready_before_theme_reopen=$(grep -c 'Terminal pane=.* state=ready_' "$state_log" || true)
launch_app
for _ in {1..80}; do
    ready_after_theme_reopen=$(grep -c 'Terminal pane=.* state=ready_' "$state_log" || true)
    [[ "$ready_after_theme_reopen" -ge $((ready_before_theme_reopen + 2)) ]] && break
    kill -0 "$app_pid" 2>/dev/null || { cat "$app_log" >&2; exit 1; }
    sleep 0.25
done
[[ "$ready_after_theme_reopen" -ge $((ready_before_theme_reopen + 2)) ]]

# Killing only one controller must freeze and reconnect it without takeover or pane loss.
controller_pid=$(pgrep -f "^$controller_bin terminal session control $cli_pane_id" | head -n 1)
[[ -n "$controller_pid" ]]
ready_before_controller_kill=$(grep -c "Terminal pane=$cli_pane_id state=ready_" "$state_log")
kill "$controller_pid"
for _ in {1..80}; do
    ready_after_controller_kill=$(grep -c "Terminal pane=$cli_pane_id state=ready_" "$state_log" || true)
    [[ "$ready_after_controller_kill" -gt "$ready_before_controller_kill" ]] && break
    sleep 0.25
done
grep -Fq "Terminal pane=$cli_pane_id state=reconnecting_" "$state_log"
[[ $(grep -c "Terminal pane=$cli_pane_id state=ready_" "$state_log") -gt "$ready_before_controller_kill" ]]

# A second writable controller is rejected; Bessie never passes --takeover implicitly.
conflict_output=$(printf '\n' | XDG_CONFIG_HOME="$herdr_xdg_config" XDG_STATE_HOME="$herdr_xdg_state" \
    HERDR_CONFIG_PATH="$herdr_config" HERDR_SOCKET_PATH="$herdr_socket" \
    "$herdr_bin" terminal session control "$cli_pane_id" --cols 80 --rows 24 2>&1 || true)
grep -Fq 'already has an attached client' <<<"$conflict_output"

# Quit Bessie, prove both Herdr panes and their output survive, then reopen and reacquire two fresh controllers.
stop_app
not_running=$(intent_cli status || true)
/usr/bin/python3 -c 'import json, sys; result=json.load(sys.stdin); raise SystemExit(0 if result.get("error", {}).get("code") == "bessie_not_running" else f"expected bessie_not_running: {result}")' <<<"$not_running"
kill -0 "$herdr_pid"
for _ in {1..40}; do
    ! pgrep -f "^$controller_bin terminal session control ($cli_pane_id|$split_pane_id)" >/dev/null && break
    sleep 0.25
done
! pgrep -f "^$controller_bin terminal session control ($cli_pane_id|$split_pane_id)" >/dev/null
surviving_read=$(read_pane_recent "$cli_pane_id")
surviving_second_read=$(read_pane_recent "$split_pane_id")
grep -Fq 'BESSIE_THEME_ANSI_16_牛é🐄' <<<"$surviving_read"
grep -Fq "RAW_${second_token}_牛é🐄" <<<"$surviving_second_read"

ready_before_reopen=$(grep -c 'Terminal pane=.* state=ready_' "$state_log")
launch_app
for _ in {1..80}; do
    ready_after_reopen=$(grep -c 'Terminal pane=.* state=ready_' "$state_log" || true)
    [[ "$ready_after_reopen" -ge $((ready_before_reopen + 2)) ]] && break
    kill -0 "$app_pid" 2>/dev/null || { cat "$app_log" >&2; exit 1; }
    sleep 0.25
done
[[ $(grep -c 'Terminal pane=.* state=ready_' "$state_log") -ge $((ready_before_reopen + 2)) ]]

# Relaunch with the app-owned process flow enabled and prove it creates and retains a real shell pane.
stop_app
process_automation=1
terminal_automation=1
snapshot_trigger=disabled
launch_app
for _ in {1..120}; do
    grep -Fq 'Process launch pane=' "$state_log" && grep -Fq 'kind=shell agent_started=false shell_preserved=false' "$state_log" && break
    kill -0 "$app_pid" 2>/dev/null || { cat "$app_log" >&2; exit 1; }
    sleep 0.25
done
shell_launch_line=$(grep 'Process launch pane=.*kind=shell agent_started=false shell_preserved=false' "$state_log" | tail -n 1)
shell_pane_id=$(sed -n 's/.*Process launch pane=\([^ ]*\) kind=shell.*/\1/p' <<<"$shell_launch_line")
[[ -n "$shell_pane_id" ]]
shell_token=${shell_pane_id//:/_}
for _ in {1..80}; do
    grep -Fq "Terminal pane=$shell_pane_id viewport raw=true paste=true" "$state_log" && break
    sleep 0.25
done
grep -Fq "Terminal pane=$shell_pane_id viewport raw=true paste=true" "$state_log"
shell_read=$(read_pane_recent "$shell_pane_id")
grep -Fq "RAW_${shell_token}_牛é🐄" <<<"$shell_read"

# The manifest is authoritative for supported kinds. The requested executable comes from the Mac login PATH.
manifest_json=$(printf '%s\n' '{"id":"mac-agent-manifests","method":"server.agent_manifests","params":{}}' | nc -U "$herdr_socket")
grep -Fq '"type":"agent_manifest_status"' <<<"$manifest_json"
grep -Fq "\"agent\":\"$requested_agent_kind\"" <<<"$manifest_json" || {
    echo "Herdr does not report the requested agent kind: $requested_agent_kind" >&2
    exit 1
}

agent_status_from_snapshot() {
    local pane_id="$1"
    local agent_kind="$2"
    /usr/bin/python3 -c '
import json, sys
root = json.load(sys.stdin)
target, requested = sys.argv[1:3]

def walk(value):
    if isinstance(value, dict):
        if value.get("pane_id") == target and value.get("agent") == requested:
            status = value.get("agent_status") or value.get("status") or ""
            if status:
                print(status)
                raise SystemExit
        for child in value.values():
            walk(child)
    elif isinstance(value, list):
        for child in value:
            walk(child)

walk(root)
' "$pane_id" "$agent_kind"
}

stop_app
terminal_automation=0
process_agent_kind=$requested_agent_kind
launch_app
for _ in {1..160}; do
    grep -Fq "kind=$requested_agent_kind agent_started=true shell_preserved=false" "$state_log" && break
    kill -0 "$app_pid" 2>/dev/null || { cat "$app_log" >&2; exit 1; }
    sleep 0.25
done
grep -Fq "kind=$requested_agent_kind agent_started=true shell_preserved=false" "$state_log"
agent_launch_line=$(grep "Process launch pane=.*kind=$requested_agent_kind agent_started=true shell_preserved=false" "$state_log" | tail -n 1)
agent_pane_id=$(sed -n 's/.*Process launch pane=\([^ ]*\) kind=.*/\1/p' <<<"$agent_launch_line")
[[ -n "$agent_pane_id" ]]

agent_status=''
for _ in {1..80}; do
    agent_snapshot=$(printf '%s\n' '{"id":"mac-agent-snapshot","method":"session.snapshot","params":{}}' | nc -U "$herdr_socket")
    agent_status=$(agent_status_from_snapshot "$agent_pane_id" "$requested_agent_kind" <<<"$agent_snapshot")
    case "$agent_status" in
        blocked|idle|working|done) break ;;
    esac
    sleep 0.25
done
case "$agent_status" in
    blocked|idle|working|done) ;;
    *) echo "Live $requested_agent_kind pane did not reach a semantic agent state: ${agent_status:-missing}" >&2; exit 1 ;;
esac

# Bessie can quit without killing the Herdr-owned agent, then reopen onto that same pane without launching another one.
stop_app
surviving_agent_snapshot=$(printf '%s\n' '{"id":"mac-agent-survival","method":"session.snapshot","params":{}}' | nc -U "$herdr_socket")
surviving_agent_status=$(agent_status_from_snapshot "$agent_pane_id" "$requested_agent_kind" <<<"$surviving_agent_snapshot")
case "$surviving_agent_status" in
    blocked|idle|working|done) ;;
    *) echo "Live $requested_agent_kind pane did not survive app exit as the same authoritative agent record" >&2; exit 1 ;;
esac
process_automation=0
process_agent_kind=''
agent_ready_before_reopen=$(grep -c "Terminal pane=$agent_pane_id state=ready_" "$state_log" || true)
connected_before_agent_reopen=$(grep -c '^Connected$' "$state_log" || true)
launch_app
for _ in {1..80}; do
    agent_ready_after_reopen=$(grep -c "Terminal pane=$agent_pane_id state=ready_" "$state_log" || true)
    connected_after_agent_reopen=$(grep -c '^Connected$' "$state_log" || true)
    [[ "$agent_ready_after_reopen" -gt "$agent_ready_before_reopen" && "$connected_after_agent_reopen" -gt "$connected_before_agent_reopen" ]] && break
    kill -0 "$app_pid" 2>/dev/null || { cat "$app_log" >&2; exit 1; }
    sleep 0.25
done
[[ $(grep -c "Terminal pane=$agent_pane_id state=ready_" "$state_log" || true) -gt "$agent_ready_before_reopen" ]]
[[ $(grep -c '^Connected$' "$state_log" || true) -gt "$connected_before_agent_reopen" ]]
printf 'Live agent proof pane=%s kind=%s status=%s executable=%s\n' \
    "$agent_pane_id" "$requested_agent_kind" "$agent_status" "$requested_agent_path" >> "$state_log"

# Run the release-gating terminal and app performance workload in the isolated
# Herdr fixture. Evidence contains timing/resource values and opaque sequences,
# never terminal payloads, commands, paths, or host identity.
stop_app
performance_tab=$(XDG_CONFIG_HOME="$herdr_xdg_config" XDG_STATE_HOME="$herdr_xdg_state" \
    HERDR_CONFIG_PATH="$herdr_config" HERDR_SOCKET_PATH="$herdr_socket" \
    "$herdr_bin" tab create --workspace "$cli_workspace_id" --label "bessie-perf-$$" --focus)
performance_tab_pane_id=$(sed -n 's/.*"pane_id":"\([^"]*\)".*/\1/p' <<<"$performance_tab" | head -n 1)
[[ -n "$performance_tab_pane_id" ]] || {
    echo "Could not create the second performance tab: $performance_tab" >&2
    exit 1
}
performance_evidence_path="$pane_switch_performance_evidence_path"
terminal_automation=0
terminal_performance_probe=0
terminal_performance_pane_id=''
pane_switch_performance_probe=1
snapshot_trigger=disabled
design_preview=''
rm -f "$terminal_performance_evidence_path" "$pane_switch_performance_evidence_path" \
    "$terminal_performance_resources_path" \
    "$terminal_performance_report_path" "$terminal_performance_profile_path"
launch_app
osascript -e "tell application id \"$package_bundle_identifier\" to activate"
for _ in {1..160}; do
    grep -Fq 'Performance pane switch probe complete transitions=20 tabs=2' "$state_log" && break
    kill -0 "$app_pid" 2>/dev/null || { cat "$app_log" >&2; exit 1; }
    sleep 0.25
done
grep -Fq 'Performance pane switch probe complete transitions=20 tabs=2' "$state_log"
[[ -s "$pane_switch_performance_evidence_path" ]]
stop_app

performance_evidence_path="$terminal_performance_evidence_path"
terminal_performance_probe=1
terminal_performance_pane_id=$performance_tab_pane_id
pane_switch_performance_probe=0
launch_app
osascript -e "tell application id \"$package_bundle_identifier\" to activate"

# Keep a native macOS stack sample from the measured packaged app. It is taken
# after the scripted terminal workloads settle, so the trace diagnoses visible
# idle rendering rather than perturbing the latency and throughput samples.
(
    for _ in {1..1600}; do
        if grep -Fq 'Performance terminal probe complete' "$state_log" \
            && grep -Fq 'Performance pane switch probe complete' "$state_log" \
            && grep -Fq 'Performance resize probe complete' "$state_log"; then
            /usr/bin/sample "$app_pid" 3 -file "$terminal_performance_profile_path" >/dev/null
            exit
        fi
        kill -0 "$app_pid" 2>/dev/null || exit 1
        sleep 0.25
    done
    exit 1
) &
performance_profile_pid=$!

cpu_samples="$herdr_dir/runtime/bessie-terminal-cpu-$$.txt"
rss_samples="$herdr_dir/runtime/bessie-terminal-rss-$$.txt"
idle_cpu_samples="$herdr_dir/runtime/bessie-terminal-idle-cpu-$$.txt"
: > "$cpu_samples"
: > "$rss_samples"
: > "$idle_cpu_samples"
performance_started=$SECONDS
for _ in {1..300}; do
    kill -0 "$app_pid" 2>/dev/null || { cat "$app_log" >&2; exit 1; }
    if grep -Fq 'Performance terminal probe failed' "$state_log" \
        || grep -Fq 'Performance pane switch probe failed' "$state_log" \
        || grep -Fq 'Performance resize probe failed' "$state_log"; then
        tail -n 120 "$state_log" >&2
        exit 1
    fi
    read -r cpu_sample rss_sample < <(ps -p "$app_pid" -o %cpu= -o rss=)
    [[ "$cpu_sample" =~ ^[0-9]+([.][0-9]+)?$ && "$rss_sample" =~ ^[0-9]+$ ]]
    printf '%s\n' "$cpu_sample" >> "$cpu_samples"
    printf '%s\n' "$rss_sample" >> "$rss_samples"
    sleep 1
done
performance_duration=$((SECONDS - performance_started))
for _ in {1..160}; do
    if grep -Fq 'Performance terminal probe complete' "$state_log" \
        && grep -Fq 'Performance pane switch probe complete' "$state_log" \
        && grep -Fq 'Performance resize probe complete' "$state_log"; then
        break
    fi
    kill -0 "$app_pid" 2>/dev/null || { cat "$app_log" >&2; exit 1; }
    sleep 0.25
done
grep -Fq 'Performance terminal probe complete echo_samples=200 megabyte_runs=5 line_runs=5 continuous_seconds=300 continuous_input_samples=100' "$state_log"
grep -Fq 'Performance pane switch probe complete transitions=20 tabs=2' "$state_log"
grep -Fq 'Performance resize probe complete storms=40' "$state_log"
wait "$performance_profile_pid"
performance_profile_pid=''
[[ -s "$terminal_performance_profile_path" ]]

# Measure a fresh 30-second idle window after the terminal workload settles.
for _ in {1..30}; do
    kill -0 "$app_pid" 2>/dev/null || { cat "$app_log" >&2; exit 1; }
    read -r idle_cpu_sample _ < <(ps -p "$app_pid" -o %cpu= -o rss=)
    [[ "$idle_cpu_sample" =~ ^[0-9]+([.][0-9]+)?$ ]]
    printf '%s\n' "$idle_cpu_sample" >> "$idle_cpu_samples"
    sleep 1
done

/usr/bin/python3 - "$terminal_performance_resources_path" "$cpu_samples" "$idle_cpu_samples" "$rss_samples" "$performance_duration" <<'PY'
import json
import sys

output, cpu_path, idle_path, rss_path, duration = sys.argv[1:]
read = lambda path: [float(value) for value in open(path, encoding="utf-8") if value.strip()]
payload = {
    "duration_seconds": float(duration),
    "sample_interval_seconds": 1.0,
    "cpu_percent": read(cpu_path),
    "idle_cpu_percent": read(idle_path),
    "rss_mb": [value / 1024.0 for value in read(rss_path)],
}
with open(output, "w", encoding="utf-8") as stream:
    json.dump(payload, stream, indent=2, sort_keys=True)
PY

/usr/bin/python3 - "$terminal_performance_evidence_path" "$pane_switch_performance_evidence_path" <<'PY'
import json
import sys

terminal_path, switches_path = sys.argv[1:]
terminal = json.load(open(terminal_path, encoding="utf-8"))
switches = json.load(open(switches_path, encoding="utf-8"))
switch_spans = [
    span for span in switches["spans"]
    if span.get("start_milestone") == "terminal_switch_requested"
    and span.get("end_milestone") == "terminal_switch_surface_attached"
    and "duration_ms" in span
]
if len(switch_spans) != 20:
    raise ValueError(f"expected 20 pane-switch spans, found {len(switch_spans)}")
terminal["spans"].extend(switch_spans)
terminal["milestones"].extend(
    mark for mark in switches["milestones"]
    if mark.get("milestone") in {"terminal_switch_requested", "terminal_switch_surface_attached"}
)
with open(terminal_path, "w", encoding="utf-8") as stream:
    json.dump(terminal, stream, indent=2, sort_keys=True)
PY

/usr/bin/python3 scripts/run-hardening-benchmarks.py \
    --terminal-app-evidence "$terminal_performance_evidence_path" \
    --resource-samples "$terminal_performance_resources_path" \
    > "$terminal_performance_report_path"
grep -Fq 'PASS printable_echo_p95_ms' "$terminal_performance_report_path"
grep -Fq 'PASS one_megabyte_output_max_ms' "$terminal_performance_report_path"
grep -Fq 'PASS fifty_thousand_lines_max_ms' "$terminal_performance_report_path"
grep -Fq 'PASS pane_switch_first_usable_max_ms' "$terminal_performance_report_path"
grep -Fq 'PASS resize_convergence_max_ms' "$terminal_performance_report_path"
grep -Fq 'PASS continuous_output_input_max_ms' "$terminal_performance_report_path"
grep -Fq 'PASS idle_cpu_average_percent' "$terminal_performance_report_path"
grep -Fq 'PASS resident_memory_max_mb' "$terminal_performance_report_path"
grep -Fq 'overall: PASS' "$terminal_performance_report_path"

stop_app
terminal_performance_probe=0
terminal_performance_pane_id=''
pane_switch_performance_probe=0
terminal_automation=0
startup_performance_probe=1
startup_performance_scenario=warm
snapshot_trigger=live-two-pane
design_preview=new-process
mkdir -p "$startup_evidence_dir"
for sample in {1..20}; do
    performance_evidence_path="$startup_evidence_dir/warm-$sample.json"
    rm -f "$performance_evidence_path"
    launch_app
    for _ in {1..120}; do
        startup_evidence_ready "$performance_evidence_path" && break
        kill -0 "$app_pid" 2>/dev/null || { cat "$app_log" >&2; exit 1; }
        sleep 0.25
    done
    startup_evidence_ready "$performance_evidence_path" || {
        echo "Warm startup sample $sample did not produce complete evidence." >&2
        tail -n 100 "$state_log" >&2
        exit 1
    }
    stop_app
done
startup_performance_probe=0
terminal_automation=1
performance_evidence_path="$herdr_dir/runtime/bessie-performance-$$.json"

# Re-capture the primary connected product surfaces from the current build.
capture_design_surface herd herd
capture_design_surface attention attention
capture_design_surface workspaces workspaces
capture_design_surface workspace workspace
capture_design_surface agent-detail agent-detail

# Slice L locks both sides of the appearance switch. Capture the light Herd
# shell and terminal grid explicitly alongside the established dark artifacts.
capture_design_surface herd-light herd true light
capture_design_surface workspace-light workspace true light
capture_design_surface sidebar-windowed workspace true light
capture_design_surface sidebar-fullscreen workspace false light true
stop_app
printf '%s\n' '{"preferences":{"appearance":"dark","appIcon":"light"}}' > "$presentation_path"

# Capture the notification controls in the connected Settings surface as a second native artifact.
stop_app
settings_snapshot_path="$mac_dir/dist/Bessie-settings.png"
rm -f "$settings_snapshot_path"
snapshot_path=$settings_snapshot_path
snapshot_trigger=''
design_preview=settings
launch_app
for _ in {1..80}; do
    [[ -s "$settings_snapshot_path" ]] && break
    kill -0 "$app_pid" 2>/dev/null || { cat "$app_log" >&2; exit 1; }
    sleep 0.25
done
[[ -s "$settings_snapshot_path" ]]
file "$settings_snapshot_path" | grep -Fq 'PNG image data'
settings_width=$(sips -g pixelWidth "$settings_snapshot_path" | awk '/pixelWidth/ {print $2}')
settings_height=$(sips -g pixelHeight "$settings_snapshot_path" | awk '/pixelHeight/ {print $2}')
[[ "$settings_width" -ge 760 && "$settings_height" -ge 520 ]]
[[ $(stat -f %z "$settings_snapshot_path") -gt 20000 ]]
xcrun swift scripts/verify-design-snapshot.swift "$settings_snapshot_path"
grep -Fq "Window snapshot path=$settings_snapshot_path" "$state_log"

# Capture the finite picker in every named Catppuccin mapping. These are additive
# to the exact achromatic verifier above; named palettes do not redefine it.
capture_design_surface settings-catppuccin-latte settings false catppuccinLatte
capture_design_surface settings-catppuccin-frappe settings false catppuccinFrappe
capture_design_surface settings-catppuccin-macchiato settings false catppuccinMacchiato
capture_design_surface settings-catppuccin-mocha settings false catppuccinMocha

# Capture the connected native Projects catalog using an isolated recipe root.
stop_app
mkdir -p "$projects_root"
cat > "$projects_root/11111111-1111-1111-1111-111111111111.json" <<JSON
{
  "archivedAt": null,
  "createdAt": "2026-08-01T00:00:00Z",
  "group": "Verification",
  "id": "11111111-1111-1111-1111-111111111111",
  "name": "Mac verification Project",
  "projectDescription": "Isolated Projects Milestone 4 visual proof",
  "schemaVersion": 1,
  "tabs": [{
    "id": "22222222-2222-2222-2222-222222222222",
    "name": "Main",
    "panes": [{
      "command": "printf bessie-project-open-proof",
      "id": "33333333-3333-3333-3333-333333333333",
      "label": "Proof shell",
      "placement": { "type": "root" }
    }]
  }],
  "updatedAt": "2026-08-01T00:00:00Z",
  "workingDirectory": "$mac_dir"
}
JSON
projects_snapshot_path="$mac_dir/dist/Bessie-projects.png"
rm -f "$projects_snapshot_path"
snapshot_path=$projects_snapshot_path
design_preview=projects
launch_app
for _ in {1..80}; do
    [[ -s "$projects_snapshot_path" ]] && break
    kill -0 "$app_pid" 2>/dev/null || { cat "$app_log" >&2; exit 1; }
    sleep 0.25
done
[[ -s "$projects_snapshot_path" ]]
file "$projects_snapshot_path" | grep -Fq 'PNG image data'
projects_width=$(sips -g pixelWidth "$projects_snapshot_path" | awk '/pixelWidth/ {print $2}')
projects_height=$(sips -g pixelHeight "$projects_snapshot_path" | awk '/pixelHeight/ {print $2}')
[[ "$projects_width" -ge 760 && "$projects_height" -ge 520 ]]
[[ $(stat -f %z "$projects_snapshot_path") -gt 20000 ]]
xcrun swift scripts/verify-design-snapshot.swift "$projects_snapshot_path"
grep -Fq "Window snapshot path=$projects_snapshot_path" "$state_log"

# Capture the local workspace file browser. The focused verification workspace
# uses the repository root as its cwd, so this exercises a real WorkspaceFS root.
stop_app
files_snapshot_path="$mac_dir/dist/Bessie-files.png"
rm -f "$files_snapshot_path"
snapshot_path=$files_snapshot_path
design_preview=files
launch_app
for _ in {1..80}; do
    [[ -s "$files_snapshot_path" ]] && break
    kill -0 "$app_pid" 2>/dev/null || { cat "$app_log" >&2; exit 1; }
    sleep 0.25
done
[[ -s "$files_snapshot_path" ]]
file "$files_snapshot_path" | grep -Fq 'PNG image data'
files_width=$(sips -g pixelWidth "$files_snapshot_path" | awk '/pixelWidth/ {print $2}')
files_height=$(sips -g pixelHeight "$files_snapshot_path" | awk '/pixelHeight/ {print $2}')
[[ "$files_width" -ge 760 && "$files_height" -ge 520 ]]
[[ $(stat -f %z "$files_snapshot_path") -gt 20000 ]]
xcrun swift scripts/verify-design-snapshot.swift "$files_snapshot_path"
grep -Fq "Window snapshot path=$files_snapshot_path" "$state_log"

# Capture the reviewed draft produced from the authoritative current workspace.
stop_app
project_capture_snapshot_path="$mac_dir/dist/Bessie-project-capture.png"
rm -f "$project_capture_snapshot_path"
snapshot_path=$project_capture_snapshot_path
design_preview=project-capture
launch_app
for _ in {1..80}; do
    [[ -s "$project_capture_snapshot_path" ]] && break
    kill -0 "$app_pid" 2>/dev/null || { cat "$app_log" >&2; exit 1; }
    sleep 0.25
done
[[ -s "$project_capture_snapshot_path" ]]
file "$project_capture_snapshot_path" | grep -Fq 'PNG image data'
capture_width=$(sips -g pixelWidth "$project_capture_snapshot_path" | awk '/pixelWidth/ {print $2}')
capture_height=$(sips -g pixelHeight "$project_capture_snapshot_path" | awk '/pixelHeight/ {print $2}')
[[ "$capture_width" -ge 900 && "$capture_height" -ge 620 ]]
[[ $(stat -f %z "$project_capture_snapshot_path") -gt 20000 ]]
grep -Fq "Window snapshot path=$project_capture_snapshot_path" "$state_log"

# Capture the pre-mutation launch review sheet for command-bearing Projects.
stop_app
project_launch_review_snapshot_path="$mac_dir/dist/Bessie-project-launch-review.png"
rm -f "$project_launch_review_snapshot_path"
snapshot_path=$project_launch_review_snapshot_path
design_preview=project-launch-review
launch_app
for _ in {1..80}; do
    [[ -s "$project_launch_review_snapshot_path" ]] && break
    kill -0 "$app_pid" 2>/dev/null || { cat "$app_log" >&2; exit 1; }
    sleep 0.25
done
[[ -s "$project_launch_review_snapshot_path" ]]
file "$project_launch_review_snapshot_path" | grep -Fq 'PNG image data'
launch_review_width=$(sips -g pixelWidth "$project_launch_review_snapshot_path" | awk '/pixelWidth/ {print $2}')
launch_review_height=$(sips -g pixelHeight "$project_launch_review_snapshot_path" | awk '/pixelHeight/ {print $2}')
[[ "$launch_review_width" -ge 520 && "$launch_review_height" -ge 480 ]]
[[ $(stat -f %z "$project_launch_review_snapshot_path") -gt 15000 ]]
grep -Fq "Window snapshot path=$project_launch_review_snapshot_path" "$state_log"
design_preview=''

# U12 release evidence. Reuse this verifier's packaged app and isolated Herdr
# fixture; the matrix harness changes presentation inputs only and emits a
# complete dark/light manifest. Performance probes and budgets above remain
# independent and unchanged.
stop_app
PATH="$PATH" \
HERDR_CONFIG_PATH="$herdr_config" BESSIE_HERDR_SOCKET_PATH="$herdr_socket" \
XDG_CONFIG_HOME="$herdr_xdg_config" XDG_STATE_HOME="$herdr_xdg_state" \
BESSIE_STATE_LOG_PATH="$state_log" BESSIE_PRESENTATION_PATH="$presentation_path" \
BESSIE_PROJECTS_PATH="$projects_root" BESSIE_CAPTURE_APP="$mac_dir/dist/Bessie.app" \
BESSIE_CAPTURE_OUTPUT="$mac_dir/dist/redesign-matrix" \
    ./scripts/capture-redesign-matrix.sh
/usr/bin/python3 -c 'import json,sys; value=json.load(open(sys.argv[1])); raise SystemExit(0 if len(value.get("artboards", [])) == 30 else "redesign manifest is incomplete")' \
    "$mac_dir/dist/redesign-matrix/manifest.json"

# Close the existing disposable workspace through the bus at its established
# safe cleanup point, including the exact cascade and one-shot token (AE4).
closed_workspace_id=$cli_workspace_id
close_args="{\"connection_id\":\"local-bessie\",\"workspace_id\":\"$cli_workspace_id\"}"
close_projection=$(intent_cli call session.projection --json '{"connection_id":"local-bessie"}')
close_challenge=$(intent_cli call workspace.close --json "$close_args" || true)
confirm_token=$(/usr/bin/python3 -c '
import json, sys
projection = json.loads(sys.argv[1])["value"]
workspace_id = sys.argv[2]
result = json.load(sys.stdin)
workspace = next((item for item in projection["workspaces"] if item["workspace_id"] == workspace_id), None)
if workspace is None:
    raise SystemExit(f"workspace missing before close: {workspace_id}")
count = workspace["pane_count"]
noun = "pane" if count == 1 else "panes"
expected = f"This will stop processes in {count} {noun}. Closing Bessie alone leaves them running."
error = result.get("error", {})
if error.get("code") != "needs_confirmation" or error.get("message") != expected or not error.get("confirm_token"):
    raise SystemExit(f"bad confirmation challenge: expected={expected!r}, result={result}")
print(error["confirm_token"])
' "$close_projection" "$cli_workspace_id" <<<"$close_challenge")
close_success=$(intent_cli call workspace.close --json "$close_args" --confirm "$confirm_token")
assert_intent_ok <<<"$close_success"
cli_workspace_id=''
for _ in {1..40}; do
    grep -Eq '^Snapshot workspace_labels=$' "$state_log" && break
    sleep 0.25
done
grep -Eq '^Snapshot workspace_labels=$' "$state_log"
closed_snapshot=$(printf '%s\n' '{"id":"mac-agent-bus-closed","method":"session.snapshot","params":{}}' | nc -U "$herdr_socket")
/usr/bin/python3 -c '
import json, sys
snapshot = json.load(sys.stdin)
target = sys.argv[1]

def contains(value):
    if isinstance(value, dict):
        return value.get("workspace_id") == target or any(contains(child) for child in value.values())
    if isinstance(value, list):
        return any(contains(child) for child in value)
    return False

if contains(snapshot):
    raise SystemExit(f"closed workspace remains in Herdr snapshot: {target}")
' "$closed_workspace_id" <<<"$closed_snapshot"
reuse_result=$(intent_cli call workspace.close --json "$close_args" --confirm "$confirm_token" || true)
/usr/bin/python3 -c 'import json, sys; result=json.load(sys.stdin); raise SystemExit(0 if result.get("error", {}).get("code") == "confirm_token_invalid" else f"confirmation token reuse did not fail: {result}")' <<<"$reuse_result"
kill -0 "$herdr_pid"
for _ in {1..40}; do
    ! pgrep -f "^$controller_bin terminal session control" >/dev/null && break
    sleep 0.25
done
! pgrep -f "^$controller_bin terminal session control" >/dev/null
connected_before_restart=$(grep -c 'Connected' "$state_log" || true)

# Prove that a live app observes loss and reconverges after only the isolated server restarts.
kill "$herdr_pid"
wait "$herdr_pid" 2>/dev/null || true
herdr_pid=''
for _ in {1..40}; do
    grep -Fq 'Retrying' "$state_log" && break
    kill -0 "$app_pid" 2>/dev/null || { cat "$app_log" >&2; exit 1; }
    sleep 0.25
done
grep -Fq 'Retrying' "$state_log"

find "$herdr_dir/runtime" -maxdepth 1 -type s \( -name 'herdr.sock' -o -name 'herdr-client.sock' \) -delete 2>/dev/null || true
XDG_CONFIG_HOME="$herdr_xdg_config" XDG_STATE_HOME="$herdr_xdg_state" \
HERDR_CONFIG_PATH="$herdr_config" HERDR_SOCKET_PATH="$herdr_socket" \
    "$herdr_bin" server >>"$herdr_log" 2>&1 &
herdr_pid=$!
for _ in {1..40}; do
    [[ -S "$herdr_socket" ]] && break
    kill -0 "$herdr_pid" 2>/dev/null || { cat "$herdr_log" >&2; exit 1; }
    sleep 0.25
done
[[ -S "$herdr_socket" ]]
tail -n 8 "$herdr_log" | grep -Fq "logs: $herdr_xdg_config/herdr/herdr-server.log"

for _ in {1..60}; do
    connected_count=$(grep -c 'Connected' "$state_log" || true)
    [[ "$connected_count" -gt "$connected_before_restart" ]] && break
    kill -0 "$app_pid" 2>/dev/null || { cat "$app_log" >&2; exit 1; }
    sleep 0.25
done
[[ $(grep -c 'Connected' "$state_log" || true) -gt "$connected_before_restart" ]]

stop_app

kill -0 "$herdr_pid"
snapshot_json=$(printf '%s\n' '{"id":"mac-final-snapshot","method":"session.snapshot","params":{}}' | nc -U "$herdr_socket")
grep -Fq '"id":"mac-final-snapshot"' <<<"$snapshot_json"
grep -Fq '"type":"session_snapshot"' <<<"$snapshot_json"

# A normal Bessie launch must start an isolated named session as a detached server and reconnect without user intervention.
mkdir -p "$autostart_xdg_config" "$autostart_xdg_state"
! env PATH=/usr/bin:/bin /bin/sh -c 'command -v herdr' >/dev/null 2>&1
: > "$autostart_state_log"
: > "$autostart_app_log"
rm -f "$autostart_snapshot_path"
printf '%s\n' '{"preferences":{"startupBehavior":"lastWorkspace"}}' > "$autostart_presentation_path"
launch_autostart_app
for _ in {1..80}; do
    grep -Fq 'Connected' "$autostart_state_log" && break
    kill -0 "$app_pid" 2>/dev/null || { cat "$autostart_app_log" >&2; exit 1; }
    sleep 0.25
done
grep -Fq 'Starting Herdr' "$autostart_state_log"
grep -Fq 'Connected' "$autostart_state_log"
grep -Fq "Runtime stage=workspaceReady source=bundled path=$packaged_runtime finding=none api=true" "$autostart_state_log"
for _ in {1..40}; do
    [[ -s "$autostart_snapshot_path" ]] && break
    sleep 0.25
done
[[ -s "$autostart_snapshot_path" ]]
[[ $(stat -f %z "$autostart_snapshot_path") -gt 20000 ]]
stop_app

setup_automation=1
autostart_snapshot_trigger=disabled
launch_autostart_app
for _ in {1..80}; do
    grep -Eq 'Terminal pane=.* state=ready_' "$autostart_state_log" && \
        grep -Fq '"first_real_terminal_completion_version":1' "$autostart_presentation_path" && break
    kill -0 "$app_pid" 2>/dev/null || { cat "$autostart_app_log" >&2; exit 1; }
    sleep 0.25
done
grep -Eq 'Terminal pane=.* state=ready_' "$autostart_state_log"
grep -Fq '"first_real_terminal_completion_version":1' "$autostart_presentation_path"
autostart_status=$(XDG_CONFIG_HOME="$autostart_xdg_config" XDG_STATE_HOME="$autostart_xdg_state" \
    HERDR_SESSION=bessie "$herdr_bin" status server --json)
grep -Fq '"running":true' <<<"$autostart_status"
grep -Fq '"session":"bessie"' <<<"$autostart_status"
grep -Fq '"detached_server_daemon":true' <<<"$autostart_status"
default_status=$(XDG_CONFIG_HOME="$autostart_xdg_config" XDG_STATE_HOME="$autostart_xdg_state" \
    HERDR_SESSION=default "$herdr_bin" status server --json)
grep -Fq '"running":false' <<<"$default_status"
stop_app
autostart_after_quit=$(XDG_CONFIG_HOME="$autostart_xdg_config" XDG_STATE_HOME="$autostart_xdg_state" \
    HERDR_SESSION=bessie "$herdr_bin" status server --json)
grep -Fq '"running":true' <<<"$autostart_after_quit"

setup_automation=0
startup_performance_probe=1
startup_performance_scenario=cold
autostart_snapshot_trigger=live-two-pane
autostart_design_preview=new-process
for sample in {1..5}; do
    XDG_CONFIG_HOME="$autostart_xdg_config" XDG_STATE_HOME="$autostart_xdg_state" \
        HERDR_SESSION=bessie "$herdr_bin" server stop >/dev/null
    stopped_status=$(XDG_CONFIG_HOME="$autostart_xdg_config" XDG_STATE_HOME="$autostart_xdg_state" \
        HERDR_SESSION=bessie "$herdr_bin" status server --json)
    grep -Fq '"running":false' <<<"$stopped_status"
    performance_evidence_path="$startup_evidence_dir/cold-$sample.json"
    rm -f "$performance_evidence_path"
    launch_autostart_app
    for _ in {1..160}; do
        startup_evidence_ready "$performance_evidence_path" && break
        kill -0 "$app_pid" 2>/dev/null || { cat "$autostart_app_log" >&2; exit 1; }
        sleep 0.25
    done
    startup_evidence_ready "$performance_evidence_path" || {
        echo "Cold startup sample $sample did not produce complete evidence." >&2
        tail -n 100 "$autostart_state_log" >&2
        exit 1
    }
    stop_app
done
startup_performance_probe=0
autostart_snapshot_trigger=disabled
autostart_design_preview=herd

XDG_CONFIG_HOME="$autostart_xdg_config" XDG_STATE_HOME="$autostart_xdg_state" \
    HERDR_SESSION=bessie "$herdr_bin" server stop >/dev/null
autostart_stopped=$(XDG_CONFIG_HOME="$autostart_xdg_config" XDG_STATE_HOME="$autostart_xdg_state" \
    HERDR_SESSION=bessie "$herdr_bin" status server --json)
grep -Fq '"running":false' <<<"$autostart_stopped"
find "$autostart_root" -depth -delete

/usr/bin/python3 - "$startup_evidence_dir" "$startup_samples_path" <<'PY'
import json
import math
import sys
from pathlib import Path

root = Path(sys.argv[1])
output = Path(sys.argv[2])

def duration(payload, start, end):
    marks = payload["milestones"]
    start_values = [mark["elapsed_ms"] for mark in marks if mark["milestone"] == start]
    end_values = [mark["elapsed_ms"] for mark in marks if mark["milestone"] == end]
    if not start_values or not end_values:
        raise ValueError(f"missing {start}->{end}")
    start_value = min(start_values)
    candidates = [value for value in end_values if value >= start_value]
    if not candidates:
        raise ValueError(f"out-of-order {start}->{end}")
    return min(candidates) - start_value

def read_samples(prefix, expected_count):
    paths = sorted(root.glob(f"{prefix}-*.json"), key=lambda path: int(path.stem.split("-")[-1]))
    if len(paths) != expected_count:
        raise ValueError(f"expected {expected_count} {prefix} samples, found {len(paths)}")
    return [json.loads(path.read_text()) for path in paths]

warm = read_samples("warm", 20)
cold = read_samples("cold", 5)
all_samples = warm + cold
stalls = [
    float(span["duration_ms"])
    for payload in all_samples
    for span in payload["spans"]
    if span["start_milestone"] == "startup_main_thread_probe_scheduled"
    and span["end_milestone"] == "startup_main_thread_probe_completed"
    and "duration_ms" in span
]
if len(stalls) < 20 or any(not math.isfinite(value) or value < 0 for value in stalls):
    raise ValueError("startup main-thread evidence is incomplete")
result = {
    "evidence_kind": "packaged_local_measurement",
    "first_window_content_ms": [duration(payload, "process_start", "first_window_content") for payload in warm],
    "warm_shell_ready_ms": [duration(payload, "connection_start", "first_complete_frame") for payload in warm],
    "cold_shell_ready_ms": [duration(payload, "connection_start", "first_complete_frame") for payload in cold],
    "startup_main_thread_stall_ms": stalls,
}
output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
PY
/usr/bin/python3 scripts/run-hardening-benchmarks.py \
    --startup-samples "$startup_samples_path" > "$startup_report_path"
grep -Fq 'PASS first_window_content_p95_ms' "$startup_report_path"
grep -Fq 'PASS warm_shell_ready_p95_ms' "$startup_report_path"
grep -Fq 'PASS cold_shell_ready_p95_ms' "$startup_report_path"
grep -Fq 'PASS startup_main_thread_stall_max_ms' "$startup_report_path"
grep -Fq 'overall: PASS' "$startup_report_path"

if [[ "$skip_install" == 1 ]]; then
    echo "Packaged verification passed; installation skipped by BESSIE_SKIP_INSTALL=1. Startup and terminal performance budgets passed."
    exit 0
fi

# Install the verified package while retaining a restorable backup until all
# installed-app identity checks pass.
find "$install_stage" -depth -delete 2>/dev/null || true
find "$install_backup" -depth -delete 2>/dev/null || true
ditto "$mac_dir/dist/Bessie.app" "$install_stage"
codesign --verify --deep --strict "$install_stage"
# Stop every exact installed-path owner before moving the bundle. This also
# clears validated leftovers from this installer's historical backup paths and
# refuses unrelated BessieApp executables.
bessie_terminate_installation_owners "$installed_executable"
if [[ -e "$installed_app" ]]; then
    mv "$installed_app" "$install_backup"
fi
if ! mv "$install_stage" "$installed_app"; then
    [[ ! -e "$install_backup" ]] || mv "$install_backup" "$installed_app"
    exit 1
fi
install_candidate_active=true

if ! (
    codesign --verify --deep --strict "$installed_app"
    cmp "$mac_dir/dist/Bessie.app/Contents/MacOS/BessieApp" "$installed_app/Contents/MacOS/BessieApp"
    cmp "$mac_dir/dist/Bessie.app/Contents/Resources/Herdr/herdr" "$installed_app/Contents/Resources/Herdr/herdr"
    cmp "$mac_dir/dist/Bessie.app/Contents/Resources/Herdr/LICENSE" "$installed_app/Contents/Resources/Herdr/LICENSE"
    cmp "$mac_dir/dist/Bessie.app/Contents/Resources/Bessie-LICENSE.txt" "$installed_app/Contents/Resources/Bessie-LICENSE.txt"
    cmp "$mac_dir/dist/Bessie.app/Contents/Resources/libghostty-spm-LICENSE.txt" "$installed_app/Contents/Resources/libghostty-spm-LICENSE.txt"
    cmp "$mac_dir/dist/Bessie.app/Contents/Resources/Ghostty-LICENSE.txt" "$installed_app/Contents/Resources/Ghostty-LICENSE.txt"
    cmp "$mac_dir/dist/Bessie.app/Contents/Resources/Sparkle-LICENSE.txt" "$installed_app/Contents/Resources/Sparkle-LICENSE.txt"
    if [[ "$codesign_identity" == - ]]; then
        [[ $(shasum -a 256 "$installed_app/Contents/Resources/Herdr/herdr" | awk '{print $1}') == "$herdr_sha256" ]]
    else
        codesign -dv --verbose=4 "$installed_app/Contents/Resources/Herdr/herdr" 2>&1 | grep -Fq "$codesign_identity"
    fi
    [[ $(lipo -archs "$installed_app/Contents/Resources/Herdr/herdr") == "$herdr_architecture" ]]
    [[ $("$installed_app/Contents/Resources/Herdr/herdr" --version) == "$herdr_expected_version" ]]
); then
    find "$installed_app" -depth -delete
    [[ ! -e "$install_backup" ]] || mv "$install_backup" "$installed_app"
    exit 1
fi

# Relaunch the installed app only against the already-proven isolated server.
installed_state_log="$herdr_dir/runtime/bessie-installed-state-$$.log"
installed_app_log="$herdr_dir/runtime/bessie-installed-app-$$.log"
installed_token="verify-installed-$$"
: > "$installed_state_log"
: > "$installed_app_log"
rm -f "$installed_menu_snapshot"
/usr/bin/open -n "$installed_app" \
    --stdout "$installed_app_log" \
    --stderr "$installed_app_log" \
    --env "BESSIE_REPOSITORY_ROOT=$mac_dir" \
    --env "HERDR_CONFIG_PATH=$herdr_config" \
    --env "BESSIE_HERDR_SOCKET_PATH=$herdr_socket" \
    --env "XDG_CONFIG_HOME=$herdr_xdg_config" \
    --env "XDG_STATE_HOME=$herdr_xdg_state" \
    --env "PATH=$PATH" \
    --env "BESSIE_STATE_LOG_PATH=$installed_state_log" \
    --env "BESSIE_RUN_TOKEN=$installed_token" \
    --env "BESSIE_INTENT_SOCKET_PATH=$intent_socket" \
    --env "BESSIE_PRESENTATION_PATH=$presentation_path" \
    --env "BESSIE_DESIGN_ARTBOARD=15" \
    --env "BESSIE_MENU_BAR_SNAPSHOT_PATH=$installed_menu_snapshot" \
    --env "BESSIE_WINDOW_SNAPSHOT_DELAY=2" \
    --env "NSDisablePersistentUI=YES" \
    --env "BESSIE_TERMINAL_LIVE_AUTOMATION=0" \
    --env "BESSIE_PROCESS_LIVE_AUTOMATION=0"
for _ in {1..80}; do
    installed_line=$(grep -F "App run=$installed_token pid=" "$installed_state_log" | tail -n 1 || true)
    if [[ -n "$installed_line" ]]; then
        installed_pid=${installed_line##* pid=}
        break
    fi
    sleep 0.25
done
[[ "$installed_pid" =~ ^[0-9]+$ ]]
installed_owner=$(bessie_assert_single_installed_owner "$installed_executable")
[[ ${installed_owner%%$'\t'*} == "$installed_pid" ]]
for _ in {1..80}; do
    grep -Fq 'Connected' "$installed_state_log" \
        && grep -Fq "Menu bar status owner pid=$installed_pid visible=true" "$installed_state_log" \
        && [[ -s "$installed_menu_snapshot" ]] \
        && break
    kill -0 "$installed_pid"
    sleep 0.25
done
grep -Fq 'Connected' "$installed_state_log"
grep -Fq "Menu bar status owner pid=$installed_pid visible=true" "$installed_state_log"
grep -Fq "Menu-bar snapshot path=$installed_menu_snapshot width=900 height=470" "$installed_state_log"
[[ -s "$installed_menu_snapshot" ]]
file "$installed_menu_snapshot" | grep -Fq 'PNG image data'
[[ $(sips -g pixelWidth "$installed_menu_snapshot" | awk '/pixelWidth/ {print $2}') == 900 ]]
[[ $(sips -g pixelHeight "$installed_menu_snapshot" | awk '/pixelHeight/ {print $2}') == 470 ]]
kill -0 "$herdr_pid"
bessie_terminate_installation_owners "$installed_executable"
installed_pid=''
kill -0 "$herdr_pid"

system_default_after=$(HERDR_SESSION=default "$installed_app/Contents/Resources/Herdr/herdr" status server --json 2>&1 || true)
[[ "$system_default_after" == "$system_default_before" ]]
install_candidate_active=false
find "$install_backup" -depth -delete 2>/dev/null || true

# Finish in the ordinary user configuration, with no verification environment.
/usr/bin/open "$installed_app"
installed_owner=''
for _ in {1..80}; do
    installed_owner=$(bessie_assert_single_installed_owner "$installed_executable" 2>/dev/null || true)
    [[ -z "$installed_owner" ]] || break
    sleep 0.25
done
[[ -n "$installed_owner" ]]
installed_pid=${installed_owner%%$'\t'*}
leave_installed_app_running=true

echo "Mac tests, locked bundled Herdr identity and notices, automatic detached Bessie-session startup, focused native surfaces, validated workspace, Settings, and installed menu-bar PNGs, live libghostty panes, composite input, app-driven shell and $requested_agent_kind launches, semantic agent state, agent survival across app reopen, manifest discovery, controller recovery, external CLI convergence, isolated Herdr restart, release packaging, exact installed-app identity, pre-install owner termination, and one normal installed status owner passed. Installed Bessie remains running as pid $installed_pid."
REMOTE
