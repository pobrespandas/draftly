# Transfer cancellation discovery

CI [41815621541](https://github.com/pobrespandas/draftly/actions/runs/41815621541)
failed on `2e28255`. The official MCP SDK tests found a cancellation tool in a
plain draft-reader catalog. That tool is not read-only. The same extra tool
also broke the concurrent discovery inventory. All three failures had this cause.

Discovery and permission checks now share one capability predicate. Transfer
cancellation requires either `files.read` or `files.write`. Upload owners do
not need export permission. A plain draft reader cannot receive this tool.
The host still checks transfer ownership before cancellation.

The local official SDK suite passed after the change. The shared catalog test
also checks discovery and permission decisions with no capability, draft read,
file read, file write, and both file capabilities. Full CI remains required.
