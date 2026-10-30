"""Test release-writer coordination with an in-memory object store."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit

spec = importlib.util.spec_from_file_location("release_lock", Path(__file__).with_name("release-lock.py"))
lock = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lock)


class FakeStore:
    def __init__(self, bucket="fixture-bucket"):
        self.bucket = bucket
        self.current = None
        self.next_generation = 1
        self.unknown_create = False
        self.unknown_delete = False
        self.deletes = []
    def scope(self):
        return {"bucket": self.bucket, "object": "draftly/site-writer.lock"}
    def create(self, owner):
        if self.current is not None:
            raise lock.Busy("Another writer holds the lock.")
        self.current = {"owner": owner, "generation": str(self.next_generation)}
        self.next_generation += 1
        if self.unknown_create:
            raise OSError("Lost create response")
        return self.current.copy()
    def read(self):
        return self.current.copy() if self.current else None
    def delete(self, generation):
        self.deletes.append(generation)
        if self.current is None or self.current["generation"] != generation:
            raise ValueError("Generation mismatch")
        self.current = None
        if self.unknown_delete:
            raise OSError("Lost delete response")


class ReleaseLockTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="draftly-release-lock-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.journal = self.root / "lock.json"
        self.store = FakeStore()

    def test_one_holder_blocks_another_and_releases_its_generation(self):
        first = lock.acquire(self.store, self.journal)
        with self.assertRaises(lock.Busy):
            lock.acquire(self.store, self.root / "other.json")
        self.assertEqual(self.store.current, first)
        lock.release(self.store, self.journal)
        self.assertIsNone(self.store.current)
        self.assertEqual(self.store.deletes, [first["generation"]])
        self.assertEqual(json.loads(self.journal.read_text())["state"], "released")

    def test_unknown_create_requires_recovery_without_another_create(self):
        self.store.unknown_create = True
        with self.assertRaises(OSError):
            lock.acquire(self.store, self.journal)
        self.assertEqual(json.loads(self.journal.read_text())["state"], "creating")
        held = lock.recover(self.store, self.journal)
        self.assertEqual(held, self.store.current)
        self.assertEqual(self.store.next_generation, 2)

    def test_unknown_create_does_not_adopt_another_writer(self):
        self.store.unknown_create = True
        with self.assertRaises(OSError):
            lock.acquire(self.store, self.journal)
        self.store.current = {"owner": "f" * 32, "generation": "2"}
        with self.assertRaisesRegex(ValueError, "does not belong"):
            lock.recover(self.store, self.journal)
        self.assertEqual(self.store.deletes, [])

    def test_unknown_delete_can_be_reconciled_without_deleting_a_new_owner(self):
        lock.acquire(self.store, self.journal)
        self.store.unknown_delete = True
        with self.assertRaises(OSError):
            lock.release(self.store, self.journal)
        self.store.unknown_delete = False
        next_lock = lock.acquire(self.store, self.root / "next.json")
        lock.recover(self.store, self.journal)
        self.assertEqual(self.store.current, next_lock)
        self.assertEqual(json.loads(self.journal.read_text())["state"], "released")
        self.assertEqual(len(self.store.deletes), 1)

    def test_release_refuses_a_replaced_lock(self):
        lock.acquire(self.store, self.journal)
        self.store.current = {"owner": "f" * 32, "generation": "2"}
        with self.assertRaisesRegex(ValueError, "does not belong"):
            lock.release(self.store, self.journal)
        self.assertEqual(self.store.deletes, [])

    def test_check_requires_the_same_held_owner_and_generation(self):
        held = lock.acquire(self.store, self.journal)
        self.assertEqual(lock.check(self.store, self.journal), held)
        for current in (None, {"owner": "f" * 32, "generation": held["generation"]},
                        {"owner": held["owner"], "generation": "999"}):
            with self.subTest(current=current):
                self.store.current = current
                with self.assertRaises(ValueError):
                    lock.check(self.store, self.journal)
        self.assertEqual(self.store.deletes, [])

    def test_check_rejects_different_scope_and_released_journal(self):
        lock.acquire(self.store, self.journal)
        with self.assertRaisesRegex(ValueError, "scope"):
            lock.check(FakeStore(bucket="other-bucket"), self.journal)
        lock.release(self.store, self.journal)
        with self.assertRaisesRegex(ValueError, "hold"):
            lock.check(self.store, self.journal)

    def test_journal_cannot_be_recovered_or_released_in_a_different_bucket(self):
        lock.acquire(self.store, self.journal)
        other = FakeStore(bucket="other-bucket")
        with self.assertRaisesRegex(ValueError, "scope"):
            lock.release(other, self.journal)
        self.assertIsNotNone(self.store.current)
        self.assertEqual(other.deletes, [])

    def test_unknown_create_with_no_object_does_not_retry(self):
        with patch.object(self.store, "create", side_effect=OSError("lost")) as create:
            with self.assertRaises(OSError):
                lock.acquire(self.store, self.journal)
            self.assertIsNone(lock.recover(self.store, self.journal))
            self.assertEqual(create.call_count, 1)
        self.assertEqual(json.loads(self.journal.read_text())["state"], "not_acquired")

    def test_storage_requests_use_generation_preconditions(self):
        store = lock.StorageLock("fixture-bucket", "fixture-token")
        metadata = {"bucket": "fixture-bucket", "name": store.OBJECT, "generation": "42"}
        with patch.object(store, "request", side_effect=[metadata, metadata, {"owner": "a" * 32}, {}]) as request:
            self.assertEqual(store.create("a" * 32)["generation"], "42")
            self.assertEqual(store.read(), {"owner": "a" * 32, "generation": "42"})
            store.delete("42")
        calls = request.call_args_list
        self.assertEqual(parse_qs(urlsplit(calls[0].args[1]).query)["ifGenerationMatch"], ["0"])
        self.assertEqual(parse_qs(urlsplit(calls[2].args[1]).query)["generation"], ["42"])
        self.assertEqual(parse_qs(urlsplit(calls[3].args[1]).query)["ifGenerationMatch"], ["42"])

    def test_storage_rejects_wrong_metadata_and_missing_versioned_content(self):
        store = lock.StorageLock("fixture-bucket", "fixture-token")
        metadata = {"bucket": "fixture-bucket", "name": store.OBJECT, "generation": "42"}
        with patch.object(store, "request", return_value={**metadata, "bucket": "wrong-bucket"}):
            with self.assertRaisesRegex(ValueError, "metadata"):
                store.create("a" * 32)
        with patch.object(store, "request", side_effect=[metadata, None]):
            with self.assertRaisesRegex(ValueError, "content"):
                store.read()

    def test_existing_or_symlink_journal_is_not_overwritten(self):
        self.journal.write_text("keep")
        with self.assertRaises(FileExistsError):
            lock.acquire(self.store, self.journal)
        self.assertEqual(self.journal.read_text(), "keep")
        self.assertIsNone(self.store.current)

    def test_invalid_journal_is_rejected_before_touching_store(self):
        self.journal.write_text('{"state":"held","owner":"bad","generation":"1"}')
        with self.assertRaises(ValueError):
            lock.release(self.store, self.journal)
        self.assertEqual(self.store.deletes, [])

    def test_acquire_failure_does_not_claim_the_lock(self):
        self.store.current = {"owner": "a" * 32, "generation": "8"}
        with self.assertRaises(lock.Busy):
            lock.acquire(self.store, self.journal)
        self.assertEqual(json.loads(self.journal.read_text())["state"], "busy")
        self.assertEqual(self.store.current["generation"], "8")

    def test_acquire_does_not_contact_store_if_journal_sync_fails(self):
        with patch.object(lock.os, "fsync", side_effect=OSError("sync failed")):
            with self.assertRaisesRegex(OSError, "sync failed"):
                lock.acquire(self.store, self.journal)
        self.assertIsNone(self.store.current)

    def test_release_does_not_delete_if_journal_sync_fails(self):
        held = lock.acquire(self.store, self.journal)
        with patch.object(lock.os, "fsync", side_effect=OSError("sync failed")):
            with self.assertRaisesRegex(OSError, "sync failed"):
                lock.release(self.store, self.journal)
        self.assertEqual(self.store.current, held)
        self.assertEqual(self.store.deletes, [])

    def test_directory_sync_failure_prevents_remote_changes(self):
        with patch.object(lock, "sync_directory", side_effect=OSError("directory sync failed")):
            with self.assertRaisesRegex(OSError, "directory sync failed"):
                lock.acquire(self.store, self.journal)
        self.assertIsNone(self.store.current)

        self.journal.unlink()
        held = lock.acquire(self.store, self.journal)
        with patch.object(lock, "sync_directory", side_effect=OSError("directory sync failed")):
            with self.assertRaisesRegex(OSError, "directory sync failed"):
                lock.release(self.store, self.journal)
        self.assertEqual(self.store.current, held)
        self.assertEqual(self.store.deletes, [])
        self.assertEqual(json.loads(self.journal.read_text())["state"], "releasing")


if __name__ == "__main__":
    unittest.main()
