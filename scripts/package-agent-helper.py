#!/usr/bin/env python3
"""Prepare a signed agent helper in a new isolated output directory."""
import argparse
import datetime
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

TEAM = "NM92LU2KKV"
IDENTIFIER = "com.pobrespandas.draftly.agent"
GROUP = TEAM + ".com.pobrespandas.draftly.agent-access"
UNSAFE = ("com.apple.security.get-task-allow", "get-task-allow",
          "com.apple.security.cs.disable-library-validation",
          "com.apple.security.cs.allow-dyld-environment-variables",
          "com.apple.security.cs.allow-unsigned-executable-memory")


def validate_profile(profile, now=None):
    now = now or datetime.datetime.now(datetime.timezone.utc)
    if not isinstance(profile, dict) or not isinstance(profile.get("Entitlements"), dict):
        raise ValueError("The helper profile has invalid entitlements.")
    expiry = profile.get("ExpirationDate")
    if not isinstance(expiry, datetime.datetime):
        raise ValueError("The helper profile has no expiration date.")
    if expiry.tzinfo is None:
        expiry = expiry.replace(tzinfo=datetime.timezone.utc)
    allowed = profile.get("Entitlements", {})
    if (expiry <= now or profile.get("TeamIdentifier") != [TEAM]
            or allowed.get("com.apple.application-identifier") != TEAM + "." + IDENTIFIER
            or allowed.get("com.apple.developer.team-identifier") != TEAM):
        raise ValueError("The helper profile has expired or has a different identity.")
    groups = allowed.get("keychain-access-groups", [])
    if not isinstance(groups, list) or not any(g in groups for g in [GROUP, TEAM + ".*"]):
        raise ValueError("The helper profile does not permit the agent Keychain group.")
    certificates = profile.get("DeveloperCertificates")
    if not isinstance(certificates, list) or not certificates or not all(isinstance(c, bytes) and c for c in certificates):
        raise ValueError("The helper profile has no signing certificates.")


def run(command, capture=False):
    result = subprocess.run(command, check=True, capture_output=capture)
    return result.stdout if capture else b""


def package(executable, profile_path, output, identity, version, build, runner=run):
    executable, profile_path, output = Path(executable), Path(profile_path), Path(output)
    if (executable.is_symlink() or not executable.is_file() or profile_path.is_symlink()
            or not profile_path.is_file()):
        raise ValueError("Use regular executable and profile files.")
    if not identity or identity.startswith("-") or any(c in identity for c in "\n\r\0"):
        raise ValueError("Specify a signing identity.")
    if not version or not build or any(c in version + build for c in "\n\r\0"):
        raise ValueError("Specify the helper version and build.")
    profile_bytes = profile_path.read_bytes()
    profile = plistlib.loads(runner(["security", "cms", "-D", "-i", str(profile_path)], capture=True))
    validate_profile(profile)
    if profile_path.read_bytes() != profile_bytes:
        raise ValueError("The helper profile changed during validation.")
    # Reserve a new output. Failures leave only this isolated candidate for inspection.
    output.mkdir(parents=False, exist_ok=False)
    app = output / "DraftlyAgent.app"
    contents = app / "Contents"
    (contents / "MacOS").mkdir(parents=True)
    shutil.copyfile(executable, contents / "MacOS/draftly-agent")
    (contents / "MacOS/draftly-agent").chmod(0o755)
    (contents / "embedded.provisionprofile").write_bytes(profile_bytes)
    info = {"CFBundleIdentifier": IDENTIFIER, "CFBundleName": "Draftly Agent",
            "CFBundleExecutable": "draftly-agent", "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": version, "CFBundleVersion": build,
            "LSUIElement": True, "LSMinimumSystemVersion": "26.0"}
    (contents / "Info.plist").write_bytes(plistlib.dumps(info))
    rights = {"com.apple.application-identifier": TEAM + "." + IDENTIFIER,
              "com.apple.developer.team-identifier": TEAM, "keychain-access-groups": [GROUP]}
    with tempfile.TemporaryDirectory(prefix="draftly-agent-signing-") as work:
        entitlements = Path(work) / "entitlements.plist"
        entitlements.write_bytes(plistlib.dumps(rights))
        runner(["codesign", "--force", "--sign", identity, "--options", "runtime", "--timestamp",
                "--entitlements", str(entitlements), str(app)])
        requirement = ('=anchor apple generic and certificate leaf[subject.OU] = "' + TEAM
                       + '" and identifier "' + IDENTIFIER + '"')
        runner(["codesign", "--verify", "--deep", "--strict", "-R", requirement, str(app)])
        actual = plistlib.loads(runner(["codesign", "-d", "--entitlements", ":-", str(app)], capture=True))
        if any(actual.get(key) != value for key, value in rights.items()) or any(
                key in actual and actual[key] is not False for key in UNSAFE):
            raise ValueError("The signed helper has unexpected entitlements.")
        certificate = str(Path(work) / "certificate")
        runner(["codesign", "-d", "--extract-certificates=" + certificate, str(app)])
        if Path(certificate + "0").read_bytes() not in profile["DeveloperCertificates"]:
            raise ValueError("The signing certificate is not permitted by the helper profile.")
    return {"app": str(app.absolute()), "bundleIdentifier": IDENTIFIER,
            "keychainSharingVerified": False, "notarizationVerified": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["executable", "profile", "output", "identity", "version", "build"]:
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(package(args.executable, args.profile, args.output, args.identity, args.version, args.build), indent=2))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit("Agent packaging failed: " + str(error))


if __name__ == "__main__":
    main()
