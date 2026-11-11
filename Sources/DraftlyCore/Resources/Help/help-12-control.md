# Permissions, reviews, and Stop Work

Settings → Agents lists connections and their status. Review the whole-library or selected-resource scope, capabilities, and expiry for each connection. Revoke a connection you no longer use.

## Stop work
Use Stop Work to stop agent work. Switching off local access prevents local clients from continuing. Revocation removes a connection's authorization. These controls do not undo edits or recall effects that already completed.

Locking or suspending the Mac pauses access. Unlocking or waking is not a reason to assume a previous operation succeeded. Check the connection status and operation result before continuing.

## Human reviews and macOS permissions
Destructive operations and effects that require review remain subject to approval in the app. Calendar, Reminders, automation, folders, and other native features can also need macOS permission. A Draftly grant does not replace those permissions.

Mail and Messages tools open a composition window for review. Do not interpret that as proof that a message was sent.

## An uncertain result
If an operation reports outcome_unknown, inspect its status and destination. Do not automatically repeat the write or external effect. An error, disconnect, cancellation, or restart does not establish that no effect occurred.

Never share authentication tokens or connection credentials in a support report.
