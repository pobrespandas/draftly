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
