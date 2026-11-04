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

Inputs use typed contracts. Text is bounded at 65,536 Unicode scalar values. URL input
is bounded at 8,192 Unicode scalar values. Print accepts text or HTML. Each request uses
literal input; it does not read a draft or editor implicitly. Unknown host
fields and targets are rejected. Other native contracts remain unavailable.

## Authority and execution

The loaded host supplies a fresh native adapter and the shared app-owned
approval store as one execution environment. This does not depend on enabling
destructive library mutations. Agent access still starts off. The environment
and operation registry must both exist before the service advertises a tool.

Each request needs `nativeUse` and a separate one-use human review of its
concrete parameters. HTTP and HTTPS URL opening uses that grant. Other allowed
URL schemes also need `scriptsUnrestricted` and library scope, as in reviewed
Actions. File, data and JavaScript URLs are rejected before review.

The operation journal reserves the request identity before execution. Changed
intent under the same ID is rejected. Repeated requests return the same pending
operation or stored result. Cancellation or loss of authority after submission
withholds the result and records an uncertain effect. It does not replay it.
The host must finish cleanup before the operation becomes terminal.

`completed` reports the adapter's completion response. A false result is retained
and is not automatically retried. Native share and print still use their normal
system interfaces. The request cannot select a destination through hidden fields.

## Private results

The journal stores request fingerprints, not request content. Clipboard text
and converted text remain only in memory. A journal-recovered result
has `resultAvailable: false` and `text: null`; it does not read the clipboard or
convert the input again. Boolean completion results remain recoverable. See
[the decision](adr/0005-agent-transient-native-results.md).

## Evidence and remaining gates

Contract tests cover bounded input, unknown fields, unsafe URLs, targets,
prepared-key rejection and consistent result availability. Service tests cover
all seven adapters, review, denial, cancellation, session invalidation, malformed
responses, uncertain effects, intent changes and journal recovery without private
text. A suspended fake host checks cancellation cleanup and late-result denial.
A local-host test uses real socket transports and checks recovery after reconnect.

These tests use fake native effects. They do not read the system clipboard,
open a destination, print, share or play speech. Native adapter tests remain
separate. The final focal run passed 29 app tests in six suites and five contract tests.
The complete strict runner verified 1 consumer, 189 contract, 824 Core and
1,627 app tests (2,641 total). The native package-name Debug build and two
project-generator checks passed. Logs are retained under `/tmp/draftly-native-*`.
CI and signed installed acceptance remain open. The public release is unchanged.
