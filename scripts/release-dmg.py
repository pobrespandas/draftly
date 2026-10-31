#!/usr/bin/env python3
"""Create and verify a notarized disk image for a release candidate."""
import hashlib
import json
from pathlib import Path
import re
import tempfile


def digest(path):
    with Path(path).open('rb') as stream:
        result = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def create(app, output, version, profile, run):
    if not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', version):
        raise ValueError('The disk image version is invalid.')
    output = Path(output)
    image = output / ('Draftly-' + version + '.dmg')
    if any(path.exists() or path.is_symlink() for path in
           (image, image.with_suffix('.dmg.sha256'), output / 'disk-image.json')):
        raise ValueError('The disk image output already exists.')
    with tempfile.TemporaryDirectory(prefix='draftly-dmg-') as temporary:
        payload = Path(temporary) / 'payload'
        payload.mkdir()
        run(['ditto', str(app), str(payload / 'Draftly.app')])
        (payload / 'Applications').symlink_to('/Applications')
        run(['hdiutil', 'create', '-volname', 'Draftly', '-srcfolder', str(payload),
             '-format', 'UDZO', str(image)])
    run(['codesign', '--force', '--timestamp', '--sign', 'Developer ID Application', str(image)])
    response = json.loads(run(['xcrun', 'notarytool', 'submit', str(image), '--keychain-profile',
                              profile, '--output-format', 'json'], capture=True))
    submission = response.get('id')
    if not isinstance(submission, str) or not re.fullmatch(r'[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}', submission):
        raise ValueError('The disk image submission ID is invalid.')
    (output / 'dmg-notary-submission.json').write_text(json.dumps(response) + '\n')
    result = json.loads(run(['xcrun', 'notarytool', 'wait', submission, '--keychain-profile',
                            profile, '--timeout', '30m', '--output-format', 'json'], capture=True))
    if result.get('id') != submission or result.get('status') != 'Accepted':
        raise ValueError('Apple did not accept the disk image.')
    run(['xcrun', 'stapler', 'staple', str(image)])
    verify(image, run)
    value = digest(image)
    image.with_suffix('.dmg.sha256').write_text(value + '  ' + image.name + '\n')
    metadata = {'version': version, 'name': image.name, 'sha256': value,
                'zipSHA256': digest(output / 'Draftly.zip'), 'notarySubmission': submission}
    (output / 'disk-image.json').write_text(json.dumps(metadata, indent=2) + '\n')
    return metadata


def verify(image, run):
    run(['codesign', '--verify', '--strict', str(image)])
    run(['xcrun', 'stapler', 'validate', str(image)])
    run(['hdiutil', 'verify', str(image)])
    run(['spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', str(image)])


def assets(candidate, version, zip_digest):
    candidate = Path(candidate)
    manifest = candidate / 'disk-image.json'
    if not manifest.exists():
        return {}
    if manifest.is_symlink() or manifest.stat().st_size > 4096:
        raise ValueError('The disk image manifest is invalid.')
    metadata = json.loads(manifest.read_text())
    name = 'Draftly-' + version + '.dmg'
    if (not isinstance(metadata, dict) or metadata.get('version') != version
            or metadata.get('name') != name or metadata.get('zipSHA256') != zip_digest
            or not isinstance(metadata.get('sha256'), str)
            or not re.fullmatch(r'[a-f0-9]{64}', metadata['sha256'])
            or not isinstance(metadata.get('notarySubmission'), str)
            or not re.fullmatch(r'[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}', metadata['notarySubmission'])):
        raise ValueError('The disk image does not match the candidate.')
    image, checksum = candidate / name, candidate / (name + '.sha256')
    if image.is_symlink() or checksum.is_symlink() or digest(image) != metadata['sha256']:
        raise ValueError('The disk image checksum is invalid.')
    if checksum.read_text() != metadata['sha256'] + '  ' + name + '\n':
        raise ValueError('The disk image checksum file is invalid.')
    return {name: image, name + '.sha256': checksum, 'disk-image.json': manifest}
