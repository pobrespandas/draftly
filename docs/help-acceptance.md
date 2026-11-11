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
