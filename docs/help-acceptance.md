# Integrated help acceptance

Checked on 11 November 2026, against the help branch based on 19d1754.

## Implementation

The app includes 18 Markdown articles in the core resource bundle. Help →
Draftly Help opens a separate native window. Search matches words in titles,
categories, and article text. The reader reuses the chat Markdown presentation.
The manual needs no network connection. External reference links need a network.

## Evidence

- The Draftly product build passed.
- Both HelpGuideTests passed. They load all bundled articles, check unique
  identities and content, and check multi-word, empty, and missing search terms.
- `git diff --check` passed.
- An isolated app with a separate bundle ID and temporary library opened the
  manual from Help. All 18 topics appeared in the index.
- Searching for `outcome_unknown` found the permissions article by its body.
  Selecting it displayed that article. A missing term showed No Results.
  Clearing search restored the full index.
- Native QA used a dark appearance. It did not open the normal library or
  create a model connection.

## Remaining acceptance

Full CI and the signed release package remain untested for this change. Native
QA did not check every external link, VoiceOver, light appearance, or the Help
keyboard shortcut. The manual is in English, matching the app. This is not an
Apple Help Book with system-wide topic indexing. It provides its own in-app
search. No release was published for this change.

## Agent help and workflow skill

The local catalog now has 139 operations. The two additions are help.search
and help.get. They use the same bundled articles as the Help window. They need
an active authenticated connection, but no draft capability or resource scope.
They cannot read draft text. Existing public tool names stay unchanged.

The separate bundled skill is available through help.get with id agent-skill.
Its source is `Sources/DraftlyCore/Resources/draftly/SKILL.md`. It uses the
standard skill frontmatter. It is not an extra user-guide sidebar article.
The skill validator passed. This change does not install it into a client's
personal skill folder. The shared model instructions point clients to its tool
representation when a Draftly creation or change needs the workflow.

The shared prompt directs models to search the installed guide for product
instructions, use current access results, and distinguish a draft from its open
editor. Help is reference data. It does not grant permission to run examples.
Routine authorized reads need no skill load. With tools off, the chat must not
claim that it consulted installed help or saved a draft.

The SDK/CLI suite passed 20 tests, including discovery, reading the bundled
skill, missing IDs, unchanged notes, complete and paged catalogs, and revocation.
Contract, guide, and service tests passed. The service check covered a grant
without draft capabilities, invalid input, missing articles, denied draft reads,
and revoked access. These are isolated local-host tests, not installed signed
client acceptance or live model evaluation.

Live Apple Intelligence and ChatGPT requests using the new skill remain to be
checked in a signed installed QA. Full CI and publication also remain pending.

The 37 chat regression tests passed after the final prompt change. They cover
mocked provider and tool behavior, cancellation, stream validation, and model
session boundaries. They do not establish that a live model will choose the
help tools correctly.

## Installed model acceptance — 11 November, QA build 74

The installed app was `~/Applications/Draftly Help Agent QA.app`, source c431904.
It used the existing isolated library A2E91C40-0C42-4F37-96B3-76E07449F8A0.
Its QA-only display version was 0.6.0-alpha.1. This does not set a release tag.
The normal installed app and library were not used.

The app and helper passed strict signature verification. Notary submission
44d9ce09-db65-4d23-8fd8-b1ae6eaf403e was accepted and the ticket was stapled.
The user approved the QA connections. Each scenario used a fresh conversation.

- Apple Intelligence On-Device searched and read the installed help. It correctly
  distinguished the Maintenance default-action replacement from the broader
  installation/update replacement.
- Apple read agent-skill in a separate scenario. It answered that Undo must use
  editor.undo and that manual text replacement must not be called Undo.
- ChatGPT GPT-6.1-Sol searched and read the same help article. It named the article
  and explained the replacement scope correctly.
- ChatGPT read agent-skill and explained both the Undo rule and failed-Undo
  handling: report the failure and keep current text unless another recovery is
  requested.

The activity store confirmed help.search and help.get success for each model,
and a separate help.get success for each skill scenario. Only those operations
and server.capabilities/server.schemas appeared in the four successful scenario
connections. No draft read, write, or external effect was requested. The list
kept 17 QA drafts with the same visible modification dates.

All QA connections were revoked. The UI showed local access off. Independent
metadata inspection confirmed enabled=false and zero unrevoked connections.
The QA sign-in was retained; no credentials were copied into this report.

### Correction found by the installed test

Build 73 repeated catalog discovery without reaching a help operation. The run
was stopped, its connection was revoked, and local access was switched off.
The activity record showed only successful capability/schema reads.

Build 74 adds compact Apple help-search and help-read tools. They call the same
service and check current authorization for each request. They do not add an
MCP operation or bypass the permission gateway. The 18 Apple tool tests passed,
including the compact help tools and rejection after revocation.

These checks establish the two demonstrated help/skill tasks. They do not prove
that either model always follows the skill or can recover every failed edit.
The older installed Undo limitation is not resolved by this change.

## Full PR validation

PR #124 head 69e0915 passed CI run 43124190648. Native tests, test inventory,
local app build, script tests, matrix checks, and the required combined result
all passed. The website job was not selected because no website code changed.
The installed model build used c431904; the following commit changed only this
acceptance document. No merge or publication is part of this acceptance.
