#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/bessie-release-tests.XXXXXX")
trap 'rm -rf "$work"' EXIT

assert_fails() {
    local expected=$1
    shift
    local output
    if output=$("$@" 2>&1); then
        echo "Expected failure containing: $expected" >&2
        return 1
    fi
    grep -Fq "$expected" <<<"$output" || {
        printf 'Expected failure containing %q, got:\n%s\n' "$expected" "$output" >&2
        return 1
    }
}

metadata="$repo_root/scripts/release-metadata.py"
release="$repo_root/scripts/release-app.sh"

append_fixture_feed_signature() {
    python3 - "$1" <<'PY'
import base64, pathlib, sys
path = pathlib.Path(sys.argv[1])
data = path.read_bytes()
signature = base64.b64encode(bytes(64)).decode()
path.write_bytes(data + f"<!-- sparkle-signatures:\nedSignature: {signature}\nlength: {len(data)}\n-->\n".encode())
PY
}

assert_fails 'marketing version' python3 "$metadata" validate-version --version 1.2 --build 10 --tag v1.2.0
assert_fails 'tag must be v1.2.3' python3 "$metadata" validate-version --version 1.2.3 --build 10 --tag release-1.2.3
python3 "$metadata" validate-version --version 1.2.3 --build 10.2 --tag v1.2.3

cat >"$work/previous.xml" <<'XML'
<?xml version="1.0"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel>
<item><title>Bessie 1.1.9</title><pubDate>Wed, 05 Aug 2026 00:00:00 +0000</pubDate><sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion><sparkle:releaseNotesLink>https://github.com/skeletor-js/bessie/releases/tag/v1.1.9</sparkle:releaseNotesLink><enclosure url="https://github.com/skeletor-js/bessie/releases/download/v1.1.9/Bessie-1.1.9-6.zip" length="4" type="application/octet-stream" sparkle:version="6" sparkle:shortVersionString="1.1.9" sparkle:edSignature="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==" /></item>
<item><title>Bessie 1.2.0</title><pubDate>Thu, 06 Aug 2026 00:00:00 +0000</pubDate><sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion><sparkle:releaseNotesLink>https://github.com/skeletor-js/bessie/releases/tag/v1.2.0</sparkle:releaseNotesLink><enclosure url="https://github.com/skeletor-js/bessie/releases/download/v1.2.0/Bessie-1.2.0-7.zip" length="4" type="application/octet-stream" sparkle:version="7" sparkle:shortVersionString="1.2.0" sparkle:edSignature="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==" /></item>
<item><title>Bessie 1.2.1</title><pubDate>Fri, 07 Aug 2026 00:00:00 +0000</pubDate><sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion><sparkle:releaseNotesLink>https://github.com/skeletor-js/bessie/releases/tag/v1.2.1</sparkle:releaseNotesLink><enclosure url="https://github.com/skeletor-js/bessie/releases/download/v1.2.1/Bessie-1.2.1-8.zip" length="4" type="application/octet-stream" sparkle:version="8" sparkle:shortVersionString="1.2.1" sparkle:edSignature="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==" /></item>
<item>
<title>Bessie 1.2.2</title><pubDate>Sat, 08 Aug 2026 00:00:00 +0000</pubDate>
<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
<sparkle:releaseNotesLink>https://github.com/skeletor-js/bessie/releases/tag/v1.2.2</sparkle:releaseNotesLink>
<enclosure url="https://github.com/skeletor-js/bessie/releases/download/v1.2.2/Bessie-1.2.2-9.zip" length="4" type="application/octet-stream" sparkle:version="9" sparkle:shortVersionString="1.2.2" sparkle:edSignature="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==" />
</item></channel></rss>
XML
append_fixture_feed_signature "$work/previous.xml"
printf old! >"$work/Bessie-1.2.2-9.zip"
python3 "$metadata" check-previous --appcast "$work/previous.xml" --archive "$work/Bessie-1.2.2-9.zip" --build 10 --tag v1.2.3 --version 1.2.3
assert_fails 'strictly greater' python3 "$metadata" check-previous --appcast "$work/previous.xml" --archive "$work/Bessie-1.2.2-9.zip" --build 9 --tag v1.2.3 --version 1.2.3
assert_fails 'already appears' python3 "$metadata" check-previous --appcast "$work/previous.xml" --archive "$work/Bessie-1.2.2-9.zip" --build 10 --tag v1.2.2 --version 1.2.3
assert_fails 'previous archive length' python3 "$metadata" check-previous --appcast "$work/previous.xml" --archive "$work/missing/Bessie-1.2.2-9.zip" --build 10 --tag v1.2.3 --version 1.2.3
assert_fails 'must not be lower' python3 "$metadata" check-previous --appcast "$work/previous.xml" --archive "$work/Bessie-1.2.2-9.zip" --build 10 --tag v1.1.0 --version 1.1.0

