#!/bin/zsh
# Install a built Hesiod as a self-contained macOS application bundle.
#
#   scripts/macos/install_macos_app.sh [build_dir] [install_dir]
#
# Defaults: build_dir = ./build, install_dir = ~/Applications.
#
# Hesiod resolves its resources through paths relative to the working
# directory ("data/icons", "data/examples", ...), exactly like the Linux
# AppImage zip where the binary sits next to a data folder. The bundle keeps
# that contract: the launcher switches to a per-user workspace
# (~/Library/Application Support/hesiod/workspace, next to Hesiod's own
# autosave data) that links to the bundled data. It deliberately avoids
# ~/Documents, which is privacy-protected and would prompt on first launch.
# Exports given a relative file name land in that workspace; settings and
# autosaves already use the standard per-user locations (QStandardPaths).
#
# The binary links against the Homebrew libraries it was built with, so the
# bundle is meant for the machine that built it.

set -euo pipefail

root_dir="$(cd "$(dirname "$0")/../.." && pwd)"
build_dir="${1:-$root_dir/build}"
install_dir="${2:-$HOME/Applications}"
bin_dir="$build_dir/bin"
app="$install_dir/Hesiod.app"

[[ -x "$bin_dir/hesiod" ]] || { echo "error: $bin_dir/hesiod not found (build first)" >&2; exit 1; }
[[ -d "$bin_dir/data" ]] || { echo "error: $bin_dir/data not found" >&2; exit 1; }

version="0.6.0"
build_version="$(cat "$bin_dir/data/git_version.txt" 2>/dev/null || echo "$version")"

echo "[install] $app  ($build_version)"
mkdir -p "$install_dir"
staging="$(mktemp -d "$install_dir/.Hesiod.app.XXXXXX")"
trap 'rm -rf "$staging"' EXIT

mkdir -p "$staging/Contents/MacOS" "$staging/Contents/Resources"
cp "$bin_dir/hesiod" "$staging/Contents/MacOS/hesiod"
cp -R "$bin_dir/data" "$staging/Contents/Resources/data"

# --- icon (512 px source -> .icns)
iconset="$(mktemp -d)/Hesiod.iconset"
mkdir -p "$iconset"
src_icon="$bin_dir/data/hesiod_icon.png"
for size in 16 32 128 256 512; do
  sips -z $size $size "$src_icon" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  if (( double <= 512 )); then
    sips -z $double $double "$src_icon" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
  fi
done
iconutil -c icns "$iconset" -o "$staging/Contents/Resources/Hesiod.icns"
rm -rf "$(dirname "$iconset")"

# --- launcher (CFBundleExecutable). exec keeps the PID, and the real binary
# lives in Contents/MacOS, so macOS attributes the process to this bundle.
# Named launch-hesiod: the default macOS filesystem is case-insensitive, so
# "Hesiod" would overwrite the "hesiod" binary.
cat > "$staging/Contents/MacOS/launch-hesiod" <<'LAUNCHER'
#!/bin/zsh
contents="$(cd "$(dirname "$0")/.." && pwd)"
workspace="$HOME/Library/Application Support/hesiod/workspace"
logs="$HOME/Library/Logs/Hesiod"
mkdir -p "$workspace" "$logs"
# data/ must resolve from the working directory; keep the link pointing at
# this bundle so reinstalling or moving the app keeps working. Never replace
# a real directory someone put there.
if [[ -L "$workspace/data" || ! -e "$workspace/data" ]]; then
  ln -sfn "$contents/Resources/data" "$workspace/data"
fi
cd "$workspace" || exit 1
exec "$contents/MacOS/hesiod" "$@" >>"$logs/hesiod.log" 2>&1
LAUNCHER
chmod +x "$staging/Contents/MacOS/launch-hesiod"

cat > "$staging/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>launch-hesiod</string>
  <key>CFBundleIdentifier</key>
  <string>org.hesiod.app</string>
  <key>CFBundleName</key>
  <string>Hesiod</string>
  <key>CFBundleDisplayName</key>
  <string>Hesiod</string>
  <key>CFBundleIconFile</key>
  <string>Hesiod</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${version}</string>
  <key>CFBundleVersion</key>
  <string>${build_version}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.graphics-design</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
</dict>
</plist>
PLIST

# Replace any previous install atomically enough for a single user.
rm -rf "$app"
mv "$staging" "$app"
trap - EXIT
# Refresh Finder / Launch Services so the new icon and name show up.
touch "$app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app" >/dev/null 2>&1 || true

echo "[install] done. Workspace: ~/Library/Application Support/hesiod/workspace  Log: ~/Library/Logs/Hesiod/hesiod.log"
