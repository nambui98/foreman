#!/usr/bin/env bash
# Build a Release copy of Foreman and zip it for a GitHub release, as three downloads:
#   release/Foreman-<version>-universal.zip      Apple silicon + Intel (one binary)
#   release/Foreman-<version>-apple-silicon.zip  arm64 only
#   release/Foreman-<version>-intel.zip          x86_64 only
# Usage: scripts/package-release.sh
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild -project Foreman.xcodeproj -scheme Foreman -configuration Release -derivedDataPath build -quiet build
APP="build/Build/Products/Release/Foreman.app"
# Refuse to ship a single-architecture build: the release must run on Apple silicon and Intel.
ARCHS=$(lipo -archs "$APP/Contents/MacOS/Foreman")
for arch in arm64 x86_64; do
  [[ " $ARCHS " == *" $arch "* ]] || { echo "missing $arch slice (got: $ARCHS)" >&2; exit 1; }
done
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
mkdir -p release
rm -f release/Foreman-"$VERSION"*.zip

# zip_app <app bundle> <suffix>: ditto keeps symlinks, extended attributes and the signature intact.
zip_app() {
  local zip="release/Foreman-$VERSION-$2.zip"
  ditto -c -k --keepParent "$1" "$zip"
  shasum -a 256 "$zip"
}

zip_app "$APP" universal

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
for pair in "arm64:apple-silicon" "x86_64:intel"; do
  arch=${pair%%:*}; suffix=${pair#*:}
  mkdir -p "$WORK/$suffix"
  ditto "$APP" "$WORK/$suffix/Foreman.app"
  lipo "$APP/Contents/MacOS/Foreman" -thin "$arch" -output "$WORK/$suffix/Foreman.app/Contents/MacOS/Foreman"
  # Thinning changes the executable, so the ad-hoc signature has to be redone.
  codesign --force --sign - "$WORK/$suffix/Foreman.app"
  codesign --verify "$WORK/$suffix/Foreman.app"
  zip_app "$WORK/$suffix/Foreman.app" "$suffix"
done
