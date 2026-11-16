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

## Remaining acceptance

Installed model QA and complete CI remain pending. Automatic tests prove the
adapter and native history path. They do not prove that the local model selects
the tool for a real Spanish request. Do not mark the older installed Apple Undo
limitation as resolved until that check passes. No release includes this change.
