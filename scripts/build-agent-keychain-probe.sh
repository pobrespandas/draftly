#!/bin/zsh
# Compile a manual acceptance tool. This script does not sign or run it.
set -euo pipefail
cd "${0:A:h:h}"
if [[ "${1:-}" == "--help" ]]; then
    print 'Compile the manual agent Keychain probe. Signing and execution are separate manual steps.'
    exit 0
fi
[[ $# == 0 ]] || { print -u2 'No arguments are supported.'; exit 2; }
swift build --product AgentLocalSecurity
probe_debug="$(swift build --show-bin-path)"
probe_root="$PWD/.build/manual-agent-keychain"
mkdir -p "$probe_root"
xcrun swiftc -parse-as-library -swift-version 6 -package-name draftly \
    -target "$(uname -m)-apple-macos26.0" \
    -I "$probe_debug" -I "$probe_debug/Modules" -L "$probe_debug" -lAgentLocalSecurity -lAgentContracts \
    Tools/AgentKeychainProbe/main.swift -o "$probe_root/AgentKeychainProbe"
print "$probe_root/AgentKeychainProbe"
