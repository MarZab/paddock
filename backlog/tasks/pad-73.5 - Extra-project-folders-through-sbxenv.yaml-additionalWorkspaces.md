---
id: PAD-73.5
title: Extra project folders through sbxenv.yaml additionalWorkspaces
status: In Progress
assignee: []
created_date: '2026-11-04 09:33'
updated_date: '2026-11-04 15:07'
labels: []
dependencies:
  - PAD-73.3
documentation:
  - doc-14
  - doc-11
  - doc-10
parent_task_id: PAD-73
priority: medium
type: feature
ordinal: 78000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A project often needs a second folder: a sibling repo it builds against, a shared library, or a docs checkout. sbx supports this in `sbxenv.yaml` as `additionalWorkspaces` (`path` required, `target`, `readOnly`; relative paths resolve from the file's folder), and `sbx ls --json` already reports `workspaces` as a list. The operator decided (2026-11-04) to plan this in.

It widens the security rule "Only the operator-chosen project folder is ever mounted". The rule becomes: the project folder plus the extra folders the operator confirmed, each checked by FolderPolicy.

The project file is agent-writable, so an entry there is only a suggestion until the operator confirms it. sbx merges lists from the project file and Paddock's overlay, so Paddock cannot drop an entry. An unconfirmed or refused entry has to block create instead.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Each `additionalWorkspaces` path is resolved (relative to the file, symlinks followed) and checked by FolderPolicy like a project folder; one that fails blocks create with the reason (tests per violation, including `..` and a symlink to `$HOME`)
- [ ] #2 The confirmation sheet lists each extra folder with its resolved path and read-only or writable; nothing is mounted until the operator confirms, and adding a folder or turning one writable asks again
- [x] #3 Read-only is the default: an entry without `readOnly: true` is shown as writable and warned about; an extra folder that is another Paddock project's folder is marked as such
- [x] #4 `target`, if allowed at all after PAD-73.1, must be an absolute path that is not a system directory (`/`, `/etc`, `/usr`, `/bin`, home of `agent`); otherwise it is refused
- [x] #5 SandboxSync compares the sandbox's `workspaces` with the project folder plus confirmed extras, and a difference is a recreate item (confirmed first)
- [x] #6 The Info tab shows a sandbox's extra folders, with open in Finder
- [x] #7 CLAUDE.md security rule on mounted folders and backlog docs Security rules, Project config file, and App config describe extra folders
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Path checks are in ProjectEnvironment.checkExtraFolders (FolderPolicy per path, links followed, project folder refused, target refused when relative or a system folder, other project marked). Sheet, recreate item, Info tab wait on PAD-73.3 wiring.

Built for operator-added extra folders on today's create path, with no sbxenv.yaml (operator, 2026-11-04: read-only by default).
- Project.extraFolders lives in Paddock's project file.
- ExtraFolders: check, checkAll, argument (PATH or PATH:ro), inSandbox (from sbx's workspaces), and otherProject. They are checked when added and again at every create (ProjectRunError.extraFolder stops the create).
- sbx create gets them after the project folder.
- SandboxSync shows an extra-folders recreate item.
- App: an Info tab row (Read-only, Show in Finder, Remove, Add Folder, a mark for another project's folder) and a New Project sheet section. Not compiled here.
- CLAUDE.md security rule, and backlog docs Security rules, ProjectStore, and UI, updated. Tests: ExtraFoldersTests, plus the Sync and ProjectRunner cases.
Still open: AC2 (the confirmation sheet for sbxenv.yaml's additionalWorkspaces) and AC4 (target), which wait on PAD-73.3.

AC2: the sbxenv.yaml confirmation sheet lists each additionalWorkspaces entry (resolved path, read-only or writable, another project's folder marked); create needs the confirmed fingerprint, so a new or writable entry asks again. Operator-added folders go into the overlay's additionalWorkspaces. Waits for the Mac build to check.
<!-- SECTION:NOTES:END -->
