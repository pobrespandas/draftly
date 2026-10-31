#!/usr/bin/env python3
"""Stop unchanged releases before allocating a signing or native runner."""
import argparse
import importlib.util
from pathlib import Path
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('release_history', ROOT / 'scripts/release-history.py')
history = importlib.util.module_from_spec(spec)
spec.loader.exec_module(history)
PACKAGE_ROOTS = ('Sources/', 'Resources/', 'Vendor/', 'Configuration/', 'Draftly.xcodeproj/')
PACKAGE_FILES = {'Package.swift', 'Package.resolved', 'scripts/build-app.sh',
                 'scripts/package-release.py', 'scripts/release-dmg.py', 'scripts/release-toolchain.py'}


def latest_tag(releases):
    versions = []
    for release in releases:
        if not isinstance(release, dict) or not isinstance(release.get('draft'), bool) or not isinstance(release.get('prerelease'), bool):
            raise ValueError('Invalid release history.')
        if release['draft'] or release['prerelease']:
            continue
        tag = release.get('tag_name', '')
        if not isinstance(tag, str) or not tag.startswith('v'):
            raise ValueError('Invalid published version tag.')
        versions.append((history.version_tuple(tag[1:]), tag))
    return max(versions)[1] if versions else None


def package_path(path):
    if path in PACKAGE_FILES or path.startswith(PACKAGE_ROOTS):
        return True
    if path.endswith('.md') or path.startswith(('Tests/', 'docs/', 'website/', 'scripts/',
                                               '.github/', '.agents/', '.claude/', 'Tools/')):
        return False
    return path not in ('.gitignore', 'LICENSE', 'skills-lock.json')


def changed_package(base, head, run=subprocess.check_output):
    for value in (base, head):
        if not re.fullmatch(r'[a-f0-9]{40}', value):
            raise ValueError('Package comparison requires full commit identities.')
    subprocess.run(['git', 'merge-base', '--is-ancestor', base, head], cwd=ROOT, check=True, capture_output=True)
    paths = run(['git', 'diff', '--name-only', '--no-renames', '-z', base, head, '--'], cwd=ROOT)
    for raw in paths.split(b'\0'):
        if not raw:
            continue
        path = raw.decode('utf-8')
        if path == 'Configuration/Info.plist':
            values = []
            for commit in (base, head):
                value = plistlib.loads(run(['git', 'show', commit + ':' + path], cwd=ROOT))
                for key in ('CFBundleShortVersionString', 'CFBundleVersion'):
                    value.pop(key, None)
                values.append(value)
            if values[0] == values[1]:
                continue
        if package_path(path):
            return True
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--resume-run-id', default='')
    args = parser.parse_args()
    if args.resume_run_id:
        if not re.fullmatch(r'[1-9][0-9]*', args.resume_run_id):
            raise ValueError('Invalid recovery run identity.')
        print('package=true')
        return
    tag = latest_tag(history.fetch_releases())
    if tag is None:
        print('package=true')
        return
    def commit(ref):
        return subprocess.check_output(['git', 'rev-parse', '--verify', ref + '^{commit}'], cwd=ROOT, text=True).strip()
    changed = changed_package(commit('refs/tags/' + tag), commit('HEAD'))
    print('package=' + str(changed).lower())
    if not changed:
        print('No package changes since the latest published version.', file=sys.stderr)


if __name__ == '__main__':
    main()
