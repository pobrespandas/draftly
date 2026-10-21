#!/usr/bin/env python3
"""Record reference contracts. Keep compatibility evidence on refresh."""
import argparse
import concurrent.futures
import copy
import datetime
import hashlib
import gzip
import html
import importlib.util
import json
from pathlib import Path
import re
import urllib.request

_test_reference_spec = importlib.util.spec_from_file_location(
    "draftly_swift_test_references", Path(__file__).with_name("swift_test_references.py"))
_test_reference_module = importlib.util.module_from_spec(_test_reference_spec)
_test_reference_spec.loader.exec_module(_test_reference_module)
SwiftTestReferences = _test_reference_module.SwiftTestReferences

ROOT = Path(__file__).resolve().parent.parent
OBJECTS = "Draft Editor Workspace Action ActionGroup ActionLog App Context Prompt SelectPrompt Tag Syntax Version Window Device HTTP HTTPResponse XMLRPC XMLRPCResponse FileManager Bookmark Credential HTML HTMLPreview HTMLToMarkdown MultiMarkdown GitHubMarkdown MustacheTemplate Shortcut AppleScript ShellScript Mail Message Calendar Event Reminder ReminderList Speech Location ModelSession Script URL CallbackURL Base64 QueryDate Task SelectPromptItem navigationMarker linkedItem Share".split()
REFERENCE_FIELDS = {"member", "anchor", "kind", "static", "readonly", "signatures", "contract", "referenceRemoved", "referenceChanged"}
CORE_OBJECTS = set("Draft Editor Workspace QueryDate Task navigationMarker linkedItem Syntax Version ActionLog Prompt SelectPrompt SelectPromptItem".split())
CORE_STEPS = {"createDraft", "configureWindow", "prompt"}
STEP_TYPES = set("share clipboard mail message reminder listInReminders event export openIn print speak createDraft insertText defineTemplateTag configureWindow script runShortcut runAppleScript htmlpreview configurationKey includeAction prompt url callbackUrl runDrafts4Action".split())
APPROVED_EXCLUSIONS = {"Window.showChatConsole", "Window.hideChatConsole", "step:runDrafts4Action"}
REQUIRED_ENGINE_CONTRACTS = frozenset({
    "completion and timer isolation",
    "synchronous deadline",
    "promise rejection and asynchronous timeout",
    "cross-window exclusion",
    "shared included scripts",
    "circular inclusion",
    "queue cancellation",
    "final callback selection",
    "unknown disabled imports",
    "separator imports",
    "worker isolation and responsiveness",
    "host request lifetime",
    "task cancellation",
    "common asynchronous entry points",
})



def archive_reference(raw, name, url, captured_at, root=ROOT):
    digest = hashlib.sha256(raw).hexdigest()
    relative = Path("docs/research/action-api-reference") / captured_at[:10] / (name + "." + digest + ".html.gz")
    target = root / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        try:
            saved = gzip.decompress(target.read_bytes())
        except (OSError, EOFError) as error:
            raise ValueError("The saved reference archive is corrupt: " + str(relative)) from error
        if saved != raw:
            raise ValueError("The saved reference archive is corrupt: " + str(relative))
    else:
        target.write_bytes(gzip.compress(raw, mtime=0))
    return {"path": str(relative), "sha256": digest, "url": url, "capturedAt": captured_at}


def plain(value):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", "", value))).strip()


def parse_members(text):
    headings = list(re.finditer(r'<h3[^>]*id="([^"]+)"[^>]*>(.*?)</h3>', text, re.S))
    members, seen = [], set()
    for index, match in enumerate(headings):
        anchor, heading = match.groups()
        if anchor.startswith("about-"):
            continue
        body = text[match.end():headings[index + 1].start() if index + 1 < len(headings) else len(text)]
        signatures = re.findall(r'<div class="tsd-signature[^\"]*"[^>]*>(.*?)</div>', body, re.S)
        if not signatures:
            continue
        name = re.search(r'<span class="tsd-kind-(?:property|accessor|call-signature|constructor-signature)">([^<]+)</span>', signatures[0])
        label = name.group(1) if name else plain(re.search(r'<span>(.*?)</span>', heading, re.S).group(1))
        if anchor == "constructor":
            label = "constructor"
        kind = "constructor" if label == "constructor" else "method" if "tsd-signatures" in body[:body.find(signatures[0])] else "property"
        static = ">Static</code>" in heading
        key = (label, kind, static)
        if key in seen:
            continue
        seen.add(key)
        description = re.search(r'<div class="tsd-comment tsd-typography">(.*?)</div>', body, re.S)
        members.append({"member": label, "anchor": anchor, "kind": kind, "static": static,
                        "readonly": ">Readonly</code>" in heading,
                        "signatures": [plain(value) for value in signatures],
                        "contract": plain(description.group(1)) if description else "",
                        "implementation": "not-audited", "automatedTest": None, "liveCheck": None})
    return members


