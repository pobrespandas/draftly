# Chat tools and access

The shield or tools control in Chat Console shows its tool status. Open it for details. A model can write a response without having permission to change your library.

## Automatic connections
When local access is enabled and a provider is available, Chat Console can connect tools automatically. New libraries enable local access by default. A saved off state and Stop Work remain effective. Opening the chat does not override them.

New connections preselect the whole library, including future resources, and all available capabilities. Review the scope in Settings → Agents. You can choose limited resources instead. A whole-library grant includes more than the draft currently on screen.

## If tools are off
1. Read the tool-status detail.
2. Check local access in Settings → Agents.
3. Check the selected provider and ChatGPT sign-in if applicable.
4. Check whether the connection expired, was revoked, or is paused.
5. Review the active connection and its scope before sending another request.

A model cannot create a draft if its current catalog and grant do not permit creation. Changing access must refresh the authorized tools. Ask for a new request after resolving access; do not rely on a claim from an older conversation.

An update from an earlier release can expand active, unexpired grants once to all available tools and the whole library. It does not extend expiry, reactivate revoked or expired grants, or turn on saved-off local access. Review connections after updating.
