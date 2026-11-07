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
