# Chat usability acceptance

## Composer reconstruction follow-up

A final review found that a new ChatConsolePanel did not copy an existing
unsent prompt into its new EditorSession. The send state could therefore refer
to text that the empty composer did not show. An offscreen native-view test
reproduced this twice, with Unicode text. The prompt observer now also runs
when the view first appears. The same test and the 20-test chat/composition
run passed. Return, Shift-Return, marked IME text, independent Undo, and
conversation resets still passed. Installed reconstruction QA and final-head
CI remain required. The Mac was locked when installed QA was requested.
The build-59 evidence below predates this one-line view correction.

## Installed checkpoint — build 59, 10 November 2026

Code: 6dd321a. Signed installed QA: build 59. The shared panel boundaries,
five-line composer limit, independent Undo, and conversation reset passed.
The combined 42-test run covers submission, Shift-Return, marked IME text,
conversation state, host defaults, and Apple tools. It passed. Physical input
method candidate selection was not tested; the marked-text path was tested.

Apple On-Device and ChatGPT created one neutral draft each, read the correct
created draft, edited the open editor, and read the updated text. Native Undo
restored both edits. The sent composer and a new conversation did not restore
the previous prompt through Undo. Automatic connections worked after provider
and conversation changes. Both providers stopped an in-progress response.
ChatGPT GPT-6-Luna produced a partial list while Stop remained available.
Scrolling up kept the scrollbar below 1 and showed Latest message. That action
returned it to 1 during generation. Stop returned the UI to idle. No extra
notes were created during these cancellation tests. Access was revoked and
the isolated QA was closed with access off.

The signed source-0.4.0 QA fixture updated to build 59 through Sparkle. Its
neutral draft, ID, expiry dates, and revoked/expired grants were preserved.
The live synthetic grant expanded once. Access stayed off and metadata stayed
identical after restart. This fixture uses a loopback feed adapter and synthetic
grants without credentials; it is not acceptance of an unmodified public binary
or multi-device sync. Public archive checksum/signature checks passed earlier.

Full exact-head CI remains required. Run 42857185053 passed tooling and the
contract matrix. GitHub cancelled its native job because no hosted macOS ARM
runner acquired it. The aggregate check therefore failed. The previous full
run on 88e4705 passed. Do not treat that older run as final-head acceptance.

Older checkpoints below record the failures and corrections in order.

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

### Final composer QA build 51 — 10 November 2026

Build 51 uses 5a1914f. The app and helper passed combined notarization
bb6ebb34-8356-459d-b19d-5c8b868947cb, stapling, and strict code signature
verification. The separate update target passed notarization
75d35182-7228-43d9-989e-e18d2e6b492e.

With access off, installed ChatGPT returned the exact Unicode response
“Compositor final café 🐼.” Return sent the prompt; Command-Z left the composer
empty after send. Apple Intelligence On-Device started a response and Stop
returned the UI to idle. A ChatGPT streaming response also stopped correctly.
During streaming, scrolling up kept the transcript at scroll value 0 and
showed Latest message. That button returned the scrollbar to 1 and resumed
following the response. The library remained empty and no tools were enabled.
Tool-backed editing and signed update installation remain unverified because
connection approval and the Keychain handoff are still pending.

### Authorized tool QA and Apple replay regression

The user approved Apple and ChatGPT connections only in the isolated QA.
Keychain signing then completed and the signed loopback feed became available.
CI run 42822300408 completed successfully for 5a1914f.

Installed ChatGPT reconnected after New Chat, created and read a neutral draft,
then edited the open editor and read the saved result. Native Undo restored
44 characters from 67. Apple created a second draft, but read the previously
open draft and reported that text as the creation result. Its next edit turn
repeated the prior creation before updating the open draft. The native Undo
restored the original text after that update. This is a failed acceptance case,
not a passing multi-turn tool session. Both connections were revoked and local
access was switched off before changing the implementation.

The follow-up separates previous turns from the current request in stateless
Apple context. Instructions forbid replaying earlier writes and require the
created draft ID for verification. The focused run passed 24 chat and Apple
adapter tests; the Xcode build passed. Installed regression acceptance and a
new CI run remain required.

Build 52 (ca786b2) passed notarization 9d32850d-e392-4ace-bf6b-fc63883d5964
and full CI run 42840334185. Installed creation with another draft open still
read that old draft despite the prompt change. Acceptance failed. The QA
connection was revoked and access was switched off.

The Apple bridge now retains the ID returned by a successful creation for one
model response. Its convenience read and edit use that ID during the response.
A fresh response returns to the open draft. Generic calls still use explicit
IDs and the existing permission checks. Nine adapter tests passed, including
creation while another draft exists, reading the created content, and resetting
the target for the next turn. This requires another installed regression run.

