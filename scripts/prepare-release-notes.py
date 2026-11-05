#!/usr/bin/env python3
"""Prepare reviewed release notes and a changelog from Conventional Commits."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import subprocess

spec = importlib.util.spec_from_file_location('notes_channels', Path(__file__).with_name('release-channels.py'))
channels = importlib.util.module_from_spec(spec)
spec.loader.exec_module(channels)
HEADER = '# Changelog\n\nEntries describe source changes. Public downloads are listed on [GitHub Releases](https://github.com/pobrespandas/draftly/releases).\n'
SUBJECT = re.compile(r'(?P<type>[a-z]+)(?:\((?P<scope>[^)\n]+)\))?(?P<breaking>!)?: (?P<text>.+)\Z')


def classify(message):
    lines = message.splitlines()
    subject = lines[0] if lines else ''
    match = SUBJECT.fullmatch(subject)
    breaking = bool(match and match['breaking']) or any(re.match(r'^BREAKING[ -]CHANGE: .+', line) for line in lines[1:])
    kind = match['type'] if match else 'other'
    section = 'Breaking changes' if breaking else {'feat': 'Features', 'fix': 'Fixes', 'perf': 'Performance'}.get(kind, 'Other changes')
    return section, match['text'] if match else subject, match['scope'] if match else None


def recommended_version(base, commits):
    version, channel = channels.parse(base)
    if channel != 'stable':
        raise ValueError('Use the previous stable tag as the release baseline.')
    major, minor, patch = map(int, version.split('.'))
    sections = {classify(message)[0] for _, message in commits}
    if 'Breaking changes' in sections:
        if major == 0:
            minor += 1; patch = 0
        else:
            major += 1; minor = patch = 0
    elif 'Features' in sections:
        minor += 1; patch = 0
    elif sections:
        patch += 1
    else:
        return None
    return f'{major}.{minor}.{patch}'


def render(tag, commits):
    channels.parse(tag)
    groups = {}
    for commit, message in commits:
        if not re.fullmatch(r'[a-f0-9]{40}', commit):
            raise ValueError('Use full commit identities for release notes.')
        section, text, scope = classify(message)
        if not text:
            raise ValueError('A commit has no subject.')
        prefix = f'{scope}: ' if scope else ''
        groups.setdefault(section, []).append(f'- {prefix}{text} ({commit[:7]})')
    if not groups:
        raise ValueError('The release has no changes.')
    output = [f'Draftly {tag[1:]}']
    for section in ('Breaking changes', 'Features', 'Fixes', 'Performance', 'Other changes'):
        if section in groups:
            output.extend(['', section, *groups[section]])
    return '\n'.join(output) + '\n'


def write(root, tag, notes):
    root = Path(root)
    channels.parse(tag)
    changelog = root / 'CHANGELOG.md'
    path = root / 'docs/releases' / (tag + '.txt')
    existing = changelog.read_text() if changelog.exists() else HEADER
    heading = '## [' + tag[1:] + ']'
    if path.exists() or any(line.startswith(heading) for line in existing.splitlines()):
        raise ValueError('Release notes already exist. Review them without overwriting history.')
    if not existing.startswith('# Changelog\n'):
        raise ValueError('The changelog header is invalid.')
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(notes)
    insertion = existing.find('\n## ')
    if insertion < 0:
        insertion = len(existing.rstrip())
    changelog.write_text(existing[:insertion].rstrip() + '\n\n' + heading + '\n\n' + notes.rstrip() + '\n' + existing[insertion:])


def read_commits(base):
    channels.parse(base)
    baseline = subprocess.check_output(['git', 'rev-parse', '--verify', 'refs/tags/' + base + '^{commit}'], text=True).strip()
    subprocess.run(['git', 'merge-base', '--is-ancestor', baseline, 'HEAD'], check=True, capture_output=True)
    raw = subprocess.check_output(['git', 'log', '--first-parent', '--format=%H%x00%B%x00', baseline + '..HEAD'], text=True)
    fields = raw.split('\0')
    return [(fields[index].strip(), fields[index + 1].strip()) for index in range(0, len(fields) - 1, 2)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--since', required=True, help='Previous stable tag')
    parser.add_argument('--tag', required=True, help='Proposed stable, alpha, or beta tag')
    parser.add_argument('--write', action='store_true', help='Write notes and changelog after review')
    args = parser.parse_args()
    commits = read_commits(args.since)
    minimum = recommended_version(args.since, commits)
    if minimum is None or channels.precedence(args.tag)[:3] < tuple(map(int, minimum.split('.'))):
        parser.error('The tag is below the required version increment: ' + str(minimum))
    notes = render(args.tag, commits)
    if args.write:
        write(Path.cwd(), args.tag, notes)
    print(json.dumps({'minimumVersion': minimum, 'tag': args.tag, 'notes': notes, 'written': args.write}, indent=2))


if __name__ == '__main__':
    main()
