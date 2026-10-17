#!/bin/zsh
# Builds a universal (Apple Silicon + Intel) release of the Mac app into build/,
# plus a zip to copy to another Mac. On first launch there, right-click the app and choose Open.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen --quiet
xcodebuild -project Imprint.xcodeproj -scheme Imprint-Mac -configuration Release \
    -destination "generic/platform=macOS" -derivedDataPath build/DerivedData ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    -quiet build

rm -rf build/Imprint.app build/Imprint.zip
cp -R build/DerivedData/Build/Products/Release/Imprint.app build/
ditto -c -k --keepParent build/Imprint.app build/Imprint.zip
echo "Built build/Imprint.app and build/Imprint.zip"
