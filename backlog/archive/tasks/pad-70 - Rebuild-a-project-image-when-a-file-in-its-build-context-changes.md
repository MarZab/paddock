---
id: PAD-70
title: Rebuild a project image when a file in its build context changes
status: To Do
assignee: []
created_date: '2026-11-03 16:28'
updated_date: '2026-11-04 15:07'
labels:
  - images
dependencies:
  - PAD-69
documentation:
  - doc-7
priority: medium
ordinal: 70000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The image tag (`ImageBuild.tag`) hashes the Dockerfile, build arguments, the Dockerfile and context paths, and the agent section, but not the files the Dockerfile COPYs, so editing only those (say, the root mise.toml's tool versions) never rebuilds. Projects work around it with a hand-kept hash in `[image.buildArgs]` (REV). Hashing the whole context was impractical while the copy took the whole folder; once the copy honours .dockerignore (PAD-69), the files that reach the build are a small, known set and can be part of the tag.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The tag covers the path, mode, and content of every file that reaches the build (after .dockerignore), so changing, adding, or removing one gives a new tag and Sync lists a recreate
- [ ] #2 Files excluded by .dockerignore do not affect the tag; tests cover both cases
- [ ] #3 Computing the tag stays cheap for a filtered context (no full read of excluded folders) and does not block the main actor
- [ ] #4 The same file set and hash apply with [images] builder = "docker"
- [ ] #5 backlog doc Custom images no longer says COPYed files are outside the hash
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Obsolete (PAD-73.4, 2026-11-04): Paddock no longer builds project images. A project's own v3 kit has a dockerfile that sbx builds itself at create, and a change to the kit's files changes its fingerprint, which asks the operator again and lists a recreate item.
<!-- SECTION:NOTES:END -->
