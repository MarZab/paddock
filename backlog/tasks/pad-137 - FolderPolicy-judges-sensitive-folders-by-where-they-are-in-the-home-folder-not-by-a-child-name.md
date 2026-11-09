---
id: PAD-137
title: >-
  FolderPolicy judges sensitive folders by where they are in the home folder,
  not by a child name
status: In Progress
assignee: []
created_date: '2026-11-09 08:06'
updated_date: '2026-11-09 08:15'
labels:
  - security
  - folder-policy
dependencies: []
priority: high
ordinal: 139000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A project with its own `.azure` (azd creates one in the project root), `.docker`, `Library` (Unity) and so on could not be created: the contains check refused any folder with a direct child of a sensitive name, anywhere on disk. Those names are sensitive in the home folder. Operator decision 2026-11-09: anchor the rule to the home folder.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A project folder with its own directory named like a sensitive entry is accepted
- [x] #2 A folder that is, is inside, or contains a sensitive entry of the home folder is still refused, including `~/.config` holding `~/.config/gh`
- [x] #3 A direct child with a sensitive name that is a link to a sensitive folder of the home folder is refused
- [x] #4 FolderPolicyTests cover these; Security rules doc, CLAUDE.md and CHANGELOG state the new rule
- [ ] #5 Creating a project whose folder has its own directory with a sensitive name asks the operator to confirm, naming those directories
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Operator: hard block only the home folder and its sensitive folders; a name match is a confirm step in the New Project sheet. Root, a folder containing home, and Paddock config overlap stay refused.

Committed. Tests and lint pass on Linux (594 PaddockCore, 36 PaddockShell). AC5 is App code, not yet built or exercised on the Mac: stays open until mise run build and a create with a project .azure.
<!-- SECTION:NOTES:END -->
