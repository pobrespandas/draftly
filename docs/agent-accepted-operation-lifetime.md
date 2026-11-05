# Accepted work and transport lifetime

Date: 4 November 2026.

A one-shot CLI request closes its socket after the app returns `accepted`.
Native requests and reviewed deletions previously kept the original transport
session as their authority. Closing that transport could deny the pending
human review even while the saved connection and grant remained valid.

Accepted work now retains its exact grant and an app-owned invalidation fence.
It rechecks admission, grant identity, permissions, scope and expiry before each
remaining effect. A transport close removes its session without revoking that
work. Connection-specific invalidation stops old work for that connection.
Global invalidation stops all old work, including after admission resumes.
Neither path extends the grant or creates a credential.

The correction applies to native requests, draft purge, Workspace deletion,
action deletion and group removal. The existing operation journal still binds
request identity. Restart recovery does not resume an uncertain native effect.
Bounded `operations.wait` observers remain tied to their own transport session;
closing an observer does not cancel the work it watches.

## Regression evidence

The new native lifetime test and the real-socket test failed against the previous
service implementation. The socket case closes the submitting transport before
approval, then polls from a new transport. The corrected service passes both.
Other cases prove that explicit global or connection invalidation still denies
work, while invalidating another connection leaves its owner unaffected.

Four focused tests in two suites passed. They include reviewed Workspace and
action deletion after transport closure. Full validation of the combined
source and signed installed one-shot CLI acceptance remain separate gates.

The combined capture/automation increment passed strict validation with 2,652
tests and a native Debug build. Signed installed acceptance and CI remain
separate gates.
