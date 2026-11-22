# Chat model refactoring — 22 November 2026

## Baseline and scope

The branch starts from e4c6fab on main. The unchanged ChatConsoleModelTests
suite passed all 15 tests before edits. The normal checkout has unrelated
local changes. This work uses a separate worktree and leaves those changes
and the installed app untouched.

ChatConsoleModel mixes conversation persistence, cross-window history merging,
provider discovery, response tasks, and observable presentation state. This
block extracts persistence and merging into ChatConversationStore. The model
keeps its published state, subscriptions, provider selection, cancellation,
and tool connection lifecycle. It composes the concrete store; no inheritance
or new protocol is needed.

## Preserved rules

- Keep chatConsole.state and its JSON fields, message IDs, dates, and roles.
- Restore the newest 50 conversations. Validate the saved selection against
  that retained set. The model keeps its existing fallback selection rule.
- Merge stored conversations before writes. Keep each message identity once
  across windows and retain the current date ordering and title calculation.
- Keep merge and write synchronous on MainActor, with no suspension between
  them. Keep the existing handling of missing, invalid, and unencodable data.
- Do not change library data, MCP contracts, model instructions, Undo,
  permissions, streaming, or conversation storage location.

## Validation

The final build and 39 tests passed in ChatConversationStoreTests,
ChatConsoleModelTests, AgentChatToolSessionTests, and AppleChatToolsTests.
The three storage cases check literal existing JSON with Unicode and newlines,
the 50-conversation retention boundary and selection, and invalid stored data
while local history exists. Existing model tests check restoration, two-window
merging, cancellation, provider changes, and late responses.

The first compatibility fixture had a title that differed from its first user
message. The unchanged merge rule recalculates that title before saving. The
fixture now uses a title produced by the existing rule. No production behavior
changed to satisfy the assertion. git diff --check passed.

Native installed QA and complete CI are separate from these focused results.
This change does not require a model login or an agent grant to test storage.
No release was published as part of this block.

## Next candidates

1. Separate provider discovery and availability from ChatConsoleModel. Preserve
   the selected unavailable ChatGPT model, account epoch cancellation, and
   automatic tool connection conditions. Existing provider tests are the base.
2. Review response task ownership before extracting a response coordinator.
   Preserve response identity, streaming updates, cancellation, and rejection
   of late results after a conversation or account change. Do not combine this
   with provider extraction in one commit.
3. Review WindowModel separately. It already delegates editing, file commands,
   and workspace preparation. Extract a responsibility only when its state and
   lifecycle can move together. File size alone does not justify another layer.

These are candidates for the next blocks, not claims of completed acceptance.
