#!/usr/bin/env python3
"""Prepare Cloud QA metadata with a separate local library."""
import copy
import plistlib
from pathlib import Path
import sys
import uuid

CLOUD_QA_CONTAINER = "iCloud.com.andrestobelem.draftly.cloudqa"


def cloud_qa_metadata(template, previous, generated_library_id):
    info = copy.copy(template)
    info["CFBundleName"] = info["CFBundleDisplayName"] = "Draftly iCloud QA"
    info["DraftlyCloudTesting"] = True
    info["DraftlyQATestContainer"] = CLOUD_QA_CONTAINER
    same_container = previous.get("DraftlyQATestContainer") == CLOUD_QA_CONTAINER
    info["DraftlyUITestingLibraryID"] = previous.get("DraftlyUITestingLibraryID", generated_library_id) if same_container else generated_library_id
    return info, not same_container and bool(previous)


def prepare(path, *, source_path=Path("Configuration/Info.plist"), uuid_factory=None):
    path = Path(path)
    previous = plistlib.loads(path.read_bytes()) if path.exists() else {}
    template = plistlib.loads(Path(source_path).read_bytes())
    factory = uuid.uuid4 if uuid_factory is None else uuid_factory
    info, save_previous = cloud_qa_metadata(template, previous, str(factory()))
    if save_previous:
        path.with_name("Info.previous.plist").write_bytes(plistlib.dumps(previous))
    path.write_bytes(plistlib.dumps(info))


def main(argv=None):
    arguments = sys.argv[1:] if argv is None else argv
    prepare(Path(arguments[0]))


if __name__ == "__main__":
    main()
