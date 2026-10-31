#!/usr/bin/env python3
"""Select checks before allocating native runners. Unknown paths run all checks."""
import argparse
import json
import os
import re
import subprocess

SCOPES = ('native', 'tooling', 'website', 'matrix')
NATIVE_ROOTS = ('Sources/', 'Tests/', 'Resources/', 'Vendor/', 'Configuration/',
                'Draftly.xcodeproj/')
NATIVE_FILES = {'Package.swift', 'Package.resolved', 'scripts/build-app.sh',
                'scripts/run-swift-tests.py', '.github/workflows/ci.yml',
                'scripts/ci-change-scope.py', 'scripts/test_ci_change_scope.py'}


def select_checks(paths, *, force=False):
    selected = dict.fromkeys(SCOPES, force)
    for path in paths:
        if path in NATIVE_FILES or path.startswith(NATIVE_ROOTS) or path.endswith('.swift'):
            selected.update(native=True, tooling=True, matrix=True)
        elif path.endswith('.md') or path.startswith(('docs/design-system/', '.agents/', '.claude/')):
            continue
        elif path.startswith('website/'):
            selected['website'] = True
        elif path.startswith(('scripts/', '.github/workflows/')):
            selected['tooling'] = True
        elif path.startswith('docs/'):
            selected['matrix'] = True
        elif path in ('.gitignore', 'LICENSE', 'skills-lock.json'):
            continue
        else:
            selected = dict.fromkeys(SCOPES, True)
    return selected


def changed_paths(base, head):
    if any(not re.fullmatch(r'[a-f0-9]{40}', value or '') or value == '0' * 40
           for value in (base, head)):
        return None
    result = subprocess.run(['git', 'diff', '--name-only', '--no-renames', '-z',
                             base, head, '--'], check=True, capture_output=True)
    return [path.decode('utf-8') for path in result.stdout.split(b'\0') if path]


def verify_results(results):
    plan = results.get('plan', {})
    if plan.get('result') != 'success':
        raise ValueError('Check selection did not pass.')
    for scope, job in [('native', 'macos'), ('tooling', 'tooling'),
                       ('website', 'website'), ('matrix', 'matrix')]:
        selected = plan.get('outputs', {}).get(scope)
        if selected not in ('true', 'false'):
            raise ValueError('Missing or invalid selection: ' + scope)
        expected = 'success' if selected == 'true' else 'skipped'
        if results.get(job, {}).get('result') != expected:
            raise ValueError('The selected CI result does not match: ' + job)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', default='')
    parser.add_argument('--head', default='')
    parser.add_argument('--verify-results', action='store_true')
    parser.add_argument('--force', choices=('true', 'false'), default='false')
    parser.add_argument('--diagnostic', default='')
    args = parser.parse_args()
    if args.verify_results:
        verify_results(json.loads(os.environ['RESULTS']))
        print('All selected checks passed.')
        return
    if args.diagnostic and args.diagnostic != 'all':
        selected = dict.fromkeys(SCOPES, False)
        selected['native'] = True
    else:
        paths = changed_paths(args.base, args.head) if args.force != 'true' else None
        selected = select_checks(paths or [], force=paths is None)
    for scope, enabled in selected.items():
        print(f'{scope}={str(enabled).lower()}')


if __name__ == '__main__':
    main()