def member_key(member):
    return member.get("member"), member.get("kind"), bool(member.get("static"))


def snapshot(name):
    section = "types" if name in {"navigationMarker", "linkedItem"} else "classes"
    url = "https://scripting.getdrafts.com/" + section + "/" + name
    try:
        with urllib.request.urlopen(url, timeout=30) as response:
            raw = response.read()
        members = parse_members(raw.decode())
        if not members:
            raise ValueError("No member signatures were found")
        captured_at = datetime.datetime.now(datetime.timezone.utc).isoformat()
        archive = archive_reference(raw, name, url, captured_at)
        return {"object": name, "url": url, "sha256": archive["sha256"], "snapshotDate": captured_at, "referenceArchive": archive, "members": members}
    except Exception as error:
        return {"object": name, "url": url, "fetchError": str(error), "members": []}


def merge_evidence(objects, previous):
    old_objects = {obj["object"]: obj for obj in previous.get("objects", [])}
    for obj in objects:
        old = old_objects.get(obj["object"], {})
        for field, value in old.items():
            if field not in {"members", "sha256", "url", "object", "fetchError", "snapshotDate"}:
                obj.setdefault(field, value)
        if "fetchError" in obj and old.get("members"):
            obj["members"] = old["members"]
            obj["sha256"] = old.get("sha256")
            obj["snapshotDate"] = old.get("snapshotDate", previous.get("referenceDate"))
            continue
        evidence = {member["anchor"].lower(): member for member in old.get("members", [])}
        by_key = {member_key(member): member for member in old.get("members", []) if member.get("member")}
        current_keys = {member_key(member) for member in obj["members"] if member.get("member")}
        current_anchors = {member["anchor"].lower() for member in obj["members"]}
        for member in obj["members"]:
            prior = evidence.get(member["anchor"].lower()) or by_key.get(member_key(member), {})
            for field, value in prior.items():
                if field not in REFERENCE_FIELDS:
                    member[field] = value
            changed = any(field in prior and prior[field] != member.get(field) for field in ("signatures", "contract", "readonly", "kind", "static"))
            if prior.get("referenceChanged") or changed:
                member["referenceChanged"] = True
                member["reviewRequired"] = True
        for anchor, member in evidence.items():
            if anchor not in current_anchors and (not member.get("member") or member_key(member) not in current_keys):
                obj["members"].append(dict(member, referenceRemoved=True))
    return objects


def supplement_reference(previous, reference):
    """Update one reference. Keep the baseline date and all other evidence."""
    name = reference.get("object")
    if name not in OBJECTS:
        raise ValueError("The supplemental object is outside the inventory.")
    if reference.get("fetchError") or not reference.get("members") or not reference.get("referenceArchive"):
        raise ValueError("The supplemental reference is incomplete.")
    result = copy.deepcopy(previous)
    updated = merge_evidence([copy.deepcopy(reference)], result)[0]
    objects = result.setdefault("objects", [])
    for index, existing in enumerate(objects):
        if existing.get("object") == name:
            objects[index] = updated
            break
    else:
        objects.append(updated)
    result.setdefault("supplementalReferences", []).append({
        "object": name, "referenceArchive": copy.deepcopy(reference["referenceArchive"])
    })
    return result


