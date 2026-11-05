# Scoped local import inputs

`AgentImportReading` resolves inline text, ready connection-owned transfers and
files within saved directory bookmarks. The caller supplies a byte limit no
larger than the transfer limit and a live authority validator. HTTPS input still
returns `interactionRequired`; this component does not fetch a URL.

Bookmark input requires `files.read` and access to the bookmark resource ID. The
ID binds the saved permission bytes. The reader uses the saved bookmark, not a
caller-supplied absolute path. It validates the relative path, resolves the
granted root once with `realpath`, and opens each component with `openat` and
`O_NOFOLLOW`. Directory handles pin each ancestor while traversal continues.
The final descriptor must be a regular file. Nonblocking opens reject FIFOs
without waiting for a writer. File size and bounded reads limit allocation.

The reader checks authority between read chunks and before returning. It also
checks the saved bookmark identity again. Size and modification metadata must
remain unchanged during the read. This detects ordinary concurrent writes; it is
not a file-system snapshot or a guarantee against a privileged local process.
No path or bookmark bytes are returned to the caller.

Backup validation and restore preview now use this resolver. They can read a
saved, authorized backup file without opening a picker or changing the library.
A missing bookmark fails closed. Network input still needs its reviewed route.
Theme installation and replacement remain without handlers. File-mode theme
installation still needs creation and validation of its own saved file bookmark.

## Local coverage

Nine cases cover exact-size reads, oversized files, resource denial, missing
capability, parent traversal, symbolic-link escape, directories, FIFOs and live
authority loss. Backup integration tests validate and preview saved input while
preserving library data. Existing transfer ownership tests remain applicable.
Signed installed access remains open.

Strict validation passed 1 consumer, 193 contract, 826 Core and 1,674 app tests
(2,694 total). Native Debug passed. Logs: `/tmp/draftly-import-reading-full.log`
and `/tmp/draftly-import-reading-build.log`. Current-source CI remains pending.

## Root identity check

The reader checks that the resolved root is a directory before canonicalization.
After opening it, device and inode must match that check. A symbolic-link swap
between the check and open fails before traversal. This narrows the path race;
it does not claim to stop a privileged process from controlling the file system.

Expanded tests cover 12 cases. They include a root swap injected at the authority
check, changed saved permission bytes, and a symbolic link at the final file.
All four focused tests in two suites passed, including backup integration. The
log is `/tmp/draftly-import-root-check.log`. The preceding complete 2,694-test
result predates this root check.

Native Debug passed after the root check. Log: `/tmp/draftly-import-root-build.log`.

## Narrow file permission capture

The snapshot can now capture a file permission for theme installation. It does so
while the original file descriptor and granted directory scope remain live. The
resolved permission must refer to the same device, inode, size and modification
metadata. The snapshot returns permission bytes only to the app-owned effect
route. They are not part of CLI or MCP results.

Expanded input tests cover 24 cases with permission capture on and off. Complete
validation passed 2,701 tests and native Debug. See
[installation evidence](agent-theme-installation-review.md) for final logs and
remaining acceptance. The earlier local-input reports above predate capture.

## Reviewed HTTPS inputs

The parent command now owns the reviewed HTTPS download. The local input reader
still rejects network input. See [HTTPS input evidence](agent-https-input-acceptance.md)
for authority checks, limits, recovery and acceptance gaps.
