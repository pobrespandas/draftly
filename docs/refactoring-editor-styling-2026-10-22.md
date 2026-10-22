# Editor styling refactoring — 22 October 2026

## Scope and base

This stage implements R2 from the modularity audit. The base is 62b280e on the
completed Cloud QA preparation branch. The primary checkout stayed on main at
5494342. Both checkouts were clean. No build or test process was active.
Previous work remains on its branches. No installed app was changed.

Before edits, Core674, app777, Python80 and the local Debug build passed.
The Swift runner matched all XML results to the discovered inventory.
The annotated tag pre-refactor-editor-styling-2026-10-22 marks this base.
The branch is agent/editor-styling-2026-10-22.

## Problem and boundary

NativeEditor.Coordinator.highlight applied base attributes, visual syntax rules,
custom syntax scopes, links and indentation metrics. The coordinator also owns
text events, synchronization, selection and Undo. Styling changes therefore
required editing the component that protects text coherence.

EditorSyntaxStyler now owns attribute application. Its inputs are font settings,
paragraph settings, Markdown mode, syntax name, syntax definition, theme and link
mode. Its apply operation receives an NSTextView and captured native link
attributes. It does not read a session, window model or NativeEditor.

Coordinator.highlight remains the entry point. It captures native link defaults
once and delegates. Events, text mutation, selection, Undo, focus, invalidation,
style invalidation keys and notification order remain in their previous places.
ThemeTextAttributes and SyntaxDefinition retain their rules. No protocol or
alternate syntax engine was added.

The attribute body matches the base after input substitution and indentation.
The initial storage guard and link-default capture remain at the boundary.
The generated Xcode project changes only the new source references and build
entry. Public APIs, identities, formats, scripts and backups have no changes.

## Preserved behavior

Application order remains base attributes, built-in visual rules, custom default
scopes, detected and custom links, theme scopes, active-link theme, native link
presentation and indentation metrics. Task scopes still cannot replace task
foreground colors. Inherited fonts, heading levels and paragraph metrics remain.
Built-in visual fallback expressions were not removed or combined.

Styling still resets attributes before applying them. Removing a theme, scope or
link mode restores the existing defaults. Empty text still sets typing attributes.
No rollback, new error handling, text replacement or callback was added.

## Automatic verification

Three new characterization methods passed against the original coordinator:

- overlappingStylesKeepCustomScopesAndActiveLinksLast checks overlapping
  Markdown, custom scopes and active links, including inherited font attributes.
- removingStylesRetainsNativeUndoAndUnicodeSelection checks style removal with
  a pending text edit, retained Unicode selection, native Undo/Redo and callbacks.
- emptyTextRestoresBaseTypingAttributesWithoutUndo checks empty storage and
  paragraph typing attributes across theme changes.

After extraction, stylerRestoresExplicitLinkDefaultsIndependentlyForEachView
checks the direct boundary. A shared styling value handles two text views with
separate explicit link defaults, including nil, without leaking presentation.
All existing test names and cases remain.

The focused run passed 72 methods in nine suites. The final complete run passed
Core674 and app781 with matching XML/discovery inventories. Python80 passed.
The structural matrix check passed with zero errors. The strict engine gate
still reports six partial contracts and 18 diagnostics. Those are outside R2;
this refactoring does not claim to resolve compatibility acceptance.

The final local Debug build passed. No build and Swift test run overlapped.
Source and tests stayed fixed during the complete final run. Temporary outputs
use /tmp/draftly-styling-* and are not versioned. No screenshots or raw logs
were added. No timeout or retry was changed.

## Native verification and limits

Tests exercise AppKit text storage, installed editor bindings and native Undo
in memory or in hidden test hosts. They do not display, activate or move windows,
request permissions, play sounds or read personal data. No new manual Computer
Use session was needed for this private extraction. This is not a new visual
parity or native feature acceptance claim. The usual app was not replaced.

Earlier XML-RPC and host-start timing failures remain independent known risks.
Neither appeared in this baseline or final run. No shared cause or fix is claimed.

## Continuation

R1, R2, R4 and R5 are implemented on the stacked refactoring branches. R3 shared
text mutation is the next proposed stage. Preserve distinct caller policies in
updateNSView and synchronizeScriptEdit. Functional cloning, strict engine
acceptance, signing and iCloud acceptance remain separate work.
