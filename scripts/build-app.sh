#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mode="${1:---local}"
if [[ "$mode" == "--icloud" ]]; then
    xcodebuild -project Draftly.xcodeproj -scheme Draftly -configuration Debug \
        -derivedDataPath .build/xcode -allowProvisioningUpdates build
elif [[ "$mode" == "--local" ]]; then
    xcodebuild -project Draftly.xcodeproj -scheme Draftly -configuration Debug \
        -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO \
        CODE_SIGN_ENTITLEMENTS= DRAFTLY_CLOUDKIT_CONTAINER= build
    codesign --force --sign - .build/xcode/Build/Products/Debug/Draftly.app
else
    print -u2 "Usage: scripts/build-app.sh [--local|--icloud]"
    exit 2
fi
print "App: $PWD/.build/xcode/Build/Products/Debug/Draftly.app"
