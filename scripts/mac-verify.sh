#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mac_host=${BESSIE_MAC_HOST:-jordan-macbook}
mac_dir=${BESSIE_MAC_DIR:-/Users/jordanstella/GitHub/bessie}
agent_kind=${BESSIE_AGENT_KIND:-codex}
codesign_identity=${BESSIE_CODESIGN_IDENTITY:--}
mirror_marker='source=/home/hermes/code/bessie'
verification_lock=/tmp/bessie-mac-verify.lock

case "$agent_kind" in
    pi|claude|codex|gemini|amp|grok|hermes) ;;
    *) echo "Refusing unsupported live verification agent: $agent_kind" >&2; exit 1 ;;
esac

case "$mac_dir" in
    /Users/jordanstella/GitHub/bessie|/tmp/bessie-verify-*) ;;
    *) echo "Refusing unapproved Mac mirror path: $mac_dir" >&2; exit 1 ;;
esac

if ! ssh "$mac_host" mkdir "$verification_lock"; then
    echo "Another Bessie Mac verification is already running: $verification_lock" >&2
    exit 1
fi
trap 'ssh "$mac_host" rmdir "$verification_lock" 2>/dev/null || true' EXIT

ssh "$mac_host" bash -s -- "$mac_dir" "$mirror_marker" <<'REMOTE'
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
    --exclude='.git/' \
    --exclude='.build/' \
    --exclude='.swiftpm/' \
    --exclude='.local/' \
    --exclude='dist/' \
    "$repo_root/" "$mac_host:$mac_dir/"

ssh "$mac_host" bash -s -- "$mac_dir" "$agent_kind" "$codesign_identity" <<'REMOTE'
set -euo pipefail
trap 'status=$?; trap - ERR; echo "Mac verification failed at remote line $LINENO (exit $status)." >&2; exit $status' ERR
mac_dir=$1
requested_agent_kind=$2
codesign_identity=$3
export BESSIE_CODESIGN_IDENTITY="$codesign_identity"
mac_dir=$(cd "$mac_dir" && pwd -P)
cd "$mac_dir"

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
install_stage="/Applications/.Bessie.app.install-$$"
install_backup="/tmp/Bessie.app.backup-$$"
install_candidate_active=false
runtime_case_pid=''
runtime_case_root=''
runtime_case_herdr=''
missing_bundle_case=''
corrupt_bundle_case=''
launch_counter=0
cli_workspace_id=''
process_automation=0
process_agent_kind=''
terminal_automation=1
setup_automation=0
snapshot_trigger=live-two-pane
design_preview=''

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
        --env "BESSIE_PROJECTS_PATH=$projects_root"
        --env "BESSIE_TERMINAL_LIVE_AUTOMATION=$terminal_automation"
        --env "BESSIE_WINDOW_SNAPSHOT_PATH=$snapshot_path"
        --env "BESSIE_PROCESS_LIVE_AUTOMATION=$process_automation"
        --env "BESSIE_PROCESS_AGENT_KIND=$process_agent_kind"
        --env "BESSIE_PROCESS_CWD=$mac_dir"
    )
    [[ -z "$snapshot_trigger" ]] || open_args+=(--env "BESSIE_WINDOW_SNAPSHOT_TRIGGER=$snapshot_trigger")
    [[ -z "$design_preview" ]] || open_args+=(--env "BESSIE_DESIGN_PREVIEW=$design_preview")
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
        --env "BESSIE_SETUP_AUTOMATION=$setup_automation" \
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

