#!/bin/zsh
# Build a manual UI preview. This command does not open a window.
set -euo pipefail
cd "${0:A:h:h}"
if [[ "${1:-}" == "--help" ]]; then
    print 'Build an isolated manual Agents Settings preview. The printed app must be opened separately.'
    exit 0
fi
[[ $# == 0 ]] || { print -u2 'No arguments are supported.'; exit 2; }
swift build --product AgentContracts
preview_root="$PWD/.build/manual-agent-settings"
preview_app="$preview_root/Draftly Agents UI Preview.app"
mkdir -p "$preview_app/Contents/MacOS"
preview_debug="$(swift build --show-bin-path)"
xcrun swiftc -parse-as-library -swift-version 6 -package-name draftly \
    -module-name DraftlyAgentsUIPreview -target "$(uname -m)-apple-macos26.0" \
    -I "$preview_debug" -L "$preview_debug" -lAgentContracts \
    Sources/Draftly/AgentConnectionRecord.swift \
    Sources/Draftly/AgentConnectionRegistry.swift \
    Sources/Draftly/AgentPairingCoordinator.swift \
    Sources/Draftly/AgentGrantEditingCopy.swift \
    Sources/Draftly/AgentConnectionsSettingsModel.swift \
    Sources/Draftly/AgentPermissionPresentation.swift \
    Sources/Draftly/AgentConnectionsSettingsView.swift \
    Tools/AgentSettingsPreview/main.swift \
    -o "$preview_app/Contents/MacOS/DraftlyAgentsUIPreview"
python3 - "$preview_app/Contents/Info.plist" <<'PY'
import plistlib
import sys
with open(sys.argv[1], 'wb') as output:
    plistlib.dump({
        'CFBundleIdentifier': 'com.pobrespandas.draftly.agent-settings-preview',
        'CFBundleExecutable': 'DraftlyAgentsUIPreview',
        'CFBundleName': 'Draftly Agents UI Preview',
        'CFBundlePackageType': 'APPL',
        'CFBundleShortVersionString': '1',
        'CFBundleVersion': '1',
        'LSMinimumSystemVersion': '26.0',
        'NSQuitAlwaysKeepsWindows': False,
    }, output)
PY
codesign --force --sign - "$preview_app"
print "$preview_app"
