#!/usr/bin/env bash

bessie_packaging_error() {
    echo "Sparkle packaging: $*" >&2
    return 1
}

bessie_find_sparkle_xcframework() {
    local repo_root=$1
    python3 - "$repo_root" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1]).resolve()
build_root = (root / ".build").resolve()
artifact_root = (build_root / "artifacts").resolve()
resolved_path = root / "Package.resolved"
workspace_path = build_root / "workspace-state.json"

with resolved_path.open() as handle:
    resolved = json.load(handle)
pins = [pin for pin in resolved.get("pins", []) if pin.get("identity") == "sparkle"]
expected_state = {
    "revision": "79bc9e872948e47877e76f194cb0c8e0412b0b90",
    "version": "2.9.5",
}
if len(pins) != 1 or pins[0].get("location") != "https://github.com/sparkle-project/Sparkle" or pins[0].get("state") != expected_state:
    raise SystemExit("Sparkle packaging: Package.resolved is not pinned to the approved Sparkle 2.9.5 revision")

with workspace_path.open() as handle:
    workspace = json.load(handle)
matches = []
for artifact in workspace.get("object", {}).get("artifacts", []):
    package = artifact.get("packageRef", {})
    source = artifact.get("source", {})
    if (
        package.get("identity") == "sparkle"
        and package.get("location") == "https://github.com/sparkle-project/Sparkle"
        and artifact.get("targetName") == "Sparkle"
        and artifact.get("kind") == {"xcframework": {}}
        and source.get("type") == "remote"
        and source.get("url") == "https://github.com/sparkle-project/Sparkle/releases/download/2.9.5/Sparkle-for-Swift-Package-Manager.zip"
        and source.get("checksum") == "34b9b2071f3de0012eca3faa3a9290bb94e62131e9a74f6dc91514a000097a6c"
    ):
        matches.append(pathlib.Path(artifact.get("path", "")).resolve())
if len(matches) != 1:
    raise SystemExit(f"Sparkle packaging: expected one resolved Sparkle 2.9.5 artifact, found {len(matches)}")
candidate = matches[0]
if artifact_root not in candidate.parents or candidate.name != "Sparkle.xcframework" or not (candidate / "Info.plist").is_file():
    raise SystemExit("Sparkle packaging: resolved Sparkle artifact escapes repository-local .build/artifacts")
print(candidate)
PY
}

bessie_find_macos_sparkle_framework() {
    local xcframework=$1
    python3 - "$xcframework" <<'PY'
import pathlib
import plistlib
import sys

root = pathlib.Path(sys.argv[1]).resolve()
with (root / "Info.plist").open("rb") as handle:
    info = plistlib.load(handle)
matches = []
for library in info.get("AvailableLibraries", []):
    if library.get("SupportedPlatform") != "macos":
        continue
    identifier = library.get("LibraryIdentifier")
    library_path = library.get("LibraryPath")
    if not isinstance(identifier, str) or library_path != "Sparkle.framework":
        continue
    if library.get("SupportedPlatformVariant") is not None:
        continue
    architectures = library.get("SupportedArchitectures")
    if not isinstance(architectures, list) or set(architectures) != {"arm64", "x86_64"}:
        continue
    candidate = root / identifier / library_path
    resolved_candidate = candidate.resolve()
    if root not in resolved_candidate.parents or resolved_candidate.name != "Sparkle.framework":
        continue
    if resolved_candidate.is_dir():
        matches.append(resolved_candidate)
if len(matches) != 1:
    raise SystemExit(
        f"Sparkle packaging: expected exactly one declared macOS Sparkle.framework, found {len(matches)}"
    )
print(matches[0])
PY
}

