#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mac_host=${BESSIE_MAC_HOST:-jordan-macbook}
mac_dir=${BESSIE_MAC_DIR:-/Users/jordanstella/GitHub/bessie}
mirror_marker='source=/home/hermes/code/bessie'

if [[ "$mac_dir" != /Users/jordanstella/GitHub/bessie ]]; then
    echo "Refusing unapproved Mac mirror path: $mac_dir" >&2
    exit 1
fi

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

ssh "$mac_host" bash -s -- "$mac_dir" <<'REMOTE'
set -euo pipefail
mac_dir=$1
cd "$mac_dir"

herdr_version=0.7.5
herdr_sha256=37350546b0012555943b92eaf962665de4e264395baeb44227b8015e8ff5b0d6
herdr_url=https://github.com/herdrdev/herdr/releases/download/v0.7.5/herdr-macos-aarch64
herdr_dir="$mac_dir/.local/herdr"
herdr_bin="$herdr_dir/herdr"
herdr_socket="$herdr_dir/runtime/herdr.sock"
herdr_config="$herdr_dir/config.toml"
herdr_xdg_config="$herdr_dir/xdg-config/verify-$$"
herdr_xdg_state="$herdr_dir/xdg-state/verify-$$"
herdr_log="$herdr_dir/runtime/server.log"
state_log="$herdr_dir/runtime/bessie-state.log"
app_log="$herdr_dir/runtime/bessie-app.log"
snapshot_path="$mac_dir/dist/Bessie-window.png"
herdr_pid=''
app_pid=''
process_automation=0
process_agent_kind=''
snapshot_trigger=live-two-pane

launch_app() {
    local app_bundle="$mac_dir/dist/Bessie.app"
    local app_executable="$app_bundle/Contents/MacOS/BessieApp"
    open -n "$app_bundle" --stdout "$app_log" --stderr "$app_log" \
        --env "BESSIE_REPOSITORY_ROOT=$mac_dir" \
        --env "BESSIE_HERDR_PATH=$herdr_bin" \
        --env "HERDR_CONFIG_PATH=$herdr_config" \
        --env "HERDR_SOCKET_PATH=$herdr_socket" \
        --env "XDG_CONFIG_HOME=$herdr_xdg_config" \
        --env "XDG_STATE_HOME=$herdr_xdg_state" \
        --env "BESSIE_STATE_LOG_PATH=$state_log" \
        --env "BESSIE_PRESENTATION_PATH=$herdr_dir/runtime/bessie-presentation-$$.json" \
        --env "BESSIE_TERMINAL_LIVE_AUTOMATION=1" \
        --env "BESSIE_WINDOW_SNAPSHOT_PATH=$snapshot_path" \
        --env "BESSIE_WINDOW_SNAPSHOT_TRIGGER=$snapshot_trigger" \
        --env "BESSIE_PROCESS_LIVE_AUTOMATION=$process_automation" \
        --env "BESSIE_PROCESS_AGENT_KIND=$process_agent_kind" \
        --env "BESSIE_PROCESS_CWD=$mac_dir"
    for _ in {1..40}; do
        app_pid=$(pgrep -f "^$app_executable$" | tail -n 1 || true)
        [[ -n "$app_pid" ]] && return
        sleep 0.25
    done
    echo "Bessie did not launch through LaunchServices." >&2
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

cleanup() {
    stop_app || true
    if [[ -n "$herdr_pid" ]] && kill -0 "$herdr_pid" 2>/dev/null; then
        executable=$(ps -p "$herdr_pid" -o command=)
        case "$executable" in
            "$herdr_bin"\ server*) kill "$herdr_pid"; wait "$herdr_pid" 2>/dev/null || true ;;
            *) echo "Refusing to stop unexpected Herdr process: $executable" >&2 ;;
        esac
    fi
}
trap cleanup EXIT

./scripts/check.sh

