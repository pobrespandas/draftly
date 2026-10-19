#!/usr/bin/env python3
"""Prepare a signed CloudKit test app with a separate local library."""
import plistlib
from pathlib import Path
import sys
import uuid

path = Path(sys.argv[1])
previous = plistlib.loads(path.read_bytes()) if path.exists() else {}
info = plistlib.loads(Path("Configuration/Info.plist").read_bytes())
info["CFBundleName"] = info["CFBundleDisplayName"] = "Draftly iCloud QA"
info["DraftlyCloudTesting"] = True
container = "iCloud.com.andrestobelem.draftly.cloudqa"
info["DraftlyQATestContainer"] = container
if previous.get("DraftlyQATestContainer") == container:
    info["DraftlyUITestingLibraryID"] = previous.get("DraftlyUITestingLibraryID", str(uuid.uuid4()))
else:
    info["DraftlyUITestingLibraryID"] = str(uuid.uuid4())
    if previous:
        path.with_name("Info.previous.plist").write_bytes(plistlib.dumps(previous))
path.write_bytes(plistlib.dumps(info))