bessie_validate_sparkle_framework() {
    local framework=$1
    local version="$framework/Versions/B"
    local -a required=(
        "$version/Sparkle"
        "$version/Autoupdate"
        "$version/Updater.app/Contents/MacOS/Updater"
        "$version/XPCServices/Installer.xpc/Contents/MacOS/Installer"
        "$version/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"
    )
    local required_path
    local entry
    local -a xpc_services=()

    [[ -d "$version" ]] || {
        bessie_packaging_error "Sparkle.framework is missing Versions/B"
        return 1
    }
    [[ -L "$framework/Versions/Current" && $(readlink "$framework/Versions/Current") == B ]] || {
        bessie_packaging_error "Sparkle.framework Versions/Current must be a symlink to B"
        return 1
    }
    for entry in \
        Sparkle Autoupdate Headers Modules PrivateHeaders Resources Updater.app XPCServices
    do
        [[ -L "$framework/$entry" && $(readlink "$framework/$entry") == "Versions/Current/$entry" ]] || {
            bessie_packaging_error "Sparkle.framework $entry symlink is missing or flattened"
            return 1
        }
    done
    for required_path in "${required[@]}"; do
        [[ -f "$required_path" && ! -L "$required_path" && -x "$required_path" ]] || {
            bessie_packaging_error "required Sparkle 2.9.5 code is missing, linked, or non-executable: $required_path"
            return 1
        }
    done
    while IFS= read -r -d '' entry; do
        xpc_services+=("$(basename "$entry")")
    done < <(find -P "$version/XPCServices" -mindepth 1 -maxdepth 1 -type d -name '*.xpc' -print0 | sort -z)
    [[ ${#xpc_services[@]} -eq 2 && ${xpc_services[0]} == Downloader.xpc && ${xpc_services[1]} == Installer.xpc ]] || {
        bessie_packaging_error "unexpected Sparkle XPC service set: ${xpc_services[*]:-(none)}"
        return 1
    }
    if find -P "$framework" \( -name BinaryDelta -o -name generate_appcast -o \
        -name generate_keys -o -name sign_update -o -name old_dsa_scripts -o \
        -name '*.dSYM' \) -print -quit | grep -q .; then
        bessie_packaging_error "Sparkle.framework contains excluded release tools, DSA scripts, or dSYMs"
        return 1
    fi
}

bessie_validate_resolved_sparkle_code() {
    local framework=$1
    local version="$framework/Versions/B"
    local subject
    local executable
    local identifier
    local -a subjects=(
        "$version/Updater.app|$version/Updater.app/Contents/MacOS/Updater|org.sparkle-project.Sparkle.Updater"
        "$version/Autoupdate|$version/Autoupdate|Autoupdate-"
        "$version/XPCServices/Installer.xpc|$version/XPCServices/Installer.xpc/Contents/MacOS/Installer|org.sparkle-project.InstallerLauncher"
        "$version/XPCServices/Downloader.xpc|$version/XPCServices/Downloader.xpc/Contents/MacOS/Downloader|org.sparkle-project.DownloaderService"
        "$framework|$version/Sparkle|org.sparkle-project.Sparkle"
    )

    bessie_validate_sparkle_framework "$framework"
    codesign --verify --deep --strict "$framework"
    for subject in "${subjects[@]}"; do
        IFS='|' read -r subject executable identifier <<<"$subject"
        lipo -archs "$executable" | tr ' ' '\n' | grep -Fx arm64 >/dev/null || {
            bessie_packaging_error "Sparkle code is missing arm64: $executable"
            return 1
        }
        [[ $(codesign -dv --verbose=4 "$subject" 2>&1 | sed -n 's/^Identifier=//p' | head -n 1) == "$identifier"* ]] || {
            bessie_packaging_error "unexpected Sparkle code identifier for $subject"
            return 1
        }
    done
    [[ $(otool -D "$version/Sparkle" | tail -n 1) == '@rpath/Sparkle.framework/Versions/B/Sparkle' ]] || {
        bessie_packaging_error "unexpected Sparkle framework install name"
        return 1
    }
}

bessie_copy_sparkle_framework() {
    local source=$1
    local destination=$2

    [[ $(uname -s) == Darwin ]] || {
        bessie_packaging_error "framework copying requires macOS ditto"
        return 1
    }
    [[ ! -e "$destination" && ! -L "$destination" ]] || {
        bessie_packaging_error "refusing to overwrite existing framework destination: $destination"
        return 1
    }
    mkdir -p "$(dirname "$destination")"
    /usr/bin/ditto "$source" "$destination"
    bessie_validate_sparkle_framework "$destination"
}

bessie_validate_package_metadata() {
    local variant=$1
    local marketing_version=$2
    local build_version=$3
    local feed_url=$4
    local public_key=$5
    local approved_public_key_sha256=$6

    python3 - \
        "$variant" "$marketing_version" "$build_version" "$feed_url" "$public_key" \
        "$approved_public_key_sha256" <<'PY'
import base64
import hashlib
import re
import sys
from urllib.parse import urlparse

variant, marketing, build, feed, public_key, approved_key_hash = sys.argv[1:]
if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,3}", marketing):
    raise SystemExit("Sparkle packaging: marketing version must be numeric dotted notation")
if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", build):
    raise SystemExit("Sparkle packaging: build version must be numeric or dotted-numeric")
if variant == "verify":
    if feed or public_key or approved_key_hash:
        raise SystemExit("Sparkle packaging: verification packages must omit production feed inputs")
    raise SystemExit(0)
if variant != "production":
    raise SystemExit("Sparkle packaging: unsupported package variant")
parsed = urlparse(feed)
if feed != "https://bessie.dev/appcast.xml" or parsed.scheme != "https":
    raise SystemExit("Sparkle packaging: production feed must be https://bessie.dev/appcast.xml")
try:
    decoded_key = base64.b64decode(public_key, validate=True)
except Exception as error:
    raise SystemExit("Sparkle packaging: SUPublicEDKey must be canonical base64") from error
if len(decoded_key) != 32 or not any(decoded_key):
    raise SystemExit("Sparkle packaging: SUPublicEDKey must decode to a nonzero 32-byte Ed25519 public key")
if base64.b64encode(decoded_key).decode() != public_key:
    raise SystemExit("Sparkle packaging: SUPublicEDKey must use canonical base64 encoding")
if not re.fullmatch(r"[0-9a-f]{64}", approved_key_hash):
    raise SystemExit("Sparkle packaging: production requires an approved public-key SHA-256")
if hashlib.sha256(decoded_key).hexdigest() != approved_key_hash:
    raise SystemExit("Sparkle packaging: SUPublicEDKey does not match its separately approved SHA-256")
PY
}

bessie_render_info_plist() {
    local source=$1
    local destination=$2
    local bundle_identifier=$3
    local variant=$4
    local marketing_version=$5
    local build_version=$6
    local feed_url=$7
    local public_key=$8
    local approved_public_key_sha256=$9

    bessie_validate_package_metadata \
        "$variant" "$marketing_version" "$build_version" "$feed_url" "$public_key" \
        "$approved_public_key_sha256"
    python3 - \
        "$source" "$destination" "$bundle_identifier" "$variant" \
        "$marketing_version" "$build_version" "$feed_url" "$public_key" <<'PY'
import pathlib
import plistlib
import sys

source, destination, bundle_id, variant, marketing, build, feed, public_key = sys.argv[1:]
template = pathlib.Path(source).read_text()
replacements = {
    "__BESSIE_BUNDLE_IDENTIFIER__": bundle_id,
    "__BESSIE_MARKETING_VERSION__": marketing,
    "__BESSIE_BUILD_VERSION__": build,
    "__BESSIE_SPARKLE_FEED_URL__": feed,
    "__BESSIE_SPARKLE_PUBLIC_ED_KEY__": public_key,
}
for placeholder, value in replacements.items():
    if template.count(placeholder) != 1:
        raise SystemExit(f"Info.plist.in must contain exactly one {placeholder} placeholder.")
    template = template.replace(placeholder, value)
info = plistlib.loads(template.encode())
if variant == "verify":
    for key in tuple(info):
        if key.startswith("SU"):
            info.pop(key)
pathlib.Path(destination).write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_XML, sort_keys=False))
PY
    python3 - "$destination" "$variant" "$feed_url" "$public_key" <<'PY'
