# Installed agent editing acceptance

## Source and isolation

The signed isolated app and helper used source `f6f6190` on 3 November 2026.
The app used its retained neutral QA library with iCloud off. The normal app
and library were not opened. A new native pairing granted draft and editor
read and write access to one draft and window. Renewal was off. Access expired
at 23:03:03 Buenos Aires time on 3 November (02:03:03 UTC on 4 November).

The developer approved a later extension to the selected Share Action and its
native capability. The extension kept the same expiry and did not grant script
execution, full-library scope, other Actions, or access to the second draft.
No sharing destination was selected and no content was sent.

## Verified on f6f6190

| Scenario | Installed result |
| --- | --- |
| Prepare an editor range edit | Text stayed unchanged until execution. |
| Execute the edit over CLI | The native editor showed the exact Unicode text. |
| Repeat the same request | The saved result returned. Text was not appended again. |
| Native keyboard Undo and Redo | Undo restored the original text. Redo restored the edit. |
| Retry after native Undo | The result returned without applying the edit again. |
| Edit and Undo over MCP | The installed helper completed both calls. A repeated edit after Undo did not change the text. |
| Manual edit after preparation | The stale agent write returned `version_conflict`. The manual text stayed intact. |
| Read or write the other draft | The request failed without returning its content or changing it. |
| Stop Work before submitting a prepared edit | Access turned off. The request failed through the withdrawn endpoint. |
| Resume after Stop Work | No late edit appeared. Completed changes and their receipt stayed intact. |
| Replace a grant with identical permissions | The old prepared key returned `permission_denied`. Current authorized reads still worked. |

The stop-before-submission check did not place a synchronous editor mutation
in an execution queue. It does not establish interruption inside an atomic edit.
Existing registry tests cover queued cancellation separately.

During the MCP probe, an Undo prepared through a separate CLI call encountered
a version conflict. A fresh read and preparation through the same MCP session
completed the Undo. The rejected request did not change the text. Preparation
must use a current version; a conflict is not permission to repeat an edit.

## Native review correction

The native Share review sheet blocked Settings and had no Stop Work control.
Source `e9528d1` adds the existing Stop Work command to that sheet. A failure
keeps the sheet open and shows the model error. The signed corrected QA app
started with access off. Its editor had a new window ID; the old grant did not
automatically include that new window.

The correction passed 169 focused tests in five suites and the native QA build.
A resumed native pairing granted the same neutral draft, its current editor,
and Share until 23:24 on 3 November. The corrected Stop Work button closed the
review and disabled access. After explicit resume, the old review was absent.
The operation was `cancelled` with no completed effects. Repeating its request
returned the same operation without another review or native selector.

A second operation reached the native share selector. The journal recorded a
`submitted` share effect while the operation remained `running`. No destination
was selected. The QA process was killed before a native result returned. After
reopen, access stayed off. Explicit resume let CLI and MCP retrieve the same
operation as `outcome_unknown`, with the share effect marked `unknown`.
Repeating the original request through both clients returned that operation;
no new review or selector appeared. This checks process interruption and
recovery. It does not simulate a completed transmission to a sharing service.

Before the resumed grant expired, a draft write was prepared and then the grant
was revoked in Settings. Execution returned `permission_denied`. The native
editor retained its prior text and did not show the rejected-write marker.

## Actual expiry and cleanup on e9528d1

At `2026-11-04T02:03:04.079Z`, the existing MCP session could no longer read the
approved draft. A new CLI request could not execute a draft write prepared
before expiry. The grant record was unchanged and unrevoked, and host access
was still enabled. This isolates expiry from revocation or Stop Work. The native
editor still showed the prior text and no rejected-write marker.

The test connection was then revoked. Stop Work disabled access. The QA exited,
helper discovery returned no endpoints, and the original shared preferences
were restored and compared with the pre-QA backup. The normal library was not
opened. Recovery artifacts retain the signed prior QA and neutral test data.

## Full CI and final QA state

Full CI [41758319817](https://github.com/pobrespandas/draftly/actions/runs/41758319817)
passed for `882b945`, which includes the `e9528d1` review correction. Tooling,
matrix, native tests, the native app build, and the required-check gate passed.
Website checks were not selected because this change did not edit the site.

The resumed QA ended before its grant deadline. All test grants are revoked,
local access is off, the process is closed, and helper discovery is empty. The
original shared preferences were restored and compared with the fresh backup.
Chat Console showed its native editing consent. That consent was not approved,
so no ChatGPT editing connection or model edit was created. Cancel closed the
prompt during cleanup. A real model edit still needs fresh native consent.

## Remaining acceptance

- Complete a real Chat Console edit through fresh native consent.

Private request and response files are retained in the local QA recovery
directory. They are not release assets. This report does not establish normal
host startup, screen-lock handling, notarization, named-client support, or a
published agents feature. PR #105 stays in draft.

## Chat Console stream failure

A later approved ChatGPT editing session failed before local tool execution.
The activity log contained only `server.capabilities` and `server.schemas` for
that connection. The response completed with an empty output list. No editor
read or mutation ran. Disconnect revoked the connection and Stop Work closed
the host before the QA update.

The provider now retains `response.output_item.done` items when the final output
list is empty. It still requires a successful final response, complete contiguous
item positions, no unfinished or reopened item in the batch, matching response
identities, valid calls, and the existing
permission checks. Partial items, failed responses, gaps, conflicting positions,
and foreign response identities cannot execute a tool. Reasoning items remain
in continuation history. This follows the completed-item event shape in the
[OpenAI function calling guide](https://developers.openai.com/api/docs/guides/function-calling).
The 23 focused provider, tool-session, console, and transport tests passed. The
native QA build passed. Installed acceptance of this correction remains pending.
The empty final
list alone does not prove which preceding events the service sent.
