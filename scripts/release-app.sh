#!/usr/bin/env bash
set -euo pipefail
umask 077

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
metadata="$repo_root/scripts/release-metadata.py"
release_scratch=
raw_submission=
raw_log=

cleanup() {
    rm -f "${raw_submission:-}" "${raw_log:-}"
    [[ -z ${release_scratch:-} ]] || rm -rf "$release_scratch"
}
trap cleanup EXIT

shasum_cmd=shasum

usage() {
    cat <<'EOF'
Usage:
  release-app.sh prepare --version X.Y.Z --build N[.N] --tag vX.Y.Z \
    --approved-source-commit SHA --identity "Developer ID Application: ..." \
    --team-id TEAMID --notary-profile PROFILE --sparkle-account ACCOUNT \
    --approved-key-sha256 SHA256 --feed-url https://bessie.dev/appcast.xml \
    --archive-url HTTPS_URL --release-notes FILE.html --output DIRECTORY \
    (--previous-appcast FILE --previous-archive FILE | --initial-release)
  release-app.sh verify PREPARED_DIRECTORY
  release-app.sh publish PREPARED_DIRECTORY

prepare uses macOS Keychain credentials and creates local, non-published artifacts.
verify is secret-free. publish verifies but intentionally performs no publication.
EOF
}

die() {
    echo "Release preparation: $*" >&2
    exit 1
}

sha256_file() {
    "$shasum_cmd" -a 256 "$1" | awk '{print $1}'
}

app_seal() {
    python3 - "$1" <<'PY'
import hashlib, os, pathlib, stat, subprocess, sys
root = pathlib.Path(sys.argv[1]).resolve()
digest = hashlib.sha256()
for path in sorted([root, *root.rglob("*")], key=lambda value: str(value.relative_to(root))):
    relative = str(path.relative_to(root)).encode()
    details = path.lstat()
    digest.update(relative + b"\0" + str(stat.S_IMODE(details.st_mode)).encode() + b"\0")
    if path.is_symlink():
        digest.update(b"L\0" + os.readlink(path).encode() + b"\0")
    elif path.is_file():
        digest.update(b"F\0" + str(details.st_size).encode() + b"\0")
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    else:
        digest.update(b"D\0")
if pathlib.Path("/usr/bin/xattr").is_file():
    result = subprocess.run(
        ["/usr/bin/xattr", "-lr", str(root)],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    digest.update(b"XATTRS\0" + result.stdout)
print(digest.hexdigest())
PY
}

command=${1:-}
case "$command" in
    verify)
        [[ $# -eq 2 ]] || { usage >&2; exit 2; }
        exec python3 "$metadata" verify "$2"
        ;;
    publish)
        [[ $# -eq 2 ]] || die "publish is an operator boundary and requires a prepared directory"
        python3 "$metadata" verify "$2"
        die "publish is an operator boundary; U5 never uploads, releases, deploys, or changes a feed"
        ;;
    prepare) shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac

version=
build=
tag=
source_commit=
identity=
team_id=
notary_profile=
sparkle_account=
approved_key_sha256=
feed_url=
archive_url=
release_notes=
output=
previous_appcast=
previous_archive=
initial_release=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) version=${2:-}; shift 2 ;;
        --build) build=${2:-}; shift 2 ;;
        --tag) tag=${2:-}; shift 2 ;;
        --approved-source-commit) source_commit=${2:-}; shift 2 ;;
        --identity) identity=${2:-}; shift 2 ;;
        --team-id) team_id=${2:-}; shift 2 ;;
        --notary-profile) notary_profile=${2:-}; shift 2 ;;
        --sparkle-account) sparkle_account=${2:-}; shift 2 ;;
        --approved-key-sha256) approved_key_sha256=${2:-}; shift 2 ;;
        --feed-url) feed_url=${2:-}; shift 2 ;;
        --archive-url) archive_url=${2:-}; shift 2 ;;
        --release-notes) release_notes=${2:-}; shift 2 ;;
        --output) output=${2:-}; shift 2 ;;
        --previous-appcast) previous_appcast=${2:-}; shift 2 ;;
        --previous-archive) previous_archive=${2:-}; shift 2 ;;
        --initial-release) initial_release=1; shift ;;
        *) die "unknown argument: $1" ;;
    esac
