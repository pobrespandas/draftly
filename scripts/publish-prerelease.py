#!/usr/bin/env python3
"""Publish a verified alpha or beta without changing the stable feed or site."""
import argparse
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


verification = load('prerelease_verification', 'verify-release-candidate.py')
publisher = load('stable_publisher', 'publish-github-release.py')
stage = verification.stage


class GitHub(stage.GitHub):
    def create_draft(self, tag, notes):
        return self.api(stage.REPOSITORY + '/releases', body={
            'tag_name': tag, 'name': 'Draftly ' + tag[1:], 'body': notes,
            'draft': True, 'prerelease': True, 'make_latest': 'false'})

    def publish(self, release_id):
        if isinstance(release_id, bool) or not isinstance(release_id, int) or release_id <= 0:
            raise ValueError('Invalid release ID.')
        response = json.loads(self.command(['api', '--method', 'PATCH', '--input', '-',
            stage.REPOSITORY + '/releases/' + str(release_id)],
            body=json.dumps({'draft': False, 'prerelease': True, 'make_latest': 'false'})))
        if not isinstance(response, dict) or response.get('id') != release_id or response.get('draft') is not False or response.get('prerelease') is not True:
            raise ValueError('Publication is unconfirmed. Reinspect before retrying.')


def publish(candidate, tag, public_key, notes, *, enabled, github=None,
            verify=verification.verify, download=publisher.verify_public_asset):
    if enabled != 'YES':
        raise ValueError('Prerelease publication is disabled.')
    version, channel = stage.prepare.release.channels.parse(tag)
    if channel == 'stable' or not notes.strip():
        raise ValueError('A prerelease tag and release notes are required.')
    candidate = Path(candidate)
    metadata = verify(candidate, tag, public_key)
    commit = metadata['sourceCommit']
    paths = {name: candidate / name for name in ('Draftly.zip', 'Draftly.zip.sha256', 'candidate.json')}
    paths.update(stage.load_module('prerelease_dmg', 'release-dmg.py').assets(candidate, version, metadata['sha256']))
    hashes = {name: (path.stat().st_size, stage.file_digest(path)) for name, path in paths.items()}
    if hashes['Draftly.zip'][1] != 'sha256:' + metadata['sha256']:
        raise ValueError('The candidate ZIP changed after verification.')
    github = github or GitHub()

    def check_source():
        if github.refs(tag) != (commit, commit):
            raise ValueError('The tag and main no longer match the verified candidate.')
        if any((path.stat().st_size, stage.file_digest(path)) != hashes[name] for name, path in paths.items()):
            raise ValueError('A candidate asset changed.')

    check_source()
    release = stage.find_release(github.releases(), tag)
    if release is None:
        github.create_draft(tag, notes)
        release = stage.find_release(github.releases(), tag)
    missing = stage.validate_assets(release, paths, notes, tag, allow_missing=True, prerelease=True)
    if missing:
        if release['draft'] is not True:
            raise ValueError('Do not repair assets in a public prerelease.')
        github.upload(tag, missing)
    release = stage.find_release(github.releases(), tag)
    stage.validate_assets(release, paths, notes, tag, allow_missing=False, prerelease=True)
    check_source()
    release_id = release.get('id')
    if isinstance(release_id, bool) or not isinstance(release_id, int) or release_id <= 0:
        raise ValueError('Invalid release ID.')
    if release['draft']:
        github.publish(release_id)
    public = stage.find_release(github.releases(), tag)
    stage.validate_assets(public, paths, notes, tag, allow_missing=False, prerelease=True)
    if public['draft'] is not False or public.get('id') != release_id:
        raise ValueError('Publication is unconfirmed. Reinspect before retrying.')
    for name, (size, digest) in hashes.items():
        download('https://github.com/pobrespandas/draftly/releases/download/' + tag + '/' + name, size, digest)
    check_source()
    return {'tag': tag, 'channel': channel, 'releaseId': release_id, 'sha256': metadata['sha256']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', required=True)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--public-key', required=True)
    parser.add_argument('--notes', required=True)
    parser.add_argument('--enabled', default='NO', choices=['YES', 'NO'])
    args = parser.parse_args()
    result = publish(args.candidate, args.tag, args.public_key, Path(args.notes).read_text(), enabled=args.enabled)
    print(json.dumps(result, sort_keys=True))


if __name__ == '__main__':
    main()
