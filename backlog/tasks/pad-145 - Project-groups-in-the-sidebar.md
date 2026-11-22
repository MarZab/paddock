---
id: PAD-145
title: Project groups in the sidebar
status: Done
assignee:
  - '@claude'
created_date: '2026-11-22 07:55'
updated_date: '2026-11-22 08:08'
labels: []
dependencies: []
ordinal: 147000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
With many projects the sidebar's one Projects list gets long. The operator wants to put projects in groups, kept in each project's file and edited in Info's Agent card, and fold a group down to its running projects, or close it to a count, from its title.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A project has an optional group, kept in its project file (group), read by older files as none, edited in Info's Agent card
- [x] #2 The sidebar shows one section per group, titled with the group's name, sorted by name, projects not indented; projects without a group are in Other, last; with no groups at all the one Projects section stays as it is
- [x] #3 Clicking a group's title cycles open (every project), folded (only running projects), closed (no rows, the number of running projects on the right), and back to open; every group starts open
- [x] #4 A line separates the System section from the projects
- [x] #5 Grouping and the fold cycle are tested in PaddockCore; doc UI describes groups
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Project.group (optional, normalized) in ProjectStore; ProjectGroups in PaddockCore: sections (by name, case-insensitive, Other last, one plain section without groups) and Fold (open > running > closed). 2. AppModel.setGroup saves the project file. 3. Sidebar: a section per group with GroupHeader cycling the fold, count of running when closed; overview via context menu, problems mark, breadcrumb; Divider above System. 4. Info Agent card: Group field (text field + menu of groups in use). 5. Tests, docs UI and ProjectStore, CHANGELOG.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Core done and tested on Linux (ProjectGroupsTests; full suite 640 tests pass, lint clean). App views not built yet: needs mise run build and a look on the Mac. Fold state is in memory (every group open at launch).

Operator iterated on the header count on the Mac (BUILD SUCCEEDED 2026-11-22 09:07): every group heading shows running/all at the right, caption regular, running green (grey at 0), 16 pt in from the edge.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Projects have an optional group (project file key group, trimmed, set in Info's Agent card by a field or a menu of groups in use). Once any project has one, the sidebar shows a section per group (sorted, case-insensitive) and Other last; without groups it stays one Projects section. Clicking a group title cycles open, running only, closed; each heading shows running/all (running green, grey at 0). The overview is in the heading's context menu, the first group's problem mark, and the breadcrumb. A line separates System. Fold state is in memory. ProjectGroups is tested in PaddockCore (full suite and lint pass on Linux); the views were built and checked on the Mac by the operator.
<!-- SECTION:FINAL_SUMMARY:END -->
