#!/usr/bin/env python3
"""Build a notarized Developer ID candidate without publishing it."""

import argparse
import base64
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parent.parent
TEAM = "NM92LU2KKV"
BUNDLE = "com.pobrespandas.draftly"
CONTAINER = "iCloud.com.andrestobelem.draftly"
FEED = "https://draftly.pobrespandas.com/appcast.xml"


def validate_key(value):
    try:
        decoded = base64.b64decode(value, validate=True)
    except (ValueError, TypeError) as error:
        raise ValueError("The Sparkle public key is not valid base64.") from error
    if len(decoded) != 32:
        raise ValueError("The Sparkle public key must contain 32 bytes.")


def validate_metadata(source, built, *, public_key=None):
    version = source.get("CFBundleShortVersionString")
    build = source.get("CFBundleVersion")
    if not isinstance(version, str) or not re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", version):
        raise ValueError("The source version must use MAJOR.MINOR.PATCH.")
    if not isinstance(build, str) or not re.fullmatch(r"[1-9]\d*", build):
        raise ValueError("The source build must be a positive integer.")
    for key, expected in (("CFBundleIdentifier", BUNDLE), ("CFBundleName", "Draftly"),
                          ("CFBundleShortVersionString", version), ("CFBundleVersion", build)):
        if built.get(key) != expected:
            raise ValueError("The built app has an unexpected " + key + ".")
    urls = built.get("CFBundleURLTypes", [])
    if not isinstance(urls, list) or not any(
            isinstance(item, dict) and isinstance(item.get("CFBundleURLSchemes"), list)
            and "draftly" in item["CFBundleURLSchemes"] for item in urls):
        raise ValueError("The built app does not register draftly://.")
    if public_key is not None:
        validate_key(public_key)
        if (built.get("DraftlyUpdatesEnabled") != "YES" or built.get("SUPublicEDKey") != public_key
                or built.get("SUFeedURL") != FEED or built.get("SUAutomaticallyUpdate") is not False
                or built.get("SUAllowsAutomaticUpdates") is not False
                or built.get("SUEnableAutomaticChecks") is not True
                or built.get("SURequireSignedFeed") is not True
                or built.get("SUVerifyUpdateBeforeExtraction") is not True):
            raise ValueError("The built app has an unexpected update configuration.")
    elif built.get("DraftlyUpdatesEnabled") == "YES":
        raise ValueError("The built app unexpectedly enables updates.")
    return version, build


def run_command(command, *, runner=subprocess.run, capture=False):
    result = runner(command, cwd=ROOT, check=True, text=True, capture_output=capture)
    return result.stdout if capture else ""


def read_json(output, description):
    try:
        value = json.loads(output)
    except (TypeError, json.JSONDecodeError) as error:
        raise ValueError(description + " did not return valid JSON.") from error
    if not isinstance(value, dict):
        raise ValueError(description + " did not return an object.")
    return value


def source_commit(tag, runner):
    if run_command(["git", "status", "--porcelain", "--untracked-files=normal"], runner=runner, capture=True).strip():
        raise ValueError("The source tree must be clean before building a candidate.")
    commit = run_command(["git", "rev-parse", "--verify", "HEAD^{commit}"], runner=runner, capture=True).strip()
    tagged = run_command(["git", "rev-parse", "--verify", "refs/tags/" + tag + "^{commit}"],
                         runner=runner, capture=True).strip()
    if not re.fullmatch(r"[a-f0-9]{40}", commit) or tagged != commit:
        raise ValueError("The candidate tag must identify the current commit.")
    return commit