def parity_errors(entry, label, approved_exclusions, *, test_references=None):
    if test_references is None:
        test_references = SwiftTestReferences(ROOT)
    errors = []
    if any(entry.get(field) for field in ("referenceChanged", "reviewRequired", "referenceRemoved")):
        errors.append("Parity reference review required: " + label)
    status = entry.get("compatibilityStatus")
    if status == "excluded":
        if label not in approved_exclusions:
            errors.append("Unapproved exclusion: " + label)
        return errors
    if status == "unavailable":
        evidence = entry.get("availabilityEvidence")
        if not isinstance(evidence, dict) or not all(evidence.get(field) for field in ("date", "platform", "reason", "evidence")) or not test_references.valid(entry.get("automatedTest")):
            errors.append("Missing unavailable-capability evidence: " + label)
        return errors
    if status != "complete":
        errors.append("Contract is not complete: " + label)
    for field in ("defaults", "result", "errors", "automatedTest", "implementationEvidence", "reviewDate"):
        if not entry.get(field):
            errors.append("Missing parity " + field + ": " + label)
    if not test_references.valid(entry.get("automatedTest")):
        errors.append("Invalid contract test reference: " + label)
    cases = entry.get("contractCases", {})
    for topic in ("normal", "defaults", "errors"):
        case = cases.get(topic) if isinstance(cases, dict) else None
        if not isinstance(case, dict) or not (
            case.get("assertion") and test_references.valid(case.get("test"))
            or topic != "normal" and case.get("notApplicable")
        ):
            errors.append("Missing contract case " + topic + ": " + label)
    native = entry.get("nativeVerification")
    if not isinstance(native, dict) or native.get("status") not in {"passed", "not-required"}:
        errors.append("Missing native verification: " + label)
    elif native["status"] == "passed" and not all(native.get(field) for field in ("date", "evidence")):
        errors.append("Incomplete native verification: " + label)
    elif native["status"] == "not-required" and not native.get("reason"):
        errors.append("Missing native-verification reason: " + label)
    if entry.get("limitations"):
        errors.append("Unresolved contract limitations: " + label)
    if status == "complete":
        references = [entry.get("automatedTest"), entry.get("legacyAutomatedTest")]
        references.extend(case.get("test") for case in (cases.values() if isinstance(cases, dict) else []) if isinstance(case, dict))
        for field in ("supportingTests", "additionalAutomatedTests"):
            supporting = entry.get(field, [])
            if not isinstance(supporting, list):
                errors.append("Invalid test reference collection " + field + ": " + label)
            else:
                references.extend(supporting)
        for reference in references:
            if reference is not None and not test_references.valid(reference):
                errors.append("Invalid contract test reference: " + label + ": " + str(reference))
                continue
            issue = test_references.issue(reference)
            if issue:
                errors.append("Unaccepted contract test: " + label + ": " + issue)
    return errors


def swift_code_mask(source):
    return _test_reference_module.swift_code_mask(source)


def test_reference_issue(value):
    return SwiftTestReferences(ROOT).issue(value)


def valid_test_reference(value):
    return SwiftTestReferences(ROOT).valid(value)


def test_reference_paths(value):
    return SwiftTestReferences(ROOT).paths(value)


def validate_archive(archive, root=ROOT):
    if not isinstance(archive, dict) or not all(archive.get(field) for field in ("path", "url", "sha256", "capturedAt")):
        return False
    path = (root / archive["path"]).resolve()
    if not path.is_relative_to(root.resolve()):
        return False
    try:
        return hashlib.sha256(gzip.decompress(path.read_bytes())).hexdigest() == archive["sha256"]
    except (OSError, ValueError, EOFError):
        return False


