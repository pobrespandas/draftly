#!/usr/bin/env python3
"""Check the signed app against its embedded provisioning profile."""
import argparse
import datetime
import json
import plistlib
import re
from pathlib import Path
import subprocess


def read_plist(command):
    return plistlib.loads(subprocess.check_output(command, stderr=subprocess.DEVNULL))


def verify_developer_id(metadata, team):
    authorities = [line for line in metadata.splitlines() if line.startswith("Authority=Developer ID Application: ")]
    if len(authorities) != 1 or not authorities[0].endswith(f" ({team})"):
        raise ValueError("The signature is not a Developer ID Application for the expected team.")
    if not re.search(r"flags=0x[0-9a-fA-F]+\([^\n)]*\bruntime\b", metadata):
        raise ValueError("The signature does not enable hardened runtime.")


def verify(app, *, expected_bundle_identifier=None, expected_team=None, expected_container=None,
           expected_cloud_environment=None, expected_push_environment=None, require_developer_id=False):
    app = Path(app)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    rights = read_plist(["codesign", "-d", "--entitlements", ":-", str(app)])
    profile = read_plist(["security", "cms", "-D", "-i", str(app / "Contents/embedded.provisionprofile")])
    allowed = profile["Entitlements"]
    container = info.get("DraftlyCloudKitContainer", "")
    if not container or container.startswith("$("):
        raise ValueError("The app has no resolved CloudKit container.")
    if container not in rights.get("com.apple.developer.icloud-container-identifiers", []):
        raise ValueError("The signature does not include the configured CloudKit container.")
    if container not in allowed.get("com.apple.developer.icloud-container-identifiers", []):
        raise ValueError("The profile does not permit the CloudKit container.")
    if "CloudKit" not in rights.get("com.apple.developer.icloud-services", []):
        raise ValueError("The signature does not enable CloudKit.")
    team = rights.get("com.apple.developer.team-identifier")
    if not team or team not in profile.get("TeamIdentifier", []):
        raise ValueError("The signature team does not match the profile.")
    if expected_bundle_identifier is not None and info["CFBundleIdentifier"] != expected_bundle_identifier:
        raise ValueError("The bundle identifier does not match the expected bundle identifier.")
    if expected_team is not None and team != expected_team:
        raise ValueError("The signature team does not match the expected team.")
    if expected_container is not None and container != expected_container:
        raise ValueError("The configured CloudKit container does not match the expected container.")
    application = rights.get("com.apple.application-identifier")
    if application != f"{team}.{info['CFBundleIdentifier']}" or application != allowed.get("com.apple.application-identifier"):
        raise ValueError("The app identity does not match the profile.")
    environment = rights.get("com.apple.developer.icloud-container-environment")
    if environment not in allowed.get("com.apple.developer.icloud-container-environment", []):
        raise ValueError("The profile does not permit the CloudKit environment.")
    if expected_cloud_environment is not None and environment != expected_cloud_environment:
        raise ValueError("The CloudKit environment does not match the expected environment.")
    push = rights.get("com.apple.developer.aps-environment")
    if not push or push != allowed.get("com.apple.developer.aps-environment"):
        raise ValueError("The push environment does not match the profile.")
    if expected_push_environment is not None and push != expected_push_environment:
        raise ValueError("The push environment does not match the expected environment.")
    if require_developer_id:
        if rights.get("com.apple.security.get-task-allow", False):
            raise ValueError("A Developer ID distribution cannot enable get-task-allow.")
        signature = subprocess.run(["codesign", "-d", "--verbose=4", str(app)], check=True,
                                   capture_output=True, text=True)
        verify_developer_id(signature.stdout + "\n" + signature.stderr, team)
    if profile["ExpirationDate"] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
        raise ValueError("The provisioning profile has expired.")
    return {"bundleIdentifier": info["CFBundleIdentifier"], "version": info["CFBundleShortVersionString"],
            "build": info["CFBundleVersion"], "teamIdentifier": team, "teamName": profile.get("TeamName"),
            "container": container, "cloudEnvironment": environment, "pushEnvironment": push,
            "profileExpires": profile["ExpirationDate"].isoformat() + "Z",
            "registeredDeviceCount": len(profile.get("ProvisionedDevices", [])),
            "notarizationVerified": False}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", help="Path to the signed app bundle.")
    parser.add_argument("--expected-bundle-identifier", help="Required bundle identifier, when specified.")
    parser.add_argument("--expected-team", help="Required signing team, when specified.")
    parser.add_argument("--expected-container", help="Required CloudKit container, when specified.")
    parser.add_argument("--expected-cloud-environment", choices=["Development", "Production"])
    parser.add_argument("--expected-push-environment", choices=["development", "production"])
    parser.add_argument("--require-developer-id", action="store_true")
    args = parser.parse_args(argv)
    try:
        print(json.dumps(verify(args.app, expected_bundle_identifier=args.expected_bundle_identifier,
                                expected_team=args.expected_team, expected_container=args.expected_container,
                                expected_cloud_environment=args.expected_cloud_environment,
                                expected_push_environment=args.expected_push_environment,
                                require_developer_id=args.require_developer_id), indent=2))
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"Signing check failed: {error}")


if __name__ == "__main__":
    main()
