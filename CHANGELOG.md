# Changelog

Entries describe source changes. Public downloads are listed on [GitHub Releases](https://github.com/pobrespandas/draftly/releases).

Historical entries were imported from public GitHub release notes. Unpublished historical candidates were excluded.


## [0.3.0]

Draftly 0.3.0

Chat Console shows when draft tools are connected and how to connect them.
Apple Intelligence On-Device can address the open draft directly.
ChatGPT and Apple Intelligence use tool results to report whether an edit
succeeded.

A new MCP connection proposes all available permissions and the entire
library. Review and narrow the scope before approving. Local agent access
starts off.

During catalog stabilization, this update restores the default actions and
groups. It replaces custom and edited actions and groups. It preserves drafts.

Requires macOS 26 or later. Apple Intelligence On-Device requires a compatible
Mac with Apple Intelligence enabled.

## [0.2.0]

Draftly 0.2.0

Use the Chat Console with ChatGPT or Apple Intelligence On-Device. Connect
Draftly tools to give the chat temporary read or edit access to the open
draft and editor.

Connect local clients such as Codex and Claude Code through Draftly's MCP
helper. In Settings, open Agents and enable local access. Review the client's
connection request and choose which resources it can use. Local access starts
off. You can revoke access or stop work in Settings.

During catalog stabilization, this update restores the default actions and
groups. It replaces custom and edited actions and groups. It preserves drafts.

Requires macOS 26 or later. Apple Intelligence On-Device requires a compatible
Mac with Apple Intelligence enabled.

## [0.1.10]

Draftly 0.1.10

Fix an empty default action catalog on a fresh iCloud library. The five default
action groups now appear without waiting for an iCloud import. Their stored
symbols and colors are included.

When import succeeds, Draftly completes the pending catalog replacement without
adding duplicate defaults. During catalog stabilization, installation and updates
replace all actions and groups, including custom and edited actions. Drafts are
preserved. Changes made after a completed installation stay until the next update.

Agent access remains disabled. Chat Console is not included in this release.
Requires macOS 26 or later.

## [0.1.9]

Draftly 0.1.9

This update improves text composition in the editor. It preserves marked text
while the editor updates and reduces repeated syntax analysis.

The default action catalog is restored after installation or update. This
temporary behavior replaces all existing actions and action groups, including
custom and edited actions. Drafts are not replaced. Libraries that use iCloud
wait for a successful import before the catalog is restored.

Agent access remains disabled. Agent testing continues in a separate QA build.

## [0.1.7]

Draftly 0.1.7

The default action catalog updates automatically after installation or update.
This temporary update replaces all existing actions and action groups, including
custom and edited actions. It restores the five default groups with their current
icons and colors. Drafts are not replaced. Changes made after this installation
remain until the next installation or update.

Libraries that use iCloud wait for a successful import before replacement.
If iCloud is unavailable, the existing catalog remains until the import succeeds.
Agent access remains disabled.

## [0.1.6]

Draftly 0.1.6

Replace the default action catalog from Settings > Maintenance. This restores
deleted defaults and replaces edited defaults with the current Basic, Editing,
Markdown, Tools, and Processing actions. Personal actions remain unchanged.
Repeated replacement does not create duplicate groups or actions.

Store the reviewed action symbols, colors, and bar labels with the catalog.
The action list, bar, inspector, and exports use those stored values.

Existing libraries keep their current actions until you choose Replace Default
Actions. Automatic catalog updates are not enabled in this version.

Agent access remains disabled in normal app startup. No agent helper is bundled.

Requires macOS 26 or later.

## [0.1.5]

Draftly 0.1.5

Use native Settings tabs, action group buttons, and action list selection.
Select an action with one click. Run it with Return or a double click.

Improve default action colors, symbols, and action bar labels. Correct the
default Inbox, Save Version, and Stats actions. Upgrade unchanged local copies
while preserving customized actions. Existing cloud libraries retain their
actions; defaults can be installed explicitly from Settings.

Open and close panels without an added transition. Keep the action panel
toolbar button visible as an enabled control when its panel is closed.

Agent access remains disabled in normal app startup.

Requires macOS 26 or later.

## [0.1.3]

Draftly 0.1.3

Fix a draft-list click that could only move focus from the editor instead of
opening the selected draft. A single click now selects and opens the draft.

Requires macOS 26 or later.

## [0.1.2]

Draftly 0.1.2

This release validates the public update and reinstall process.
It retains the app features and clean-install correction from 0.1.1.
No new app features are included.

Requires macOS 26 or later.

## [0.1.1]

Draftly 0.1.1

Fixes a startup error on clean installations when no local preferences exist.
Existing preferences and libraries remain unchanged.

Requires macOS 26 or later.

## [0.1.0]

Draftly 0.1.0

First public release for macOS 26 or later.

Capture and organize drafts with tags, flags and Workspaces.
Edit plain text, Markdown, HTML, MultiMarkdown and TaskPaper.
Use the integrated Markdown preview and installed Nerd Fonts.
Create and run Actions with JavaScript and native steps.
Customize editor fonts, themes, margins and shortcuts.
Export and restore library backups, including Action history.
Check for signed updates. Draftly asks before it installs an update.

Draftly has one edition. There is no Pro tier.

Compatibility work continues. Some Drafts scripting contracts and native
integrations still have open checks. See the project status for current limits:
https://github.com/pobrespandas/draftly/blob/main/docs/status.md