import plistlib
import sys

path, variant, feed, public_key = sys.argv[1:]
with open(path, "rb") as handle:
    info = plistlib.load(handle)
if "SUAllowsInsecureUpdates" in info:
    raise SystemExit("Sparkle packaging: rendered plist contains SUAllowsInsecureUpdates")
if variant == "verify":
    if any(key.startswith("SU") for key in info):
        raise SystemExit("Sparkle packaging: verification plist contains production Sparkle policy")
else:
    expected = {
        "SUFeedURL": feed,
        "SUPublicEDKey": public_key,
        "SURequireSignedFeed": True,
        "SUVerifyUpdateBeforeExtraction": True,
        "SUSignedFeedFailureExpirationInterval": 0,
        "SUEnableAutomaticChecks": True,
        "SUAllowsAutomaticUpdates": True,
        "SUAutomaticallyUpdate": True,
        "SUSendProfileInfo": False,
    }
    for key, value in expected.items():
        if info.get(key) != value or type(info[key]) is not type(value):
            raise SystemExit(f"Sparkle packaging: rendered plist has invalid {key}")
PY
}

bessie_sparkle_code_subjects() {
    local framework=$1
    local version="$framework/Versions/B"
    printf '%s\n' \
        "$version/Updater.app" \
        "$version/Autoupdate" \
        "$version/XPCServices/Installer.xpc" \
        "$version/XPCServices/Downloader.xpc" \
        "$version/Sparkle" \
        "$framework"
}

