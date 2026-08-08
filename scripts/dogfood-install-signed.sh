#!/usr/bin/env bash
# Package Bessie with a stable Apple signing identity and install to
# /Applications/Bessie.app for daily dogfood.
#
# Must run in an interactive GUI login on the Mac (keychain unlock). SSH-only
# sessions hit errSecInternalComponent for Developer ID.
#
# Usage (on jordan-macbook, from the Mac mirror):
#   ./scripts/dogfood-install-signed.sh
#   BESSIE_CODESIGN_IDENTITY="Apple Development: …" ./scripts/dogfood-install-signed.sh
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

default_identity='Developer ID Application: JORDAN JAMES STELLA (T4K7A3GPQ6)'
identity=${BESSIE_CODESIGN_IDENTITY:-$default_identity}

if [[ "$identity" == "-" ]]; then
  echo "Refusing ad-hoc dogfood install. Set BESSIE_CODESIGN_IDENTITY to a real identity." >&2
  exit 1
fi

if [[ ${1:-} == --print-package-configuration && $# == 1 ]]; then
  bundle_identifier=$(
    BESSIE_PACKAGE_VARIANT=production \
    BESSIE_CODESIGN_IDENTITY="$identity" \
    ./scripts/package-app.sh --print-bundle-identifier
  )
  printf 'variant=production\nbundle_identifier=%s\n' "$bundle_identifier"
  exit 0
fi
if [[ $# -ne 0 ]]; then
  echo "Usage: $0 [--print-package-configuration]" >&2
  exit 1
fi

if [[ $(uname -s) != Darwin ]]; then
  echo "dogfood-install-signed.sh requires macOS." >&2
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -F "$identity" >/dev/null; then
  echo "Signing identity not found in keychain: $identity" >&2
  security find-identity -v -p codesigning >&2 || true
  exit 1
fi

# Probe signing before a long package (fails fast if keychain is locked).
probe=$(mktemp /tmp/bessie-codesign-probe.XXXXXX)
echo probe >"$probe"
if ! codesign --force --sign "$identity" "$probe" 2>/dev/null; then
  rm -f "$probe"
  cat >&2 <<'EOF'
codesign could not use the identity (errSecInternalComponent is common over SSH).

Fix:
  1. Sit at the Mac GUI session (or Screen Sharing)
  2. Unlock login keychain if needed
  3. Run this script in Terminal.app / iTerm on the Mac, not over headless SSH
  4. On first use, choose "Always Allow" for codesign access to the private key
EOF
  exit 1
fi
rm -f "$probe"

export BESSIE_CODESIGN_IDENTITY="$identity"
export BESSIE_PACKAGE_VARIANT=production
./scripts/package-app.sh

pkg_app="$repo_root/dist/Bessie.app"
pkg_bin="$pkg_app/Contents/MacOS/BessieApp"
installed_app=/Applications/Bessie.app
installed_bin="$installed_app/Contents/MacOS/BessieApp"
stage="/Applications/.Bessie.app.install-$$"
backup="/tmp/Bessie.app.backup-$$"

test -x "$pkg_bin"
codesign --verify --deep --strict "$pkg_app"
signature_details=$(codesign -dv --verbose=4 "$pkg_app" 2>&1)
grep -F "$identity" <<<"$signature_details" >/dev/null

# Prefer not killing unrelated apps; only stop BessieApp.
if pids=$(pgrep -f "^/Applications/Bessie.app/Contents/MacOS/BessieApp" || true); then
  # shellcheck disable=SC2086
  kill $pids 2>/dev/null || true
  sleep 1
fi

rm -rf "$stage" "$backup"
ditto "$pkg_app" "$stage"
if [[ -e "$installed_app" ]]; then
  mv "$installed_app" "$backup"
fi
if ! mv "$stage" "$installed_app"; then
  [[ ! -e "$backup" ]] || mv "$backup" "$installed_app"
  echo "Install move failed" >&2
  exit 1
fi
rm -rf "$backup"

codesign --verify --deep --strict "$installed_app"
cmp -s "$pkg_bin" "$installed_bin"
open -a "$installed_app"

echo "Installed signed Bessie:"
echo "  identity: $identity"
shasum -a 256 "$installed_bin"
codesign -dv --verbose=2 "$installed_app" 2>&1 | grep -E 'Authority=|TeamIdentifier=|Signature=' || true
echo
echo "Next (once): System Settings → Notifications → Bessie → allow banners."
echo "Then in Bessie Settings, Send test notification."
