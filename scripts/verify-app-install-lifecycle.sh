#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/scripts/lib/bessie-app-lifecycle.sh"

test_root="/tmp/bessie-app-lifecycle-verify-$$"
test_app="$test_root/Applications/Bessie.app"
test_executable="$test_app/Contents/MacOS/BessieFixture"
test_backup="$test_root/Bessie.app.backup"
export BESSIE_APP_PROCESS_NAME=BessieFixture

cleanup() {
    if [[ -e "$test_executable" ]]; then
        bessie_terminate_installation_owners "$test_executable" >/dev/null 2>&1 || true
    fi
    find "$test_root" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT

# A first install has no bundle directory yet and therefore no possible owner.
bessie_terminate_installation_owners "$test_executable"

mkdir -p "$(dirname "$test_executable")"
cat > "$test_root/fixture.c" <<'C'
#include <signal.h>
#include <unistd.h>

int main(void) {
    for (;;) pause();
}
C
xcrun clang "$test_root/fixture.c" -o "$test_executable"
codesign --force --sign - "$test_executable" >/dev/null 2>&1

launch_fixture() {
    "$test_executable" &
    fixture_pid=$!
    for _ in {1..40}; do
        [[ $(bessie_processes_for_executable "$test_executable" | wc -l | tr -d ' ') -ge 1 ]] && return
        kill -0 "$fixture_pid"
        sleep 0.1
    done
    echo "Lifecycle fixture was not discoverable by exact executable path." >&2
    return 1
}

# Reproduce the unsafe causal chain first: moving a live bundle changes the
# resolved executable path but does not terminate its status-item owner.
launch_fixture
stale_pid=$fixture_pid
mv "$test_app" "$test_backup"
kill -0 "$stale_pid"
[[ $(_bessie_process_executable "$stale_pid") == "$test_backup/Contents/MacOS/BessieFixture" ]]
kill "$stale_pid"
wait "$stale_pid" 2>/dev/null || true
mv "$test_backup" "$test_app"

# A pre-install owner must be gone before the old bundle is moved. If it is not,
# the move/delete sequence leaves the process and its status item alive.
launch_fixture
preinstall_pid=$fixture_pid
bessie_terminate_installation_owners "$test_executable"
! kill -0 "$preinstall_pid" 2>/dev/null
wait "$preinstall_pid" 2>/dev/null || true
mv "$test_app" "$test_backup"
! kill -0 "$preinstall_pid" 2>/dev/null
mv "$test_backup" "$test_app"

# The post-launch assertion must reject duplicate exact owners and accept one.
launch_fixture
first_pid=$fixture_pid
launch_fixture
second_pid=$fixture_pid
if bessie_assert_single_installed_owner "$test_executable" >/dev/null 2>&1; then
    echo "Lifecycle assertion accepted duplicate installed owners." >&2
    exit 1
fi
bessie_terminate_installation_owners "$test_executable"
! kill -0 "$first_pid" 2>/dev/null
! kill -0 "$second_pid" 2>/dev/null
wait "$first_pid" 2>/dev/null || true
wait "$second_pid" 2>/dev/null || true

launch_fixture
single_pid=$fixture_pid
bessie_assert_single_installed_owner "$test_executable"
bessie_terminate_installation_owners "$test_executable"
! kill -0 "$single_pid" 2>/dev/null
wait "$single_pid" 2>/dev/null || true

# A process with the same name at another executable path must block the
# install helper, not be killed merely because its process name matches.
unrelated_executable="$test_root/unrelated/BessieFixture"
mkdir -p "$(dirname "$unrelated_executable")"
cp "$test_executable" "$unrelated_executable"
"$unrelated_executable" &
unrelated_pid=$!
for _ in {1..40}; do
    [[ $(_bessie_process_executable "$unrelated_pid") == "$unrelated_executable" ]] && break
    kill -0 "$unrelated_pid"
    sleep 0.1
done
if bessie_terminate_installation_owners "$test_executable" >/dev/null 2>&1; then
    echo "Lifecycle helper accepted an unrelated same-name executable." >&2
    exit 1
fi
kill -0 "$unrelated_pid"
bessie_terminate_installation_owners "$unrelated_executable"
! kill -0 "$unrelated_pid" 2>/dev/null
wait "$unrelated_pid" 2>/dev/null || true

echo "Bessie exact-executable install lifecycle checks passed."
