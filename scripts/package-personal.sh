#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
scripts/build-app.sh --personal
app=.build/personal/Build/Products/Release/Draftly.app
output=.build/distribution
mkdir -p "$output"
python3 scripts/verify-cloud-signing.py "$app" > "$output/signing-report.json"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output/Draftly-personal.zip"
shasum -a 256 "$output/Draftly-personal.zip" > "$output/Draftly-personal.zip.sha256"
print "Package: $PWD/$output/Draftly-personal.zip"
print "This development build requires a registered Mac. See docs/icloud-distribution.md."
