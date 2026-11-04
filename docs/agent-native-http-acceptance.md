# Reviewed bounded HTTP

`native.http` now uses the shared app-owned native review and operation journal.
The host is created only after approval and a fresh authority check. The review
shows the method, URL, headers, body, timeout and redirect choice. The operation
requires `native.use`. It does not require unrestricted scripts or library scope.
This is an outbound HTTP client. It does not expose Draftly over HTTP.

## Request and response

The URL must use HTTP or HTTPS. User information and fragments are rejected.
The method must be an HTTP token. Headers use a bounded JSON string map. Duplicate
case-insensitive names, control characters and managed transport headers are
rejected. The caller may supply explicit authentication headers. The adapter does
not resolve secrets or read the app's account credentials.

A request can contain UTF-8 text or canonical Base64, not both. The body limit is
65,536 bytes. The network timeout defaults to 60 seconds and accepts up to 90.
The existing operation deadline also applies. Responses retain up to 65,536 body
bytes and bounded headers. Declared size and streamed bytes are checked. HEAD,
204 and 304 may announce representation size without a body; streamed bytes
remain limited for these responses too.

The response contains status, success, headers as JSON, decoded text and exact
body bytes as Base64. Text uses the existing HTTP charset decoder. A valid HTTP
error response remains available, with a failed effect outcome. A transport error,
revocation or cancellation after submission remains uncertain. The app does not
repeat the request automatically.

## Session policy

Each call uses a separate session. Cookie storage, credential storage, additional
configuration headers and caching are disabled. Only normal server-trust handling
uses default challenge behavior. Other authentication challenges are cancelled at
both session and task level. Explicit request headers remain possible.

Redirects default to off. When enabled, the delegate keeps the scheme, hostname
and effective port of the reviewed origin. It rejects credential-bearing redirect
URLs. It does not silently follow another origin or a TLS downgrade.

The transport uses Foundation's
[asynchronous bytes](https://developer.apple.com/documentation/foundation/urlsession/asyncbytes)
for bounded consumption. Apple's documentation describes opting out of
[credential storage](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/urlcredentialstorage)
and [cookie storage](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/httpcookiestorage)
by setting those stores to nil. Task cancellation invalidates the private session.
[Cancellation](https://developer.apple.com/documentation/foundation/urlsessiontask/cancel())
cannot undo work already performed by a server.

## Result privacy and evidence

HTTP results are transient. A recovered operation returns `resultAvailable: false`
and no response content. Neither request secrets nor response text or Base64 are
saved in the operation journal. Recovery does not send another request.

Focused checks cover review before host construction, one effect, HTTP failure
status, private result recovery, binary request and response bytes, body limits,
header rejection, same-origin redirects and cancellation. Loopback tests use real
TCP connections. They verify redirect destinations, reject another hostname on
the same server, accept bodyless representation sizes, and observe connection
closure on cancellation. A fixture event deadline prevents indefinite pipe waits.
No external service or installed library was used.

## Remaining acceptance

Signed installed review, actual HTTPS/TLS, revocation and Stop Work during live
HTTP, helper/client workflows and distribution remain open. Automatic HTTPS input
resolution for themes and backups is not connected yet. It must use an authorized
source-effect route rather than an unreviewed fetch. Keep agents unpublished until
the complete acceptance plan passes.

## Local validation

Strict validation verified 1 consumer, 195 contract, 833 Core and 1,682 app tests
(2,711 total). Native Debug passed. Final evidence:
`/tmp/draftly-native-http-verified.log`,
`/tmp/draftly-native-http-verified` and
`/tmp/draftly-native-http-verified-build.log`.
The expanded focused logs are `/tmp/draftly-native-http-expanded.log` and
`/tmp/draftly-native-http-final-focused.log`. Source coverage is 115 connected or
conditional names of 137; 22 names have no direct handler. Current-source CI and
the installed acceptance above remain open.