done

for required_name in version build tag source_commit identity team_id notary_profile \
    sparkle_account approved_key_sha256 feed_url archive_url release_notes output; do
    [[ -n ${!required_name} ]] || die "missing required --${required_name//_/-}"
done
[[ "$feed_url" == https://bessie.dev/appcast.xml ]] || die "feed URL must be exactly https://bessie.dev/appcast.xml"
[[ "$team_id" =~ ^[A-Z0-9]{10}$ ]] || die "team ID must be ten uppercase alphanumeric characters"
[[ "$approved_key_sha256" =~ ^[0-9a-f]{64}$ ]] || die "approved Sparkle public-key SHA-256 is invalid"
[[ -f "$release_notes" && "$release_notes" == *.html ]] || die "release notes must be an existing HTML file"
if [[ "$initial_release" == 1 ]]; then
    [[ -z "$previous_appcast" && -z "$previous_archive" ]] || die "initial release cannot also provide previous artifacts"
else
    [[ -n "$previous_appcast" && -n "$previous_archive" ]] || die "previous appcast and previous archive are required unless --initial-release is explicit"
fi

python3 "$metadata" validate-version --version "$version" --build "$build" --tag "$tag"
archive_name="Bessie-$version-$build.zip"
python3 "$metadata" validate-url --url "$archive_url" --tag "$tag" --archive "$archive_name"
if [[ "$initial_release" == 0 ]]; then
    python3 "$metadata" check-previous \
        --appcast "$previous_appcast" --archive "$previous_archive" --build "$build" \
        --tag "$tag" --version "$version"
fi

[[ $(uname -s) == Darwin || ${BESSIE_RELEASE_FIXTURE_MODE:-0} == 1 ]] || die "prepare requires a trusted macOS release host"
head_commit=$(git -C "$repo_root" rev-parse HEAD)
[[ "$source_commit" == "$head_commit" && "$source_commit" =~ ^[0-9a-f]{40}$ ]] || die "approved source commit must exactly match HEAD"
[[ -z $(git -C "$repo_root" status --porcelain=v1 --untracked-files=all) ]] || die "approved source must have a clean working tree"
tag_commit=$(git -C "$repo_root" rev-parse "refs/tags/$tag^{commit}" 2>/dev/null || true)
[[ "$tag_commit" == "$source_commit" ]] || die "tag $tag must already resolve to the approved source commit"

output_parent=$(cd "$(dirname "$output")" && pwd -P)
output="$output_parent/$(basename "$output")"
case "$output" in
    "$repo_root"|"$repo_root"/*) die "release output must be outside the source repository" ;;
esac
[[ ! -e "$output" ]] || die "release output already exists: $output"

if [[ ${BESSIE_RELEASE_FIXTURE_MODE:-0} == 1 ]]; then
    security_cmd=$(command -v security)
    xcrun_cmd=$(command -v xcrun)
    codesign_cmd=$(command -v codesign)
    ditto_cmd=$(command -v ditto)
    spctl_cmd=$(command -v spctl)
    shasum_cmd=$(command -v shasum)
    package_path=$PATH
else
    security_cmd=/usr/bin/security
    xcrun_cmd=/usr/bin/xcrun
    codesign_cmd=/usr/bin/codesign
    ditto_cmd=/usr/bin/ditto
    spctl_cmd=/usr/sbin/spctl
    shasum_cmd=/usr/bin/shasum
    package_path=/usr/bin:/bin:/usr/sbin:/sbin
    for system_tool in "$security_cmd" "$xcrun_cmd" "$codesign_cmd" "$ditto_cmd" "$spctl_cmd" "$shasum_cmd" /usr/bin/curl; do
        [[ -x "$system_tool" ]] || die "required system tool is unavailable: $system_tool"
    done
fi

identity_output=$($security_cmd find-identity -v -p codesigning 2>&1) || die "signing Keychain is locked or unavailable"
grep -Fq "\"$identity\"" <<<"$identity_output" || die "requested Developer ID identity is missing or locked"
[[ "$identity" == "Developer ID Application:"*" ($team_id)" ]] || die "Developer ID identity and team ID do not match"

release_scratch=$(mktemp -d "${TMPDIR:-/tmp}/bessie-release-prepare.XXXXXX")
notary_preflight="$release_scratch/notary-preflight.json"
if ! "$xcrun_cmd" notarytool history --keychain-profile "$notary_profile" --output-format json >"$notary_preflight" 2>&1; then
    die "notary Keychain profile is missing, locked, or unusable"
fi
python3 - "$notary_preflight" <<'PY'
import json, sys
try:
    json.load(open(sys.argv[1]))
except Exception:
    raise SystemExit("Release preparation: notary profile did not return valid JSON")
PY
rm -f "$notary_preflight"

# Release tools are resolved from the exact repository-local Sparkle 2.9.5 artifact.
# shellcheck source=scripts/lib/sparkle-packaging.sh
source "$repo_root/scripts/lib/sparkle-packaging.sh"
if [[ ${BESSIE_RELEASE_FIXTURE_MODE:-0} == 1 ]]; then
    [[ -d ${BESSIE_RELEASE_FIXTURE_ROOT:-} ]] || die "fixture mode requires an existing temporary fixture root"
    fixture_root=$(cd "$BESSIE_RELEASE_FIXTURE_ROOT" && pwd -P)
    fixture_temp=$(python3 -c 'import pathlib,tempfile; print(pathlib.Path(tempfile.gettempdir()).resolve())')
    case "$fixture_root" in
        "$fixture_temp"/*) ;;
        *) die "fixture mode requires a temporary fixture root" ;;
    esac
    sparkle_tools_root=$fixture_root
else
    sparkle_archive="$release_scratch/Sparkle-for-Swift-Package-Manager.zip"
    /usr/bin/curl --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
        --output "$sparkle_archive" \
        'https://github.com/sparkle-project/Sparkle/releases/download/2.9.5/Sparkle-for-Swift-Package-Manager.zip'
    [[ $(sha256_file "$sparkle_archive") == 34b9b2071f3de0012eca3faa3a9290bb94e62131e9a74f6dc91514a000097a6c ]] || \
        die "downloaded Sparkle tools archive does not match the pinned 2.9.5 SHA-256"
    mkdir "$release_scratch/sparkle"
    "$ditto_cmd" -x -k "$sparkle_archive" "$release_scratch/sparkle"
    "$xcrun_cmd" swift package --package-path "$repo_root" resolve
    [[ -z $(git -C "$repo_root" status --porcelain=v1 --untracked-files=all) ]] || \
        die "Swift package resolution mutated the approved source"
    sparkle_xcframework=$(bessie_find_sparkle_xcframework "$repo_root")
    resolved_tools=$(find "$release_scratch/sparkle" -type f -path '*/bin/generate_keys' -print)
    [[ -n "$resolved_tools" && "$resolved_tools" != *$'\n'* ]] || die "official Sparkle archive did not contain exactly one release tool set"
    sparkle_tools_root=$(dirname "$(dirname "$resolved_tools")")
    [[ $(basename "$sparkle_xcframework") == Sparkle.xcframework ]] || die "resolved Sparkle artifact validation failed"
fi
generate_keys="$sparkle_tools_root/bin/generate_keys"
generate_appcast="$sparkle_tools_root/bin/generate_appcast"
sign_update="$sparkle_tools_root/bin/sign_update"
for tool in "$generate_keys" "$generate_appcast" "$sign_update"; do
    [[ -f "$tool" && -x "$tool" && ! -L "$tool" ]] || die "missing exact Sparkle 2.9.5 release tool: $tool"
done
[[ ! -e "$sparkle_tools_root/bin/sparkle-cli" ]] || die "removed sparkle-cli must not be present"

sparkle_public_key=$($generate_keys --account "$sparkle_account" -p 2>/dev/null) || die "Sparkle Keychain key is missing, locked, or unusable"
[[ "$sparkle_public_key" != *$'\n'* && -n "$sparkle_public_key" ]] || die "Sparkle public-key preflight returned unexpected output"
actual_key_sha256=$(python3 - "$sparkle_public_key" <<'PY'
import base64, hashlib, sys
try:
    key = base64.b64decode(sys.argv[1], validate=True)
except Exception:
    raise SystemExit(1)
if len(key) != 32 or not any(key):
    raise SystemExit(1)
print(hashlib.sha256(key).hexdigest())
PY
) || die "Sparkle Keychain key did not produce a valid public Ed25519 key"
[[ "$actual_key_sha256" == "$approved_key_sha256" ]] || die "Sparkle Keychain key does not match the separately approved public-key SHA-256"
if [[ "$initial_release" == 0 ]]; then
    previous_signature=$(python3 - "$previous_appcast" <<'PY'
import sys, xml.etree.ElementTree as ET
ns = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
root = ET.parse(sys.argv[1]).getroot()
def version(value): return tuple(int(part) for part in value.split("."))
item = max(
    root.findall("./channel/item"),
    key=lambda candidate: version(
        candidate.findtext(
            ns + "version",
            candidate.find("enclosure").get(ns + "version", "0"),
        )
    ),
)
enclosure = item.find("enclosure")
signature = enclosure.get(ns + "edSignature", "")
if not signature:
    raise SystemExit(1)
print(signature)
PY
    ) || die "previous appcast is missing its latest archive signature"
    "$sign_update" --account "$sparkle_account" --verify "$previous_appcast" >/dev/null || \
        die "previous appcast failed Sparkle signature verification"
    "$sign_update" --account "$sparkle_account" --verify "$previous_archive" "$previous_signature" >/dev/null || \
        die "previous archive failed Sparkle signature verification"
fi

mkdir -p "$output/evidence" "$output/work"
app_path="$repo_root/dist/Bessie.app"
BESSIE_PACKAGE_VARIANT=production \
BESSIE_CODESIGN_IDENTITY="$identity" \
BESSIE_EXPECTED_TEAM_ID="$team_id" \
BESSIE_MARKETING_VERSION="$version" \
BESSIE_BUILD_VERSION="$build" \
BESSIE_SPARKLE_FEED_URL="$feed_url" \
BESSIE_SPARKLE_PUBLIC_ED_KEY="$sparkle_public_key" \
BESSIE_APPROVED_SPARKLE_PUBLIC_ED_KEY_SHA256="$approved_key_sha256" \
    env PATH="$package_path" "$repo_root/scripts/package-app.sh"

"$codesign_cmd" --verify --deep --strict "$app_path"
signature_details=$($codesign_cmd -dv --verbose=4 "$app_path" 2>&1)
grep -Fqx "Authority=$identity" <<<"$signature_details" || die "packaged app does not use the exact approved Developer ID identity"
grep -Fqx "TeamIdentifier=$team_id" <<<"$signature_details" || die "packaged app does not use the approved team"
python3 "$metadata" check-plist --path "$app_path/Contents/Info.plist" \
    --version "$version" --build "$build" --public-key "$sparkle_public_key"

notary_archive="$output/work/notarization.zip"
"$ditto_cmd" -c -k --sequesterRsrc --keepParent "$app_path" "$notary_archive"
notary_archive_sha256=$(sha256_file "$notary_archive")
raw_submission="$output/work/notary-submission.raw.json"
set +e
"$xcrun_cmd" notarytool submit "$notary_archive" --wait --keychain-profile "$notary_profile" \
    --output-format json >"$raw_submission" 2>&1
notary_exit=$?
set -e
python3 "$metadata" redact-notary --source "$raw_submission" --destination "$output/evidence/notary-submission.json"
submission_id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id", ""))' "$output/evidence/notary-submission.json")
notary_status=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status", ""))' "$output/evidence/notary-submission.json")
rm -f "$raw_submission"
[[ "$notary_exit" == 0 && "$notary_status" == Accepted ]] || die "notarization was not accepted; redacted evidence retained in $output/evidence"
[[ -n "$submission_id" ]] || die "accepted notarization response omitted its submission ID"
raw_log="$output/work/notary-log.raw.json"
"$xcrun_cmd" notarytool log "$submission_id" --keychain-profile "$notary_profile" "$raw_log" >/dev/null 2>&1 || \
    die "accepted notarization log could not be retrieved"
python3 "$metadata" redact-notary --source "$raw_log" --destination "$output/evidence/notary-log.json"
rm -f "$raw_log"
read -r log_job_id log_status log_sha256 < <(python3 - "$output/evidence/notary-log.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
print(data.get("jobId", ""), data.get("status", ""), data.get("sha256", ""))
PY
)
[[ "$log_job_id" == "$submission_id" && "$log_status" == Accepted && "$log_sha256" == "$notary_archive_sha256" ]] || \
    die "notarization log does not bind the accepted submission to the local archive SHA-256"

"$xcrun_cmd" stapler staple "$app_path"
"$xcrun_cmd" stapler validate "$app_path"
"$spctl_cmd" --assess --type execute --verbose=4 "$app_path"
"$codesign_cmd" --verify --deep --strict "$app_path"
post_staple_seal=$(app_seal "$app_path")

archive="$output/$archive_name"
"$ditto_cmd" -c -k --sequesterRsrc --keepParent "$app_path" "$archive"
[[ "$post_staple_seal" == "$(app_seal "$app_path")" ]] || die "app bundle mutated after stapling or while final archive bytes were created"
final_extract="$release_scratch/final-archive"
mkdir "$final_extract"
"$ditto_cmd" -x -k "$archive" "$final_extract"
extracted_apps=$(find "$final_extract" -mindepth 1 -maxdepth 1 -type d -name Bessie.app -print)
[[ -n "$extracted_apps" && "$extracted_apps" != *$'\n'* ]] || die "final archive must contain exactly one top-level Bessie.app"
extracted_app=$extracted_apps
"$codesign_cmd" --verify --deep --strict "$extracted_app"
"$xcrun_cmd" stapler validate "$extracted_app"
"$spctl_cmd" --assess --type execute --verbose=4 "$extracted_app"
extracted_signature=$($codesign_cmd -dv --verbose=4 "$extracted_app" 2>&1)
grep -Fqx "Authority=$identity" <<<"$extracted_signature" || die "final archive has the wrong Developer ID identity"
grep -Fqx "TeamIdentifier=$team_id" <<<"$extracted_signature" || die "final archive has the wrong signing team"
python3 "$metadata" check-plist --path "$extracted_app/Contents/Info.plist" \
    --version "$version" --build "$build" --public-key "$sparkle_public_key"
[[ "$post_staple_seal" == "$(app_seal "$app_path")" ]] || die "app bundle mutated during final archive extraction verification"
archive_sha256=$(sha256_file "$archive")
archive_length=$(wc -c <"$archive" | tr -d ' ')
printf '%s  %s\n' "$archive_sha256" "$archive_name" >"$archive.sha256"

appcast_stage="$output/work/appcast"
mkdir -p "$appcast_stage"
cp "$archive" "$appcast_stage/$archive_name"
cp "$release_notes" "$appcast_stage/${archive_name%.zip}.html"
if [[ "$initial_release" == 0 ]]; then
    cp "$previous_appcast" "$output/appcast.xml"
fi
download_prefix=${archive_url%/"$archive_name"}/
release_url="https://github.com/skeletor-js/bessie/releases/tag/$tag"
"$generate_appcast" --account "$sparkle_account" --maximum-deltas 0 --maximum-versions 0 \
    --download-url-prefix "$download_prefix" --full-release-notes-url "$release_url" \
    -o "$output/appcast.xml" "$appcast_stage"
if find "$appcast_stage" -type f \( -name '*.delta' -o -iname '*delta*' \) -print -quit | grep -q .; then
    die "Sparkle generated forbidden delta files"
fi
if [[ "$initial_release" == 0 ]]; then
    python3 "$metadata" compare-retained --previous "$previous_appcast" --generated "$output/appcast.xml"
fi

archive_signature=$(python3 - "$output/appcast.xml" "$build" <<'PY'
import sys, xml.etree.ElementTree as ET
ns = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
root = ET.parse(sys.argv[1]).getroot(); matches = []
for item in root.findall("./channel/item"):
    enclosure = item.find("enclosure")
    if enclosure is not None and item.findtext(ns + "version", enclosure.get(ns + "version", "")) == sys.argv[2]:
        matches.append(enclosure.get(ns + "edSignature", ""))
if len(matches) != 1 or not matches[0]:
    raise SystemExit(1)
print(matches[0])
PY
) || die "generated appcast is missing the final archive signature"
"$sign_update" --account "$sparkle_account" --verify "$archive" "$archive_signature" >/dev/null
"$sign_update" --account "$sparkle_account" --verify "$output/appcast.xml" >/dev/null
[[ "$archive_sha256" == "$(sha256_file "$archive")" ]] || die "final archive mutated after checksum or Sparkle signing"

cp "$release_notes" "$output/release-notes.html"
executable_sha256=$(sha256_file "$app_path/Contents/MacOS/BessieApp")
appcast_sha256=$(sha256_file "$output/appcast.xml")
herdr_version=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["expected_version_output"])' "$repo_root/scripts/herdr-runtime-lock.json")
herdr_protocol=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["protocol"])' "$repo_root/scripts/herdr-runtime-lock.json")
python3 - "$output/release.json" "$source_commit" "$tag" "$version" "$build" \
    "$feed_url" "$archive_name" "$archive_url" "$archive_length" "$archive_sha256" \
    "$appcast_sha256" "$executable_sha256" "$post_staple_seal" "$identity" "$team_id" \
    "$submission_id" "$notary_status" "$herdr_version" "$herdr_protocol" \
    "$notary_archive_sha256" <<'PY'
