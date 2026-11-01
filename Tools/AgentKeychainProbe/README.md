# Manual agent Keychain acceptance

This tool checks the real AgentCredentialKeychain adapter between two signed
processes. It is not part of the app or the automatic test suites.

Run `scripts/build-agent-keychain-probe.sh` to compile it. That command does not
sign, launch, read Keychain, or create a credential.

For a manual acceptance session:

1. Put the compiled probe in an isolated app-like wrapper. Use the principal
   application identifier, its embedded profile, team entitlement and exact agent
   Keychain group from ADR 0001. Sign with hardened runtime and the existing
   Developer ID certificate. Do not register or install this test wrapper.
2. Use `package-agent-helper.py` with the same compiled probe as its executable
   and the helper profile. This creates a second wrapper with the helper identity.
3. Run the application-role executable with `exercise` and the absolute path to
   the helper-role executable. The program creates a random connection UUID and
   32-byte credential, checks the application read, passes only that neutral
   credential through a pipe to the helper, and compares the helper result.
4. Require `Signed adapter sharing and cleanup passed.` The application removes
   the neutral item and checks that it is absent before printing this result.
   If cleanup fails, it reports the neutral connection UUID for recovery. Never
   substitute an existing connection UUID or a user's credential.

The helper `read` mode receives the expected value on standard input and prints
only `matched`. It never prints a credential or enumerates items. An unsigned
exercise must fail identity validation before creating an item.

A successful session proves adapter sharing for those two signed packages on
that Mac. It does not prove normal app embedding, notarization, replacement by a
new helper version, graphical lock handling or permission lifecycle behavior.
Keep those acceptance cases separate. Never run this tool automatically in CI.
