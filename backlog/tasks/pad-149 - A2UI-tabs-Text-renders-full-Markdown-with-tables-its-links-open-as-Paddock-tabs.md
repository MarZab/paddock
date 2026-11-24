---
id: PAD-149
title: >-
  A2UI tabs: Text renders full Markdown with tables; its links open as Paddock
  tabs
status: Done
assignee:
  - '@claude'
created_date: '2026-11-24 22:26'
updated_date: '2026-11-24 22:54'
labels: []
dependencies: []
priority: medium
type: enhancement
ordinal: 157000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Agents put Markdown in A2UI Text components, tables above all; A2UI's Swift Text draws headings, lists, code, quotes and emphasis but no tables (and the basic catalog has no Table), so a table showed as pipes. Decided with the operator (2026-11-24): Paddock replaces Text, as it does Image, Video and AudioPlayer, with a native renderer for GitHub Markdown including tables, and the reference tells agents what Text renders. Links in that Markdown open as Paddock tabs: a path relative to the tab's messages as a native tab (paddock open FILE --native), an http(s) URL as a page tab of the sandbox's browser like openUrl (the operator asked for a native tab; a native tab loads only files, never the network, per CLAUDE.md, so web links go to the sandbox browser); anything else opens nothing. Images in Markdown are not loaded (alt text), raw HTML is text, as in A2UI.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Parsing lives in PaddockCore (A2UIMarkdown, swift-markdown with GFM tables, Linux-tested): headings, paragraphs, emphasis, strikethrough, inline code, code blocks, quotes, nested and task lists, rules, tables with column alignment; images become their alt text, HTML stays text
- [x] #2 Links are classified as a sandbox web page (http, https), a file next to the tab's messages (relative, no escape), or none; nothing else is clickable
- [x] #3 PaddockA2UI draws it natively (tables as a SwiftUI Grid, wide ones scroll) as the basic catalog's Text, with its caption and body variants
- [x] #4 Clicking a web link opens a page tab in the sandbox's browser; clicking a file link opens it as a native tab through paddock (--show-file ID PATH, resolved inside the tab's folder); the tab says what happened
- [x] #5 The A2UI reference says what Text renders, that tables work, and when to use a Column of Rows instead; doc Browser describes it
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. A2UIMarkdown in PaddockCore: swift-markdown (with MarkdownPage.repairTablePipes) to blocks and styled runs; images as alt text, HTML as text; Link classifies web pages and files next to the messages. 2. paddock --show-file ID PATH (inside the tab's folder) and A2UICommands.openFile, ProjectRunner.a2uiOpenFile. 3. PaddockA2UI: PaddockText replaces the basic catalog's Text (caption/body), MarkdownBlocksView with a Grid for tables, links through OpenURLAction to A2UITab.open (web: openInSandbox; file: A2UITabLink.openFile). 4. Reference rules (Text and Markdown) regenerated; doc Browser; CHANGELOG.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
The operator asked for links in a native tab; a native tab loads only sandbox files, never the network (CLAUDE.md), so file links open as native tabs and web links as page tabs of the sandbox's browser, like openUrl. The generated schema's Text description (simple Markdown, no links) is overridden by a line in Paddock's rules. Linux: 643 + 36 tests and lint pass (A2UIMarkdownTests, the --show-file helper test). PaddockA2UI's view and its two new tests build on the Mac.

Checked by the operator in a project on the Mac (2026-11-24): works.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
A2UI tabs' Text is Paddock's: its string is parsed in PaddockCore (A2UIMarkdown, swift-markdown with GitHub tables) and drawn natively, tables as a SwiftUI Grid with column alignment, caption and body as in A2UI, images as alt text and HTML as text. Links open only as tabs: a file next to the messages as a native tab (paddock --show-file, inside the tab's folder), an http(s) page in the sandbox's browser; anything else opens nothing. The agents' reference says what Text renders and when to build rows from components. Linux tests pass (A2UIMarkdownTests, the --show-file helper test); built and used in a project on the Mac; PaddockA2UI's two new tests (links to the right action, a Markdown table in a tab) have yet to run there (mise run test).
<!-- SECTION:FINAL_SUMMARY:END -->
