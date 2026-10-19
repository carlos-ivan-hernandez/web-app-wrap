#!/usr/bin/env bash
# Builds "dist/Web App Wrap.app". Pass --install to also copy it into /Applications.
# UNIVERSAL=1 builds for both Apple silicon and Intel (requires full Xcode, not just the command line tools).
set -euo pipefail
cd "$(dirname "$0")/.."

arch_flags=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  arch_flags=(--arch arm64 --arch x86_64)
fi

swift build -c release ${arch_flags[@]+"${arch_flags[@]}"}
bin_dir="$(swift build -c release ${arch_flags[@]+"${arch_flags[@]}"} --show-bin-path)"

app="dist/Web App Wrap.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Support/Info.plist "$app/Contents/Info.plist"
cp "$bin_dir/WebAppWrap" "$app/Contents/MacOS/WebAppWrap"
# The browser shell that gets copied into every app Web App Wrap creates.
cp "$bin_dir/WebAppWrapRuntime" "$app/Contents/Resources/WebAppWrapRuntime"

# Web App Wrap draws its own icon with the same renderer it uses for generated apps.
"$app/Contents/MacOS/WebAppWrap" icon --name "Web App Wrap" --symbol macwindow.badge.plus \
  --out "$app/Contents/Resources/AppIcon.icns" >/dev/null

xattr -cr "$app"
codesign --force --sign - "$app/Contents/Resources/WebAppWrapRuntime"
codesign --force --sign - "$app"
echo "Built $app"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf "/Applications/Web App Wrap.app"
  cp -R "$app" /Applications/
  echo "Installed /Applications/Web App Wrap.app"
  if [[ -d /Applications/WebWrap.app ]]; then
    echo "Note: the old /Applications/WebWrap.app is still installed; you can delete it."
  fi
fi
