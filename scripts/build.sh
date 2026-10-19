#!/usr/bin/env bash
# Builds dist/WebWrap.app. Pass --install to also copy it into /Applications.
# UNIVERSAL=1 builds for both Apple silicon and Intel (requires full Xcode, not just the command line tools).
set -euo pipefail
cd "$(dirname "$0")/.."

arch_flags=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  arch_flags=(--arch arm64 --arch x86_64)
fi

swift build -c release ${arch_flags[@]+"${arch_flags[@]}"}
bin_dir="$(swift build -c release ${arch_flags[@]+"${arch_flags[@]}"} --show-bin-path)"

app="dist/WebWrap.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Support/Info.plist "$app/Contents/Info.plist"
cp "$bin_dir/WebWrap" "$app/Contents/MacOS/WebWrap"
# The browser shell that gets copied into every app WebWrap creates.
cp "$bin_dir/WebWrapRuntime" "$app/Contents/Resources/WebWrapRuntime"

# WebWrap draws its own icon with the same renderer it uses for generated apps.
"$app/Contents/MacOS/WebWrap" icon --name WebWrap --symbol macwindow.badge.plus \
  --out "$app/Contents/Resources/AppIcon.icns" >/dev/null

xattr -cr "$app"
codesign --force --sign - "$app/Contents/Resources/WebWrapRuntime"
codesign --force --sign - "$app"
echo "Built $app"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf /Applications/WebWrap.app
  cp -R "$app" /Applications/
  echo "Installed /Applications/WebWrap.app"
fi
