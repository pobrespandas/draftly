"""Test site changes against their deployed base without contacting Firebase."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("site_overlay", Path(__file__).with_name("site-overlay.py"))
overlay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(overlay)


class SiteOverlayTests(unittest.TestCase):
    def test_changed_and_new_files_apply_only_to_matching_live_base(self):
        base = {"/index.html": b"old", "/actions.html": b"old actions"}
        target = {"/index.html": b"new", "/actions.html": b"old actions", "/release.mjs": b"new script"}
        live = {"/index.html": b"old", "/release.mjs": None}
        self.assertEqual(overlay.plan(base, target, live), {"/index.html": b"new", "/release.mjs": b"new script"})

    def test_already_applied_files_are_not_overwritten(self):
        self.assertEqual(overlay.plan({"/index.html": b"old"}, {"/index.html": b"new"},
                                      {"/index.html": b"new"}), {})

    def test_changed_live_file_and_unrelated_new_file_are_conflicts(self):
        for base, target, live in [({"/index.html": b"old"}, {"/index.html": b"new"}, {"/index.html": b"other"}),
                                   ({}, {"/release.mjs": b"new"}, {"/release.mjs": b"other"})]:
            with self.subTest(live=live), self.assertRaisesRegex(ValueError, "changed independently"):
                overlay.plan(base, target, live)

    def test_deletion_needs_matching_live_bytes(self):
        self.assertEqual(overlay.plan({"/old.css": b"old"}, {}, {"/old.css": b"old"}), {"/old.css": None})
        self.assertEqual(overlay.plan({"/old.css": b"old"}, {}, {"/old.css": None}), {})
        with self.assertRaisesRegex(ValueError, "changed independently"):
            overlay.plan({"/old.css": b"old"}, {}, {"/old.css": b"other"})

    def test_requires_actual_live_observation_for_each_change(self):
        with self.assertRaisesRegex(ValueError, "not observed"):
            overlay.plan({"/index.html": b"old"}, {"/index.html": b"new"}, {})

    def test_inspection_detects_drift_and_only_reads_changed_paths(self):
        base = {"/index.html": b"old", "/unchanged.html": b"same"}
        target = {"/index.html": b"new", "/unchanged.html": b"same", "/release.mjs": b"new js"}
        snapshot = {"version": "live", "files": {"/index.html": "hash", "/unchanged.html": "other"}, "config": {}}
        calls = []
        def fetch(path, expected):
            calls.append((path, expected))
            return b"old"
        result = overlay.inspect(None, base, target, snapshot=lambda _: snapshot, fetch=fetch)
        self.assertEqual(calls, [("/index.html", "hash")])
        self.assertEqual(result["baseVersion"], "live")
        self.assertEqual(result["changedPaths"], ["/index.html", "/release.mjs"])
        self.assertEqual(result["deletedPaths"], [])

    def test_inspection_rejects_unsafe_paths_before_fetch(self):
        calls = []
        def snapshot(_):
            return {"version": "live", "files": {"/../secret": "hash"}, "config": {}}
        with self.assertRaises(ValueError):
            overlay.inspect(None, {}, {"/../secret": b"new"}, snapshot=snapshot,
                            fetch=lambda path, digest: calls.append(path))
        self.assertEqual(calls, [])

    def test_inspection_rejects_live_changes_between_snapshots(self):
        states = iter([{"version": "before", "files": {}, "config": {}},
                       {"version": "after", "files": {}, "config": {}}])
        with self.assertRaisesRegex(ValueError, "changed during"):
            overlay.inspect(None, {}, {"/release.mjs": b"new"}, snapshot=lambda _: next(states), fetch=None)

    def test_git_inventory_uses_committed_files_and_rejects_symlinks(self):
        with tempfile.TemporaryDirectory(prefix="draftly-site-overlay-") as directory:
            root = Path(directory)
            def git(*arguments):
                return subprocess.run(["git", *arguments], cwd=root, check=True, capture_output=True, text=True).stdout.strip()
            git("init", "-q")
            git("config", "user.name", "Neutral Test")
            git("config", "user.email", "test@example.invalid")
            site = root / "website/public"
            site.mkdir(parents=True)
            (site / "index.html").write_bytes(b"committed")
            git("add", "website/public/index.html")
            git("commit", "-qm", "fixture")
            commit = git("rev-parse", "HEAD")
            (site / "index.html").write_bytes(b"uncommitted")
            self.assertEqual(overlay.read_git_tree(root, commit), {"/index.html": b"committed"})
            (site / "link").symlink_to("index.html")
            git("add", "website/public/link")
            git("commit", "-qm", "symlink fixture")
            with self.assertRaisesRegex(ValueError, "non-file"):
                overlay.read_git_tree(root, git("rev-parse", "HEAD"))

    def test_reserved_or_unsafe_paths_and_invalid_content_are_rejected(self):
        for path in ("/appcast.xml", "/../secret", "/a//b", "/a?b", "/a#b", "relative", "/a\\b"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                overlay.plan({}, {path: b"new"}, {path: None})
        with self.assertRaises(ValueError):
            overlay.plan({}, {"/index.html": "not bytes"}, {"/index.html": None})


if __name__ == "__main__":
    unittest.main()