### Shared panel boundaries

The user requested aligned header and footer boundaries across the editor and
chat. Each split panel has a separate NSHostingController, so measurements and
environment values must be passed through each panel root. The two writing
panels now report intrinsic header/footer heights by slot and receive common
minimum heights. Footer borders belong to WritingPanel. The chat tools state
is a compact header button with status and controls in a popover. It no longer
adds a separate row above the transcript. DraftTagStrip and the chat header use
the same 45-point constant. Multiline composition can expand both footer bands.

The existing defaults remain automatic tools on and first-library access on.
Explicit Disconnect, Stop Work, and manual access off remain effective. The QA
screenshots with access off followed deliberate cleanup, not the install
default. The focused 34-test run and Xcode build passed. Installed alignment,
wrapped input, custom themes, and final model regression remain open.

Installed build 54 (46fc399) passed notarization
19bfce40-90be-47b3-90a8-b0a685f544ce, stapling, and strict signature checks.
Native light-mode QA showed a continuous divider below both 45-point headers.
The footer divider aligned across the editor and chat with an empty composer.
Pasting seven neutral Unicode lines expanded both footer regions together;
the composer scrolled internally. Clearing the prompt returned both dividers
to the compact position. The tool state was accessible as a header button and
no separate status row displaced the transcript. Access remained off during
this visual test. Model regression and update acceptance remain pending.

### Typed Apple conversation history

Installed build 54 correctly verified the ID created in the first response.
Its unquoted creation request omitted the requested second line. On the next
turn, it still repeated creation despite an explicit request not to create.
This failed acceptance. The connection was revoked and local access was turned
off. No passing multi-turn Apple claim is made for that build.

Authorized Apple requests now carry the current prompt separately from completed
chat turns. NativeModelAPI adds earlier turns as Foundation Models Transcript
prompt/response entries and sends only the current prompt to respond. Previous
unanswered or cancelled user turns are not replayed. Each response still gets
fresh tools bound to the current permission session. ChatGPT's existing typed
message path and persisted conversation format are unchanged. The SDK interface
confirms the transcript initializer on supported macOS versions. The focused
25-test run and Xcode build passed. Installed regression remains open.


### Installed typed-history and update regression

Signed and notarized build 55 (88e4705) created one two-line Unicode draft.
Two later turns edited and read the intended draft without another creation.
Native Undo restored both edits. ChatGPT also edited and read the test draft;
Undo restored its content. Automatic connections worked after provider and
conversation changes. Manual scroll exposed Latest message. That action
returned to the streaming response. Stop ended both provider responses.
Apple used a contradictory closing reassurance after one successful edit.
Its reported content was correct, but that sentence was not. A fresh Apple
story response created a draft before Stop. Stop does not undo committed work.
All model connections were revoked and local access was turned off afterward.

The signed Sparkle update from the isolated source-0.4.0 fixture to build 55
preserved the neutral draft and its identity. The fixture uses a QA-only
loopback feed adapter, not the unmodified public binary. Synthetic connection
metadata had no credentials. Its live scope expanded; expired and revoked
records stayed unchanged. The update incorrectly enabled stored access off.
This failed the update gate. Access was immediately turned off.

The correction records whether host configuration existed before migration.
Only a new library receives the enabled default. Existing enabled hosts resume;
existing disabled hosts stay off. Four regression combinations cover stored
on/off and an absent/present defaults marker. The focused 59-test run and
Xcode build passed. A new installed signed update remains required.


Build 56 (3c84168) passed notarization fdf40272-0818-405c-b48b-e16a7523f888.
The repeated signed Sparkle update from the isolated source-0.4.0 fixture
installed build 56 at the original path. The neutral draft retained its ID and
content. Access stayed off before update, after update, and after restart.
The live synthetic record expanded to the library. Expired and revoked records
kept their resource scopes. Expiry dates did not change. Metadata was identical
after restart, which confirms that migration did not repeat. No credential was
created for this metadata fixture. The source-0.4.0 loopback-adapter limitation
still applies. Both QA apps were closed with access off.


### Apple context regression in final-code QA

Installed build 56 passed combined notarization
1d66785a-4274-4f7f-bb53-9c3df1bacb64. Automatic tools connected after enabling
the approved isolated QA. A fresh request to edit and read the open editor
failed with 8,561 supplied tokens against the model limit of 8,192. The draft
stayed unchanged. The error was shown; no success was reported. Dark-mode
header and footer boundaries stayed aligned. The connection was revoked and
access was turned off before closing the app.

The Apple gateway schemas no longer repeat every operation name in two enums.
The model loads authorized names through discovery. Each discovery and call
still validates the current grant. Tests cover a denied discovery and denied
execution through the string-name gateway. The complete library tool schema
fixture must stay below 8,000 bytes; this is a byte bound, not a token claim.
All 10 Apple adapter tests and the Xcode build passed. Another installed model
run is required before acceptance.