mkdir -p "$herdr_dir/runtime" "$herdr_xdg_config" "$herdr_xdg_state"
if [[ ! -x "$herdr_bin" ]] || [[ $(shasum -a 256 "$herdr_bin" | awk '{print $1}') != "$herdr_sha256" ]]; then
    download="$herdr_dir/herdr.download"
    curl -fL "$herdr_url" -o "$download"
    [[ $(shasum -a 256 "$download" | awk '{print $1}') == "$herdr_sha256" ]] || {
        echo "Downloaded Herdr checksum did not match v$herdr_version." >&2
        exit 1
    }
    chmod 755 "$download"
    mv -f "$download" "$herdr_bin"
fi

[[ $(shasum -a 256 "$herdr_bin" | awk '{print $1}') == "$herdr_sha256" ]]
[[ $("$herdr_bin" --version) == "herdr $herdr_version" ]]

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
grep -Fq '"protocol":17' <<<"$status_json"

XDG_CONFIG_HOME="$herdr_xdg_config" XDG_STATE_HOME="$herdr_xdg_state" \
    BESSIE_LIVE_HERDR_SOCKET="$herdr_socket" BESSIE_LIVE_RUN_ID="verify-$$" xcrun swift test
./scripts/package-app.sh

test -x dist/Bessie.app/Contents/MacOS/BessieApp
plutil -lint dist/Bessie.app/Contents/Info.plist
otool -L dist/Bessie.app/Contents/MacOS/BessieApp > "$herdr_dir/runtime/bessie-otool.txt"
nm -gU dist/Bessie.app/Contents/MacOS/BessieApp > "$herdr_dir/runtime/bessie-symbols.txt"
grep -Fq '/Metal.framework/' "$herdr_dir/runtime/bessie-otool.txt"
grep -Fq 'GhosttyTerminal03AppB4View' "$herdr_dir/runtime/bessie-symbols.txt"

: > "$state_log"
: > "$app_log"
rm -f "$snapshot_path"
launch_app

for _ in {1..40}; do
    grep -Fq 'Connected' "$state_log" && break
    kill -0 "$app_pid" 2>/dev/null || { cat "$app_log" >&2; exit 1; }
    sleep 0.25
done

grep -Fq 'Connecting' "$state_log"
grep -Fq 'Connected' "$state_log"

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

# The manifest is authoritative for supported kinds. Run an agent only when its canonical binary is present.
manifest_json=$(printf '%s\n' '{"id":"mac-agent-manifests","method":"server.agent_manifests","params":{}}' | nc -U "$herdr_socket")
grep -Fq '"type":"agent_manifest_status"' <<<"$manifest_json"
installed_agent=''
for kind in pi claude codex gemini cursor devin agy cline opencode copilot kimi kiro droid amp grok hermes kilo qodercli maki; do
    if grep -Fq "\"agent\":\"$kind\"" <<<"$manifest_json" && command -v "$kind" >/dev/null 2>&1; then
        installed_agent=$kind
        break
    fi
done
if [[ -n "$installed_agent" ]]; then
    stop_app
    process_agent_kind=$installed_agent
    launch_app
    for _ in {1..160}; do
        grep -Fq "kind=$installed_agent agent_started=true shell_preserved=false" "$state_log" && break
        sleep 0.25
    done
    grep -Fq "kind=$installed_agent agent_started=true shell_preserved=false" "$state_log"
else
    printf '%s\n' 'Agent live prerequisite unavailable: no Herdr-supported agent executable is installed on the Mac PATH.' >> "$state_log"
fi

XDG_CONFIG_HOME="$herdr_xdg_config" XDG_STATE_HOME="$herdr_xdg_state" \
HERDR_CONFIG_PATH="$herdr_config" HERDR_SOCKET_PATH="$herdr_socket" \
    "$herdr_bin" workspace close "$cli_workspace_id" >/dev/null
for _ in {1..40}; do
    grep -Eq '^Snapshot workspace_labels=$' "$state_log" && break
    sleep 0.25
done
grep -Eq '^Snapshot workspace_labels=$' "$state_log"
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

echo "Mac tests, focused native surfaces, a validated live-window PNG, live libghostty panes, composite input, app-driven shell launch, manifest discovery, controller recovery, app reopen survival, external CLI convergence, isolated Herdr restart, release packaging, and connected app launch passed."
REMOTE
