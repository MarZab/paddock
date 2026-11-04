---
id: PAD-83
title: >-
  FolderPolicy also rejects folders inside sensitive directories, and the list
  covers more than four names
status: In Progress
assignee: []
created_date: '2026-11-04 18:43'
updated_date: '2026-11-04 18:54'
labels:
  - security
  - folder-policy
dependencies: []
priority: high
type: bug
ordinal: 88000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Review 2026-11-04. FolderPolicy.check rejects a folder only when it IS $HOME or / , contains $HOME, or has a DIRECT child named .ssh, .aws, .gnupg or Library. A folder INSIDE those (~/.ssh, ~/.aws, ~/Library/Keychains, ~/.gnupg/private-keys-v1.d) has no such child, so it passes, and the same holds for ~/.kube, ~/.docker, ~/.config/gh, ~/.netrc-style stores. FolderPolicy is the only guard against mounting credentials into a sandbox (CLAUDE.md, Security rules), and it also guards extra folders (ExtraFolders, ProjectEnvironment.checkExtraFolders). Case-insensitive APFS and symlinks are resolved already (canonical); keep that.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A folder that is, or is inside, one of the sensitive entries under $HOME is rejected with a new violation case (inside, not only contains)
- [ ] #2 The sensitive list gains at least .kube, .docker, .config/gh, .config/gcloud, .azure, .npmrc-holding dirs the operator would not expect, and Library/Keychains; decide the list in a doc, with the reason per entry
- [ ] #3 FolderPolicyTests cover: inside .ssh, inside Library, nested symlink into .aws, case variant .SSH, each new entry
- [ ] #4 Security rules doc and CLAUDE.md state the broadened rule
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
insideSensitiveEntry added, list extended (.kube .docker .azure .config/gh .config/gcloud), tests in FolderPolicyTests, docs and CLAUDE.md updated. NOT compiled. AC2 asks for a per-entry reason doc: not written.
<!-- SECTION:NOTES:END -->
