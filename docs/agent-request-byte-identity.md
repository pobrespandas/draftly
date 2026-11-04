# Accepted request byte identity

Date: 4 November 2026.

Accepted work binds a request ID to one connection, grant and normalized intent.
The live cache previously compared Swift string values. Swift considers composed
and decomposed Unicode text equal, even when their UTF-8 bytes differ. A changed
literal native argument could therefore reuse an existing request ID.

The live cache now compares SHA-256 fingerprints of the canonical JSON bytes.
It uses the same encoding and size bound as the journal. Schema defaults and
object-key order remain normalized. Byte-distinct parameter text produces a
version conflict. The identity cache retains a digest instead of the request
content. Authorization and effect approval remain separate checks.

A regression test failed for composed and decomposed text with and without a
journal. Both cases pass after the correction. The focal run passed 33 tests
in four suites, including operation lifetime, journal and native service cases.
Full validation of the combined source remains a separate gate.
