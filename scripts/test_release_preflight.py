"""Tests for release source identity checks."""
import importlib.util
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("release_preflight", Path(__file__).with_name("release-preflight.py"))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleasePreflightTests(unittest.TestCase):
    def test_matching_source_passes(self):
        release.validate("v1.2.3", "abc", "abc", "abc", "1.2.3", "12")

    def test_invalid_tags_fail(self):
        for tag in ("1.2.3", "v01.2.3", "v1.2.3-beta", "v1.2", "v1.2.3\n"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release.validate(tag, "abc", "abc", "abc", "1.2.3", "12")

    def test_tag_and_app_version_must_match(self):
        with self.assertRaisesRegex(ValueError, "CFBundleShortVersionString"):
            release.validate("v1.2.3", "abc", "abc", "abc", "1.2.4", "12")

    def test_build_is_a_positive_integer(self):
        for build in (None, "0", "01", "1.2", 1, "-1"):
            with self.subTest(build=build), self.assertRaises(ValueError):
                release.validate("v1.2.3", "abc", "abc", "abc", "1.2.3", build)

    def test_head_main_and_tag_must_be_the_same_commit(self):
        for head, main, tag_commit in (("abc", "def", "abc"), ("abc", "abc", "def"),
                                       ("", "", ""), ("abc", "", "abc")):
            with self.subTest(head=head, main=main, tag=tag_commit), self.assertRaises(ValueError):
                release.validate("v1.2.3", head, main, tag_commit, "1.2.3", "12")


class ReleaseNotesPreflightTests(unittest.TestCase):
    def test_reads_unicode_notes_without_changing_the_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "v1.2.3.txt"
            text = "Draftly 1.2.3\nUnicode ñ — 🐼.\n"
            path.write_text(text, encoding="utf-8")
            release.validate_notes("v1.2.3", root)
            self.assertEqual(path.read_text(encoding="utf-8"), text)

    def test_missing_empty_and_invalid_utf8_notes_stop_preflight(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "v1.2.3.txt"
            with self.assertRaises(OSError):
                release.validate_notes("v1.2.3", root)
            for content in (b"", b" \n\t", b"\xff"):
                path.write_bytes(content)
                with self.subTest(content=content), self.assertRaises((ValueError, UnicodeError)):
                    release.validate_notes("v1.2.3", root)


class ReleasePreflightCLITests(unittest.TestCase):
    def test_cli_accepts_main_tag_and_rejects_moved_main(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / "Configuration"
            config.mkdir()
            with (config / "Info.plist").open("wb") as output:
                plistlib.dump({"CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "12"}, output)
            notes = root / "docs/releases"
            notes.mkdir(parents=True)
            (notes / "v1.2.3.txt").write_text("Neutral fixture release notes.\n", encoding="utf-8")
            def git(*args):
                return subprocess.run(["git", *args], cwd=root, check=True,
                                      capture_output=True, text=True).stdout.strip()
            git("init", "-q")
            git("-c", "user.name=QA", "-c", "user.email=qa@example.invalid",
                "commit", "--allow-empty", "-qm", "fixture")
            git("tag", "v1.2.3")
            git("update-ref", "refs/remotes/origin/main", git("rev-parse", "HEAD"))
            command = ["python3", str(Path(release.__file__).resolve()), "v1.2.3"]
            self.assertEqual(subprocess.run(command, cwd=root, capture_output=True).returncode, 0)
            (notes / "v1.2.3.txt").unlink()
            missing = subprocess.run(command, cwd=root, capture_output=True, text=True)
            self.assertNotEqual(missing.returncode, 0)
            self.assertIn("v1.2.3.txt", missing.stderr)
            (notes / "v1.2.3.txt").write_text("Neutral fixture release notes.\n", encoding="utf-8")
            git("-c", "user.name=QA", "-c", "user.email=qa@example.invalid",
                "commit", "--allow-empty", "-qm", "new main")
            git("update-ref", "refs/remotes/origin/main", git("rev-parse", "HEAD"))
            result = subprocess.run(command, cwd=root, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("must match origin/main", result.stderr)


if __name__ == "__main__":
    unittest.main()
