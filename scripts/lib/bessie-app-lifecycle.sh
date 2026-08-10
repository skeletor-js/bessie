#!/usr/bin/env bash

# Shared install-time lifecycle checks for the Bessie status-item owner. Every
# signal target is validated by exact executable path and process start time.

_bessie_canonical_executable() {
    local executable=$1
    local directory
    directory=$(dirname "$executable")
    local missing_suffix=''
    while [[ ! -d "$directory" ]]; do
        local parent
        parent=$(dirname "$directory")
        [[ "$parent" != "$directory" ]] || return 1
        missing_suffix="/$(basename "$directory")$missing_suffix"
        directory=$parent
    done
    directory=$(cd "$directory" && pwd -P) || return 1
    printf '%s%s/%s\n' "$directory" "$missing_suffix" "$(basename "$executable")"
}

_bessie_process_executable() {
    local pid=$1
    lsof -a -p "$pid" -d txt -Fn 2>/dev/null \
        | awk '/^n/ { sub(/^n/, ""); print; exit }'
}

_bessie_process_start_time() {
    local pid=$1
    ps -p "$pid" -o lstart= 2>/dev/null | sed 's/[[:space:]]*$//'
}

_bessie_named_processes() {
    local process_name=${BESSIE_APP_PROCESS_NAME:-BessieApp}
    local pid executable started
    for pid in $(pgrep -x "$process_name" 2>/dev/null || true); do
        executable=$(_bessie_process_executable "$pid")
        started=$(_bessie_process_start_time "$pid")
        [[ -n "$executable" ]] || executable='<unresolved>'
        [[ -n "$started" ]] || started='<unresolved>'
        printf '%s\t%s\t%s\n' "$pid" "$executable" "$started"
    done
}

bessie_processes_for_executable() {
    local expected
    expected=$(_bessie_canonical_executable "$1") || return 1
    local pid executable started
    while IFS=$'\t' read -r pid executable started; do
        [[ -n "$pid" ]] || continue
        [[ "$executable" == "$expected" ]] || continue
        printf '%s\t%s\t%s\n' "$pid" "$executable" "$started"
    done < <(_bessie_named_processes)
}

_bessie_is_managed_install_executable() {
    local executable=$1
    local installed_executable=$2
    if [[ "$executable" == "$installed_executable" ]]; then
        return 0
    fi
    [[ ${BESSIE_APP_PROCESS_NAME:-BessieApp} == BessieApp ]] || return 1
    case "$executable" in
        /Applications/.Bessie.app.install-[0-9]*/Contents/MacOS/BessieApp|\
        /private/tmp/Bessie.app.backup-[0-9]*/Contents/MacOS/BessieApp|\
        /tmp/Bessie.app.backup-[0-9]*/Contents/MacOS/BessieApp) return 0 ;;
        *) return 1 ;;
    esac
}

_bessie_process_matches() {
    local pid=$1
    local expected_executable=$2
    local expected_start=$3
    [[ $(_bessie_process_executable "$pid") == "$expected_executable" ]] \
        && [[ $(_bessie_process_start_time "$pid") == "$expected_start" ]]
}

_bessie_request_graceful_termination() {
    local pid=$1
    local result=''
    if [[ $(uname -s) == Darwin && -x /usr/bin/osascript ]]; then
        result=$(/usr/bin/osascript -l JavaScript -e '
function run(argv) {
    ObjC.import("AppKit")
    const app = $.NSRunningApplication.runningApplicationWithProcessIdentifier(Number(argv[0]))
    if (!app) return "missing"
    return app.terminate ? "requested" : "refused"
}
' "$pid" 2>/dev/null || true)
    fi
    [[ "$result" == requested || "$result" == missing ]] || kill -TERM "$pid"
}

bessie_terminate_installation_owners() {
    local installed_executable
    installed_executable=$(_bessie_canonical_executable "$1") || return 1
    local records
    records=$(_bessie_named_processes)
    [[ -n "$records" ]] || return 0

    local pid executable started
    while IFS=$'\t' read -r pid executable started; do
        [[ -n "$pid" ]] || continue
        if ! _bessie_is_managed_install_executable "$executable" "$installed_executable"; then
            echo "Refusing to stop unrelated ${BESSIE_APP_PROCESS_NAME:-BessieApp} process: pid=$pid executable=$executable" >&2
            return 1
        fi
    done <<< "$records"

    while IFS=$'\t' read -r pid executable started; do
        [[ -n "$pid" ]] || continue
        if ! _bessie_process_matches "$pid" "$executable" "$started"; then
            echo "Refusing to terminate changed process identity: pid=$pid" >&2
            return 1
        fi
        _bessie_request_graceful_termination "$pid"
    done <<< "$records"

    while IFS=$'\t' read -r pid executable started; do
        [[ -n "$pid" ]] || continue
        for _ in {1..40}; do
            ! kill -0 "$pid" 2>/dev/null && break
            sleep 0.25
        done
        if kill -0 "$pid" 2>/dev/null; then
            if ! _bessie_process_matches "$pid" "$executable" "$started"; then
                echo "Refusing to force-terminate changed process identity: pid=$pid" >&2
                return 1
            fi
            kill -KILL "$pid"
            for _ in {1..20}; do
                ! kill -0 "$pid" 2>/dev/null && break
                sleep 0.25
            done
        fi
        if kill -0 "$pid" 2>/dev/null; then
            echo "Bessie process survived bounded termination: pid=$pid executable=$executable" >&2
            return 1
        fi
        wait "$pid" 2>/dev/null || true
    done <<< "$records"

    records=$(_bessie_named_processes)
    while IFS=$'\t' read -r pid executable started; do
        [[ -n "$pid" ]] || continue
        if _bessie_is_managed_install_executable "$executable" "$installed_executable"; then
            echo "Bessie install owner remains after termination: pid=$pid executable=$executable" >&2
            return 1
        fi
        echo "Unexpected ${BESSIE_APP_PROCESS_NAME:-BessieApp} process appeared during termination: pid=$pid executable=$executable" >&2
        return 1
    done <<< "$records"
}

bessie_assert_single_installed_owner() {
    local installed_executable
    installed_executable=$(_bessie_canonical_executable "$1") || return 1
    local records
    records=$(_bessie_named_processes)
    local count
    count=$(printf '%s\n' "$records" | sed '/^$/d' | wc -l | tr -d ' ')
    if [[ "$count" -ne 1 ]]; then
        echo "Expected exactly one ${BESSIE_APP_PROCESS_NAME:-BessieApp} status owner, found $count." >&2
        [[ -z "$records" ]] || printf '%s\n' "$records" >&2
        return 1
    fi
    local pid executable started
    IFS=$'\t' read -r pid executable started <<< "$records"
    if [[ "$executable" != "$installed_executable" ]]; then
        echo "Sole ${BESSIE_APP_PROCESS_NAME:-BessieApp} owner has unexpected executable: pid=$pid executable=$executable" >&2
        return 1
    fi
    printf '%s\t%s\n' "$pid" "$executable"
}
