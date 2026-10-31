#!/bin/bash
# Build a release candidate on an ephemeral GitHub-hosted macOS runner.
set +x
set -euo pipefail
umask 077

if [[ "${GITHUB_ACTIONS:-}" != "true" || "${RUNNER_ENVIRONMENT:-}" != "github-hosted" ]]; then
    echo "Release signing requires a GitHub-hosted runner." >&2
    exit 1
fi
for name in RUNNER_TEMP RELEASE_TAG DRAFTLY_DEVELOPER_ID_PROFILE DRAFTLY_SPARKLE_PUBLIC_KEY \
    APPLE_DEVELOPER_ID_P12_B64 APPLE_DEVELOPER_ID_P12_PASSWORD APPLE_DEVELOPER_ID_PROFILE_B64 \
    APPLE_NOTARY_API_KEY_B64 APPLE_NOTARY_KEY_ID APPLE_NOTARY_ISSUER_ID; do
    if [[ -z "${!name:-}" ]]; then
        echo "Release signing configuration is incomplete: $name." >&2
        exit 1
    fi
done
if [[ ! "$RELEASE_TAG" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "The release tag is invalid." >&2
    exit 1
fi
python3 scripts/release-toolchain.py
python3 - <<'PY'
import base64, os
try:
    key = base64.b64decode(os.environ['DRAFTLY_SPARKLE_PUBLIC_KEY'], validate=True)
except ValueError:
    raise SystemExit('The Sparkle public key is invalid.')
if len(key) != 32:
    raise SystemExit('The Sparkle public key must contain 32 bytes.')
PY

workdir="$(mktemp -d "${RUNNER_TEMP}/draftly-signing.XXXXXXXX")"
keychain="$workdir/release.keychain-db"
profile_path=""
profile_owned=0
cleanup() {
    if [[ "$profile_owned" == "1" ]]; then rm -f "$profile_path"; fi
    security delete-keychain "$keychain" >/dev/null 2>&1 || true
    rm -rf "$workdir"
}
trap cleanup EXIT

keychain_password="$(openssl rand -hex 32)"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -l -u -t 7200 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security list-keychains -d user -s "$keychain"
security default-keychain -d user -s "$keychain"

printf '%s' "$APPLE_DEVELOPER_ID_P12_B64" | base64 -D > "$workdir/identity.p12"
security import "$workdir/identity.p12" -k "$keychain" -P "$APPLE_DEVELOPER_ID_P12_PASSWORD" \
    -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null

printf '%s' "$APPLE_DEVELOPER_ID_PROFILE_B64" | base64 -D > "$workdir/profile.provisionprofile"
security cms -D -i "$workdir/profile.provisionprofile" > "$workdir/profile.plist"
profile_uuid="$(python3 - "$workdir/profile.plist" <<'PY'
import plistlib, re, sys
with open(sys.argv[1], 'rb') as source:
    uuid = plistlib.load(source).get('UUID')
if not isinstance(uuid, str) or not re.fullmatch(r'[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}', uuid):
    raise SystemExit('The signing profile UUID is invalid.')
print(uuid)
PY
)"
profile_dir="${DRAFTLY_CI_PROFILE_DIRECTORY:-${HOME}/Library/MobileDevice/Provisioning Profiles}"
mkdir -p "$profile_dir"
profile_path="$profile_dir/$profile_uuid.provisionprofile"
if [[ -e "$profile_path" || -L "$profile_path" ]]; then
    echo "The signing profile destination already exists." >&2
    exit 1
fi
python3 - "$workdir/profile.provisionprofile" "$profile_path" <<'PY'
import os, shutil, sys
with open(sys.argv[1], 'rb') as source:
    target = open(sys.argv[2], 'xb')
    try:
        with target:
            shutil.copyfileobj(source, target)
    except BaseException:
        os.unlink(sys.argv[2])
        raise
PY
profile_owned=1

printf '%s' "$APPLE_NOTARY_API_KEY_B64" | base64 -D > "$workdir/notary.p8"
notary_options=(--key "$workdir/notary.p8" --key-id "$APPLE_NOTARY_KEY_ID" --issuer "$APPLE_NOTARY_ISSUER_ID" --keychain "$keychain")
xcrun notarytool store-credentials "Draftly Release CI" "${notary_options[@]}"

# The build and its tools do not need the original CI secret values.
unset APPLE_DEVELOPER_ID_P12_B64 APPLE_DEVELOPER_ID_P12_PASSWORD APPLE_DEVELOPER_ID_PROFILE_B64 \
    APPLE_NOTARY_API_KEY_B64 APPLE_NOTARY_KEY_ID APPLE_NOTARY_ISSUER_ID \
    DRAFTLY_SPARKLE_PRIVATE_KEY DRAFTLY_FIREBASE_ACCESS_TOKEN GH_TOKEN GITHUB_TOKEN
python3 scripts/package-release.py --tag "$RELEASE_TAG" \
    --output ".build/release-candidates/$RELEASE_TAG" --profile "$DRAFTLY_DEVELOPER_ID_PROFILE" \
    --notary-profile "Draftly Release CI" --public-key "$DRAFTLY_SPARKLE_PUBLIC_KEY" --dmg
