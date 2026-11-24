---
id: PAD-148
title: 'New Project: keep Claude''s sessions and create the sandbox files by default'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-24 22:07'
updated_date: '2026-11-24 22:16'
labels: []
dependencies: []
priority: low
type: enhancement
ordinal: 156000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The operator wants both on for new projects (2026-11-24): keeping Claude Code sessions across recreates (PAD-127) and writing sbxenv.yaml with a project kit (SandboxFiles) were opt-in, and nearly every project wants them. Both stay switches in New Project; a folder that has its own sbxenv.yaml still gets no files, and only Claude Code projects keep sessions.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A new project draft keeps Claude sessions unless the operator turns it off; a non-Claude project still keeps none
- [x] #2 New Project's "Create sbxenv.yaml and a kit" starts on; a folder with an sbxenv.yaml still gets no files
- [x] #3 A test covers the draft default; doc UI (or the doc that describes New Project) says both start on
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ProjectDraft.keepsClaudeSessions starts true (NewProject.make still keeps sessions only for Claude Code; tested in ClaudeSessionsTests); New Project's writesFiles starts true (a folder with sbxenv.yaml still gets none, addProject's existing check). Doc UI and doc Project config file say both start on. The sheet's default is app code: checked in the Mac build.

Built on the Mac at 401b0e4 (no warnings).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
New projects start with Keep Claude's sessions on (ProjectDraft.keepsClaudeSessions; still Claude Code only) and Create sbxenv.yaml and a kit on (New Project's writesFiles; a folder with its own sbxenv.yaml still gets none). Tested in ClaudeSessionsTests; docs UI and Project config file updated; built on the Mac.
<!-- SECTION:FINAL_SUMMARY:END -->
