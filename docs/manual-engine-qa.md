# Manual engine callback checks

Run these checks in a separate Computer Use session. Automated tests stay in the
background. Use a local QA library and neutral text.

## Prepare the apps

Copy a fresh local Draftly build to a new QA app bundle under `~/Applications`.
Keep the installed Draftly app unchanged. Set these Info.plist values on the copy:

- `CFBundleIdentifier`: `com.andrestobelem.draftly.engine-qa`
- `DraftlyUITesting`: true
- `DraftlyUITestingLibraryID`: a new UUID; retain it for the whole session
- `DraftlyCallbackScheme`: `draftly-engine-qa`
- `CFBundleURLTypes`: register only `draftly-engine-qa`

Build `scripts/qa-callback-helper.swift` as an AppKit executable in a separate
`Draftly Callback Helper.app`. Use deployment target macOS 26 or later. Its bundle
identifier is `com.andrestobelem.draftly.callback-helper`; its executable name is
`CallbackHelper`. Set `LSUIElement` to false and register only `draftly-engine-echo`.
Sign the QA app with the existing Apple Development identity. A Team ID is
required for the recorded App Intent check. Sign the helper locally. Register
both bundles with Launch Services.

Keep the helper under `~/Applications`. In the recorded session, Launch Services
listed the `/tmp` helper but NSWorkspace could not resolve its URL scheme. Moving
the test bundles out of the temporary directory resolved that setup failure.

## Run the checks

1. Open QA. Create a neutral draft.
2. Import `scripts/fixtures/engine-native-actions.json` through the Actions importer.
   Its installation URL is `drafts://action?data=` plus percent-encoded file text.
3. Run Success. Check the returned Unicode text and the original window.
4. Run Cancelled and Error. Check that no following step changes the text.
5. Run Late. Type replacement text within eight seconds. After the reply arrives,
   check that the replacement remains and no window was added.
6. Run Shell. Check its Unicode output in the editor.
7. Check Execution History for each result.

The helper only opens callbacks with the QA scheme and callback host. It sends no
messages. Its control window can also deliver normal Draftly URLs explicitly to QA.
The helper checks the destination bundle identity and test-library setting. It
does not change the normal Draftly scheme registration. Close QA and remove only
the app copies and
library UUID created for this session. Keep the source and fixture for repetition.

## Automation checks

Use the helper control window to send normal `draftly://` URLs explicitly to QA.
Verify the field value before pressing Open in QA. The helper displays the actual
URL delivered. Check that QA is not running before each cold-launch case.

- Create: send neutral text and check the created note.
- Open: send that note UUID and check the selected row and text.
- Capture: send neutral text and check the separate Capture window. Pending
  capture text must remain across a quit and append the new text.
- Run: import `scripts/fixtures/engine-automation-actions.json`. Send action name
  and note UUID, plus x-success, x-cancel, and x-error URLs pointing to
  `draftly-engine-echo://received?status=...`. Confirm Run Action. The helper must
  show the final status and only the matching final parameters.

For App Intents, create a disposable shortcut in Shortcuts. Search for the exact
QA app name to separate it from other installed builds. Add Run Draft Action and
use the neutral action name and QA UUID. Test success, failure, and cancellation
separately. The recorded ad hoc build failed to communicate because the system
could not obtain its Team ID. Development signing fixed that setup failure.

For native Shortcut execution, create a separate disposable shortcut containing
only a Text action with output `Shortcut output café 🐼`. Name it
`Draftly QA Text — disposable`, then run QA Native Shortcut from Draftly.
The recorded UI execution of this shortcut worked. Both the app adapter and a
direct command-line invocation waited without completing. The app returned timeout
and retained the source text. Native Shortcut success remains pending.

Native callback timeout, entry-point timeout/busy/concurrency, speech, location,
Calendar, and Reminders still require their separate real checks. Deleting a
shortcut affects iCloud and other devices. Confirm deletion if normal recovery is
not available; retain the disposable fixtures while that confirmation is pending.
