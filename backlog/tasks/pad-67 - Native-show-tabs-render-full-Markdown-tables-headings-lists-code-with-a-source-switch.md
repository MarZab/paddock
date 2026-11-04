---
id: PAD-67
title: >-
  Native show tabs render full Markdown (tables, headings, lists, code), with a
  source switch
status: In Progress
assignee: []
created_date: '2026-11-01 15:31'
updated_date: '2026-11-01 15:42'
labels:
  - app
  - browser
dependencies: []
ordinal: 67000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Agents write Markdown a lot (reports, inventories, plans) and show it with `paddock open FILE --native`. The native tab rendered it with AttributedString inline-only parsing, so headings, lists, tables, fenced code, block quotes and YAML front matter showed as raw `#`, `-` and `|`. A real-world sample that must render well: a backlog-style doc with front matter, 9-column GFM tables whose cells hold code spans, `<img src>` text and stray pipes like `"0"|"1"`. The operator also wants to see the file as it is when the rendering looks wrong.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A .md/.markdown native tab renders GFM: headings, emphasis, lists (nested, ordered, task lists), tables (wide ones scroll sideways), fenced and inline code, block quotes, rules, strikethrough, links and images
- [ ] #2 YAML front matter at the top shows as a small key/value block, not as a rule and a heading
- [ ] #3 Raw HTML in the Markdown shows as literal text; nothing from the file runs (no JavaScript, CSP allows no scripts, no network)
- [ ] #4 Relative images and links to files beside it load through paddock-file:// (a linked .md renders too); anchors to headings work; other links do nothing
- [ ] #5 A table row with more cells than its header because of an unspaced pipe (a|b) keeps that pipe as text
- [ ] #6 A Source/Rendered switch on the tab shows the file as plain text and back, kept per tab while Paddock runs
- [ ] #7 Rendering follows light and dark mode
- [ ] #8 Fixture tests in PaddockCore cover the sample document, escaping, links/images, front matter and the pipe repair; Browser and Security rules docs updated
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Add swift-markdown (cmark-gfm) to PaddockCore; MarkdownPage turns Markdown into a self-contained HTML page with our own walker (escapes everything, raw HTML as text, slugged heading ids, safe link/image URLs, CSP meta, light/dark CSS), front matter split off first, unspaced pipes escaped only in rows that have too many cells.
2. NativeShowPolicy: markdown renders in the sealed web view; the scheme handler serves .md files as the rendered page (NativeShowPolicy.response), JavaScript off for markdown tabs.
3. App: NativeShowView uses the web view for markdown, a Source/Rendered picker overlay, state in ProjectTerminals.
4. Fixture: the operation inventory doc as Fixtures/markdown; tests. Update doc-9 Browser and doc-14 Security rules.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Core done and tested on Linux (519 tests pass): MarkdownPage + MarkdownRenderer (swift-markdown 0.9.0, cmark-gfm), NativeShowPolicy.response/allowsJavaScript, fixture Fixtures/markdown/operation-inventory.md (the agent doc that prompted this). Findings while testing: swift-markdown turns on smart quotes by default (now off) and leaves out cmark autolinks (bare URLs linked by the renderer); CRLF is one Swift Character, normalized first; tight lists told from source lines. App side (web view for Markdown, JS off, Rendered/Source picker, ProjectTerminals.sourceShows) written but not built: needs mise run build on the Mac and a look at a real tab. Preview of the fixture: scratch/markdown-preview.html. Docs: Browser and Security rules updated.
<!-- SECTION:NOTES:END -->