def validate_matrix(matrix, require_closure=False, require_parity=False, scope="all"):
    test_references = SwiftTestReferences(ROOT)
    if scope == "engine":
        matrix = dict(matrix, objects=[], stepReferences=[])
    elif scope == "core":
        matrix = dict(matrix, objects=[obj for obj in matrix.get("objects", []) if obj["object"] in CORE_OBJECTS],
                      stepReferences=[dict(ref, steps=[step for step in ref.get("steps", []) if step["type"] in CORE_STEPS]) for ref in matrix.get("stepReferences", [])], engineContracts=[])
    errors = []
    allowed = {"complete", "partial", "absent", "excluded", "unavailable"}
    seen_objects = set()
    for obj in matrix.get("objects", []):
        name = obj["object"]
        if (require_closure or require_parity) and (obj.get("fetchError") or not obj.get("members")):
            errors.append(f"Missing current reference: {name}")
        if require_parity and not validate_archive(obj.get("referenceArchive")):
            errors.append("Missing or invalid reference archive: " + name)
        if name in seen_objects:
            errors.append(f"Duplicate object: {name}")
        seen_objects.add(name)
        seen = set()
        for member in obj.get("members", []):
            key = member_key(member)
            label = name + "." + str(member.get("member"))
            if key in seen:
                errors.append(f"Duplicate member: {label}")
            seen.add(key)
            status = member.get("compatibilityStatus")
            if status is not None and status not in allowed:
                errors.append(f"Invalid compatibility status: {label}")
            if require_closure and status is None:
                errors.append(f"Unclassified member: {label}")
            if status == "complete":
                for field in ["defaults", "result", "errors", "automatedTest", "implementationEvidence"]:
                    if not member.get(field):
                        errors.append(f"Missing {field}: {label}")
                if member.get("referenceChanged") or member.get("reviewRequired") or member.get("referenceRemoved"):
                    errors.append(f"Reference review required: {label}")
            if status in {"partial", "absent", "excluded", "unavailable"} and not member.get("limitations"):
                errors.append(f"Missing limitation: {label}")
            if require_parity:
                errors.extend(parity_errors(member, label, APPROVED_EXCLUSIONS, test_references=test_references))
    seen_steps = set()
    for reference in matrix.get("stepReferences", []):
        if require_parity and reference.get("fetchError"):
            errors.append("Missing current step reference: " + reference.get("category", "unknown"))
        for step in reference.get("steps", []):
            name = step.get("type")
            if name in seen_steps:
                errors.append(f"Duplicate step: {name}")
            seen_steps.add(name)
            if step.get("compatibilityStatus") not in allowed:
                errors.append(f"Unclassified step: {name}")
            if step.get("compatibilityStatus") != "complete" and not step.get("limitations"):
                errors.append(f"Missing step limitation: {name}")
            if require_parity:
                errors.extend(parity_errors(step, "step:" + name, APPROVED_EXCLUSIONS, test_references=test_references))
                if not validate_archive(step.get("referenceArchive")):
                    errors.append("Missing or invalid step reference archive: " + name)
    if require_parity:
        required_objects = set() if scope == "engine" else CORE_OBJECTS if scope == "core" else set(OBJECTS)
        required_steps = set() if scope == "engine" else CORE_STEPS if scope == "core" else STEP_TYPES
        for name in sorted(required_objects - seen_objects):
            errors.append("Missing scope object: " + name)
        for name in sorted(required_steps - seen_steps):
            errors.append("Missing scope step: " + name)
        if scope != "core" and not matrix.get("engineContracts"):
            errors.append("Missing engine contracts")
        seen_contracts = set()
        for entry in matrix.get("engineContracts", []):
            name = entry.get("contract")
            if not isinstance(name, str) or not name.strip():
                errors.append("Missing engine contract name")
                name = "unnamed"
            if name in seen_contracts:
                errors.append("Duplicate engine contract: " + name)
            seen_contracts.add(name)
            errors.extend(parity_errors(entry, "engine:" + name, APPROVED_EXCLUSIONS, test_references=test_references))
        if scope != "core":
            for name in sorted(REQUIRED_ENGINE_CONTRACTS - seen_contracts):
                errors.append("Missing engine contract: " + name)
    return errors


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Validate the saved matrix without fetching pages.")
    parser.add_argument("--require-closure", action="store_true", help="Require a classification for every member.")
    parser.add_argument("--require-parity", action="store_true", help="Require complete contracts, archived references, and native evidence.")
    parser.add_argument("--scope", choices=["all", "core", "engine"], default="all", help="Select the contract acceptance scope.")
    parser.add_argument("--supplement", choices=OBJECTS, help="Fetch one reference. Keep the baseline date and other references.")
    args = parser.parse_args()
    if args.supplement and (args.check or args.require_closure or args.require_parity):
        parser.error("A supplemental update cannot run with validation flags.")
    if (args.require_closure or args.require_parity) and not args.check:
        parser.error("Closure and parity checks require --check.")
    target = ROOT / "docs/research/action-api-matrix.json"
    previous = json.loads(target.read_text()) if target.exists() else {}
    if args.supplement:
        if not previous.get("referenceDate"):
            parser.error("A supplemental update requires an existing reference baseline.")
        try:
            result = supplement_reference(previous, snapshot(args.supplement))
        except ValueError as error:
            parser.error(str(error))
        target.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
        print("Recorded supplemental reference: " + args.supplement + ". Baseline date retained.")
        raise SystemExit(0)
    if args.check:
        errors = validate_matrix(previous, args.require_closure, args.require_parity, args.scope)
        for error in errors:
            print(error)
        print(f"Matrix check: {len(errors)} errors.")
        raise SystemExit(bool(errors))
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        objects = merge_evidence(list(pool.map(snapshot, OBJECTS)), previous)
    result = dict(previous)
    result.update({"referenceDate": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                   "scope": "Central and generic macOS APIs; third-party service wrappers are excluded", "objects": objects})
    for reference in result.get("stepReferences", []):
        try:
            with urllib.request.urlopen(reference["url"], timeout=30) as response:
                raw = response.read()
            archive = archive_reference(raw, "steps-" + reference["category"], reference["url"], result["referenceDate"])
            reference["referenceArchive"] = archive
            reference.pop("fetchError", None)
            for step in reference.get("steps", []):
                old_archive = step.get("referenceArchive")
                if old_archive and old_archive["sha256"] != archive["sha256"]:
                    step["reviewRequired"] = True
                step["referenceArchive"] = archive
        except Exception as error:
            reference["fetchError"] = str(error)
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(f"Recorded {sum(len(x['members']) for x in objects)} contracts; {sum('fetchError' in x for x in objects)} fetch errors.")
