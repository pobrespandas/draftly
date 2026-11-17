# Apple editor history follow-up

Checked on 16 November 2026, from main at 2cf9637.

## Change

Apple Intelligence gets compact Undo and Redo tools for the open editor when
its connection permits the underlying operations. Both tools use the existing
editor history operations. They do not replace text to simulate history.
Public MCP names, schemas, permissions, and storage formats do not change.

The adapter requires a complete current editor read. It consumes that read's
version, prepares the mutation, and uses the returned retry key. A stale read
fails without changing text. A failed preparation does not dispatch history.
The model must read the result once and report failures without a replacement.
An editor longer than the compact read limit requires the general catalog path.

## Automated acceptance

The product compiled. All 32 tests in AppleChatToolsTests,
AgentChatToolSessionTests, and AgentEditorMutationTests passed.
`git diff --check` passed.

The Apple tool suite checks native editor edits followed by Undo and Redo,
Unicode text, a missing prior read, consumed reads, concurrent changes,
revocation after discovery, and an unchanged draft outside the grant.
The test calls the same generated Undo and Redo tools supplied to the model.
Read-only connections do not get these compact history tools.

## Installed acceptance

Checked on 17 November 2026 in Draftly Help Agent QA, build 75. Its source
commit is 6f7c78c4d1cbabbd57b1d812bacbd4d391bbd50c. The app and helper pass
strict signature verification. Notarization was refused with HTTP 403 because
Apple requires a current legal agreement. This was a local signed test, not a
notarized distribution test. No system protection was disabled.

The isolated library held two drafts. Only QA Apple Undo Redo café 🐼 was used.
Apple Intelligence On-Device received Spanish requests in the installed chat:

1. Replace El panda escribe. with El panda revisa. and keep the title.
2. Undo that change with native history and read the restored text.
3. Redo that change with native history and read the result.

The editor and model output confirmed the exact original text after Undo and
the edited text after Redo. The activity log recorded one successful
editor.replaceRange, one editor.undo, and one editor.redo, with three
successful mutations.prepare calls. Undo and Redo used no replacement writes.
The connection ID was 7947930E-09DF-4B40-AB44-98488F85CD3A.

The model repeated complete verification after the edit and Redo. The existing
bounded recovery stopped those responses and displayed the actual read text.
It did not replay an effect. Undo completed with a normal text response. This
check accepts the real history path; it does not claim that repeated model
reads are resolved or that every Spanish request selects the correct tool.

After the test, the connection was disconnected. Settings showed no approved
connections and local access off. A native toolbar Undo restored the neutral
draft's original text. The other draft kept its visible modified timestamp.
The normal installed app and personal library were not opened.

## CI and limits

Full CI run 43959519154 passed on the tested source commit. It includes native
build and tests, tooling, matrix checks, and the required combined check.
The compact adapter still requires a complete read. Longer editor content can
use the existing general catalog path. No release includes this change yet.
