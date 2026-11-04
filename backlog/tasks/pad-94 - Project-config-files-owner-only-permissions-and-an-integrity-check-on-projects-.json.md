---
id: PAD-94
title: >-
  Project config files: owner-only permissions and an integrity check on
  projects/*.json
status: In Progress
assignee: []
created_date: '2026-11-04 18:43'
updated_date: '2026-11-04 18:54'
labels:
  - security
  - config
dependencies: []
priority: low
type: task
ordinal: 99000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Review 2026-11-04. ProjectStore, PaddockOverlay, ProjectKitFile, Kits and KitFile write into ~/.config/paddock with default permissions (typically 0644 files, 0755 dirs) via Data.write(.atomic). projects/<name>.json holds approvedEnvironment, the operator's approval of a sandbox definition, in plain JSON that is hand-editable by design; any process running as the same user can approve an sbxenv.yaml without the sheet. FolderPolicy keeps project folders out of this directory, so sandboxes cannot reach it, but other host software can. Paddock stores no secrets, so this is hardening, not a leak.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The config dir and its subfolders are created 0700 and files 0600, repaired at launch when looser
- [ ] #2 Decision recorded in the ProjectStore doc: either approvals carry an HMAC with a key in the macOS Keychain (Paddock stores no secrets: confirm that this key is allowed under CLAUDE.md rules first) or the risk is accepted in writing
- [ ] #3 Tests for creation modes and repair
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
The writers already created 0700/0600 for projects and overlays; added PaddockPaths.secure() (repairs folders, files, paddock.yaml, skips links) called from AppModel.loadFiles, with tests. The signing question (AC2) is not decided; Keychain use needs the operator's call under the no-secrets rule. NOT compiled.
<!-- SECTION:NOTES:END -->
