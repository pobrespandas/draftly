#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mode="${1:---local}"
case "$mode" in
    --local)
        output=.build/xcode
        configuration=Debug
        signing=(CODE_SIGNING_ALLOWED=NO CODE_SIGN_ENTITLEMENTS= DRAFTLY_CLOUDKIT_CONTAINER=)
        ;;
    --icloud)
        output=.build/icloud
        configuration=Debug
        signing=(-allowProvisioningUpdates -allowProvisioningDeviceRegistration)
        ;;
    --cloud-qa)
        output=.build/cloud-qa
        configuration=Debug
        mkdir -p .build/cloud-qa-config
        python3 scripts/prepare-cloud-qa.py .build/cloud-qa-config/Info.plist
        signing=(-allowProvisioningUpdates -allowProvisioningDeviceRegistration
            PRODUCT_BUNDLE_IDENTIFIER=com.andrestobelem.draftly.cloud-qa
            DRAFTLY_CLOUDKIT_CONTAINER=iCloud.com.andrestobelem.draftly.cloudqa
            "INFOPLIST_FILE=$PWD/.build/cloud-qa-config/Info.plist")
        ;;
    --personal)
        output=.build/personal
        configuration=Release
        signing=(-allowProvisioningUpdates -allowProvisioningDeviceRegistration)
        ;;
    *)
        print -u2 "Usage: scripts/build-app.sh [--local|--icloud|--cloud-qa|--personal]"
        exit 2
        ;;
esac
output="${DRAFTLY_BUILD_OUTPUT:-$output}"
if [[ "$mode" != "--local" && -n "${DRAFTLY_PROVISIONING_PROFILE:-}" ]]; then
    manual_signing=()
    for argument in "${signing[@]}"; do
        if [[ "$argument" != "-allowProvisioningUpdates" && "$argument" != "-allowProvisioningDeviceRegistration" ]]; then
            manual_signing+=("$argument")
        fi
    done
    signing=("${manual_signing[@]}" "DRAFTLY_CODE_SIGN_STYLE=Manual" "DRAFTLY_PROVISIONING_PROFILE=$DRAFTLY_PROVISIONING_PROFILE")
fi
xcodebuild -project Draftly.xcodeproj -scheme Draftly -configuration "$configuration" \
    -derivedDataPath "$output" "${signing[@]}" build
app="${output:a}/Build/Products/$configuration/Draftly.app"
if [[ "$mode" == "--local" ]]; then
    # Xcode removes public headers when embedding Sparkle. Reseal the local
    # framework before signing the app so strict verification can succeed.
    if [[ -d "$app/Contents/Frameworks/Sparkle.framework" ]]; then
        codesign --force --sign - "$app/Contents/Frameworks/Sparkle.framework/Versions/B"
    fi
    codesign --force --sign - "$app"
else
    python3 scripts/verify-cloud-signing.py "$app"
fi
codesign --verify --deep --strict "$app"
print "App: $app"
