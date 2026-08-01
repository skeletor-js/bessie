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

case "$app_path" in
    "$repo_root"/dist/Bessie.app) ;;
    *) echo "Refusing unexpected app path: $app_path" >&2; exit 1 ;;
esac

if [[ -e "$app_path" ]]; then
    find "$app_path" -depth -delete
fi

mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_path/BessieApp" "$app_path/Contents/MacOS/BessieApp"
cp "$repo_root/scripts/Info.plist.in" "$app_path/Contents/Info.plist"
for icon in BessieDark BessieLight; do
    icon_path="$repo_root/Sources/BessieApp/Resources/AppIcons/$icon.icns"
    test -s "$icon_path"
    cp "$icon_path" "$app_path/Contents/Resources/$icon.icns"
done

while IFS= read -r -d '' bundle; do
    cp -R "$bundle" "$app_path/Contents/Resources/"
done < <(find "$bin_path" -maxdepth 1 -type d -name '*.bundle' -print0)

chmod 755 "$app_path/Contents/MacOS/BessieApp"
plutil -lint "$app_path/Contents/Info.plist"
codesign --force --sign - "$app_path"
codesign --verify --deep --strict "$app_path"

echo "Packaged $app_path"