assert_fails 'exact immutable GitHub release URL' python3 "$metadata" validate-url --url 'http://github.com/skeletor-js/bessie/releases/download/v1.2.3/Bessie.zip' --tag v1.2.3 --archive Bessie.zip
assert_fails 'must not contain credentials' python3 "$metadata" validate-url --url 'https://token@github.com/skeletor-js/bessie/releases/download/v1.2.3/Bessie.zip' --tag v1.2.3 --archive Bessie.zip
python3 "$metadata" validate-url --url 'https://github.com/skeletor-js/bessie/releases/download/v1.2.3/Bessie.zip' --tag v1.2.3 --archive Bessie.zip

mkdir -p "$work/prepared"
mkdir -p "$work/prepared/evidence"
printf archive >"$work/prepared/Bessie-1.2.3-10.zip"
archive_sha=$(shasum -a 256 "$work/prepared/Bessie-1.2.3-10.zip" | awk '{print $1}')
archive_length=$(wc -c <"$work/prepared/Bessie-1.2.3-10.zip" | tr -d ' ')
cat >"$work/prepared/appcast.xml" <<XML
<?xml version="1.0"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel><item>
<title>Bessie 1.2.3</title><pubDate>Sun, 09 Aug 2026 00:00:00 +0000</pubDate>
<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
<sparkle:releaseNotesLink>https://github.com/skeletor-js/bessie/releases/tag/v1.2.3</sparkle:releaseNotesLink>
<enclosure url="https://github.com/skeletor-js/bessie/releases/download/v1.2.3/Bessie-1.2.3-10.zip" length="$archive_length" type="application/octet-stream" sparkle:version="10" sparkle:shortVersionString="1.2.3" sparkle:edSignature="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==" />
</item></channel></rss>
XML
append_fixture_feed_signature "$work/prepared/appcast.xml"
cat >"$work/prepared/release.json" <<JSON
{
  "schema": 1,
  "state": "prepared",
  "source_commit": "0123456789abcdef0123456789abcdef01234567",
  "tag": "v1.2.3",
  "marketing_version": "1.2.3",
  "build_version": "10",
  "minimum_system_version": "14.0",
  "feed_url": "https://bessie.dev/appcast.xml",
  "archive_name": "Bessie-1.2.3-10.zip",
  "archive_url": "https://github.com/skeletor-js/bessie/releases/download/v1.2.3/Bessie-1.2.3-10.zip",
  "archive_length": $archive_length,
  "archive_sha256": "$archive_sha",
  "appcast_sha256": "$(shasum -a 256 "$work/prepared/appcast.xml" | awk '{print $1}')",
  "sparkle_version": "2.9.5",
  "sparkle_signature_verified_during_prepare": true,
  "sparkle_tools_archive_sha256": "34b9b2071f3de0012eca3faa3a9290bb94e62131e9a74f6dc91514a000097a6c",
  "notarization_submission_id": "fixture-submission",
  "notarization_archive_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "notarization_status": "Accepted",
  "final_archive_extraction_verified": true,
  "byte_finalization_order": ["staple", "archive", "extract-verify", "checksum", "appcast-generate-sign", "sparkle-verify"]
}
JSON
cat >"$work/prepared/evidence/notary-submission.json" <<'JSON'
{"id":"fixture-submission","status":"Accepted"}
JSON
cat >"$work/prepared/evidence/notary-log.json" <<'JSON'
{"jobId":"fixture-submission","status":"Accepted","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
JSON
printf '%s  %s\n' "$archive_sha" Bessie-1.2.3-10.zip >"$work/prepared/Bessie-1.2.3-10.zip.sha256"
python3 "$metadata" verify "$work/prepared"

cp -R "$work/prepared" "$work/bad-length"
python3 - "$work/bad-length/appcast.xml" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text().replace('length="7"', 'length="8"'))
PY
assert_fails 'appcast SHA-256' python3 "$metadata" verify "$work/bad-length"

