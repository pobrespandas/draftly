# Direct native operation validation

Date: 4 November 2026. Installed acceptance remains open.

## Connected operations

| Contract | Native adapter method | Result |
| --- | --- | --- |
| `native.clipboardRead` | `getClipboard` | Text and `resultAvailable` |
| `native.clipboardWrite` | `clipboard` | `completed` |
| `native.htmlToMarkdown` | `htmlToMarkdown` | Text and `resultAvailable` |
| `native.share` | `share` | `completed` |
| `native.print` | `print` | `completed` |
| `native.openURL` | `openURL` | `completed` |
| `native.speak` | `speak` | `completed` |
| `native.dictate` | `dictate` | Text and `resultAvailable` |
| `native.transcribe` | `transcribe` | Text and `resultAvailable` |
| `native.location` | `location` | Coordinates and `resultAvailable` |
| `native.shell` | `shellScript` | Process result and `resultAvailable` |
| `native.appleScript` | `appleScript` | Native result JSON and `resultAvailable` |
| `native.shortcut` | `shortcut` | Text and `resultAvailable` |

Inputs use typed contracts. Text is bounded at 65,536 Unicode scalar values. URL input
is bounded at 8,192 Unicode scalar values. Print accepts text or HTML. Each request uses
literal input or an explicit native capture interface; it does not read a draft
or editor implicitly. Unknown host
fields and targets are rejected. Other native contracts remain unavailable.

## Authority and execution

The loaded host supplies a fresh native adapter and the shared app-owned
approval store as one execution environment. This does not depend on enabling
destructive library mutations. Agent access still starts off. The environment
and operation registry must both exist before the service advertises a tool.

The native adapter is created only after approval and a fresh authority check.
Each request needs `nativeUse` and a separate one-use human review of its
concrete parameters. HTTP and HTTPS URL opening uses that grant. Other allowed
URL schemes also need `scriptsUnrestricted` and library scope, as in reviewed
Actions. File, data and JavaScript URLs are rejected before review. Shell, AppleScript
and Shortcuts require `scriptsUnrestricted` and library scope. Their review
states that they use the person's macOS permissions and full library access.

The operation journal reserves the request identity before execution. Changed
intent under the same ID is rejected. Repeated requests return the same pending
operation or stored result. Cancellation or loss of authority after submission
withholds the result and records an uncertain effect. It does not replay it.
The host must finish cleanup before the operation becomes terminal. Accepted
work survives an ordinary transport close under the same grant. Explicit
connection/global invalidation, revocation, expiry and Stop Work still stop old
work. See [accepted work lifetime](agent-accepted-operation-lifetime.md).

`completed` reports the adapter's completion response. A false result is retained
and is not automatically retried. Native share and print still use their normal
system interfaces. The request cannot select a destination through hidden fields.

## Private results

The journal stores request fingerprints, not request content. Clipboard text,
conversions, transcripts, location, process output and AppleScript values remain
only in memory. A journal-recovered result has `resultAvailable: false` and a
null payload. It does not repeat capture, code execution or a read. Boolean
completion results remain recoverable. See [the decision](adr/0005-agent-transient-native-results.md).

## Capture and automation contracts

Dictation and transcription accept a locale. Transcription uses the native audio
file picker. Neither contract accepts a caller-supplied path or authorization
state. Location returns bounded latitude and longitude values.

Shell accepts source and literal arguments. It returns an exit status, stdout
and stderr. A nonzero status remains a process result, not a transport error.
The effect record marks that execution attempt as failed. NUL arguments are
rejected. AppleScript accepts source, an optional subroutine and a serialized
JSON argument array. Nonempty arguments require a subroutine. Argument/result
JSON is bounded at 16 levels and 4,096 values. The result keeps the native JSON
envelope and its date-path metadata without converting dates to plain strings.

Shortcuts accept a name and input text. The initial request returns an operation
ID; the app tracks completion and cancellation. A caller can poll later. The
native process stays attached to the operation instead of using the adapter's
detached mode. Unknown host-control fields are rejected.

## Evidence and remaining gates

Contract tests cover input bounds, unknown fields, unsafe URLs, process/capture
shapes, ignored arguments and private result availability. Service cases cover
all 13 routes, native review, denial, cancellation, authority changes, uncertain
effects and journal recovery. Tool discovery hides unrestricted operations from
resource-scoped grants. The socket test closes before approval and recovers
through a new transport. Byte-distinct Unicode request changes conflict even
when Swift considers their strings equal.

Most native effects use fakes. Two Shell cases use the real native adapter in
isolated in-memory libraries. They verify literal Unicode argument bytes,
nonzero exit status and cancellation of a real parent/child process group before
the operation becomes terminal. They do not read private files. Microphone,
location, audio-file selection, AppleScript helper and Shortcuts acceptance in
a signed installed app remain open. Mail and Messages remain unavailable: their
current adapters reject unconfirmed sending rather than claim delivery.

Strict validation verified 1 consumer, 193 contract, 824 Core and 1,634 app tests
(2,652 total). Native Debug build and two project checks passed. The earlier
seven-operation source `18a6e14` passed full CI
[41849728024](https://github.com/pobrespandas/draftly/actions/runs/41849728024).
CI and signed installed acceptance of the combined increment remain open.
Logs are retained under `/tmp/draftly-native-capture-*`. The public release is unchanged.