def package(output, profile, notary_profile, tag, *, public_key=None, runner=subprocess.run):
    if not profile or notary_profile.startswith("-") or not notary_profile or "\n" in profile + notary_profile:
        raise ValueError("A signing profile and a Keychain notary profile are required.")
    if public_key is not None:
        validate_key(public_key)
    output = Path(output).absolute()
    if output.exists() or output.is_symlink():
        raise FileExistsError("The candidate destination already exists: " + str(output))
    source = plistlib.loads((ROOT / "Configuration/Info.plist").read_bytes())
    version = source.get("CFBundleShortVersionString")
    if (not isinstance(version, str) or not re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", version)
            or tag != "v" + version):
        raise ValueError("The candidate tag must match the source version.")
    commit = source_commit(tag, runner)
    output.parent.mkdir(parents=True, exist_ok=True)
    # This fails if the destination exists. Never overwrite a previous candidate.
    output.mkdir()
    with tempfile.TemporaryDirectory(prefix="draftly-release-") as work:
        work = Path(work)
        archive = work / "Draftly.xcarchive"
        app = archive / "Products/Applications/Draftly.app"
        command = ["xcodebuild", "-project", str(ROOT / "Draftly.xcodeproj"), "-scheme", "Draftly",
                   "-configuration", "Release", "-destination", "generic/platform=macOS",
                   "-archivePath", str(archive), "DEVELOPMENT_TEAM=" + TEAM,
                   "DRAFTLY_CODE_SIGN_STYLE=Manual", "DRAFTLY_PROVISIONING_PROFILE=" + profile,
                   "CODE_SIGN_IDENTITY=Developer ID Application", "DRAFTLY_CLOUDKIT_ENVIRONMENT=Production",
                   "DRAFTLY_APS_ENVIRONMENT=production", "DRAFTLY_UPDATES_ENABLED=" + ("YES" if public_key else "NO"),
                   "DRAFTLY_SPARKLE_PUBLIC_KEY=" + (public_key or ""), "archive"]
        run_command(command, runner=runner)
        if source_commit(tag, runner) != commit:
            raise ValueError("The source commit changed during the build.")
        built = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        version, build = validate_metadata(source, built, public_key=public_key)
        signing = read_json(run_command([sys.executable, str(ROOT / "scripts/verify-cloud-signing.py"), str(app),
                            "--expected-bundle-identifier", BUNDLE, "--expected-team", TEAM,
                            "--expected-container", CONTAINER, "--expected-cloud-environment", "Production",
                            "--expected-push-environment", "production", "--require-developer-id"],
                            runner=runner, capture=True), "Signing verification")
        # Keep the submitted bytes and receipt if the wait is interrupted.
        submission = output / "notary-submission.zip"
        run_command(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(submission)], runner=runner)
        response = read_json(run_command(["xcrun", "notarytool", "submit", str(submission), "--keychain-profile",
                             notary_profile, "--output-format", "json"], runner=runner, capture=True), "Notary submission")
        submission_id = response.get("id")
        if not isinstance(submission_id, str) or not re.fullmatch(r"[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}", submission_id):
            raise ValueError("Notary submission did not return an identifier.")
        (output / "notary-submission.json").write_text(json.dumps({"id": submission_id}) + "\n")
        result = read_json(run_command(["xcrun", "notarytool", "wait", submission_id, "--keychain-profile",
                           notary_profile, "--timeout", "30m", "--output-format", "json"],
                           runner=runner, capture=True), "Notary wait")
        if result.get("id") != submission_id or result.get("status") != "Accepted":
            raise ValueError("Apple did not accept the notarization submission.")
        run_command(["xcrun", "stapler", "staple", str(app)], runner=runner)
        run_command(["xcrun", "stapler", "validate", str(app)], runner=runner)
        run_command(["codesign", "--verify", "--deep", "--strict", str(app)], runner=runner)
        run_command(["spctl", "--assess", "--type", "execute", str(app)], runner=runner)
        package_path = output / "Draftly.zip"
        run_command(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(package_path)], runner=runner)
        checksum = hashlib.sha256()
        with package_path.open("rb") as archive_file:
            for chunk in iter(lambda: archive_file.read(1024 * 1024), b""):
                checksum.update(chunk)
        digest = checksum.hexdigest()
        (output / "Draftly.zip.sha256").write_text(digest + "  Draftly.zip\n")
        (output / "signing-report.json").write_text(json.dumps(signing, indent=2) + "\n")
        (output / "candidate.json").write_text(json.dumps({"version": version, "build": build, "tag": tag,
            "sourceCommit": commit, "sha256": digest, "notarySubmission": submission_id,
            "updatesEnabled": public_key is not None}, indent=2) + "\n")
        # READY is the final operation. Its absence means the candidate failed.
        (output / "READY").write_text("Notarized candidate. Not published.\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, help="New output directory. Existing directories are never replaced.")
    parser.add_argument("--profile", required=True, help="Installed Developer ID provisioning profile name.")
    parser.add_argument("--notary-profile", required=True, help="Keychain profile for notarytool.")
    parser.add_argument("--tag", required=True, help="Existing version tag for the clean source commit.")
    parser.add_argument("--public-key", help="Sparkle public EdDSA key. Omit to disable update checks.")
    args = parser.parse_args()
    try:
        package(args.output, args.profile, args.notary_profile, args.tag, public_key=args.public_key)
    except (OSError, ValueError, plistlib.InvalidFileException, subprocess.SubprocessError) as error:
        raise SystemExit("Release candidate failed: " + str(error))
    print("Notarized candidate is ready. Nothing was published: " + args.output)


if __name__ == "__main__":
    main()
