# Chat usability acceptance

Status: implementation in progress. Not released.

## Intended behavior

Chat responses render Markdown blocks and retain the original source for Copy.
Create draft and Insert use the window's existing capture and editor paths.
Chat uses the editor font and the window appearance. Scrolling follows a response
only while the reader remains near the bottom.

The release migrates existing, live grants once to all currently available
capabilities and library scope. It preserves expiry, revocation and the enabled
switch. A new grant identity invalidates previous authorization snapshots.
New chat connections use library scope. They can create drafts without an
existing draft. Connection expiry remains 15 minutes. Native and destructive
operation reviews remain active.

The limited resource picker loads 50 matching resources per page. Library-wide
review does not enumerate resources. Common model instructions describe Draftly,
the current authorized tools, and confirmed results. Apple-specific tool syntax
remains in its provider adapter.

## Evidence

- Initial Markdown and migration run: 16 tests passed.
- A 10,000-draft fixture fetched two pages and searched a Unicode title in
  67 milliseconds in the first measured run. This is a local measurement,
  not a fixed latency guarantee.
- An initial concurrent run missed an approval within the timeout test's
  deadline. The isolated serial interruption test passed without a timeout change.
- Native QA build succeeded with the worktree package identity and inherited
  Swift compiler flags. The normal project identity remains unchanged.

## Remaining acceptance

Run the complete inventory after final edits. Check Markdown, accessibility,
Copy, Create, Insert, Undo, scrolling and row actions in the signed installed QA.
Test creation, editing, confirmed readback, cancellation and failure reporting
with ChatGPT and Apple Intelligence. Check a signed update from 0.4.0, including
one-time grant migration. Record CI, artifact and publication evidence before
changing this status to released.
