#!/usr/bin/env bash
# Regenerate the Xcode project and run the unit tests.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild -project Foreman.xcodeproj -scheme Foreman -derivedDataPath build -quiet test
