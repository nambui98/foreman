#!/usr/bin/env bash
# Build a Release copy of Foreman and zip it for a GitHub release.
# Usage: scripts/package-release.sh   → release/Foreman-<version>.zip
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild -project Foreman.xcodeproj -scheme Foreman -configuration Release -derivedDataPath build -quiet build
APP="build/Build/Products/Release/Foreman.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
mkdir -p release
ZIP="release/Foreman-$VERSION.zip"
rm -f "$ZIP"
# ditto keeps the bundle's symlinks, extended attributes and ad-hoc signature intact.
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP"
