# CLI and MCP clients

Draftly provides a local helper for CLI and MCP clients. The app owns the library and editor. Keep Draftly running while a client uses the connection.

## Connect a client
1. Open Settings → Agents.
2. Enable local access if you want to allow a connection.
3. Use Copy connection command and run that command in Terminal.
4. Compare the pairing code in the client and the app.
5. Review the permissions, resources, and expiry before approving.
6. Configure your client with the approved local connection.

Use the command shown by the installed app. Do not paste credentials or connection secrets into a public issue or chat.

## Available operations
The local catalog contains 139 operations across drafts, editors, actions, workspaces, settings, themes, syntax, imports, backups, activity, and native integrations. Discovery exposes handlers that are available under the current permission. A client can therefore see fewer than 139 tools.

Each operation has its own MCP tool schema. Clients must use the advertised names and fields. A cached tool list is not continuing authorization: each call checks the current grant.

Codex and Claude Code have installed-app acceptance evidence. Other clients need their own compatibility check. Draftly does not offer a remote agent endpoint over SSH, VPN, or HTTPS in this release.

For protocol contracts and client setup details, see the [repository documentation](https://github.com/pobrespandas/draftly/tree/main/docs).
