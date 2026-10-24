#!/bin/zsh
# Builds a universal (Apple Silicon + Intel) release of the Mac app into build/,
# plus a zip to copy to another Mac. On first launch there, right-click the app and choose Open.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen --quiet
xcodebuild -project Point.xcodeproj -scheme Point-Mac -configuration Release \
    -destination "generic/platform=macOS" -derivedDataPath build/DerivedData ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    -quiet build

rm -rf build/Point.app build/Point.zip
cp -R build/DerivedData/Build/Products/Release/Point.app build/
ditto -c -k --keepParent build/Point.app build/Point.zip
echo "Built build/Point.app and build/Point.zip"
