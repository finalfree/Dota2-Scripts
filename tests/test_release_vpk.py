"""Exercise release promotion guards without publishing or contacting GitHub."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from release_vpk import release_notes, select_artifact, verify_artifact


class ReleaseNotesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def notes(self, tag):
        return release_notes(self.root, tag, 'owner/repo', 'a' * 40)

    def test_first_release_uses_readme_and_pins_images_and_links(self):
        (self.root / 'README.md').write_text(
            '# First release\n[Docs](docs/guide.md)\n![Icon](artwork/icon.png)\n'
            '<img src="artwork/large.png">\n[Section](#hello)\n[Web](https://example.com)',
            encoding='utf-8')
        notes = self.notes('v0.1.0')
        self.assertIn('# First release', notes)
        self.assertIn('https://github.com/owner/repo/blob/' + 'a' * 40 + '/docs/guide.md', notes)
        self.assertIn('https://raw.githubusercontent.com/owner/repo/' + 'a' * 40 + '/artwork/icon.png', notes)
        self.assertIn('https://raw.githubusercontent.com/owner/repo/' + 'a' * 40 + '/artwork/large.png', notes)
        self.assertIn('[Section](#hello)', notes)
        self.assertIn('[Web](https://example.com)', notes)

    def test_later_release_only_uses_matching_changelog_section(self):
        (self.root / 'CHANGELOG.md').write_text(
            '# Changes\n## Unreleased\nFuture\n## [v0.2.0] - 2026-10-17\n'
            '### Fixed\n- Correct item\n## v0.1.0\nOld release\n', encoding='utf-8')
        self.assertEqual('### Fixed\n- Correct item\n', self.notes('v0.2.0'))

    def test_missing_empty_duplicate_or_wrong_version_stops_release(self):
        with self.assertRaises(ValueError):
            self.notes('v0.2.0')
        for text in ['## v0.2.0\n', '## v0.2.0\nA\n## v0.2.0\nB', '## v0.2.01\nWrong']:
            (self.root / 'CHANGELOG.md').write_text(text, encoding='utf-8')
            with self.subTest(text=text), self.assertRaises(ValueError):
                self.notes('v0.2.0')

    def test_invalid_tag_is_rejected(self):
        for tag in ['vbanana', 'v0.2', 'v0.2.0/other']:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                self.notes(tag)


class BuildSelectionTests(unittest.TestCase):
    def select(self, runs=None, expired=False, artifact_name=None):
        run = {'id': 42, 'run_attempt': 2, 'head_sha': 'abc',
               'event': 'workflow_dispatch', 'conclusion': 'success'}
        self.paths = []

        def get(path):
            self.paths.append(path)
            if '/artifacts?' in path:
                return {'artifacts': [{'id': 123, 'name': artifact_name or 'overforged-vpk-abc-42-2',
                                       'expired': expired}]}
            return {'workflow_runs': [run] if runs is None else runs}

        return select_artifact('owner/repo', 'abc', get)

    def test_selects_exact_commit_and_run_attempt(self):
        self.assertEqual((42, 123), self.select())
        self.assertIn('head_sha=abc', self.paths[0])
        self.assertIn('event=workflow_dispatch', self.paths[0])
        self.assertIn('status=success', self.paths[0])

    def test_missing_expired_or_wrong_artifact_cannot_publish(self):
        for options in [{'runs': []}, {'expired': True}, {'artifact_name': 'unrelated'}]:
            with self.subTest(options=options), self.assertRaises(ValueError):
                self.select(**options)

    def test_wrong_commit_or_nonmanual_build_is_rejected(self):
        for override in [{'head_sha': 'other'}, {'event': 'push'}, {'conclusion': 'failure'}]:
            run = {'id': 42, 'run_attempt': 2, 'head_sha': 'abc',
                   'event': 'workflow_dispatch', 'conclusion': 'success', **override}
            with self.subTest(override=override), self.assertRaises(ValueError):
                self.select(runs=[run])


class ArtifactVerificationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.data = bytes.fromhex('3412aa5501000000') + b'tested payload'
        self.digest = hashlib.sha256(self.data).hexdigest()
        self.package = self.directory / 'pak01_dir.vpk'
        self.package.write_bytes(self.data)
        self.info = {'commit': 'abc', 'package': 'pak01_dir.vpk', 'vpk_version': 1,
                     'size_bytes': len(self.data), 'sha256': self.digest}
        self.write_info()
        (self.directory / 'SHA256SUMS').write_text(f'{self.digest}  pak01_dir.vpk\n', encoding='utf-8')

    def write_info(self):
        (self.directory / 'build-info.json').write_text(json.dumps(self.info), encoding='utf-8-sig')

    def test_valid_package_passes(self):
        verify_artifact(self.directory, 'abc')

    def test_wrong_commit_or_modified_bytes_cannot_publish(self):
        with self.assertRaises(ValueError):
            verify_artifact(self.directory, 'other')
        self.package.write_bytes(self.data + b'modified')
        with self.assertRaises(ValueError):
            verify_artifact(self.directory, 'abc')

    def test_modified_checksum_cannot_publish(self):
        (self.directory / 'SHA256SUMS').write_text('0' * 64 + '  pak01_dir.vpk\n', encoding='utf-8')
        with self.assertRaises(ValueError):
            verify_artifact(self.directory, 'abc')

    def test_unexpected_files_or_vpk_version_cannot_publish(self):
        self.info['vpk_version'] = 2
        self.write_info()
        with self.assertRaises(ValueError):
            verify_artifact(self.directory, 'abc')
        self.info['vpk_version'] = 1
        self.write_info()
        (self.directory / 'unexpected.txt').write_text('extra', encoding='utf-8')
        with self.assertRaises(ValueError):
            verify_artifact(self.directory, 'abc')


if __name__ == '__main__':
    unittest.main()