Build 57 passed notarization 5df4f303-4867-4295-a672-18ba380d3b78.
The same request did not hit the context limit. It read the draft, then a tool
call failed with permission_denied. No edit occurred and no success was shown.
The QA connection was revoked and access was turned off. Gateway discovery
and execution now return bounded permission feedback to the model, rather
than ending inference when it chooses an unavailable name. The backend still
rejects the call. The hint requires exact discovery and forbids replay of an
unknown write. Ten adapter tests and the Xcode build passed. Installed recovery
remains unverified.


Build 58 passed notarization 5a8f026b-9d16-47b2-b497-469ee3161255.
Permission feedback allowed the request to continue, but catalog discovery
still exceeded the context limit (8,521 against 8,192 tokens). The draft stayed
unchanged. The session was revoked and access was turned off.

Apple now gets small direct read/edit tools for the current editor. The session
binds the editor identity from the host registry. The bridge uses editor.get,
mutations.prepare, and editor.replaceRange with the read version and UTF-16
length. It accepts only a complete read for full replacement. A stale read
cannot write, and a consumed read cannot be reused. These are provider adapters;
public MCP names, schemas, and permissions do not change. The normal editor
still owns pending text and Undo. The focused 11-test run checks pending Unicode
text, native Undo, stale versions, partial reads, hidden windows, and revocation.
It passed, as did the Xcode build. Installed direct-editor acceptance is pending.


### Final installed QA and signed update

Model QA build 59 (6dd321a) passed combined notarization
11720512-c2f2-45ec-96ac-030aeb842b74, stapling, and strict signature checks.
Apple edited the open 39-character draft to 66 characters through the direct
editor adapter. It read and reported all three exact lines. Undo restored 39.
ChatGPT GPT-6.1-Sol edited the same editor to 68 characters, read it, and reported
its exact text. Undo restored 39. Draft count stayed eight during both edits.
ChatGPT created one two-line draft (count nine); Apple created another (count
ten). Each read the new draft rather than the open control draft. The control
stayed at 39 characters. Both cancellation tests returned Stop to idle Send.
GPT-6-Luna streamed more than 130 numbered ideas before the scroll/cancel test.
The composer scrolled internally for seven Unicode lines while both footer
borders stayed aligned. New Chat cleared it; Undo did not restore that input.

The update target passed notarization ccdb103b-5a17-46a8-be42-15a004554f2e.
Sparkle installed build 59 at the original source-0.4.0 fixture path. The saved
71-character neutral draft retained ID 6F881F91-ED85-4CFE-A1B4-F10717A962C4.
Access stayed off. The live record gained library scope. Expired and revoked
records were unchanged, as were all expiry dates. A second launch left the
connection metadata identical. The updated app passed strict signature checks
and was closed with access off.


### macOS 26 keyboard fixture follow-up

Run 42866996963 passed tooling and the contract matrix. Its native process
passed the new composer reconstruction test, then exited with status zero at
returnSubmitsAndShiftReturnAddsALine. The termination trace ends in Swift's
async-main queue drain. There is no crash report and the test report is
incomplete. The inventory verifier correctly rejected the run.

The Return/Shift-Return and marked-text tests used an unattached NSTextView.
They now attach it to an offscreen window and make it the native first
responder. Key events use that window's identity. The coverage and assertions
stay intact. The 20-test chat/composition run passed locally. macOS 26 CI must
verify this fixture change. App source is unchanged from e47bc03; build 60
still contains the final app code. It is signed, but notarization could not
read the saved Keychain profile while the Mac was locked. Manual unlock,
notarization, and installed reconstruction QA remain pending.


### Native process isolation and complete inventory

Run 42870264828 repeated the status-zero termination at the Return test after
composer reconstruction passed. An offscreen input window alone did not resolve
it. The verifier still rejected the incomplete report.

The reconstruction test now runs in its own native process before the main app
tests. The existing typewriter process remains separate. The main process skips
exactly those tested identities. A verifier test checks the partition, its union,
and execution count. Every discovered case must have one passing result. There
are no test retries or reduced result requirements. Locally, the reconstruction
process passed its one test. The full verifier passed consumer 1, contracts 197,
core 837, and app 1,726. All 331 script tests passed in an isolated environment
with the CI dependency ranges. macOS 26 CI must still validate this partition.

The broad script run also exposed a Python 3.15 default change: GzipFile now uses
compression level 6. The existing feed-byte regression requires level 9. The
feed compressor now sets that level explicitly. The regression and all script
tests pass. This does not change the app source or the build-60 QA package.
Manual Mac unlock is still required for notarization and installed follow-up.
