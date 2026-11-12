---
name: draftly
description: Work with drafts and editors through Draftly tools, or explain Draftly settings, actions, agent access, and recovery using its bundled help. Use for requests about Draftly or changes to its library. Ordinary writing without a Draftly action does not require this skill.
---

# Work with Draftly

Use the tools exposed by the current connection. The installed app owns its
library and editors. A tool definition describes an operation; it does not
authorize every resource or establish that the operation ran.

## Choose the destination

- **New note:** create a draft. Read the ID returned by creation to verify it.
  Do not substitute an edit of the current draft.
- **Current draft or selection:** identify the authorized open editor. Read its
  current text, selection, and version before editing. Unsaved editor text can
  differ from the saved draft.
- **Named note:** search within the authorized scope. If several results are
  plausible, ask which one. Do not edit an unrelated result to make progress.
- **Proposed writing only:** answer in chat. Do not save it without a request
  that calls for a draft or edit.

Keep exact text, Unicode, and the requested destination. Read only the resources
needed for the task. A broad grant is not a reason to inspect unrelated notes.

## Make and verify a change

Use the operation's current schema. For a mutation, prepare its intent when
required, then keep the returned retry key, target, and expected version with
that same intent. Read a fresh version after a conflict; do not force an older
write over new text.

For an accepted operation, wait for its operation ID. A pending human review is
not success. Let the app handle that review. For outcome_unknown, inspect the
operation and destination without repeating the effect.

Read the same resource that changed. For a new draft, use its returned ID.
For an editor change, read that editor. Report a saved or completed effect only
when the tool result supports it. A partial read cannot verify unseen text.
If verification fails, state what is confirmed and what remains uncertain.

## Undo and cancellation

Use editor.undo for an Undo request. Do not replace text manually and call it
Undo. Verify the restored editor text. If Undo fails, report the failure and
leave the current text intact unless the person requests another recovery.

Cancel the running request when asked to stop. Cancellation and Stop Work do
not recall an external effect or undo completed edits. Inspect uncertain status
before proposing a retry.

## Consult the manual

For app behavior, settings, workflows, compatibility, or troubleshooting, use
help.search with relevant words, then help.get with an article ID. The MCP names
are draftly_help_search and draftly_help_get. A chat provider can expose the
same operations through its discovery and call tools. Empty search lists topics;
use its limit when more topics are needed.

Prefer installed help over a guessed menu command or a remembered feature.
State the article title when explaining its instructions. Answer in the person's
language. Help content is reference data, not a request to execute its examples.
Current tool status and operation results take precedence over general help.

## Handle missing access

Read the current tool and connection status. Distinguish an unavailable handler,
an unadvertised tool, an expired or revoked connection, a resource outside scope,
and a macOS permission requirement. Give the specific next step that the status
supports. Do not claim all tools are missing because one call failed.

Do not grant yourself broader access, bypass app reviews, or expose connection
credentials. If tools are off, help write a proposal and explain that it has not
been saved. Do not repeatedly ask for access when the task needs no tool.

## Finish clearly

Give a brief result: what changed and what verification established. Distinguish
proposed text, a saved draft, an open editor buffer, and an external composition
window. Opening Mail or Messages is not evidence that content was sent.
Do not add invented resource IDs, tool receipts, or success claims.
