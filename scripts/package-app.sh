#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

if [[ $(uname -s) != Darwin ]]; then
    echo "package-app.sh requires macOS." >&2
    exit 1
fi

xcrun swift build -c release --product BessieApp

bin_path=$(xcrun swift build -c release --show-bin-path)
app_path="$repo_root/dist/Bessie.app"
runtime_staging_path="$repo_root/.local/herdr-runtime/herdr"
runtime_path="$app_path/Contents/Resources/Herdr/herdr"
provenance_path="$app_path/Contents/Resources/Herdr/runtime-lock.json"
codesign_identity=${BESSIE_CODESIGN_IDENTITY:--}
IFS=$'\t' read -r expected_runtime_sha notice_source notice_bundle_path < <(
    /usr/bin/python3 -c 'import json, sys; lock = json.load(open(sys.argv[1])); print(lock["sha256"], lock["notice"]["source_path"], lock["notice"]["bundle_path"], sep="\t")' "$repo_root/scripts/herdr-runtime-lock.json"
)
license_source="$repo_root/$notice_source"
license_path="$app_path/$notice_bundle_path"

case "$app_path" in
    "$repo_root"/dist/Bessie.app) ;;
    *) echo "Refusing unexpected app path: $app_path" >&2; exit 1 ;;
esac

if [[ -e "$app_path" ]]; then
    find "$app_path" -depth -delete
fi

mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources/Herdr"
cp "$bin_path/BessieApp" "$app_path/Contents/MacOS/BessieApp"
cp "$repo_root/scripts/Info.plist.in" "$app_path/Contents/Info.plist"
for icon in BessieDark BessieLight; do
    icon_path="$repo_root/Sources/BessieApp/Resources/AppIcons/$icon.icns"
    test -s "$icon_path"
    cp "$icon_path" "$app_path/Contents/Resources/$icon.icns"
done

resource_bundle=$(find "$bin_path" -maxdepth 1 -type d -name '*BessieApp*.bundle' -print -quit)
[[ -n "$resource_bundle" ]] || { echo "BessieApp resource bundle was not produced." >&2; exit 1; }
while IFS= read -r -d '' resource; do
    cp -R "$resource" "$app_path/Contents/Resources/"
done < <(find "$resource_bundle" -mindepth 1 -maxdepth 1 -print0)

"$repo_root/scripts/fetch-herdr-runtime.sh" "$runtime_staging_path"
[[ $(shasum -a 256 "$runtime_staging_path" | awk '{print $1}') == "$expected_runtime_sha" ]]
cp "$runtime_staging_path" "$runtime_path"
cp "$license_source" "$license_path"
cp "$repo_root/scripts/herdr-runtime-lock.json" "$provenance_path"

chmod 755 "$app_path/Contents/MacOS/BessieApp"
chmod 755 "$runtime_path"
chmod 644 "$license_path" "$provenance_path"
[[ $(( $(stat -f %Lp "$runtime_path") & 022 )) == 0 ]]
[[ $(shasum -a 256 "$runtime_path" | awk '{print $1}') == "$expected_runtime_sha" ]]
cmp "$license_source" "$license_path"
plutil -lint "$app_path/Contents/Info.plist"

if [[ "$codesign_identity" == - ]]; then
    # The release artifact already carries a valid ad hoc signature. Preserving it
    # keeps the packaged bytes identical to the checksum-pinned official artifact.
    codesign --verify --strict "$runtime_path"
    codesign --force --sign - "$app_path"
    [[ $(shasum -a 256 "$runtime_path" | awk '{print $1}') == "$expected_runtime_sha" ]]
else
    codesign --force --options runtime --timestamp --sign "$codesign_identity" "$runtime_path"
    codesign --force --options runtime --timestamp --sign "$codesign_identity" "$app_path"
fi

codesign --verify --strict "$runtime_path"
codesign --verify --deep --strict "$app_path"

test -x "$runtime_path"
test -s "$license_path"
test -s "$provenance_path"
[[ $(( $(stat -f %Lp "$runtime_path") & 022 )) == 0 ]]

echo "Packaged $app_path"
