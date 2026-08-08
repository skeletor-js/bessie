#!/usr/bin/env bash
# Focused rebuild + install for Jordan's Mac after shortcut routing changes.
# Does NOT run the full mac-verify acceptance suite.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if [[ ${1:-} == --print-package-configuration && $# == 1 ]]; then
  : "${BESSIE_CODESIGN_IDENTITY:?Set BESSIE_CODESIGN_IDENTITY to inspect the production package configuration.}"
  bundle_identifier=$(
    BESSIE_PACKAGE_VARIANT=production \
    "$repo_root/scripts/package-app.sh" --print-bundle-identifier
  )
  printf 'variant=production\nbundle_identifier=%s\n' "$bundle_identifier"
  exit 0
fi
if [[ ${1:-} == --print-package-configuration || $# -gt 1 ]]; then
  echo "Usage: $0 [mac-directory|--print-package-configuration]" >&2
  exit 1
fi

mac_dir=${1:-/Users/jordanstella/GitHub/bessie}
cd "$mac_dir"
source "$mac_dir/scripts/lib/bessie-app-lifecycle.sh"

echo "=== mirror marker ==="
cat .bessie-mirror

echo "=== confirm shortcut policy on Mac ==="
grep -n 'firstResponderIsEditableText\|allowsDuringTextEditing\|isEditableTextResponder' \
  Sources/BessieApp/KeyboardShortcutCoordinator.swift | head -20
grep -n 'one window-scoped policy\|Cmd+Shift+P' README.md | head -10

echo "=== verify exact-executable install lifecycle ==="
bash ./scripts/verify-app-install-lifecycle.sh

installed_app=/Applications/Bessie.app
installed_executable="$installed_app/Contents/MacOS/BessieApp"
echo "=== stop validated installed Bessie owners ==="
bessie_terminate_installation_owners "$installed_executable"

echo "=== swift package clean + package-app ==="
: "${BESSIE_CODESIGN_IDENTITY:?Set BESSIE_CODESIGN_IDENTITY to a stable signing identity before installing production Bessie.}"
if [[ "$BESSIE_CODESIGN_IDENTITY" == - ]]; then
  echo "Refusing ad-hoc production install. Set BESSIE_CODESIGN_IDENTITY to a stable identity." >&2
  exit 1
fi
export BESSIE_PACKAGE_VARIANT=production
xcrun swift package clean
./scripts/package-app.sh

echo "=== package identity ==="
test -x dist/Bessie.app/Contents/MacOS/BessieApp
test -x dist/Bessie.app/Contents/Resources/Herdr/herdr
codesign --verify --deep --strict dist/Bessie.app
packaged_app_sha=$(shasum -a 256 dist/Bessie.app/Contents/MacOS/BessieApp | awk '{print $1}')
packaged_herdr_sha=$(shasum -a 256 dist/Bessie.app/Contents/Resources/Herdr/herdr | awk '{print $1}')
echo "packaged BessieApp sha256=$packaged_app_sha"
echo "packaged herdr sha256=$packaged_herdr_sha"
lipo -archs dist/Bessie.app/Contents/Resources/Herdr/herdr
dist/Bessie.app/Contents/Resources/Herdr/herdr --version

echo "=== focused keyboard tests ==="
xcrun swift test --filter 'KeyboardShortcut|KeyboardCoordinator|ProductShortcutsDoNotRequire|TopologyShortcutsYield'

echo "=== install to /Applications ==="
install_stage="/Applications/.Bessie.app.install-$$"
install_backup="/tmp/Bessie.app.backup-$$"
find "$install_stage" -depth -delete 2>/dev/null || true
find "$install_backup" -depth -delete 2>/dev/null || true

ditto "$mac_dir/dist/Bessie.app" "$install_stage"
codesign --verify --deep --strict "$install_stage"

# Recheck immediately before replacement in case Bessie relaunched during the
# build or focused tests.
bessie_terminate_installation_owners "$installed_executable"
if [[ -e "$installed_app" ]]; then
  mv "$installed_app" "$install_backup"
fi
if ! mv "$install_stage" "$installed_app"; then
  [[ ! -e "$install_backup" ]] || mv "$install_backup" "$installed_app"
  exit 1
fi

if ! (
  codesign --verify --deep --strict "$installed_app"
  cmp "$mac_dir/dist/Bessie.app/Contents/MacOS/BessieApp" "$installed_app/Contents/MacOS/BessieApp"
  cmp "$mac_dir/dist/Bessie.app/Contents/Resources/Herdr/herdr" "$installed_app/Contents/Resources/Herdr/herdr"
  cmp "$mac_dir/dist/Bessie.app/Contents/Resources/Herdr/LICENSE" "$installed_app/Contents/Resources/Herdr/LICENSE"
  installed_app_sha=$(shasum -a 256 "$installed_app/Contents/MacOS/BessieApp" | awk '{print $1}')
  [[ "$installed_app_sha" == "$packaged_app_sha" ]]
); then
  find "$installed_app" -depth -delete
  [[ ! -e "$install_backup" ]] || mv "$install_backup" "$installed_app"
  echo "Install identity checks failed; restored previous app if present." >&2
  exit 1
fi

find "$install_backup" -depth -delete 2>/dev/null || true
installed_app_sha=$(shasum -a 256 "$installed_app/Contents/MacOS/BessieApp" | awk '{print $1}')
echo "installed BessieApp sha256=$installed_app_sha"
echo "installed matches packaged: yes"

echo "=== relaunch installed app (normal user session) ==="
/usr/bin/open -n "$installed_app"
installed_owner=''
for _ in {1..80}; do
  installed_owner=$(bessie_assert_single_installed_owner "$installed_executable" 2>/dev/null || true)
  [[ -z "$installed_owner" ]] || break
  sleep 0.25
done
[[ -n "$installed_owner" ]]
printf 'installed owner %s\n' "$installed_owner"
echo "RELAUNCH_OK"

echo "REBUILD_INSTALL_OK packaged=$packaged_app_sha installed=$installed_app_sha"