cp -R "$work/prepared" "$work/bad-url"
python3 - "$work/bad-url" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
feed = root / "appcast.xml"
feed.write_text(feed.read_text().replace("https://github.com", "http://github.com"))
meta = json.loads((root / "release.json").read_text())
import hashlib
meta["appcast_sha256"] = hashlib.sha256(feed.read_bytes()).hexdigest()
(root / "release.json").write_text(json.dumps(meta))
PY
assert_fails 'exact immutable GitHub release URL' python3 "$metadata" verify "$work/bad-url"

cp -R "$work/prepared" "$work/delta"
python3 - "$work/delta" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1]); feed = root / "appcast.xml"
feed.write_text(feed.read_text().replace("</item>", "<sparkle:deltas><enclosure sparkle:deltaFrom=\"9\" /></sparkle:deltas></item>"))
meta = json.loads((root / "release.json").read_text()); meta["appcast_sha256"] = hashlib.sha256(feed.read_bytes()).hexdigest()
(root / "release.json").write_text(json.dumps(meta))
PY
assert_fails 'delta' python3 "$metadata" verify "$work/delta"

cp -R "$work/prepared" "$work/mutated"
printf mutation >>"$work/mutated/Bessie-1.2.3-10.zip"
assert_fails 'archive length' python3 "$metadata" verify "$work/mutated"

cat >"$work/insecure.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.bessie.app</string>
<key>CFBundleShortVersionString</key><string>1.2.3</string>
<key>CFBundleVersion</key><string>10</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>SUFeedURL</key><string>https://bessie.dev/appcast.xml</string>
<key>SUPublicEDKey</key><string>fixture-key</string>
<key>SURequireSignedFeed</key><true/>
<key>SUVerifyUpdateBeforeExtraction</key><true/>
<key>SUSignedFeedFailureExpirationInterval</key><integer>0</integer>
<key>SUSendProfileInfo</key><false/>
<key>SUAllowsInsecureUpdates</key><true/>
</dict></plist>
PLIST
assert_fails 'deprecated/insecure policy' python3 "$metadata" check-plist --path "$work/insecure.plist" --version 1.2.3 --build 10 --public-key fixture-key

# Exercise the complete prepare transaction in a clean, throwaway Git repository
# with fixture commands. No real identity, Keychain item, or Apple service is used.
fixture_repo="$work/fixture-repo"
fixture_tools="$work/fixture-tools"
fixture_bin="$work/bin"
mkdir -p "$fixture_repo/scripts/lib" "$fixture_tools/bin" "$fixture_bin"
cp "$release" "$metadata" "$fixture_repo/scripts/"
cp "$repo_root/scripts/herdr-runtime-lock.json" "$fixture_repo/scripts/"
: >"$fixture_repo/scripts/lib/sparkle-packaging.sh"
printf 'dist/\n' >"$fixture_repo/.gitignore"
cat >"$fixture_repo/release-notes.html" <<'EOF'
<!doctype html><html><body><h1>Bessie 1.2.3</h1><p>Fixture release notes.</p></body></html>
EOF
cat >"$fixture_repo/scripts/package-app.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
app=$(cd "$(dirname "$0")/.." && pwd)/dist/Bessie.app
mkdir -p "$app/Contents/MacOS"
printf executable >"$app/Contents/MacOS/BessieApp"
chmod +x "$app/Contents/MacOS/BessieApp"
python3 - "$app/Contents/Info.plist" <<'PY'
import os, plistlib, pathlib, sys
info = {
    "CFBundleIdentifier": "dev.bessie.app",
    "CFBundleShortVersionString": os.environ["BESSIE_MARKETING_VERSION"],
    "CFBundleVersion": os.environ["BESSIE_BUILD_VERSION"],
    "LSMinimumSystemVersion": "14.0",
    "SUFeedURL": os.environ["BESSIE_SPARKLE_FEED_URL"],
    "SUPublicEDKey": os.environ["BESSIE_SPARKLE_PUBLIC_ED_KEY"],
    "SURequireSignedFeed": True,
    "SUVerifyUpdateBeforeExtraction": True,
    "SUSignedFeedFailureExpirationInterval": 0,
    "SUSendProfileInfo": False,
}
pathlib.Path(sys.argv[1]).write_bytes(plistlib.dumps(info))
PY
SH
chmod +x "$fixture_repo/scripts/package-app.sh" "$fixture_repo/scripts/release-app.sh" "$fixture_repo/scripts/release-metadata.py"

