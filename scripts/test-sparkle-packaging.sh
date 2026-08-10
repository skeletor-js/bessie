#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

# shellcheck source=scripts/lib/sparkle-packaging.sh
source "$repo_root/scripts/lib/sparkle-packaging.sh"

fail() {
    echo "test-sparkle-packaging.sh: $*" >&2
    exit 1
}

assert_fails() {
    if "$@" >/dev/null 2>&1; then
        fail "command unexpectedly succeeded: $*"
    fi
}

grep -Fq 'url: "https://github.com/sparkle-project/Sparkle"' Package.swift
grep -Fq 'exact: "2.9.5"' Package.swift
[[ $(grep -Fc '.product(name: "Sparkle", package: "Sparkle")' Package.swift) == 1 ]]

python3 - <<'PY'
from pathlib import Path

manifest = Path("Package.swift").read_text()
app_start = manifest.index('.executableTarget(\n            name: "BessieApp"')
app_end = manifest.index("        .executableTarget(", app_start + 1)
app_target = manifest[app_start:app_end]
assert '.product(name: "Sparkle", package: "Sparkle")' in app_target
assert manifest.count('.product(name: "Sparkle", package: "Sparkle")') == 1

template = Path("scripts/Info.plist.in").read_text()
for placeholder in (
    "__BESSIE_MARKETING_VERSION__",
    "__BESSIE_BUILD_VERSION__",
    "__BESSIE_SPARKLE_FEED_URL__",
    "__BESSIE_SPARKLE_PUBLIC_ED_KEY__",
):
    assert template.count(placeholder) == 1, placeholder
assert "SUAllowsInsecureUpdates" not in template
PY

fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/bessie-sparkle-test.XXXXXX")
trap 'rm -rf "$fixture_root"' EXIT

artifact_root="$fixture_root/repo/.build/artifacts"
xcframework="$artifact_root/sparkle-project/Sparkle/Sparkle/Sparkle.xcframework"
framework="$xcframework/macos-arm64_x86_64/Sparkle.framework"
version="$framework/Versions/B"
mkdir -p \
    "$version/Updater.app/Contents/MacOS" \
    "$version/XPCServices/Installer.xpc/Contents/MacOS" \
    "$version/XPCServices/Downloader.xpc/Contents/MacOS" \
    "$version/Headers" "$version/Modules" "$version/PrivateHeaders" "$version/Resources"
touch \
    "$version/Sparkle" \
    "$version/Autoupdate" \
    "$version/Updater.app/Contents/MacOS/Updater" \
    "$version/XPCServices/Installer.xpc/Contents/MacOS/Installer" \
    "$version/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"
ln -s B "$framework/Versions/Current"
for entry in Sparkle Autoupdate Headers Modules PrivateHeaders Resources Updater.app XPCServices; do
    ln -s "Versions/Current/$entry" "$framework/$entry"
done
cat > "$xcframework/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>AvailableLibraries</key><array><dict>
<key>LibraryIdentifier</key><string>macos-arm64_x86_64</string>
<key>LibraryPath</key><string>Sparkle.framework</string>
<key>SupportedPlatform</key><string>macos</string>
<key>SupportedArchitectures</key><array><string>arm64</string><string>x86_64</string></array>
</dict></array></dict></plist>
PLIST
chmod +x \
    "$version/Sparkle" \
    "$version/Autoupdate" \
    "$version/Updater.app/Contents/MacOS/Updater" \
    "$version/XPCServices/Installer.xpc/Contents/MacOS/Installer" \
    "$version/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"
