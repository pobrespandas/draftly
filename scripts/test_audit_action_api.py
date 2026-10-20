"""Check reference parsing and evidence retention without network access."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("audit", Path(__file__).with_name("audit-action-api.py"))
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class ReferenceTests(unittest.TestCase):
    def test_exact_names_signatures_and_static_members(self):
        body = '''<h3 id="recenttags"><code>Static</code><span>recentTags</span></h3>
        <ul class="tsd-signatures"><div class="tsd-signature"><span class="tsd-kind-call-signature">recentTags</span>(): string[]</div></ul>
        <div class="tsd-comment tsd-typography">Return tags.</div>
        <h3 id="name"><span>name</span></h3><div class="tsd-signature"><span class="tsd-kind-property">name</span>: string</div>'''
        members = audit.parse_members(body)
        self.assertEqual([(m["member"], m["kind"], m["static"]) for m in members], [("recentTags", "method", True), ("name", "property", False)])
        self.assertEqual(members[0]["contract"], "Return tags.")

    def test_refresh_keeps_evidence_and_removed_members(self):
        old = {"objects": [{"object": "Draft", "members": [
            {"anchor": "query", "automatedTest": "contractTest", "signatures": ["old"], "limitations": ["known"], "reviewDate": "2026-10-19", "customEvidence": "saved"},
            {"anchor": "removed", "implementation": "partial"}]}]}
        new = [{"object": "Draft", "members": [{"anchor": "query", "signatures": ["new"]}]}]
        merged = audit.merge_evidence(new, old)[0]["members"]
        self.assertEqual(merged[0]["automatedTest"], "contractTest")
        self.assertTrue(merged[0]["referenceChanged"])
        self.assertEqual(merged[0]["customEvidence"], "saved")
        self.assertEqual(merged[0]["reviewDate"], "2026-10-19")
        self.assertTrue(merged[1]["referenceRemoved"])

    def test_failed_fetch_keeps_previous_snapshot(self):
        old = {"objects": [{"object": "Draft", "sha256": "saved", "members": [{"anchor": "query"}]}]}
        obj = audit.merge_evidence([{"object": "Draft", "fetchError": "offline", "members": []}], old)[0]
        self.assertEqual(obj["sha256"], "saved")
        self.assertEqual(obj["members"], old["objects"][0]["members"])

    def test_anchor_changes_keep_evidence_without_duplicate_members(self):
        old = {"objects": [{"object": "Draft", "reviewNotes": "Keep object evidence", "members": [
            {"member": "query", "kind": "method", "static": True, "anchor": "old-query", "signatures": ["query()"], "automatedTest": "testQuery"}]}]}
        new = [{"object": "Draft", "members": [{"member": "query", "kind": "method", "static": True, "anchor": "query", "signatures": ["query()"]}]}]
        result = audit.merge_evidence(new, old)[0]
        self.assertEqual(result["reviewNotes"], "Keep object evidence")
        self.assertEqual(len(result["members"]), 1)
        self.assertEqual(result["members"][0]["automatedTest"], "testQuery")

    def test_changed_reference_stays_pending_until_review(self):
        old = {"objects": [{"object": "Draft", "members": [{"anchor": "query", "signatures": ["new"], "referenceChanged": True}]}]}
        result = audit.merge_evidence([{"object": "Draft", "members": [{"anchor": "query", "signatures": ["new"]}]}], old)
        self.assertTrue(result[0]["members"][0]["reviewRequired"])

    def test_closure_rejects_missing_or_stale_contract_evidence(self):
        member = {"member": "query", "kind": "method", "static": True}
        matrix = {"objects": [{"object": "Draft", "members": [member]}]}
        self.assertEqual(audit.validate_matrix(matrix), [])
        self.assertIn("Unclassified member: Draft.query", audit.validate_matrix(matrix, True))
        member["compatibilityStatus"] = "complete"
        self.assertIn("Missing automatedTest: Draft.query", audit.validate_matrix(matrix))
        member.update({k: "checked" for k in ["defaults", "result", "errors", "automatedTest", "implementationEvidence"]})
        self.assertEqual(audit.validate_matrix(matrix, True), [])
        member["referenceChanged"] = True
        self.assertIn("Reference review required: Draft.query", audit.validate_matrix(matrix, True))

    def test_failed_fetch_preserves_original_snapshot_date(self):
        old = {"referenceDate": "old date", "objects": [{"object": "Draft", "members": [{"anchor": "query"}]}]}
        result = audit.merge_evidence([{"object": "Draft", "members": [], "fetchError": "offline"}], old)
        self.assertEqual(result[0]["snapshotDate"], "old date")

    def test_step_inventory_rejects_duplicates_and_unexplained_gaps(self):
        step = {"type": "script", "compatibilityStatus": "partial", "limitations": ["Native timeout acceptance pending"]}
        matrix = {"stepReferences": [{"steps": [step]}]}
        self.assertEqual(audit.validate_matrix(matrix), [])
        matrix["stepReferences"][0]["steps"].append(dict(step))
        self.assertIn("Duplicate step: script", audit.validate_matrix(matrix))
        step["limitations"] = []
        self.assertIn("Missing step limitation: script", audit.validate_matrix(matrix))



class StrictParityTests(unittest.TestCase):
    def test_empty_inventory_cannot_pass_parity(self):
        errors = audit.validate_matrix({}, require_parity=True)
        self.assertIn("Missing scope object: Draft", errors)
        self.assertIn("Missing scope step: script", errors)
        self.assertIn("Missing engine contracts", errors)

    def test_core_scope_requires_dependencies_without_requiring_engine(self):
        errors = audit.validate_matrix({}, require_parity=True, scope="core")
        self.assertIn("Missing scope object: Syntax", errors)
        self.assertIn("Missing scope step: createDraft", errors)
        self.assertNotIn("Missing scope object: HTTP", errors)
        self.assertNotIn("Missing engine contracts", errors)

    def complete_entry(self):
        test = {"suite": "UtilityActionAPITests", "test": "deviceUsesMacValuesAndReportsUnavailableBatteryExplicitly"}
        return {"compatibilityStatus": "complete", "defaults": "No input defaults.", "result": "Mac",
                "errors": "No error for this constant.", "implementationEvidence": {"file": "Bridge.js"},
                "automatedTest": test, "reviewDate": "2026-10-19",
                "contractCases": {"normal": {"test": test, "assertion": "Device.model returns Mac."},
                                  "defaults": {"notApplicable": "The property has no inputs."},
                                  "errors": {"notApplicable": "The property is a platform constant."}},
                "nativeVerification": {"status": "not-required", "reason": "This is a fixed platform constant."}}

    def engine_matrix(self):
        return {"engineContracts": [dict(self.complete_entry(), contract=name)
                                     for name in sorted(audit.REQUIRED_ENGINE_CONTRACTS)]}

    def test_engine_scope_passes_only_with_all_required_contracts(self):
        matrix = self.engine_matrix()
        self.assertEqual(audit.validate_matrix(matrix, require_parity=True, scope="engine"), [])
        for entry in list(matrix["engineContracts"]):
            with self.subTest(contract=entry["contract"]):
                reduced = {"engineContracts": [item for item in matrix["engineContracts"] if item is not entry]}
                self.assertIn("Missing engine contract: " + entry["contract"],
                              audit.validate_matrix(reduced, require_parity=True, scope="engine"))

    def test_global_scope_requires_engine_inventory_but_core_does_not(self):
        matrix = self.engine_matrix()
        removed = matrix["engineContracts"].pop()
        expected = "Missing engine contract: " + removed["contract"]
        self.assertIn(expected, audit.validate_matrix(matrix, require_parity=True))
        self.assertNotIn(expected, audit.validate_matrix(matrix, require_parity=True, scope="core"))

    def test_engine_duplicates_cannot_replace_missing_contracts(self):
        matrix = self.engine_matrix()
        removed = matrix["engineContracts"].pop()
        duplicate = dict(matrix["engineContracts"][0])
        matrix["engineContracts"].append(duplicate)
        errors = audit.validate_matrix(matrix, require_parity=True, scope="engine")
        self.assertIn("Duplicate engine contract: " + duplicate["contract"], errors)
        self.assertIn("Missing engine contract: " + removed["contract"], errors)
        self.assertEqual(audit.validate_matrix(matrix), [])

    def test_engine_scope_requires_names_and_specific_contract_evidence(self):
        matrix = self.engine_matrix()
        entry = matrix["engineContracts"][0]
        name = entry.pop("contract")
        entry["name"] = name
        errors = audit.validate_matrix(matrix, require_parity=True, scope="engine")
        self.assertIn("Missing engine contract name", errors)
        self.assertIn("Missing engine contract: " + name, errors)
        entry["contract"] = name
        entry["contractCases"].pop("errors")
        entry["nativeVerification"] = {"status": "pending"}
        errors = audit.validate_matrix(matrix, require_parity=True, scope="engine")
        self.assertIn("Missing contract case errors: engine:" + name, errors)
        self.assertIn("Missing native verification: engine:" + name, errors)

    def test_partial_contract_cannot_pass_with_a_written_limitation(self):
        entry = self.complete_entry()
        entry.update(compatibilityStatus="partial", limitations=["A branch is missing."])
        errors = audit.parity_errors(entry, "Device.model", audit.APPROVED_EXCLUSIONS)
        self.assertIn("Contract is not complete: Device.model", errors)
        self.assertIn("Unresolved contract limitations: Device.model", errors)

    def test_complete_contract_requires_cases_and_native_evidence(self):
        entry = self.complete_entry()
        self.assertEqual(audit.parity_errors(entry, "Device.model", set()), [])
        entry.pop("nativeVerification")
        entry["contractCases"].pop("errors")
        errors = audit.parity_errors(entry, "Device.model", set())
        self.assertIn("Missing native verification: Device.model", errors)
        self.assertIn("Missing contract case errors: Device.model", errors)
        entry["automatedTest"]["test"] = "thisTestDoesNotExist"
        self.assertIn("Invalid contract test reference: Device.model", audit.parity_errors(entry, "Device.model", set()))

    def test_exclusions_and_unavailability_need_specific_evidence(self):
        self.assertIn("Unapproved exclusion: Draft.query", audit.parity_errors({"compatibilityStatus": "excluded"}, "Draft.query", audit.APPROVED_EXCLUSIONS))
        entry = {"compatibilityStatus": "unavailable", "availabilityEvidence": "Not on my machine"}
        self.assertIn("Missing unavailable-capability evidence: App.startLiveActivity", audit.parity_errors(entry, "App.startLiveActivity", set()))
        entry["referenceChanged"] = True
        self.assertIn("Parity reference review required: App.startLiveActivity", audit.parity_errors(entry, "App.startLiveActivity", set()))

    def test_reference_archive_is_immutable_and_hash_checked(self):
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = audit.archive_reference(b"<html>Reference</html>", "Draft", "https://example.com/Draft", "2026-10-19T12:00:00Z", root)
            path = root / archive["path"]
            first = path.read_bytes()
            self.assertTrue(audit.validate_archive(archive, root))
            audit.archive_reference(b"<html>Reference</html>", "Draft", archive["url"], archive["capturedAt"], root)
            self.assertEqual(path.read_bytes(), first)
            path.write_bytes(b"corrupt")
            self.assertFalse(audit.validate_archive(archive, root))
            with self.assertRaises(ValueError):
                audit.archive_reference(b"<html>Reference</html>", "Draft", archive["url"], archive["capturedAt"], root)

    def test_contract_text_change_invalidates_unchanged_signature(self):
        old = {"objects": [{"object": "Draft", "members": [{"anchor": "query", "signatures": ["query()"], "contract": "Old default"}]}]}
        new = [{"object": "Draft", "members": [{"anchor": "query", "signatures": ["query()"], "contract": "New default"}]}]
        self.assertTrue(audit.merge_evidence(new, old)[0]["members"][0]["reviewRequired"])


if __name__ == "__main__":
    unittest.main()
