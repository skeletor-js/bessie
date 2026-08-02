#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
lock_path="$repo_root/scripts/herdr-runtime-lock.json"
destination=${1:-"$repo_root/.local/herdr-runtime/herdr"}
cache_dir=${BESSIE_HERDR_RUNTIME_CACHE:-"$repo_root/.local/cache/herdr-runtime"}

if [[ $(uname -s) != Darwin ]]; then
    echo "fetch-herdr-runtime.sh requires macOS to verify the pinned executable." >&2
    exit 1
fi

IFS=$'\t' read -r version architecture url expected_sha256 expected_version_output < <(
    /usr/bin/python3 -c 'import json, sys; lock = json.load(open(sys.argv[1])); print(*(lock[key] for key in ("version", "architecture", "url", "sha256", "expected_version_output")), sep="\t")' "$lock_path"
)
cache_path="$cache_dir/herdr-$version-macos-$architecture"

sha256() {
    shasum -a 256 "$1" | awk '{print $1}'
}

verify_checksum() {
    [[ $(sha256 "$1") == "$expected_sha256" ]]
}

verify_runtime() {
    local runtime=$1
    [[ $(lipo -archs "$runtime") == "$architecture" ]] || {
        echo "Herdr runtime architecture does not match $architecture: $(lipo -archs "$runtime")" >&2
        return 1
    }
    [[ $("$runtime" --version) == "$expected_version_output" ]] || {
        echo "Herdr runtime version does not match $expected_version_output." >&2
        return 1
    }
}

mkdir -p "$cache_dir" "$(dirname "$destination")"

cache_valid=false
if [[ -f "$cache_path" ]] && verify_checksum "$cache_path"; then
    cache_valid=true
fi

if [[ "$cache_valid" != true ]]; then
    [[ ! -f "$cache_path" ]] || echo "Replacing cached Herdr runtime with a mismatched checksum." >&2
    download=$(mktemp "$cache_dir/.herdr-download.XXXXXX")
    trap 'find "$download" -delete 2>/dev/null || true' EXIT
    curl --fail --location --retry 3 "$url" --output "$download"
    verify_checksum "$download" || {
        echo "Downloaded Herdr runtime checksum does not match the lock." >&2
        exit 1
    }
    chmod 755 "$download"
    verify_runtime "$download"
    mv -f "$download" "$cache_path"
    trap - EXIT
fi

verify_checksum "$cache_path" || {
    echo "Cached Herdr runtime checksum changed during verification." >&2
    exit 1
}
chmod 755 "$cache_path"
verify_runtime "$cache_path"

staged=$(mktemp "$(dirname "$destination")/.herdr-stage.XXXXXX")
trap 'find "$staged" -delete 2>/dev/null || true' EXIT
cp "$cache_path" "$staged"
verify_checksum "$staged" || {
    echo "Staged Herdr runtime checksum does not match the lock." >&2
    exit 1
}
chmod 755 "$staged"
verify_runtime "$staged"
mv -f "$staged" "$destination"
trap - EXIT

echo "Staged Herdr $version at $destination"
