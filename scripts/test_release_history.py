"""Tests for release ordering against GitHub and Sparkle history."""
import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

spec = importlib.util.spec_from_file_location("release_history", Path(__file__).with_name("release-history.py"))
history = importlib.util.module_from_spec(spec)
spec.loader.exec_module(history)


def release(version, *, draft=False, prerelease=False):
    return {"tag_name": "v" + version, "draft": draft, "prerelease": prerelease}


def feed(*versions):
    items = "".join("<item><s:shortVersionString>%s</s:shortVersionString><s:version>%s</s:version></item>" % pair
                    for pair in versions)
    return ('<rss xmlns:s="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>'
            + items + '</channel></rss>').encode()


class ReleaseHistoryTests(unittest.TestCase):
    def test_first_release_requires_no_existing_stable_history(self):
        history.validate_history("0.1.0", "1", [], None)
        history.validate_history("0.1.0", "1", [], feed())
        with self.assertRaisesRegex(ValueError, "appcast is missing"):
            history.validate_history("0.2.0", "2", [release("0.1.0")], None)

    def test_both_version_and_build_must_advance(self):
        releases = [release("1.2.0"), release("1.10.0")]
        appcast = feed(("1.2.0", "9"), ("1.10.0", "10"))
        history.validate_history("1.11.0", "11", releases, appcast)
        with self.assertRaisesRegex(ValueError, "version must be greater"):
            history.validate_history("1.9.0", "11", releases, appcast)
        with self.assertRaisesRegex(ValueError, "build must be greater"):
            history.validate_history("1.11.0", "10", releases, appcast)

    def test_rejects_duplicate_release_even_if_draft_or_prerelease(self):
        for item in (release("1.0.0"), release("1.0.0", draft=True), release("1.0.0", prerelease=True)):
            with self.subTest(item=item), self.assertRaisesRegex(ValueError, "already has"):
                history.validate_history("1.0.0", "2", [item], None)

    def test_mismatched_or_damaged_history_fails_closed(self):
        invalid = [None, b"<html/>", b"<!DOCTYPE rss><rss><channel/></rss>",
                   feed(("1.0.0", "1"), ("1.0.0", "2")),
                   feed(("1.0.0", "1"), ("1.1.0", "1")),
                   feed(("1.0.0", "4"), ("1.1.0", "3"))]
        for appcast in invalid:
            with self.subTest(appcast=appcast), self.assertRaises(ValueError):
                history.validate_history("2.0.0", "5", [release("1.0.0"), release("1.1.0")], appcast)
        with self.assertRaisesRegex(ValueError, "do not match"):
            history.validate_history("2.0.0", "5", [release("1.0.0")], feed(("1.1.0", "1")))

    def test_invalid_metadata_fails_closed(self):
        for releases in ([{"tag_name": "v1.0.0"}], [{"tag_name": "old", "draft": False, "prerelease": False}], None):
            with self.subTest(releases=releases), self.assertRaises(ValueError):
                history.validate_history("2.0.0", "5", releases, feed())
        for version, build in (("01.0.0", "1"), ("1.0.0", "01"), ("1.0.0", None)):
            with self.subTest(version=version, build=build), self.assertRaises(ValueError):
                history.validate_history(version, build, [], None)

    def test_fetch_releases_flattens_all_pages_and_rejects_invalid_pages(self):
        result = subprocess.CompletedProcess([], 0, stdout=json.dumps([[release("1.0.0")], [release("1.1.0")]]))
        with patch.object(history.subprocess, "run", return_value=result):
            self.assertEqual(history.fetch_releases(), [release("1.0.0"), release("1.1.0")])
        result.stdout = json.dumps([{"unexpected": "page"}])
        with patch.object(history.subprocess, "run", return_value=result), self.assertRaisesRegex(ValueError, "invalid release pages"):
            history.fetch_releases()

    def test_only_a_404_means_the_appcast_is_absent(self):
        for status in (404, 503):
            error = HTTPError(history.FEED_URL, status, "fixture", {}, None)
            with self.subTest(status=status), patch.object(history.urllib.request, "urlopen", side_effect=error):
                if status == 404:
                    self.assertIsNone(history.fetch_appcast())
                else:
                    with self.assertRaises(HTTPError):
                        history.fetch_appcast()


if __name__ == "__main__":
    unittest.main()