bessie_sign_code_preserving_metadata() {
    local subject=$1
    local identity=$2
    local signature_mode=$3
    local metadata_root=$4
    local metadata_name
    local identifier
    local entitlements
    local -a arguments=(--force)

    metadata_name=$(printf '%s' "$subject" | shasum -a 256 | awk '{print $1}')
    identifier=$(codesign -dv --verbose=4 "$subject" 2>&1 | sed -n 's/^Identifier=//p' | head -n 1)
    [[ -n "$identifier" ]] || {
        bessie_packaging_error "could not read the existing code identifier for $subject"
        return 1
    }
    entitlements="$metadata_root/$metadata_name.entitlements.plist"
    codesign -d --entitlements - "$subject" >"$entitlements" 2>/dev/null || true
    if ! grep -q '<plist' "$entitlements"; then
        rm -f "$entitlements"
        entitlements=""
    fi
    if [[ "$signature_mode" == developer-id ]]; then
        arguments+=(--options runtime --timestamp)
    else
        arguments+=(--requirements "=designated => identifier \"$identifier\"")
    fi
    arguments+=(--identifier "$identifier")
    if [[ -n "$entitlements" ]]; then
        arguments+=(--entitlements "$entitlements")
    fi
    arguments+=(--sign "$identity" "$subject")
    codesign "${arguments[@]}"
    [[ $(codesign -dv --verbose=4 "$subject" 2>&1 | sed -n 's/^Identifier=//p' | head -n 1) == "$identifier" ]] || {
        bessie_packaging_error "code identifier changed while signing $subject"
        return 1
    }
    codesign -d -r- "$subject" 2>&1 | grep -F "identifier \"$identifier\"" >/dev/null || {
        bessie_packaging_error "designated requirement lost identifier $identifier for $subject"
        return 1
    }
    if [[ -n "$entitlements" ]]; then
        local signed_entitlements="$metadata_root/$metadata_name.signed-entitlements.plist"
        codesign -d --entitlements - "$subject" >"$signed_entitlements" 2>/dev/null
        cmp "$entitlements" "$signed_entitlements" || {
            bessie_packaging_error "entitlements changed while signing $subject"
            return 1
        }
    fi
}

