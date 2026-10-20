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
`CallbackHelper`. Set `LSUIElement` to true and register only `draftly-engine-echo`.
Sign both copies locally and register their bundles with Launch Services.

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
messages. It exits after replying. Close QA and remove only the app copies and
library UUID created for this session. Keep the source and fixture for repetition.

These checks do not accept cold-launch automation, native callback timeout,
Shortcuts, App Intents, Calendar, or Reminders. Record each of those separately.
