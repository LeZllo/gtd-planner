#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRATCH_DIR="/private/tmp/gtd-planner-build"
APP_DIR="${ROOT_DIR}/GTD Planner.app"
MODULE_CACHE="/private/tmp/gtd-planner-swift-module-cache"
CLANG_CACHE="/private/tmp/gtd-planner-clang-cache"

mkdir -p "$MODULE_CACHE" "$CLANG_CACHE"
swift_release() {
  SWIFT_MODULECACHE_PATH="$MODULE_CACHE" CLANG_MODULE_CACHE_PATH="$CLANG_CACHE" \
    swift build -c release --scratch-path "$SCRATCH_DIR" --package-path "$ROOT_DIR" "$@"
}
swift_release
BUILD_DIR="$(swift_release --show-bin-path)"
EXECUTABLE="$BUILD_DIR/GTDPlanner"
if [[ -z "$BUILD_DIR" || ! -f "$EXECUTABLE" || ! -x "$EXECUTABLE" ]]; then
  printf 'error: Swift build did not produce an executable at: %s\n' "$EXECUTABLE" >&2
  exit 1
fi

# Sign the executable while it is still in /private/tmp. The project folder
# is FileProvider-managed and macOS may attach Finder/provenance metadata to a
# final .app bundle, which makes strict bundle signing fail intermittently.
xattr -c "$EXECUTABLE" 2>/dev/null || true
codesign --force --sign - --timestamp=none "$EXECUTABLE"
codesign --verify --strict "$EXECUTABLE"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/GTDPlanner"
cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
# Keep the copied executable's valid signature; Launch Services can launch an
# app bundle with a signed executable even when FileProvider adds metadata to
# the outer bundle after the copy.
xattr -cr "$APP_DIR" 2>/dev/null || true
echo "Built: $APP_DIR"
