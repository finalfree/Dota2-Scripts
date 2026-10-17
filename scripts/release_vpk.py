"""Prepare release notes and verify promotion of a previously built VPK artifact."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
from urllib.parse import urlencode
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[1]
FIRST_RELEASE = 'v0.1.0'
PACKAGE_NAME = 'pak02_dir.vpk'
CHECKSUM_NAME = PACKAGE_NAME + '.sha256'
BUILD_INFO_NAME = PACKAGE_NAME + '.build-info.json'


def release_notes(root, tag, repository, commit, test_build=False):
    if test_build:
        if not re.fullmatch(r'test-\d+-\d+', tag):
            raise ValueError('Test release tags must use test-RUN_ID-RUN_ATTEMPT')
    elif not re.fullmatch(r'v\d+\.\d+\.\d+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?', tag):
        raise ValueError('Use a version tag such as v0.1.0 or v0.2.0-rc.1')
    if test_build or tag == FIRST_RELEASE:
        notes = (root / 'README.md').read_text(encoding='utf-8-sig')
    else:
        changelog = root / 'CHANGELOG.md'
        if not changelog.is_file():
            raise ValueError(f'Add a CHANGELOG.md section named "## {tag}" before building this version')
        text = changelog.read_text(encoding='utf-8-sig')
        headings = list(re.finditer(r'^##[ \t]+(.+?)[ \t]*$', text, re.M))
        matches = []
        for index, heading in enumerate(headings):
            title = heading[1]
            if re.match(rf'^(?:{re.escape(tag)}|\[{re.escape(tag)}\])(?:\s|$)', title):
                end = headings[index + 1].start() if index + 1 < len(headings) else len(text)
                matches.append(text[heading.end():end].strip())
        if len(matches) != 1 or not matches[0]:
            raise ValueError(f'CHANGELOG.md must contain exactly one nonempty "## {tag}" section')
        notes = matches[0]

    # Release bodies resolve relative links differently from repository READMEs.
    # Pin all local links/images to the released commit so future edits cannot alter them.
    def absolute(path, image=False):
        if re.match(r'^(?:[A-Za-z][A-Za-z0-9+.-]*:|#|//)', path):
            return path
        path = path.removeprefix('./').lstrip('/')
        if image:
            return f'https://raw.githubusercontent.com/{repository}/{commit}/{path}'
        return f'https://github.com/{repository}/blob/{commit}/{path}'

    notes = re.sub(r'(!?\[[^\]\n]*\]\()([^\s)]+)(\))',
                   lambda m: m[1] + absolute(m[2], m[1].startswith('!')) + m[3], notes)
    notes = re.sub(r'(\bsrc=")([^"]+)(")',
                   lambda m: m[1] + absolute(m[2], True) + m[3], notes)
    return notes.strip() + '\n'


def release_body(notes, tag, repository):
    base = f'https://github.com/{repository}/releases/download/{tag}'
    downloads = '\n'.join(f'- [{name}]({base}/{name})'
                          for name in (PACKAGE_NAME, CHECKSUM_NAME, BUILD_INFO_NAME))
    heading = '测试版下载' if tag.startswith('test-') else '下载'
    return f'## {heading}\n\n{downloads}\n\n---\n\n{notes}'


def github_get(path):
    token = os.environ['GH_TOKEN']
    base = os.environ.get('GITHUB_API_URL', 'https://api.github.com')
    request = Request(base + path, headers={
        'Authorization': f'Bearer {token}',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'overforged-release',
    })
    with urlopen(request, timeout=30) as response:
        return json.load(response)


def select_artifact(repository, commit, get=github_get):
    """Use the newest successful manual run for this exact commit; never rebuild."""
    query = urlencode({'event': 'workflow_dispatch', 'status': 'success',
                       'head_sha': commit, 'per_page': 1})
    runs = get(f'/repos/{repository}/actions/workflows/build-vpk.yml/runs?{query}')['workflow_runs']
    if not runs:
        raise ValueError('No successful manual build for this commit. Run Build VPK, test it, then tag that commit.')
    run = runs[0]
    if (run['head_sha'] != commit or run['event'] != 'workflow_dispatch' or
            run['conclusion'] != 'success'):
        raise ValueError('Selected build does not match the tagged commit and successful manual event')
    name = f"overforged-vpk-{commit}-{run['id']}-{run['run_attempt']}"
    query = urlencode({'name': name, 'per_page': 100})
    artifacts = get(f"/repos/{repository}/actions/runs/{run['id']}/artifacts?{query}")['artifacts']
    matches = [a for a in artifacts if a['name'] == name and not a['expired']]
    if len(matches) != 1:
        raise ValueError('Latest manual build artifact is missing or expired. Build and test this commit again.')
    return run['id'], matches[0]['id']


def verify_artifact(directory, commit):
    expected = {PACKAGE_NAME, CHECKSUM_NAME, BUILD_INFO_NAME}
    if {p.name for p in directory.iterdir()} != expected:
        raise ValueError('Unexpected release artifact contents')
    if any(p.is_symlink() or not p.is_file() for p in directory.iterdir()):
        raise ValueError('Release artifact must contain only regular files')
    info = json.loads((directory / BUILD_INFO_NAME).read_text(encoding='utf-8-sig'))
    package = directory / PACKAGE_NAME
    if info['commit'] != commit or info['package'] != package.name or info['vpk_version'] != 1:
        raise ValueError('Artifact metadata does not match tagged commit or VPK format')
    with package.open('rb') as source:
        if source.read(8) != bytes.fromhex('3412aa5501000000'):
            raise ValueError('Expected VPK v1 header')
        source.seek(0)
        hasher = hashlib.sha256()
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            hasher.update(chunk)
        digest = hasher.hexdigest()
    checksums = (directory / CHECKSUM_NAME).read_text(encoding='utf-8-sig').strip()
    if (digest != info['sha256'] or package.stat().st_size != info['size_bytes'] or
            checksums != f'{digest}  {PACKAGE_NAME}'):
        raise ValueError('Release artifact size or SHA256 mismatch')
    print(f'Verified tested artifact for commit {commit}: {digest}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    for command in ('prepare', 'prepare-test'):
        prepare = commands.add_parser(command)
        prepare.add_argument('--tag', required=True)
        prepare.add_argument('--commit', required=True)
        prepare.add_argument('--repository', required=True)
        prepare.add_argument('--notes', type=Path, required=True)
        prepare.add_argument('--github-output', type=Path, required=True)
        if command == 'prepare-test':
            prepare.add_argument('--run-id', type=int, required=True)
            prepare.add_argument('--artifact-id', type=int, required=True)
    verify = commands.add_parser('verify')
    verify.add_argument('--directory', type=Path, required=True)
    verify.add_argument('--commit', required=True)
    args = parser.parse_args()
    if args.command == 'verify':
        verify_artifact(args.directory, args.commit)
        return
    test_build = args.command == 'prepare-test'
    notes = release_notes(ROOT, args.tag, args.repository, args.commit, test_build=test_build)
    if test_build:
        run_id, artifact_id = args.run_id, args.artifact_id
        if run_id <= 0 or artifact_id <= 0 or not args.tag.startswith(f'test-{run_id}-'):
            raise ValueError('Test release must reference the current manual build and a valid artifact ID')
    else:
        run_id, artifact_id = select_artifact(args.repository, args.commit)
    args.notes.parent.mkdir(parents=True, exist_ok=True)
    args.notes.write_text(release_body(notes, args.tag, args.repository), encoding='utf-8')
    with args.github_output.open('a', encoding='utf-8') as output:
        output.write(f'run_id={run_id}\nartifact_id={artifact_id}\ntag={args.tag}\n')
    print(f'Promoting artifact {artifact_id} from manual run {run_id}')


if __name__ == '__main__':
    main()
