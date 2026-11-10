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

## Automatic chat tools implementation

Commit `abf66c9` enables local access once per library when the app is unlocked
and protected data is available. Later manual changes to local access remain
in effect. The chat connects automatically when its provider is available.
Its connections use a distant-future expiry. Disconnect disables automatic
connection and saves that choice across restart. The CLI pairing flow keeps
its existing expiry rules.

Native build passed. Twelve existing Chat Console tests, the new persisted
opt-out test, and 47 host tests passed. Build 45 includes the Apple read adapter
correction and automatic scrolling. Notarization
`6fa2b0b4-2a45-4696-bc11-802d328d33c0` was accepted. Installed combined acceptance
is pending approval for the new automatic QA connections. Do not mark released.

## Installed combined acceptance — build 46

Build 46 uses source `181522c`. Notarization
`bd1661d5-a750-4e7b-ac8d-c30ed432750d` was accepted and stapled.
The previous QA instance was closed before this build opened the library.
The prior manual off setting remained off. After the approved QA enable step,
opening chat connected ChatGPT when model loading finished, without Connect.
Switching to Apple Intelligence also connected automatically.

Apple created `QA conjunta café 🐼` with the second line `El panda prepara café.`
and returned the saved text. Opening it showed 41 characters. Apple then read
and edited it, adding `Edición Apple confirmada.`. The editor showed 69 characters.
ChatGPT connected automatically on provider change, read the editor, prepared
and applied `editor.replaceRange`, then read the result. The editor showed
97 characters and its response matched. Native Undo restored 69 characters.

The transcript stayed at the bottom after replies. Scrolling up during a
response kept the earlier messages visible and showed Latest message. That
button returned the scrollbar to 1. Sending from an earlier position also
returned it to 1. Stop response returned the composer to idle. Disconnect
removed the connection. Settings showed no approved connections. Stop Work
turned local access off. These are observed installed results, not publication.

The CI default-off assertion was updated to check default-on without credentials,
then explicit off and protected-data admission. All 11 application-host tests
passed locally. CI must pass again before integration or release.

### Composition refactor checkpoint — 10 November 2026

The draft panel and chat now use one panel composition with header, content,
status, and footer slots. The chat composer uses NativeEditor with a separate
EditorSession and UndoManager. It uses the Markdown font preference and the
window theme. Return submits, Shift-Return inserts a line, and marked text
bypasses submission. The composer measures laid-out text, including wrapping.

The prior serial chat and theme run passed 88 tests. The independent Undo test
passed. The final composition tests, installed build acceptance, full CI, and
signed update from 0.4.0 remain open. Build 47 notarization was accepted, but
that package predates the final panel extraction and is not final acceptance.

Build 48 (3ca3aef) and its helper were signed and notarized together.
Submission b723d2bd-1758-4c1b-beae-10c3a5b91f6c was Accepted.
Installed QA confirmed Unicode paste, Shift-Return, Return submission to
ChatGPT, bottom following after the response, and an empty composer after
Command-Z following send. No tool connection was created. A seven-line prompt
exposed an inaccurate five-line height estimate. The follow-up uses the native
font line height. This correction needs a new installed acceptance build.

The complete local Swift verifier passed: consumer 1, contracts 197, core 837,
app 1718. The subsequent focused run passed 17 tests, including Return,
Shift-Return, marked IME text, independent Undo, and conversation changes.
Conversation changes clear the unsent prompt and trigger automatic tool
reconnection when enabled. Manual tool opt-out remains in force.

### Signed update fixture — 10 November 2026

The official 0.4.0 ZIP passed its published checksum and strict code signature.
A separate fixture uses source tag v0.4.0 (42c094d) with a QA-only loopback feed
adapter. It is not the unmodified public binary. Production source retains its
HTTPS feed restriction. Both fixture apps use library
46FAF430-F21D-40B8-9427-782BA82A9D40 and a separate Sparkle key in Keychain.
Archive and feed signatures remain required. The baseline is build 40; the
target is build 50 from cfa6e06. Both app/helper packages were notarized and
stapled: db7702e2-897a-40e9-be6e-f5dd43407405 and
c0e3370b-101e-41e3-976b-88960edc3a79.

The baseline opened and saved the neutral Unicode draft “Actualización 0.4.0
café 🐼” (71 characters, 10 words). Check for Updates is present. The first check
failed because sign_update was waiting for Keychain permission, so the local
feed server had not started. Computer Use cannot control SecurityAgent. User
handoff is pending. No update installation or grant migration is claimed.

Build 50 installed composer QA also confirmed that New Chat clears the prompt
and Command-Z does not restore the prior conversation's input. The composer
scrolls internally for seven lines. Apple/ChatGPT tool acceptance remains
pending the requested connection approval. Access was not enabled.

A follow-up review found that external composer resets could register a new
Undo entry after clearing the manager. Independent editor resets now clear
Undo inside the shared replacement path and do not register the old prompt.
A coordinator-level regression test confirms an empty composer with no Undo.
The focused run passed 33 chat, theme, and composition tests. A new installed
build is required for this final correction.