import json, pathlib, sys
(
    path, source_commit, tag, version, build, feed_url, archive_name, archive_url,
    archive_length, archive_sha256, appcast_sha256, executable_sha256,
    post_staple_seal, identity, team_id, submission_id, notary_status,
    herdr_version, herdr_protocol, notary_archive_sha256,
) = sys.argv[1:]
data = {
    "schema": 1,
    "state": "prepared",
    "source_commit": source_commit,
    "tag": tag,
    "marketing_version": version,
    "build_version": build,
    "minimum_system_version": "14.0",
    "feed_url": feed_url,
    "archive_name": archive_name,
    "archive_url": archive_url,
    "archive_length": int(archive_length),
    "archive_sha256": archive_sha256,
    "appcast_sha256": appcast_sha256,
    "executable_sha256": executable_sha256,
    "post_staple_app_seal": post_staple_seal,
    "sparkle_version": "2.9.5",
    "sparkle_signature_verified_during_prepare": True,
    "developer_id_identity": identity,
    "team_id": team_id,
    "notarization_submission_id": submission_id,
    "notarization_status": notary_status,
    "bundled_herdr_version": herdr_version,
    "bundled_herdr_protocol": herdr_protocol,
    "notarization_archive_sha256": notary_archive_sha256,
    "final_archive_extraction_verified": True,
    "sparkle_tools_archive_sha256": "34b9b2071f3de0012eca3faa3a9290bb94e62131e9a74f6dc91514a000097a6c",
    "byte_finalization_order": ["staple", "archive", "extract-verify", "checksum", "appcast-generate-sign", "sparkle-verify"],
    "published": False,
}
pathlib.Path(path).write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY

cat >"$output/release-evidence.md" <<EOF
# Bessie $tag release evidence

- Source commit: \`$source_commit\`
- Tag: \`$tag\`
- App version/build: \`$version\` / \`$build\`
- Sparkle: \`2.9.5\`
- Bundled Herdr: \`$herdr_version\`; protocol \`$herdr_protocol\`
- Archive SHA-256: \`$archive_sha256\`
- Executable SHA-256: \`$executable_sha256\`
- Developer ID / team: \`$identity\` / \`$team_id\`
- Notarization submission / status: \`$submission_id\` / \`$notary_status\`
- Appcast URL / prepared SHA-256: \`$feed_url\` / \`$appcast_sha256\`
- GitHub release URL: deferred; prepared target \`$release_url\`
- Cloudflare deployment/version: deferred
- Old-to-new result: deferred
- Installed executable identity: deferred
- Herdr-survival result: deferred
EOF

rm -rf "$output/work"
python3 "$metadata" verify "$output"
echo "Prepared but did not publish: $output"