python3 - "$fixture_root/repo" "$xcframework" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
xcframework = pathlib.Path(sys.argv[2]).resolve()
(root / "Package.resolved").write_text(json.dumps({
    "pins": [{
        "identity": "sparkle",
        "location": "https://github.com/sparkle-project/Sparkle",
        "state": {"revision": "79bc9e872948e47877e76f194cb0c8e0412b0b90", "version": "2.9.5"},
    }]
}))
(root / ".build/workspace-state.json").write_text(json.dumps({
    "object": {"artifacts": [{
        "kind": {"xcframework": {}},
        "packageRef": {"identity": "sparkle", "location": "https://github.com/sparkle-project/Sparkle"},
        "path": str(xcframework),
        "source": {
            "checksum": "34b9b2071f3de0012eca3faa3a9290bb94e62131e9a74f6dc91514a000097a6c",
            "type": "remote",
            "url": "https://github.com/sparkle-project/Sparkle/releases/download/2.9.5/Sparkle-for-Swift-Package-Manager.zip",
        },
        "targetName": "Sparkle",
    }]}
}))
PY

[[ $(bessie_find_sparkle_xcframework "$fixture_root/repo") == "$xcframework" ]]
[[ $(bessie_find_macos_sparkle_framework "$xcframework") == "$framework" ]]
bessie_validate_sparkle_framework "$framework"

python3 - "$fixture_root/repo/.build/workspace-state.json" <<'PY'
import json
import sys
path = sys.argv[1]
data = json.load(open(path))
data["object"]["artifacts"].append(dict(data["object"]["artifacts"][0]))
open(path, "w").write(json.dumps(data))
PY
assert_fails bessie_find_sparkle_xcframework "$fixture_root/repo"
python3 - "$fixture_root/repo/.build/workspace-state.json" <<'PY'
import json
import sys
path = sys.argv[1]
data = json.load(open(path))
data["object"]["artifacts"] = data["object"]["artifacts"][:1]
open(path, "w").write(json.dumps(data))
PY
python3 - "$fixture_root/repo/.build/workspace-state.json" <<'PY'
import json
import sys
path = sys.argv[1]
data = json.load(open(path))
data["object"]["artifacts"][0]["source"]["checksum"] = "0" * 64
open(path, "w").write(json.dumps(data))
PY
assert_fails bessie_find_sparkle_xcframework "$fixture_root/repo"
python3 - "$fixture_root/repo/.build/workspace-state.json" <<'PY'
import json
import sys
path = sys.argv[1]
data = json.load(open(path))
data["object"]["artifacts"][0]["source"]["checksum"] = "34b9b2071f3de0012eca3faa3a9290bb94e62131e9a74f6dc91514a000097a6c"
open(path, "w").write(json.dumps(data))
PY

rm "$framework/Versions/Current"
assert_fails bessie_validate_sparkle_framework "$framework"
ln -s B "$framework/Versions/Current"
rm "$version/Autoupdate"
assert_fails bessie_validate_sparkle_framework "$framework"
touch "$version/Autoupdate"
mkdir -p "$framework/bin"
touch "$framework/bin/BinaryDelta"
assert_fails bessie_validate_sparkle_framework "$framework"
rm -rf "$framework/bin"

valid_key=AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=
valid_key_sha=$(python3 -c 'import base64, hashlib, sys; print(hashlib.sha256(base64.b64decode(sys.argv[1])).hexdigest())' "$valid_key")
bessie_validate_package_metadata verify 0.1.0 3 "" "" ""
bessie_validate_package_metadata production 1.2.3 123 https://bessie.dev/appcast.xml "$valid_key" "$valid_key_sha"
assert_fails bessie_validate_package_metadata production 1.2.3 123 http://bessie.dev/appcast.xml "$valid_key" "$valid_key_sha"
assert_fails bessie_validate_package_metadata production 1.2.3 123 https://example.com/appcast.xml "$valid_key" "$valid_key_sha"
assert_fails bessie_validate_package_metadata production 1.2.3 build-123 https://bessie.dev/appcast.xml "$valid_key" "$valid_key_sha"
assert_fails bessie_validate_package_metadata production 1.2.3 123 https://bessie.dev/appcast.xml placeholder "$valid_key_sha"
assert_fails bessie_validate_package_metadata production 1.2.3 123 https://bessie.dev/appcast.xml "$valid_key" "$(printf '0%.0s' {1..64})"

rendered_plist="$fixture_root/Info.plist"
bessie_render_info_plist \
    "$repo_root/scripts/Info.plist.in" "$rendered_plist" dev.bessie.app \
    production 1.2.3 123 https://bessie.dev/appcast.xml "$valid_key" "$valid_key_sha"