cat >"$fixture_bin/security" <<'SH'
#!/usr/bin/env bash
[[ ${FAIL_IDENTITY:-0} != 1 ]] || exit 1
echo '  1) FIXTURE "Developer ID Application: Fixture (TEAM123456)"'
SH
cat >"$fixture_bin/codesign" <<'SH'
#!/usr/bin/env bash
if [[ " $* " == *" -dv "* ]]; then
    printf '%s\n' 'Authority=Developer ID Application: Fixture (TEAM123456)' 'TeamIdentifier=TEAM123456' >&2
fi
exit 0
SH
cat >"$fixture_bin/spctl" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat >"$fixture_bin/ditto" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ " $* " == *" -x "* ]]; then
    destination=${@: -1}
    mkdir -p "$destination"
    cp -R "${FIXTURE_REPO:?}/dist/Bessie.app" "$destination/Bessie.app"
    echo ditto-extract >>"${FIXTURE_COMMAND_LOG:?}"
    exit 0
fi
source_path=${@: -2:1}
destination=${@: -1}
count_file=${FIXTURE_DITTO_COUNT:?}
count=0; [[ ! -f "$count_file" ]] || count=$(<"$count_file")
count=$((count + 1)); echo "$count" >"$count_file"
printf 'ditto-%s\n' "$count" >>"${FIXTURE_COMMAND_LOG:?}"
find "$source_path" -type f -print0 | sort -z | xargs -0 cat >"$destination"
if [[ ${MUTATE_DURING_FINAL:-0} == 1 && $count -eq 2 ]]; then
    printf mutation >>"$source_path/Contents/MacOS/BessieApp"
fi
SH
cat >"$fixture_bin/xcrun" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ $1 == notarytool && $2 == history ]]; then
    [[ ${FAIL_NOTARY_PROFILE:-0} != 1 ]] || exit 1
    echo '{"history": []}'
elif [[ $1 == notarytool && $2 == submit ]]; then
    echo notary-submit >>"${FIXTURE_COMMAND_LOG:?}"
    shasum -a 256 "$3" | awk '{print $1}' >"${FIXTURE_NOTARY_SHA:?}"
    if [[ ${REJECT_NOTARY:-0} == 1 ]]; then
        echo '{"id":"fixture-submission","status":"Invalid","message":"fixture rejection"}'
        exit 1
    fi
    echo '{"id":"fixture-submission","status":"Accepted","message":"fixture acceptance"}'
elif [[ $1 == notarytool && $2 == log ]]; then
    [[ ${FAIL_NOTARY_LOG:-0} != 1 ]] || exit 1
    destination=${@: -1}
    if [[ ${BAD_NOTARY_BINDING:-0} == 1 ]]; then
        printf '{"jobId":"wrong-submission","status":"Accepted","sha256":"%064d","issues":[]}\n' 0 >"$destination"
    else
        printf '{"jobId":"fixture-submission","status":"Accepted","sha256":"%s","issues":[]}\n' "$(<"${FIXTURE_NOTARY_SHA:?}")" >"$destination"
    fi
