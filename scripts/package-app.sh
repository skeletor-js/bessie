#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

package_variant=${BESSIE_PACKAGE_VARIANT:-}
codesign_identity=${BESSIE_CODESIGN_IDENTITY:--}
case "$package_variant" in
    production)
        bundle_identifier=dev.bessie.app
        if [[ "$codesign_identity" == - ]]; then
            echo "Production package dev.bessie.app requires a stable BESSIE_CODESIGN_IDENTITY; ad-hoc signing is refused." >&2
            exit 1
        fi
        ;;
    verify) bundle_identifier=dev.bessie.app.verify ;;
    *)
        echo "BESSIE_PACKAGE_VARIANT must be production or verify." >&2
        exit 1
        ;;
esac

if [[ ${1:-} == --print-bundle-identifier && $# == 1 ]]; then
    printf '%s\n' "$bundle_identifier"
    exit 0
fi
if [[ $# -ne 0 ]]; then
    echo "Usage: BESSIE_PACKAGE_VARIANT=production|verify $0 [--print-bundle-identifier]" >&2
    exit 1
fi

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
/usr/bin/python3 - "$repo_root/scripts/Info.plist.in" "$app_path/Contents/Info.plist" "$bundle_identifier" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])
bundle_identifier = sys.argv[3]
template = source.read_text()
placeholder = "__BESSIE_BUNDLE_IDENTIFIER__"
if template.count(placeholder) != 1:
    raise SystemExit("Info.plist.in must contain exactly one bundle identifier placeholder.")
destination.write_text(template.replace(placeholder, bundle_identifier))
PY
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
[[ $(plutil -extract CFBundleIdentifier raw "$app_path/Contents/Info.plist") == "$bundle_identifier" ]]

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
if [[ "$package_variant" == production ]]; then
    if codesign -dv --verbose=4 "$app_path" 2>&1 | grep -Fq 'Signature=adhoc'; then
        echo "Production package unexpectedly has an ad-hoc signature." >&2
        exit 1
    fi
    codesign -dv --verbose=4 "$app_path" 2>&1 | grep -Fq "$codesign_identity"
fi

test -x "$runtime_path"
test -s "$license_path"
test -s "$provenance_path"
[[ $(( $(stat -f %Lp "$runtime_path") & 022 )) == 0 ]]

echo "Packaged $app_path ($package_variant, $bundle_identifier)"
