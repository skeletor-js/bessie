#!/usr/bin/env bash
# Focused Catppuccin build, install, live-theme, and visual acceptance.
# This intentionally does not invoke the broad scripts/mac-verify.sh gate.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mac_dir=${BESSIE_MAC_DIR:-$repo_root}
themes=(bessie-dark bessie-light catppuccin-latte catppuccin-frappe catppuccin-macchiato catppuccin-mocha)
catppuccin_ids=(catppuccinLatte catppuccinFrappe catppuccinMacchiato catppuccinMocha)
catppuccin_names=(catppuccin-latte catppuccin-frappe catppuccin-macchiato catppuccin-mocha)
catppuccin_schemes=(light dark dark dark)

print_configuration() {
    : "${BESSIE_CODESIGN_IDENTITY:?Set BESSIE_CODESIGN_IDENTITY to inspect production configuration.}"
    local bundle_identifier
    bundle_identifier=$(BESSIE_PACKAGE_VARIANT=production "$repo_root/scripts/package-app.sh" --print-bundle-identifier)
    printf '%s\n' \
        'variant=production' \
        "bundle_identifier=$bundle_identifier" \
        'tests=BessieThemeTests,BessieVisualFoundationTests' \
        "themes=$(IFS=,; echo "${themes[*]}")" \
        'captures=6-live,4-settings,2-interaction,2-menu-bar' \
        'evidence=42-explicit-regions-fail-closed' \
        'preferences=isolated-presentation-and-xdg' \
        'install=/Applications/Bessie.app' \
        'success=reviewed-evidence-with-no-installed-owner'
}