python3 - "$rendered_plist" "$valid_key" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as handle:
    info = plistlib.load(handle)
assert info["CFBundleIdentifier"] == "dev.bessie.app"
assert info["CFBundleShortVersionString"] == "1.2.3"
assert info["CFBundleVersion"] == "123"
assert info["SUFeedURL"] == "https://bessie.dev/appcast.xml"
assert info["SUPublicEDKey"] == sys.argv[2]
assert info["SURequireSignedFeed"] is True
assert info["SUVerifyUpdateBeforeExtraction"] is True
assert info["SUSignedFeedFailureExpirationInterval"] == 0
assert info["SUEnableAutomaticChecks"] is True
assert info["SUAllowsAutomaticUpdates"] is True
assert info["SUAutomaticallyUpdate"] is True
assert info["SUSendProfileInfo"] is False
assert "SUAllowsInsecureUpdates" not in info
PY
insecure_template="$fixture_root/Insecure-Info.plist.in"
python3 - "$repo_root/scripts/Info.plist.in" "$insecure_template" <<'PY'
import pathlib
import sys
source = pathlib.Path(sys.argv[1]).read_text()
pathlib.Path(sys.argv[2]).write_text(source.replace(
    "</dict>", "<key>SUAllowsInsecureUpdates</key><true/></dict>"
))
PY
assert_fails bessie_render_info_plist \
    "$insecure_template" "$fixture_root/Insecure-Info.plist" dev.bessie.app \
    production 1.2.3 123 https://bessie.dev/appcast.xml "$valid_key" "$valid_key_sha"

verify_plist="$fixture_root/Verify-Info.plist"
bessie_render_info_plist \
    "$repo_root/scripts/Info.plist.in" "$verify_plist" dev.bessie.app.verify \
    verify 0.1.0 3 "" "" ""
python3 - "$verify_plist" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as handle:
    info = plistlib.load(handle)
assert "SUFeedURL" not in info
assert "SUPublicEDKey" not in info
assert not any(key.startswith("SU") for key in info)
PY

valid_developer_details=$'Identifier=dev.bessie.app\nAuthority=Developer ID Application: Example (TEAM123456)\nTeamIdentifier=TEAM123456\nSignature size=9000\nflags=0x10000(runtime)\nTimestamp=Aug 9, 2026 at 1:00:00 AM'
bessie_validate_developer_id_details "$valid_developer_details" TEAM123456 fixture
macos_26_developer_details=$'Executable=/Applications/Bessie.app/Contents/MacOS/BessieApp\nIdentifier=dev.bessie.app\nCodeDirectory v=20500 size=12000 flags=0x10000(runtime) hashes=350+7 location=embedded\nAuthority=Developer ID Application: Example (TEAM123456)\nTeamIdentifier=TEAM123456\nTimestamp=Aug 9, 2026 at 1:00:00 AM'
bessie_validate_developer_id_details "$macos_26_developer_details" TEAM123456 fixture
assert_fails bessie_validate_developer_id_details "${valid_developer_details/Developer ID Application/Apple Development}" TEAM123456 fixture
assert_fails bessie_validate_developer_id_details "${valid_developer_details/TeamIdentifier=TEAM123456/TeamIdentifier=WRONGTEAM1}" TEAM123456 fixture
assert_fails bessie_validate_developer_id_details "${valid_developer_details/flags=0x10000(runtime)/flags=0x0(none)}" TEAM123456 fixture
assert_fails bessie_validate_developer_id_details "${valid_developer_details/Timestamp=/NoTimestamp=}" TEAM123456 fixture
assert_fails bessie_validate_developer_id_details "${macos_26_developer_details/flags=0x10000(runtime)/flags=0x0(none)}" TEAM123456 fixture
assert_fails bessie_validate_developer_id_details "${macos_26_developer_details/flags=0x10000(runtime)/flags=0x0(none)}"$'\nNote=flags=0x10000(runtime)' TEAM123456 fixture

echo "Sparkle packaging tests passed."
