from pathlib import Path
import argparse
import json
import re
import subprocess
import zipfile


GENERIC_PATTERNS = {
    'personal-home-path': rb'(?i)[A-Z]:[/\\]Users[/\\]',
    'private-key': rb'BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY',
    'github-token': rb'(?i)(?:ghp_|github_pat_)[A-Za-z0-9_]{20,}',
    'provider-token': rb'(?i)sk-ant-[A-Za-z0-9_-]{20,}',
}


def find_issues(name, data, private_literals):
    views = [data]
    if b'\x00' in data:
        views.append(data.decode('utf-16-le', errors='ignore').encode('utf-8'))
    # Check escaped regex/JSON text as well as the displayed text.
    views += [value.replace(b'\\.', b'.').replace(b'\\\\', b'\\') for value in list(views)]
    found = []
    for category, pattern in GENERIC_PATTERNS.items():
        if any(re.search(pattern, value) for value in views):
            found.append({'file': name, 'category': category})
    if any(needle in value for needle in private_literals for value in views):
        found.append({'file': name, 'category': 'private-environment-identifier'})
    return found


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--private-pattern-file', type=Path,
                        help='Untracked JSON array of private literal identifiers. Never include this file in a release.')
    args = parser.parse_args()
    private_literals = []
    if args.private_pattern_file:
        values = json.loads(args.private_pattern_file.read_text(encoding='utf-8'))
        if not isinstance(values, list) or any(not isinstance(v, str) or not v for v in values):
            raise ValueError('Private patterns must be a JSON array of nonempty strings')
        private_literals = [value.encode('utf-8') for value in values]

    root = Path(__file__).resolve().parents[1]
    names = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z']).decode().split('\0')
    names = [name for name in names if name]
    issues = []
    for name in names:
        if any(part in name.split('/') for part in ('private', 'runtime', 'build', '.gradle', 'backup')):
            issues.append({'file': name, 'category': 'excluded-directory'})
        if name.endswith(('.jks', '.keystore', '.pfx', '.msix')):
            issues.append({'file': name, 'category': 'excluded-file'})
        if args.private_pattern_file and (root / name).resolve() == args.private_pattern_file.resolve():
            issues.append({'file': name, 'category': 'private-pattern-file-tracked'})
        issues.extend(find_issues(name, (root / name).read_bytes(), private_literals))

    archives = sorted((root / 'dist').glob('*.zip')) + sorted((root / 'dist').glob('*.apk'))
    for archive in archives:
        with zipfile.ZipFile(archive) as zipped:
            for name in zipped.namelist():
                if not name.endswith('/'):
                    issues.extend(find_issues(archive.name + '/' + name, zipped.read(name), private_literals))
    for exe in (root / 'dist/desktop').glob('*.exe'):
        issues.extend(find_issues('desktop/' + exe.name, exe.read_bytes(), private_literals))
    print(json.dumps({'tracked_files': len(names), 'issues': issues,
                      'archives_inspected': len(archives),
                      'private_patterns_loaded': len(private_literals)}))
    return 1 if issues else 0


if __name__ == '__main__':
    raise SystemExit(main())