mode=run
if [[ ${1:-} == --print-configuration ]]; then
    [[ $# == 1 ]] || { echo "Usage: $0 [mac-directory|--print-configuration|--verify-evidence [mac-directory]]" >&2; exit 1; }
    print_configuration
    exit 0
elif [[ ${1:-} == --verify-evidence ]]; then
    mode=verify-evidence
    shift
fi
if [[ $# -gt 1 || ( $# == 1 && ${1:-} == --* ) ]]; then
    echo "Usage: $0 [mac-directory|--print-configuration|--verify-evidence [mac-directory]]" >&2
    exit 1
fi
[[ $# == 0 ]] || mac_dir=$1

cd "$mac_dir"
source "$mac_dir/scripts/lib/bessie-app-lifecycle.sh"
installed_app=/Applications/Bessie.app
installed_executable="$installed_app/Contents/MacOS/BessieApp"
herdr_bin="$installed_app/Contents/Resources/Herdr/herdr"
capture_dir="$mac_dir/dist/catppuccin-theme-captures"
evidence_manifest="$capture_dir/region-evidence.json"
acceptance_receipt="$capture_dir/acceptance-receipt.json"
real_presentation="$HOME/Library/Application Support/Bessie/presentation.json"

file_digest() {
    local path=$1
    [[ -f "$path" ]] && shasum -a 256 "$path" | awk '{print $1}' || printf 'absent\n'
}

if [[ "$mode" == verify-evidence ]]; then
    test -x "$installed_executable"
    test -x "$herdr_bin"
    [[ -z $(bessie_processes_for_executable "$installed_executable") ]] || {
        echo 'Installed Bessie must be stopped before evidence verification.' >&2
        exit 1
    }
    packaged_sha=$(file_digest "$mac_dir/dist/Bessie.app/Contents/MacOS/BessieApp")
    installed_sha=$(file_digest "$installed_executable")
    packaged_herdr_sha=$(file_digest "$mac_dir/dist/Bessie.app/Contents/Resources/Herdr/herdr")
    installed_herdr_sha=$(file_digest "$herdr_bin")
    [[ "$packaged_sha" == "$installed_sha" && "$packaged_herdr_sha" == "$installed_herdr_sha" ]]
    /usr/bin/python3 - "$acceptance_receipt" "$packaged_sha" "$installed_sha" "$packaged_herdr_sha" <<'PY'
import json, sys
path, packaged, installed, herdr = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    receipt = json.load(handle)
assert receipt["packaged_sha256"] == packaged
assert receipt["installed_sha256"] == installed
assert receipt["installed_herdr_sha256"] == herdr
assert receipt["automated_apps_stopped"] is True
assert receipt["real_presentation_before"] == receipt["real_presentation_after"]
PY
    python3 scripts/verify-catppuccin-region-evidence.py "$capture_dir" "$evidence_manifest"
    printf 'CATPPUCCIN_ACCEPTANCE_OK packaged=%s installed=%s herdr=%s captures=%s regions=42 owner=none\n' \
        "$packaged_sha" "$installed_sha" "$installed_herdr_sha" "$capture_dir"
    exit 0
fi

: "${BESSIE_CODESIGN_IDENTITY:?Set BESSIE_CODESIGN_IDENTITY to a stable signing identity.}"
[[ "$BESSIE_CODESIGN_IDENTITY" != - ]] || { echo 'Refusing ad-hoc production acceptance.' >&2; exit 1; }

run_root="/tmp/bessie-catppuccin-acceptance-$$"
xdg_config="$run_root/xdg-config"
xdg_state="$run_root/xdg-state"
presentation="$run_root/presentation.json"
state_log="$run_root/state.log"
app_log="$run_root/app.log"
app_pid=''
app_start=''
workspace_id=''
real_presentation_before=$(file_digest "$real_presentation")

stop_acceptance_app() {
    [[ -n "$app_pid" ]] || return 0
    if ! kill -0 "$app_pid" 2>/dev/null; then
        app_pid=''
        app_start=''
        if [[ -n $(bessie_processes_for_executable "$installed_executable") ]]; then
            echo 'A replacement installed Bessie process remains after the managed app exited.' >&2
            return 1
        fi
        return 0
    fi
    [[ -n "$app_start" ]] || { echo "Managed app start identity is missing: pid=$app_pid" >&2; return 1; }
    if ! _bessie_process_matches "$app_pid" "$installed_executable" "$app_start"; then
        echo "Refusing to stop changed acceptance process identity: pid=$app_pid" >&2
        return 1
    fi
    _bessie_request_graceful_termination "$app_pid"
    for _ in {1..40}; do
        ! kill -0 "$app_pid" 2>/dev/null && break
        sleep 0.25
    done
    if kill -0 "$app_pid" 2>/dev/null; then
        if ! _bessie_process_matches "$app_pid" "$installed_executable" "$app_start"; then
            echo "Refusing to escalate changed acceptance process identity: pid=$app_pid" >&2
            return 1
        fi
        kill -KILL "$app_pid"
        for _ in {1..20}; do
            ! kill -0 "$app_pid" 2>/dev/null && break
            sleep 0.25
        done
    fi
    if kill -0 "$app_pid" 2>/dev/null; then
        echo "Managed installed acceptance process survived bounded termination: pid=$app_pid" >&2
        return 1
    fi
    wait "$app_pid" 2>/dev/null || true
    app_pid=''
    app_start=''
    if [[ -n $(bessie_processes_for_executable "$installed_executable") ]]; then
        echo 'An installed Bessie process remains after stopping the managed acceptance app.' >&2
        return 1
    fi
}

herdr() {
    XDG_CONFIG_HOME="$xdg_config" XDG_STATE_HOME="$xdg_state" HERDR_SESSION=bessie "$herdr_bin" "$@"
}

cleanup() {
    local status=$?
    if ! stop_acceptance_app; then
        [[ "$status" -ne 0 ]] || status=1
    fi
    if [[ -n "$workspace_id" ]]; then herdr workspace close "$workspace_id" >/dev/null 2>&1 || true; fi
    herdr server stop >/dev/null 2>&1 || true
    find "$run_root" -depth -delete 2>/dev/null || true
    exit "$status"
}
trap cleanup EXIT

record_managed_app() {
    local run_token=$1 run_line=''
    app_pid=''
    app_start=''
    for _ in {1..120}; do
        run_line=$(grep -F "App run=$run_token pid=" "$state_log" | tail -n 1 || true)
        [[ -z "$run_line" ]] || { app_pid=${run_line##* pid=}; break; }
        sleep 0.25
    done
    [[ "$app_pid" =~ ^[0-9]+$ ]] || { cat "$app_log" >&2; echo 'Installed app did not launch.' >&2; return 1; }
    [[ $(_bessie_process_executable "$app_pid") == "$installed_executable" ]] || return 1
    app_start=$(_bessie_process_start_time "$app_pid")
    [[ -n "$app_start" ]] && _bessie_process_matches "$app_pid" "$installed_executable" "$app_start"
}

mkdir -p "$xdg_config" "$xdg_state" "$capture_dir"
printf '%s\n' '=== repository and focused native tests ==='
./scripts/check.sh
xcrun swift test --filter 'BessieThemeTests|BessieVisualFoundationTests'

printf '%s\n' '=== stable production package and install (no pre-acceptance launch) ==='
./scripts/rebuild-install-shortcuts.sh --install-only "$mac_dir"
test -x "$installed_executable"
test -x "$herdr_bin"
codesign --verify --deep --strict "$installed_app"
[[ -z $(bessie_processes_for_executable "$installed_executable") ]]

packaged_sha=$(file_digest "$mac_dir/dist/Bessie.app/Contents/MacOS/BessieApp")
installed_sha=$(file_digest "$installed_executable")
packaged_herdr_sha=$(file_digest "$mac_dir/dist/Bessie.app/Contents/Resources/Herdr/herdr")
installed_herdr_sha=$(file_digest "$herdr_bin")
[[ "$packaged_sha" == "$installed_sha" && "$packaged_herdr_sha" == "$installed_herdr_sha" ]]

find "$capture_dir" -type f -name 'Bessie-theme-*.png' -delete
rm -f "$evidence_manifest" "$acceptance_receipt"
capture_started=$(date +%s)
printf '%s\n' '{"preferences":{"appearance":"dark","appIcon":"light","cowprintEnabled":true},"first_real_terminal_completion_version":1}' > "$presentation"
: > "$state_log"
: > "$app_log"
run_token="catppuccin-live-$$"
/usr/bin/open -n "$installed_app" \
    --stdout "$app_log" --stderr "$app_log" \
    --env "XDG_CONFIG_HOME=$xdg_config" --env "XDG_STATE_HOME=$xdg_state" \
    --env 'HERDR_SESSION=bessie' --env "BESSIE_REPOSITORY_ROOT=$mac_dir" \
    --env "BESSIE_PRESENTATION_PATH=$presentation" --env "BESSIE_STATE_LOG_PATH=$state_log" \
    --env "BESSIE_RUN_TOKEN=$run_token" --env 'BESSIE_DESIGN_PREVIEW=workspace' \
    --env "BESSIE_THEME_LIVE_CAPTURE_DIR=$capture_dir" --env 'BESSIE_TERMINAL_LIVE_AUTOMATION=0' \
    --env 'NSDisablePersistentUI=YES'
record_managed_app "$run_token"

for _ in {1..160}; do
    if herdr status server --json 2>/dev/null | grep -Fq '"running":true'; then break; fi
    kill -0 "$app_pid" 2>/dev/null || { cat "$app_log" >&2; exit 1; }
    sleep 0.25
done
server_status=$(herdr status server --json)
grep -Fq '"running":true' <<<"$server_status"
herdr_socket=$(HERDR_SERVER_STATUS="$server_status" /usr/bin/python3 - <<'PY'
import json, os
print(json.loads(os.environ["HERDR_SERVER_STATUS"])["socket_path"])
PY
)
[[ -S "$herdr_socket" ]]

created=$(herdr workspace create --cwd "$mac_dir" --label "bessie-catppuccin-$$" --focus)
workspace_id=$(sed -n 's/.*"workspace_id":"\([^"]*\)".*/\1/p' <<<"$created" | head -n 1)
pane_id=$(sed -n 's/.*"pane_id":"\([^"]*\)".*/\1/p' <<<"$created" | head -n 1)
[[ -n "$workspace_id" && -n "$pane_id" ]] || { echo "Could not create capture workspace: $created" >&2; exit 1; }
split=$(herdr pane split "$pane_id" --direction right --ratio 0.5 --focus)
split_pane_id=$(sed -n 's/.*"pane_id":"\([^"]*\)".*/\1/p' <<<"$split" | head -n 1)
[[ -n "$split_pane_id" && "$split_pane_id" != "$pane_id" ]]

ansi_marker='BESSIE_THEME_ANSI_16_牛é🐄'
herdr pane run "$pane_id" printf "'\\033[41m 01 \\033[44m 04 \\033[0m\\n${ansi_marker}\\n'" >/dev/null
for _ in {1..80}; do
    pane_output=$(herdr pane read "$pane_id" --source recent --lines 160 2>/dev/null || true)
    grep -Fq "$ansi_marker" <<<"$pane_output" && break
    sleep 0.25
done
grep -Fq "$ansi_marker" <<<"$pane_output"

# Public Herdr JSON socket API contract, as used by the repository's native Mac
# verifier: pane.send_input with text plus keys:["Enter"]. This is separate from
# the command-produced ANSI marker above and proves the actual input path.
input_marker="BESSIE_THEME_INPUT_雪豹_🦬_é_$$"
input_response=$(BESSIE_INPUT_PANE_ID="$pane_id" BESSIE_INPUT_MARKER="$input_marker" /usr/bin/python3 - <<'PY' | nc -U "$herdr_socket"
import json, os
command = "printf '%s\\n' '" + os.environ["BESSIE_INPUT_MARKER"] + "'"
print(json.dumps({"id": "catppuccin-unicode-input", "method": "pane.send_input", "params": {
    "pane_id": os.environ["BESSIE_INPUT_PANE_ID"], "text": command, "keys": ["Enter"]
}}))
PY
)
grep -Fq '"type":"ok"' <<<"$input_response"
for _ in {1..80}; do
    pane_output=$(herdr pane read "$pane_id" --source recent --lines 160 2>/dev/null || true)
    grep -Fq "$input_marker" <<<"$pane_output" && break
    sleep 0.25
done
grep -Fq "$input_marker" <<<"$pane_output"

for _ in {1..240}; do
    grep -Fq 'Theme live capture complete themes=6 controller_identity=stable' "$state_log" && break
    kill -0 "$app_pid" 2>/dev/null || { cat "$app_log" >&2; exit 1; }
    sleep 0.25
done
grep -Fq 'Theme live capture complete themes=6 controller_identity=stable' "$state_log"
! grep -Fq 'Theme live capture failed' "$state_log"
final_pane_output=$(herdr pane read "$pane_id" --source recent --lines 160)
grep -Fq "$ansi_marker" <<<"$final_pane_output"
grep -Fq "$input_marker" <<<"$final_pane_output"

for index in "${!themes[@]}"; do
    file="$capture_dir/Bessie-theme-${themes[$index]}-live.png"
    [[ -s "$file" && $(stat -f %m "$file") -ge "$capture_started" ]]
    file "$file" | grep -Fq 'PNG image data'
    scheme=dark
    [[ ${themes[$index]} == bessie-light || ${themes[$index]} == catppuccin-latte ]] && scheme=light
    xcrun swift scripts/verify-design-snapshot.swift "$file" "$scheme" --surface-only true
    grep -Fq "Window snapshot path=$file" "$state_log"
done
stop_acceptance_app

for index in "${!catppuccin_ids[@]}"; do
    id=${catppuccin_ids[$index]}; name=${catppuccin_names[$index]}; scheme=${catppuccin_schemes[$index]}
    output="$capture_dir/Bessie-theme-$name-settings.png"
    printf '{"preferences":{"appearance":"%s","appIcon":"light","cowprintEnabled":true},"first_real_terminal_completion_version":1}\n' "$id" > "$presentation"
    : > "$state_log"; : > "$app_log"
    run_token="catppuccin-settings-$name-$$"
    /usr/bin/open -n "$installed_app" --stdout "$app_log" --stderr "$app_log" \
        --env "XDG_CONFIG_HOME=$xdg_config" --env "XDG_STATE_HOME=$xdg_state" --env 'HERDR_SESSION=bessie' \
        --env "BESSIE_REPOSITORY_ROOT=$mac_dir" --env "BESSIE_PRESENTATION_PATH=$presentation" \
        --env "BESSIE_STATE_LOG_PATH=$state_log" --env "BESSIE_RUN_TOKEN=$run_token" \
        --env 'BESSIE_DESIGN_PREVIEW=settings' --env "BESSIE_WINDOW_SNAPSHOT_PATH=$output" \
        --env 'BESSIE_WINDOW_SNAPSHOT_DELAY=2' --env 'BESSIE_TERMINAL_LIVE_AUTOMATION=0' --env 'NSDisablePersistentUI=YES'
    record_managed_app "$run_token"
    for _ in {1..80}; do [[ -s "$output" ]] && break; kill -0 "$app_pid" 2>/dev/null || break; sleep 0.25; done
    [[ -s "$output" && $(stat -f %m "$output") -ge "$capture_started" ]]
    file "$output" | grep -Fq 'PNG image data'
    xcrun swift scripts/verify-design-snapshot.swift "$output" "$scheme" --surface-only true
    grep -Fq "Window snapshot path=$output" "$state_log"
    stop_acceptance_app
done

for flavor in latte mocha; do
    id=catppuccinLatte; scheme=light
    [[ "$flavor" != mocha ]] || { id=catppuccinMocha; scheme=dark; }
    output="$capture_dir/Bessie-theme-catppuccin-$flavor-interaction.png"
    menu_output="$capture_dir/Bessie-theme-catppuccin-$flavor-menu-bar.png"
    printf '{"preferences":{"appearance":"%s","appIcon":"light","cowprintEnabled":true},"first_real_terminal_completion_version":1}\n' "$id" > "$presentation"
    : > "$state_log"; : > "$app_log"
    run_token="catppuccin-interaction-$flavor-$$"
    /usr/bin/open -n "$installed_app" --stdout "$app_log" --stderr "$app_log" \
        --env "XDG_CONFIG_HOME=$xdg_config" --env "XDG_STATE_HOME=$xdg_state" --env 'HERDR_SESSION=bessie' \
        --env "BESSIE_REPOSITORY_ROOT=$mac_dir" --env "BESSIE_PRESENTATION_PATH=$presentation" \
        --env "BESSIE_STATE_LOG_PATH=$state_log" --env "BESSIE_RUN_TOKEN=$run_token" \
        --env 'BESSIE_DESIGN_PREVIEW=catppuccin-acceptance' --env 'BESSIE_DESIGN_ARTBOARD=15' \
        --env "BESSIE_WINDOW_SNAPSHOT_PATH=$output" --env "BESSIE_MENU_BAR_SNAPSHOT_PATH=$menu_output" \
        --env 'BESSIE_WINDOW_SNAPSHOT_DELAY=3' --env 'BESSIE_TERMINAL_LIVE_AUTOMATION=0' --env 'NSDisablePersistentUI=YES'
    record_managed_app "$run_token"
    for _ in {1..120}; do
        [[ -s "$output" && -s "$menu_output" ]] && break
        kill -0 "$app_pid" 2>/dev/null || break
        sleep 0.25
    done
    grep -Fq 'Catppuccin interaction preview ready focus=insertion-point' "$state_log"
    for artifact in "$output" "$menu_output"; do
        [[ -s "$artifact" && $(stat -f %m "$artifact") -ge "$capture_started" ]]
        file "$artifact" | grep -Fq 'PNG image data'
        xcrun swift scripts/verify-design-snapshot.swift "$artifact" "$scheme" --surface-only true
    done
    stop_acceptance_app
done

# Preference integrity is checked only after every automated app is confirmed
# stopped. No unchecked normal-user launch follows this point.
[[ -z "$app_pid" && -z $(bessie_processes_for_executable "$installed_executable") ]]
real_presentation_after=$(file_digest "$real_presentation")
[[ "$real_presentation_before" == "$real_presentation_after" ]] || {
    echo 'Real Bessie presentation preferences changed during isolated acceptance.' >&2
    exit 1
}

/usr/bin/python3 - "$acceptance_receipt" "$packaged_sha" "$installed_sha" "$installed_herdr_sha" "$real_presentation_before" "$real_presentation_after" <<'PY'
import json, sys
path, packaged, installed, herdr, before, after = sys.argv[1:]
with open(path, "w", encoding="utf-8") as handle:
    json.dump({
        "schema_version": 1,
        "packaged_sha256": packaged,
        "installed_sha256": installed,
        "installed_herdr_sha256": herdr,
        "automated_apps_stopped": True,
        "real_presentation_before": before,
        "real_presentation_after": after,
    }, handle, indent=2)
    handle.write("\n")
PY

python3 scripts/verify-catppuccin-region-evidence.py "$capture_dir" "$evidence_manifest" --write-template
echo "Region review is required. Mark every observed region pass=true, preserve screenshot digests, then run:" >&2
echo "  $0 --verify-evidence '$mac_dir'" >&2
# The verifier intentionally fails until all required regions have an explicit
# reviewed pass. Therefore no acceptance success marker can be emitted here.
python3 scripts/verify-catppuccin-region-evidence.py "$capture_dir" "$evidence_manifest"