elif [[ $1 == stapler ]]; then
    echo "stapler-$2" >>"${FIXTURE_COMMAND_LOG:?}"
    if [[ $2 == staple ]]; then
        mkdir -p "${@: -1}/Contents/_CodeSignature"
        printf ticket >"${@: -1}/Contents/_CodeSignature/notary-ticket"
    fi
else
    exit 2
fi
SH
chmod +x "$fixture_bin"/*

fixture_key=AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=
fixture_key_sha=$(python3 -c 'import base64,hashlib,sys; print(hashlib.sha256(base64.b64decode(sys.argv[1])).hexdigest())' "$fixture_key")
cat >"$fixture_tools/bin/generate_keys" <<SH
#!/usr/bin/env bash
[[ \${FAIL_SPARKLE_KEY:-0} != 1 ]] || exit 1
printf '%s\n' '$fixture_key'
SH
cat >"$fixture_tools/bin/generate_appcast" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "generate_appcast $*" >>"${FIXTURE_COMMAND_LOG:?}"
[[ " $* " == *" --maximum-deltas 0 "* && " $* " == *" --maximum-versions 0 "* ]] || exit 2
output=; prefix=; release_url=
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) output=$2; shift 2 ;;
        --download-url-prefix) prefix=$2; shift 2 ;;
        --full-release-notes-url) release_url=$2; shift 2 ;;
        --account|--maximum-deltas|--maximum-versions) shift 2 ;;
        *) directory=$1; shift ;;
    esac
done
archive=$(find "$directory" -maxdepth 1 -name '*.zip' -print -quit)
if find "$directory" -maxdepth 1 -name '*.html' -print -quit | grep -q .; then
    echo 'release notes HTML must not be staged where Sparkle synthesizes a temporary releaseNotesLink' >&2
    exit 2
fi
name=$(basename "$archive")
versions=${name#Bessie-}; versions=${versions%.zip}; build=${versions##*-}; version=${versions%-$build}
length=$(wc -c <"$archive" | tr -d ' ')
python3 - "$output" "$prefix$name" "$release_url" "$version" "$build" "$length" <<'PY'
import base64, pathlib, sys, xml.etree.ElementTree as ET
output, url, notes, version, build, length = sys.argv[1:]
signature = base64.b64encode(bytes(64)).decode()
path = pathlib.Path(output)
prior_items = ""
if path.exists():
    root = ET.fromstring(path.read_bytes())
    prior_items = "".join(ET.tostring(item, encoding="unicode") for item in root.findall("./channel/item"))
xml = f'''<?xml version="1.0"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel>{prior_items}<item>
<title>Bessie {version}</title><pubDate>Sun, 09 Aug 2026 00:00:00 +0000</pubDate>
<sparkle:version>{build}</sparkle:version>
<sparkle:shortVersionString>{version}</sparkle:shortVersionString>
<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
<sparkle:fullReleaseNotesLink>{notes}</sparkle:fullReleaseNotesLink>
<enclosure url="{url}" length="{length}" type="application/octet-stream" sparkle:edSignature="{signature}" />
</item></channel></rss>
'''.encode()
xml += f"<!-- sparkle-signatures:\nedSignature: {signature}\nlength: {len(xml)}\n-->\n".encode()
path.write_bytes(xml)
PY
SH
cat >"$fixture_tools/bin/sign_update" <<'SH'
#!/usr/bin/env bash
[[ $1 == --account && $3 == --verify && ( $# -eq 4 || $# -eq 5 ) ]] || exit 2
echo "sign_update $*" >>"${FIXTURE_COMMAND_LOG:?}"
[[ ${FAIL_SPARKLE_VERIFY:-0} != 1 ]]
SH
chmod +x "$fixture_tools/bin"/*

git -C "$fixture_repo" init -q
git -C "$fixture_repo" config user.email fixture@example.invalid
git -C "$fixture_repo" config user.name Fixture
git -C "$fixture_repo" add .
git -C "$fixture_repo" commit -qm fixture
fixture_commit=$(git -C "$fixture_repo" rev-parse HEAD)
git -C "$fixture_repo" tag v1.2.3

run_fixture_prepare() {
    local output_name=$1
    shift
    local -a history_args=(--initial-release)
    if [[ ${1:-} == previous ]]; then
        shift
        history_args=(--previous-appcast "$work/previous.xml" --previous-archive "$work/Bessie-1.2.2-9.zip")
    fi
    rm -f "$work/ditto-count" "$work/command.log"
    env PATH="$fixture_bin:$PATH" BESSIE_RELEASE_FIXTURE_MODE=1 \
        BESSIE_RELEASE_FIXTURE_ROOT="$fixture_tools" FIXTURE_DITTO_COUNT="$work/ditto-count" \
        FIXTURE_COMMAND_LOG="$work/command.log" FIXTURE_NOTARY_SHA="$work/notary-sha" \
        FIXTURE_REPO="$fixture_repo" "$@" \
        "$fixture_repo/scripts/release-app.sh" prepare \
        --version 1.2.3 --build 10 --tag v1.2.3 \
        --approved-source-commit "$fixture_commit" \
        --identity 'Developer ID Application: Fixture (TEAM123456)' --team-id TEAM123456 \
        --notary-profile fixture-notary --sparkle-account fixture-sparkle \
        --approved-key-sha256 "$fixture_key_sha" \
        --feed-url https://bessie.dev/appcast.xml \
        --archive-url https://github.com/skeletor-js/bessie/releases/download/v1.2.3/Bessie-1.2.3-10.zip \
        --release-notes "$fixture_repo/release-notes.html" "${history_args[@]}" \
        --output "$work/$output_name"
}

assert_fails 'locked or unavailable' run_fixture_prepare missing-identity env FAIL_IDENTITY=1
assert_fails 'notary Keychain profile' run_fixture_prepare bad-notary-profile env FAIL_NOTARY_PROFILE=1
assert_fails 'Sparkle Keychain key' run_fixture_prepare missing-sparkle-key env FAIL_SPARKLE_KEY=1
assert_fails 'notarization was not accepted' run_fixture_prepare rejected-notary env REJECT_NOTARY=1
test -s "$work/rejected-notary/evidence/notary-submission.json"
assert_fails 'log could not be retrieved' run_fixture_prepare missing-notary-log env FAIL_NOTARY_LOG=1
assert_fails 'does not bind' run_fixture_prepare bad-notary-binding env BAD_NOTARY_BINDING=1
assert_fails 'mutated after stapling' run_fixture_prepare mutated-final env MUTATE_DURING_FINAL=1
assert_fails 'previous appcast failed Sparkle signature verification' run_fixture_prepare bad-previous-signature previous env FAIL_SPARKLE_VERIFY=1
run_fixture_prepare prepared-previous previous
grep -Fq 'https://github.com/skeletor-js/bessie/releases/download/v1.2.2/Bessie-1.2.2-9.zip' "$work/prepared-previous/appcast.xml"
grep -Fq 'https://github.com/skeletor-js/bessie/releases/download/v1.1.9/Bessie-1.1.9-6.zip' "$work/prepared-previous/appcast.xml"
grep -Fq 'sign_update --account fixture-sparkle --verify' "$work/command.log"
run_fixture_prepare prepared-fixture
python3 "$metadata" verify "$work/prepared-fixture"
grep -Fq 'stapler-staple' "$work/command.log"
grep -Fq 'ditto-2' "$work/command.log"
grep -Fq 'generate_appcast' "$work/command.log"
grep -Fq 'sign_update --account fixture-sparkle --verify' "$work/command.log"
python3 - "$work/command.log" <<'PY'
import pathlib, sys
lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
def index(prefix): return next(i for i, line in enumerate(lines) if line.startswith(prefix))
assert index("stapler-staple") < index("ditto-2") < index("generate_appcast") < index("sign_update")
PY

assert_fails 'publish is an operator boundary' "$release" publish

echo 'Release tooling tests passed.'
