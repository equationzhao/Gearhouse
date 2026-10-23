"""Check the publishable source for private files and stale generated resources."""
import json
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]
PUBLIC_DIRECTORIES = {'.github', 'Config', 'GearhouseApp', 'GearhouseApp.xcodeproj', 'SharedRules', 'Sources', 'Tests', 'UITests', 'scripts', 'docs'}
PUBLIC_FILES = {'.gitattributes', '.gitignore', 'AGENTS.md', 'CONTRIBUTING.md', 'LICENSE', 'Makefile', 'Package.swift', 'README.md', 'README.zh-CN.md', 'SECURITY.md', 'THIRD_PARTY_NOTICES.md'}
PRIVATE_PARTS = {'xcuserdata', '.build', 'DerivedData', 'exports', 'verification', '__pycache__', '.DS_Store'}
SENSITIVE_PATTERNS = [
    re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    re.compile(r'\b(?:ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|AKIA[A-Z0-9]{16})\b'),
    re.compile(r'\b0000[0-9A-Fa-f]{4}-[0-9A-Fa-f]{16}\b'),
]


def collect_files():
    if (ROOT / '.git').exists():
        result = subprocess.run(['git', 'ls-files', '--cached', '-z'], cwd=ROOT, check=True, capture_output=True)
        return [ROOT / path for path in result.stdout.decode().split('\0') if path]
    # Source archives have no Git index. Limit inspection to the public layout.
    return [path for path in ROOT.rglob('*') if path.is_file() and not any(part in PRIVATE_PARTS or part == '.git' for part in path.relative_to(ROOT).parts) and (path.relative_to(ROOT).parts[0] in PUBLIC_DIRECTORIES or str(path.relative_to(ROOT)) in PUBLIC_FILES)]


def check_files(files):
    failures = []
    for path in files:
        relative = path.relative_to(ROOT)
        if relative.parts[0] not in PUBLIC_DIRECTORIES and str(relative) not in PUBLIC_FILES:
            failures.append(f'{relative}: unexpected file in publication scope')
        if any(part in PRIVATE_PARTS for part in relative.parts) or path.name in {'Local.xcconfig', '.env'} or path.name.startswith('.env.') or path.suffix in {'.p12', '.p8', '.pem', '.key', '.mobileprovision', '.sqlite', '.sqlite3', '.xcuserstate', '.gearhousebackup'}:
            failures.append(f'{relative}: private file must not be published')
            continue
        try:
            text = path.read_text()
        except (UnicodeDecodeError, IsADirectoryError):
            continue
        if any(pattern.search(text) for pattern in SENSITIVE_PATTERNS):
            failures.append(f'{relative}: possible credential or device identifier; inspect locally')
        # Examples may discuss a machine path but must not include a real home path.
        if re.search(r'/(?:Users|home)/[A-Za-z0-9_.-]+/', text):
            failures.append(f'{relative}: personal absolute path')
        if path.suffix == '.md':
            for target in re.findall(r'(?<!!)\[[^\]]*\]\(([^\s)]+)\)', text):
                if ':' not in target and not target.startswith('#') and not (path.parent / unquote(target.split('#')[0])).exists():
                    failures.append(f'{relative}: broken local link {target}')
    fixture = json.loads((ROOT / 'Sources/GearhouseCore/Resources/preview-fixture.json').read_text())
    if fixture.get('account') or any(not str(activity.get('id', '')).startswith('demo-') for activity in fixture.get('activities', [])):
        failures.append('preview-fixture.json: expected synthetic, account-free demo data')
    return failures


def main():
    files = collect_files()
    if not files:
        raise SystemExit('No source files found. Stage the intended public files before checking a new repository.')
    failures = check_files(files)
    for script in ['bundle-rules.py', 'generate-project.py']:
        result = subprocess.run([sys.executable, str(ROOT / 'scripts' / script), '--check'], cwd=ROOT)
        if result.returncode:
            failures.append(f'{script}: generated files are out of date')
    if failures:
        raise SystemExit('\n'.join(failures))
    print(f'Checked {len(files)} public files: no blocked private paths, matching credential patterns, or stale generated files.')
    print('This scoped check does not replace reviewing files before publication.')


if __name__ == '__main__':
    main()
