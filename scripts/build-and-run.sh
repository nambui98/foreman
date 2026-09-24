#!/usr/bin/env bash
# Regenerate the Xcode project, build PortBar, and (re)launch it from the local build.
# Usage: scripts/build-and-run.sh [Debug|Release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-Debug}"
xcodegen generate --quiet
xcodebuild -project PortBar.xcodeproj -scheme PortBar -configuration "$CONFIG" \
  -derivedDataPath build -quiet build
APP="build/Build/Products/$CONFIG/PortBar.app"
pkill -x PortBar 2>/dev/null || true
# Wait for the old instance to exit, otherwise `open` fails with LaunchServices error -600.
while pgrep -x PortBar >/dev/null; do sleep 0.2; done
open "$APP"
echo "Launched $APP"
