#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

# shellcheck source=scripts/lib/sparkle-packaging.sh
source "$repo_root/scripts/lib/sparkle-packaging.sh"

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

marketing_version=${BESSIE_MARKETING_VERSION:-}
build_version=${BESSIE_BUILD_VERSION:-}
sparkle_feed_url=${BESSIE_SPARKLE_FEED_URL:-}
sparkle_public_key=${BESSIE_SPARKLE_PUBLIC_ED_KEY:-}
approved_sparkle_public_key_sha256=${BESSIE_APPROVED_SPARKLE_PUBLIC_ED_KEY_SHA256:-}
if [[ "$package_variant" == verify ]]; then
    marketing_version=${marketing_version:-0.1.0}
    build_version=${build_version:-3}
fi
bessie_validate_package_metadata \
    "$package_variant" "$marketing_version" "$build_version" \
    "$sparkle_feed_url" "$sparkle_public_key" "$approved_sparkle_public_key_sha256"

xcrun swift build --disable-automatic-resolution -c release --product BessieApp

bin_path=$(xcrun swift build --disable-automatic-resolution -c release --show-bin-path)
app_path="$repo_root/dist/Bessie.app"
sparkle_xcframework=$(bessie_find_sparkle_xcframework "$repo_root")
sparkle_framework_source=$(bessie_find_macos_sparkle_framework "$sparkle_xcframework")
bessie_validate_resolved_sparkle_code "$sparkle_framework_source"
sparkle_framework_path="$app_path/Contents/Frameworks/Sparkle.framework"
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

mkdir -p \
    "$app_path/Contents/MacOS" \
    "$app_path/Contents/Frameworks" \
    "$app_path/Contents/Resources/Herdr"
cp "$bin_path/BessieApp" "$app_path/Contents/MacOS/BessieApp"
bessie_copy_sparkle_framework "$sparkle_framework_source" "$sparkle_framework_path"
bessie_render_info_plist \
    "$repo_root/scripts/Info.plist.in" "$app_path/Contents/Info.plist" \
    "$bundle_identifier" "$package_variant" "$marketing_version" "$build_version" \
    "$sparkle_feed_url" "$sparkle_public_key" "$approved_sparkle_public_key_sha256"
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
[[ $(plutil -extract CFBundleShortVersionString raw "$app_path/Contents/Info.plist") == "$marketing_version" ]]
[[ $(plutil -extract CFBundleVersion raw "$app_path/Contents/Info.plist") == "$build_version" ]]
bessie_validate_sparkle_framework "$sparkle_framework_path"
bessie_verify_sparkle_linkage "$app_path/Contents/MacOS/BessieApp"

if [[ "$codesign_identity" == - ]]; then
    # The Herdr release artifact already carries a valid ad hoc signature.
    # Preserving it keeps those bytes identical to the checksum-pinned artifact.
    codesign --verify --strict "$runtime_path"
    bessie_sign_sparkle_framework "$sparkle_framework_path" - ad-hoc
    codesign --force --sign - "$app_path"
    [[ $(shasum -a 256 "$runtime_path" | awk '{print $1}') == "$expected_runtime_sha" ]]
else
    bessie_sign_sparkle_framework "$sparkle_framework_path" "$codesign_identity" developer-id
    codesign --force --options runtime --timestamp --sign "$codesign_identity" "$runtime_path"
    codesign --force --options runtime --timestamp --sign "$codesign_identity" "$app_path"
fi

codesign --verify --strict "$runtime_path"
bessie_verify_sparkle_signatures "$sparkle_framework_path"
codesign --verify --deep --strict "$app_path"
if [[ "$package_variant" == production ]]; then
    signature_details=$(codesign -dv --verbose=4 "$app_path" 2>&1)
    if grep -F 'Signature=adhoc' <<<"$signature_details" >/dev/null; then
        echo "Production package unexpectedly has an ad-hoc signature." >&2
        exit 1
    fi
    bessie_verify_developer_id_signatures \
        "$sparkle_framework_path" "$runtime_path" "$app_path"
    if [[ -n ${BESSIE_EXPECTED_TEAM_ID:-} ]]; then
        [[ ${BESSIE_EXPECTED_TEAM_ID} =~ ^[A-Z0-9]{10}$ ]] || {
            echo "BESSIE_EXPECTED_TEAM_ID must be ten uppercase alphanumeric characters." >&2
            exit 1
        }
        grep -Fqx "TeamIdentifier=$BESSIE_EXPECTED_TEAM_ID" <<<"$signature_details" || {
            echo "Production package does not use BESSIE_EXPECTED_TEAM_ID." >&2
            exit 1
        }
    fi
fi

test -x "$runtime_path"
test -s "$license_path"
test -s "$provenance_path"
[[ $(( $(stat -f %Lp "$runtime_path") & 022 )) == 0 ]]

echo "Packaged $app_path ($package_variant, $bundle_identifier)"
