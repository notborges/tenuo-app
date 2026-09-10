#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT
xcrun actool TenuoPro.icon Assets.xcassets --compile "$BUILD_DIR" \
    --output-format human-readable-text --output-partial-info-plist "$BUILD_DIR/partial.plist" \
    --app-icon TenuoPro --include-all-app-icons --enable-on-demand-resources NO \
    --development-region en --target-device mac --minimum-deployment-target 15.0 --platform macosx
cp "$BUILD_DIR/TenuoPro.icns" ../../Tenuo/Resources/TenuoPro.icns
