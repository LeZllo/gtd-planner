#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="/private/tmp/gtd-planner-build/arm64-apple-macosx/release"
APP_DIR="${ROOT_DIR}/GTD Planner.app"
MODULE_CACHE="/private/tmp/gtd-planner-swift-module-cache"
CLANG_CACHE="/private/tmp/gtd-planner-clang-cache"

mkdir -p "$MODULE_CACHE" "$CLANG_CACHE"
SWIFT_MODULECACHE_PATH="$MODULE_CACHE" CLANG_MODULE_CACHE_PATH="$CLANG_CACHE" \
  swift build -c release --scratch-path "/private/tmp/gtd-planner-build" --package-path "$ROOT_DIR"

# Sign the executable while it is still in /private/tmp. The project folder
# is FileProvider-managed and macOS may attach Finder/provenance metadata to a
# final .app bundle, which makes strict bundle signing fail intermittently.
xattr -c "$BUILD_DIR/GTDPlanner" 2>/dev/null || true
codesign --force --sign - --timestamp=none "$BUILD_DIR/GTDPlanner"
codesign --verify --strict "$BUILD_DIR/GTDPlanner"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/GTDPlanner" "$APP_DIR/Contents/MacOS/GTDPlanner"
cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
# Keep the copied executable's valid signature; Launch Services can launch an
# app bundle with a signed executable even when FileProvider adds metadata to
# the outer bundle after the copy.
xattr -cr "$APP_DIR" 2>/dev/null || true
echo "Built: $APP_DIR"
