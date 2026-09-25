#!/usr/bin/env bash
# Build a Release copy of Foreman and package it as drag-to-install disk images:
#   release/Foreman-<version>-apple-silicon.dmg  arm64 only
#   release/Foreman-<version>-intel.dmg          x86_64 only
#   release/Foreman-<version>-universal.dmg      Apple silicon + Intel (one binary)
# Each image holds Foreman.app next to an Applications shortcut.
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
rm -f release/Foreman-"$VERSION"*

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# make_dmg <suffix> <arch or "universal">: stage the app (thinned and re-signed ad hoc when a single
# architecture is asked for) beside an Applications link, then write a compressed read-only image.
make_dmg() {
  local suffix=$1 arch=$2 stage="$WORK/$1"
  mkdir -p "$stage"
  ditto "$APP" "$stage/Foreman.app"
  if [[ $arch != universal ]]; then
    lipo "$APP/Contents/MacOS/Foreman" -thin "$arch" -output "$stage/Foreman.app/Contents/MacOS/Foreman"
    codesign --force --sign - "$stage/Foreman.app"
  fi
  codesign --verify "$stage/Foreman.app"
  ln -s /Applications "$stage/Applications"
  local dmg="release/Foreman-$VERSION-$suffix.dmg"
  hdiutil create -quiet -volname "Foreman $VERSION" -srcfolder "$stage" -format UDZO -fs HFS+ -ov "$dmg"
  shasum -a 256 "$dmg"
}

make_dmg apple-silicon arm64
make_dmg intel x86_64
make_dmg universal universal