bessie_sign_sparkle_framework() {
    local framework=$1
    local identity=$2
    local signature_mode=$3
    local metadata_root
    local subject

    bessie_validate_sparkle_framework "$framework"
    metadata_root=$(mktemp -d "${TMPDIR:-/tmp}/bessie-sparkle-signing.XXXXXX")
    while IFS= read -r subject; do
        bessie_sign_code_preserving_metadata "$subject" "$identity" "$signature_mode" "$metadata_root"
    done < <(bessie_sparkle_code_subjects "$framework")
    rm -rf "$metadata_root"
}

bessie_verify_sparkle_signatures() {
    local framework=$1
    local subject

    while IFS= read -r subject; do
        codesign --verify --strict "$subject"
    done < <(bessie_sparkle_code_subjects "$framework")
}

bessie_verify_sparkle_linkage() {
    local executable=$1
    local linked

    linked=$(otool -L "$executable" | awk '/Sparkle\.framework/ { print $1 }')
    [[ "$linked" == '@rpath/Sparkle.framework/Versions/B/Sparkle' ]] || {
        bessie_packaging_error "BessieApp does not link the packaged Sparkle Versions/B path (found: ${linked:-none})"
        return 1
    }
    otool -l "$executable" | awk '
        $1 == "cmd" && $2 == "LC_RPATH" { in_rpath = 1; next }
        in_rpath && $1 == "path" && $2 == "@executable_path/../Frameworks" { found = 1 }
        in_rpath && $1 == "path" { in_rpath = 0 }
        END { exit(found ? 0 : 1) }
    ' || {
        bessie_packaging_error "BessieApp is missing @executable_path/../Frameworks LC_RPATH"
        return 1
    }
    if otool -l "$executable" | awk '$1 == "path" { print $2 }' | grep -E '(\.build/|/artifacts/|DerivedData|/Library/Caches/)' >/dev/null; then
        bessie_packaging_error "BessieApp contains a build-cache LC_RPATH"
        return 1
    fi
}

bessie_validate_developer_id_details() {
    local details=$1
    local expected_team=$2
    local label=$3

    grep -F 'Authority=Developer ID Application:' <<<"$details" >/dev/null || {
        bessie_packaging_error "$label is not signed by Developer ID Application"
        return 1
    }
    grep -F "TeamIdentifier=$expected_team" <<<"$details" >/dev/null || {
        bessie_packaging_error "$label has the wrong signing team"
        return 1
    }
    grep -E '^(flags=|CodeDirectory[[:space:]].*[[:space:]]flags=)[^[:space:]]*\(runtime\)([[:space:]]|$)' <<<"$details" >/dev/null || {
        bessie_packaging_error "$label is missing hardened runtime"
        return 1
    }
    grep -E '^Timestamp=.+$' <<<"$details" >/dev/null || {
        bessie_packaging_error "$label is missing a secure timestamp"
        return 1
    }
    ! grep -F 'Signature=adhoc' <<<"$details" >/dev/null || {
        bessie_packaging_error "$label is ad-hoc signed"
        return 1
    }
}

bessie_verify_developer_id_signatures() {
    local framework=$1
    local runtime=$2
    local app=$3
    local app_team
    local details
    local subject

    details=$(codesign -dv --verbose=4 "$app" 2>&1)
    app_team=$(sed -n 's/^TeamIdentifier=//p' <<<"$details" | head -n 1)
    [[ -n "$app_team" && "$app_team" != not\ set ]] || {
        bessie_packaging_error "production app is missing a signing team"
        return 1
    }
    bessie_validate_developer_id_details "$details" "$app_team" "$app"
    while IFS= read -r subject; do
        details=$(codesign -dv --verbose=4 "$subject" 2>&1)
        bessie_validate_developer_id_details "$details" "$app_team" "$subject"
    done < <(printf '%s\n' "$runtime"; bessie_sparkle_code_subjects "$framework")
}
