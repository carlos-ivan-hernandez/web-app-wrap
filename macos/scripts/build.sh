#!/usr/bin/env bash
# Builds "dist/WebAppWrap.app". Pass --install to also copy it into /Applications.
# UNIVERSAL=1 builds for both Apple silicon and Intel (requires full Xcode, not just the command line tools).
set -euo pipefail
cd "$(dirname "$0")/.."

arch_flags=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  arch_flags=(--arch arm64 --arch x86_64)
fi

# WebAppWrap's version is the commit it's built from, with "-dirty" if there are uncommitted
# changes. Apps in its list are rebuilt when this changes.
# Without git there's no version, and every app in the list rebuilds each time.
commit="$(git rev-parse HEAD 2>/dev/null || true)"
if [[ -z "$commit" ]]; then
  echo "warning: not a git checkout, so this build has no version." >&2
elif [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  commit="$commit-dirty"
fi

swift build -c release ${arch_flags[@]+"${arch_flags[@]}"}
bin_dir="$(swift build -c release ${arch_flags[@]+"${arch_flags[@]}"} --show-bin-path)"

app="dist/WebAppWrap.app"
rm -rf "$app" "dist/Web App Wrap.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Support/Info.plist "$app/Contents/Info.plist"
if [[ -n "$commit" ]]; then
  /usr/libexec/PlistBuddy -c "Add :WebAppWrapCommit string $commit" "$app/Contents/Info.plist"
fi
cp "$bin_dir/WebAppWrap" "$app/Contents/MacOS/WebAppWrap"
# The browser shell that gets copied into every app WebAppWrap creates.
cp "$bin_dir/WebAppWrapRuntime" "$app/Contents/Resources/WebAppWrapRuntime"

# WebAppWrap's icon is Support/AppIcon.png, drawn with the same renderer it uses for generated
# apps. The image's dark background is part of the design, so it isn't cropped off.
"$app/Contents/MacOS/WebAppWrap" icon --name "WebAppWrap" --image Support/AppIcon.png --no-auto-zoom \
  --out "$app/Contents/Resources/AppIcon.icns" >/dev/null

xattr -cr "$app"
codesign --force --sign - "$app/Contents/Resources/WebAppWrapRuntime"
codesign --force --sign - "$app"
echo "Built $app (version ${commit:-none})"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf "/Applications/WebAppWrap.app"
  cp -R "$app" /Applications/
  echo "Installed /Applications/WebAppWrap.app"
  for old in "/Applications/Web App Wrap.app" /Applications/WebWrap.app; do
    if [[ -d "$old" ]]; then
      echo "Note: the old $old is still installed; you can delete it."
    fi
  done
fi