intent_cli() {
    BESSIE_INTENT_SOCKET_PATH="$intent_socket" "$mac_dir/.build/debug/bessie" "$@"
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
    local pid=''
    runtime_case_root=$root
    mkdir -p "$root/xdg-config" "$root/xdg-state"
    printf '%s\n' '{"preferences":{}}' > "$presentation"
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
        --env "BESSIE_WINDOW_SNAPSHOT_PATH=$screenshot" \
        --env "BESSIE_WINDOW_SNAPSHOT_DELAY=1"
    for _ in {1..80}; do
        line=$(grep -F "App run=$token pid=" "$state" | tail -n 1 || true)
        [[ -z "$line" ]] || { pid=${line##* pid=}; break; }
        sleep 0.25
    done
    [[ "$pid" =~ ^[0-9]+$ ]]
    runtime_case_pid=$pid
    for _ in {1..80}; do
        grep -Fq "source=$expected_source path=$expected_path finding=$expected_finding" "$state" && break
        kill -0 "$pid"
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
    kill "$pid"
    for _ in {1..40}; do
        ! kill -0 "$pid" 2>/dev/null && break
        sleep 0.25
    done
    ! kill -0 "$pid" 2>/dev/null
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
    local pid=''
    runtime_case_root=$root
    runtime_case_herdr=$external_runtime
    mkdir -p "$root/xdg-config" "$root/xdg-state"
    printf '%s\n' '{"preferences":{"startupBehavior":"lastWorkspace"}}' > "$presentation"
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
        --env "BESSIE_TERMINAL_LIVE_AUTOMATION=0" \
        --env "BESSIE_PROCESS_LIVE_AUTOMATION=0"
    for _ in {1..80}; do
        line=$(grep -F "App run=$token pid=" "$state" | tail -n 1 || true)
        [[ -z "$line" ]] || { pid=${line##* pid=}; break; }
        sleep 0.25
    done
    [[ "$pid" =~ ^[0-9]+$ ]]
    runtime_case_pid=$pid
    for _ in {1..120}; do
        grep -Fq "Runtime stage=workspaceReady source=custom path=$external_runtime finding=none api=true" "$state" && break
        kill -0 "$pid"
        sleep 0.25
    done
    grep -Fq "Runtime stage=workspaceReady source=custom path=$external_runtime finding=none api=true" "$state"
    kill "$pid"
    for _ in {1..40}; do
        ! kill -0 "$pid" 2>/dev/null && break
        sleep 0.25
    done
    ! kill -0 "$pid" 2>/dev/null
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
    if [[ -n "$installed_pid" ]] && kill -0 "$installed_pid" 2>/dev/null; then
        installed_executable=$(ps -p "$installed_pid" -o command= 2>/dev/null || true)
        if [[ "$installed_executable" == /Applications/Bessie.app/Contents/MacOS/BessieApp ]]; then
            kill "$installed_pid"
            wait "$installed_pid" 2>/dev/null || true
        else
            echo "Refusing to stop unexpected installed-app process: $installed_executable" >&2
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

mkdir -p "$herdr_dir/runtime" "$herdr_xdg_config" "$herdr_xdg_state"
./scripts/package-app.sh

packaged_runtime="$mac_dir/dist/Bessie.app/Contents/Resources/Herdr/herdr"
packaged_license="$mac_dir/dist/Bessie.app/Contents/Resources/Herdr/LICENSE"
packaged_lock="$mac_dir/dist/Bessie.app/Contents/Resources/Herdr/runtime-lock.json"
test -x "$packaged_runtime"
test -s "$packaged_license"
test -s "$packaged_lock"
if [[ "$codesign_identity" == - ]]; then
    [[ $(shasum -a 256 "$packaged_runtime" | awk '{print $1}') == "$herdr_sha256" ]]
else
    codesign -dv --verbose=4 "$packaged_runtime" 2>&1 | grep -Fq "$codesign_identity"
fi
[[ $(lipo -archs "$packaged_runtime") == "$herdr_architecture" ]]
[[ $("$packaged_runtime" --version) == "$herdr_expected_version" ]]
[[ $(( $(stat -f %Lp "$packaged_runtime") & 022 )) == 0 ]]
cmp docs/research/herdr-apache-2.0-license.txt "$packaged_license"
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
if grep -Fq '/Users/jordanstella/.config/herdr' "$herdr_log"; then
    echo "Isolated Herdr reported a global config/log path." >&2
    exit 1
fi

status_json=$(XDG_CONFIG_HOME="$herdr_xdg_config" XDG_STATE_HOME="$herdr_xdg_state" \
    HERDR_CONFIG_PATH="$herdr_config" HERDR_SOCKET_PATH="$herdr_socket" \
    "$herdr_bin" status server --json)
grep -Fq '"running":true' <<<"$status_json"
/usr/bin/python3 -c 'import json, sys; status = json.load(sys.stdin); expected = int(sys.argv[1]); actual = status.get("protocol"); raise SystemExit(0 if actual == expected else f"Herdr protocol mismatch: {actual!r}")' "$herdr_protocol" <<<"$status_json"

# rsync preserves source mtimes, so clean SwiftPM state before trusting the mirrored build.
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
test -s dist/Bessie.app/Contents/Resources/BessieDark.icns
test -s dist/Bessie.app/Contents/Resources/BessieLight.icns
[[ $(plutil -extract CFBundleIconFile raw dist/Bessie.app/Contents/Info.plist) == BessieDark.icns ]]
[[ $(plutil -extract CFBundleShortVersionString raw dist/Bessie.app/Contents/Info.plist) == 0.1.0 ]]
[[ $(plutil -extract CFBundleVersion raw dist/Bessie.app/Contents/Info.plist) == 3 ]]
plutil -lint dist/Bessie.app/Contents/Info.plist
otool -L dist/Bessie.app/Contents/MacOS/BessieApp > "$herdr_dir/runtime/bessie-otool.txt"
nm -gU dist/Bessie.app/Contents/MacOS/BessieApp > "$herdr_dir/runtime/bessie-symbols.txt"
grep -Fq '/Metal.framework/' "$herdr_dir/runtime/bessie-otool.txt"
grep -Fq 'GhosttyTerminal03AppB4View' "$herdr_dir/runtime/bessie-symbols.txt"

: > "$state_log"
: > "$app_log"
printf '%s\n' '{"preferences":{"appearance":"dark","appIcon":"light"}}' > "$presentation_path"
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
controller_count=$(pgrep -P "$app_pid" -f "^$herdr_bin terminal session control" | wc -l | tr -d ' ')
[[ "$controller_count" == 2 ]]

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
expected = {"intents.list", "app.status", "connection.status", "session.projection", "pane.focus", "workspace.focus", "workspace.close", "project.list", "project.show"}
actual = {intent["id"] for intent in result.get("value", {}).get("intents", [])}
if result.get("ok") is not True or actual != expected:
    raise SystemExit(f"CLI intent catalog mismatch: {sorted(actual)}")
' <<<"$intent_names_json"

intent_cli status | assert_intent_ok
connection_status=$(intent_cli call connection.status --json '{"connection_id":"local-bessie"}')
/usr/bin/python3 -c 'import json, sys; value=json.load(sys.stdin).get("value", {}); raise SystemExit(0 if value == {"connected": True, "connection_id": "local-bessie"} else f"bad connection status: {value}")' <<<"$connection_status"
projection_json=$(intent_cli call session.projection --json '{"connection_id":"local-bessie"}')
/usr/bin/python3 -c 'import json, sys; value=json.load(sys.stdin).get("value", {}); raise SystemExit(0 if value.get("connection_id") == "local-bessie" and value.get("workspaces") else f"bad projection: {value}")' <<<"$projection_json"
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
    '{"jsonrpc":"2.0","id":"call","method":"tools/call","params":{"name":"app.status","arguments":{}}}' \
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
first_read=$(XDG_CONFIG_HOME="$herdr_xdg_config" XDG_STATE_HOME="$herdr_xdg_state" \
    HERDR_CONFIG_PATH="$herdr_config" HERDR_SOCKET_PATH="$herdr_socket" \
    "$herdr_bin" pane read "$cli_pane_id" --source recent --lines 200)
second_read=$(XDG_CONFIG_HOME="$herdr_xdg_config" XDG_STATE_HOME="$herdr_xdg_state" \
    HERDR_CONFIG_PATH="$herdr_config" HERDR_SOCKET_PATH="$herdr_socket" \
    "$herdr_bin" pane read "$split_pane_id" --source recent --lines 200)
grep -Fq "RAW_${first_token}_牛é🐄" <<<"$first_read"
grep -Fq "PASTE_$first_token" <<<"$first_read"
grep -Fq "RAW_${second_token}_牛é🐄" <<<"$second_read"
grep -Fq "PASTE_$second_token" <<<"$second_read"

# Killing only one controller must freeze and reconnect it without takeover or pane loss.
controller_pid=$(pgrep -P "$app_pid" -f "^$herdr_bin terminal session control $cli_pane_id" | head -n 1)
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
    ! pgrep -f "^$herdr_bin terminal session control ($cli_pane_id|$split_pane_id)" >/dev/null && break
    sleep 0.25
done
! pgrep -f "^$herdr_bin terminal session control ($cli_pane_id|$split_pane_id)" >/dev/null
surviving_read=$(XDG_CONFIG_HOME="$herdr_xdg_config" XDG_STATE_HOME="$herdr_xdg_state" \
    HERDR_CONFIG_PATH="$herdr_config" HERDR_SOCKET_PATH="$herdr_socket" \
    "$herdr_bin" pane read "$cli_pane_id" --source recent --lines 200)
grep -Fq "RAW_${first_token}_牛é🐄" <<<"$surviving_read"

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
shell_read=$(XDG_CONFIG_HOME="$herdr_xdg_config" XDG_STATE_HOME="$herdr_xdg_state" \
    HERDR_CONFIG_PATH="$herdr_config" HERDR_SOCKET_PATH="$herdr_socket" \
    "$herdr_bin" pane read "$shell_pane_id" --source recent --lines 200)
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
    ! pgrep -P "$app_pid" -f "^$herdr_bin terminal session control" >/dev/null && break
    sleep 0.25
done
! pgrep -P "$app_pid" -f "^$herdr_bin terminal session control" >/dev/null
connected_before_restart=$(grep -c '^Connected$' "$state_log")

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

find "$herdr_dir/runtime" -maxdepth 1 -type s \( -name 'herdr.sock' -o -name 'herdr-client.sock' \) -delete
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
    connected_count=$(grep -c '^Connected$' "$state_log" || true)
    [[ "$connected_count" -gt "$connected_before_restart" ]] && break
    kill -0 "$app_pid" 2>/dev/null || { cat "$app_log" >&2; exit 1; }
    sleep 0.25
done
[[ $(grep -c '^Connected$' "$state_log" || true) -gt "$connected_before_restart" ]]

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
XDG_CONFIG_HOME="$autostart_xdg_config" XDG_STATE_HOME="$autostart_xdg_state" \
    HERDR_SESSION=bessie "$herdr_bin" server stop >/dev/null
autostart_stopped=$(XDG_CONFIG_HOME="$autostart_xdg_config" XDG_STATE_HOME="$autostart_xdg_state" \
    HERDR_SESSION=bessie "$herdr_bin" status server --json)
grep -Fq '"running":false' <<<"$autostart_stopped"
find "$autostart_root" -depth -delete

# Install the verified package while retaining a restorable backup until all
# installed-app identity checks pass.
find "$install_stage" -depth -delete 2>/dev/null || true
find "$install_backup" -depth -delete 2>/dev/null || true
ditto "$mac_dir/dist/Bessie.app" "$install_stage"
codesign --verify --deep --strict "$install_stage"
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
open -n "$installed_app" \
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
[[ $(ps -p "$installed_pid" -o command=) == "$installed_app/Contents/MacOS/BessieApp" ]]
for _ in {1..80}; do
    grep -Fq 'Connected' "$installed_state_log" && break
    kill -0 "$installed_pid"
    sleep 0.25
done
grep -Fq 'Connected' "$installed_state_log"
kill "$installed_pid"
for _ in {1..40}; do
    ! kill -0 "$installed_pid" 2>/dev/null && break
    sleep 0.25
done
! kill -0 "$installed_pid" 2>/dev/null

system_default_after=$(HERDR_SESSION=default "$installed_app/Contents/Resources/Herdr/herdr" status server --json 2>&1 || true)
[[ "$system_default_after" == "$system_default_before" ]]
install_candidate_active=false
find "$install_backup" -depth -delete 2>/dev/null || true

echo "Mac tests, locked bundled Herdr identity and notices, automatic detached Bessie-session startup, focused native surfaces, validated workspace and Settings PNGs, live libghostty panes, composite input, app-driven shell and $requested_agent_kind launches, semantic agent state, agent survival across app reopen, manifest discovery, controller recovery, external CLI convergence, isolated Herdr restart, release packaging, installed-app identity, and isolated installed-app relaunch passed."
REMOTE
