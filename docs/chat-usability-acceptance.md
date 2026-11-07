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

- Commit `02bc32b`: the full inventory passed 2,749 tests (1 consumer,
  197 contracts, 837 core, 1,714 app). The final focused run passed 37 tests.
- Signed installed QA build 41 uses this commit and library
  `A2E91C40-0C42-4F37-96B3-76E07449F8A0`. Combined notarization
  `baa6293f-5098-4282-b70b-d4d3a8e1d0c8` was accepted and stapled.
- In the installed QA, Apple Intelligence returned a list with bold names.
  The chat rendered bullets and emphasis. Copy pasted the original Markdown
  into the composer with accents intact. Create draft saved the response.
  Insert increased its length from 326 to 652 characters. Undo restored 326.
- Code fences remain literal code. The first request asked for a Markdown
  example and the model wrapped it in a fence. A new conversation with a
  normal writing request rendered as expected.
- A 10,000-draft fixture fetched two pages and searched a Unicode title in
  67 milliseconds in the first measured run. This is a local measurement,
  not a fixed latency guarantee.
- An initial concurrent run missed an approval within the timeout test's
  deadline. The isolated serial interruption test passed without a timeout change.
- Native QA build succeeded with the worktree package identity and inherited
  Swift compiler flags. The normal project identity remains unchanged.

## Installed tool failure and correction

Build 41 connected Apple Intelligence with library scope and all available
capabilities. A create-and-read request failed with 8,503 input tokens against
an 8,192-token runtime limit. The library still had two drafts. The chat showed
the error and did not claim that it created the draft. Disconnect removed the
connection. Settings then showed no approved connections and local access off.

The Apple adapter now lists operation names without descriptions. It loads the
full description and schema only for the selected operation. Its two generic
schemas no longer repeat every authorized name. The gateway still checks each
name and the current permission. Public MCP operation schemas do not change.
This correction still needs installed real-model acceptance.

## ChatGPT installed acceptance

Build 41 signed in to ChatGPT in the isolated QA namespace. A 15-minute
library-wide connection created `QA ChatGPT café 🐼` with a second line,
`El panda prepara café.`. Activity recorded successful `mutations.prepare`,
`drafts.create` and `drafts.get`. The response confirmed the same text.
Opening the new draft showed 40 characters and 8 words.

Opening that draft also exposed a remaining view callback that disconnected
all chat sessions on selection changes. The correction keeps library-wide
sessions across draft changes. Resource-limited sessions still disconnect.
Both QA connections were removed and local access was turned off after testing.
The selection correction still needs installed acceptance.

## Corrected QA package

Build 43 contains commit `7d45e20`. Notarization
`06112c98-9a84-4437-b28f-5a807e991e80` was accepted and stapled.
The installed app retained the three QA drafts. Settings showed no approved
connections and local access off. ChatGPT sign-in was completed in the isolated
QA namespace before the update.

The compact catalog commit `d0708a3` passed the complete 2,749-test inventory.
The selection correction passed 12 Chat Console tests, including both library
and resource scope. Installed model acceptance remains pending.

## Remaining acceptance

Check remaining Markdown block types, accessibility, scrolling, cancellation
and row actions in the signed installed QA.
Test creation, editing, confirmed readback, cancellation and failure reporting
with ChatGPT and Apple Intelligence. Check a signed update from 0.4.0, including
one-time grant migration. Record CI, artifact and publication evidence before
changing this status to released.

## Build 43 follow-up

Apple Intelligence kept library access when the selected draft changed. Three
requests failed with the native tool-call error; no draft was created or edited.
The error log reported `AgentContracts.AgentErrorCode (1)`. It did not identify
the requested tool, so the exact cause is not yet confirmed. The adapter now
restores schema constraints on operation names while retaining compact catalog
results. Nine adapter tests passed. Real-model verification remains open.

ChatGPT read the open editor, prepared a mutation, used `editor.replaceRange`,
and read the editor again. The neutral draft grew from 40 to 71 characters.
Its response matched the editor. Native Undo restored the original 40 characters.
Stop response returned the composer to its idle state during a separate
non-mutating generation. Both connections were removed and access was off.

## Additional requested behavior

The user requested default-on chat tools without the current 15-minute product
workflow, while retaining manual Disconnect and Stop Work. This is not yet
implemented. QA connections remain explicitly time-limited.

The user also requested automatic downward scrolling. The new UI change follows
new messages and streaming content, preserves deliberate upward scrolling, and
adds Latest message. It compiled; installed visual verification remains open.

## Local model regression probes

The compact generic catalog still failed before dispatching a write. A live
in-memory probe recorded only discovery calls and a schema-format refusal.
The Apple adapter now keeps authorized name constraints and provides a direct
`draftly_create_draft` adapter. It prepares the mutation and uses the existing
create handler. Public MCP names and schemas do not change.

With the real on-device model, the create-and-read probe passed, including
observed `drafts.create` and `drafts.get`. The existing direct-edit probe also
passed. Nine deterministic adapter tests passed. The forced generic-call read
probe failed: the model reported request-ID and schema errors without calling
`drafts.get`. This is an open acceptance failure, not a passing suite. Do not
release on this evidence alone. The new adapters still need installed QA.

The generic adapter now omits empty optional envelope strings before contract
validation. The deterministic authorized-read and rejected-create test passed.
The live forced generic read still failed, this time after exceeding the
8,192-token context window (8,193 tokens). This path needs further work. No
release acceptance is claimed for it. All installed QA access remains off.

The follow-up adapter treats an empty catalog name as a list request and omits
write-envelope fields for read-only operations. The real-model forced generic
read passed in 9.3 seconds. The deterministic gateway authorization test also
passed. This is isolated-model evidence; installed acceptance is still open.
