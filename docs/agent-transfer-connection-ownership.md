# Transfers across CLI commands

A CLI `call` command opens one authenticated transport, sends one request, and
closes it. A transfer must remain usable by the next command. The first
implementation removed buffers when that transport closed. This made a
single-command export unusable from the next CLI command.

Transfers now belong to the authorized connection and its exact grant. A new
transport with that same credential can resume the transfer. It does not need
another grant. A different connection or a replacement grant cannot resume it,
even when the replacement includes broader resource scope.

The host checks the original resource scope on each request. Connection
invalidation and Stop Work clear the buffers. Cancellation and the existing
five-minute, grant-expiry and monotonic limits still apply. Transport closure
does not extend the lifetime or preserve the buffer across a host restart.

The local SDK test sends export, read and cancellation requests through
separate authenticated local clients. It also reads the exported bytes through
MCP with the same grant and rejects a hidden draft. It uses the CLI request
builder and the real socket and SDK routes. This is not signed installed CLI
or post-update acceptance. Full CI remains required.
