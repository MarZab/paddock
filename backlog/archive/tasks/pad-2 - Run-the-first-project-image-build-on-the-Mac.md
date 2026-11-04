---
id: PAD-2
title: Run the first project image build on the Mac
status: To Do
assignee: []
created_date: '2026-10-25 15:54'
updated_date: '2026-11-04 15:07'
labels:
  - images
  - verify
milestone: m-0
dependencies: []
priority: high
type: task
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ImageBuild and ImageBuilder build a project's own image in a builder sandbox when .paddock.toml has an [image] section (doc: Custom images). It is fixture-tested but has never run against real sbx. Run it on the operator's Mac with a small Dockerfile in scratch/.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A project in scratch/ with a Dockerfile FROM docker/sandbox-templates:claude-code-docker builds and its sandbox runs on paddock/<project>:<hash>
- [ ] #2 The builder sandbox is removed after success and after a failed build, and a failed build shows docker's last 30 lines
- [ ] #3 Changing the Dockerfile shows recreate under Needs attention; changing only hosts or ports does not rebuild
- [ ] #4 Any sbx output that differs from the fixtures is captured as a new fixture and the parser fixed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Obsolete (PAD-73.4, 2026-11-04): Paddock no longer builds project images. A project's own v3 kit has a dockerfile that sbx builds itself at create, and a change to the kit's files changes its fingerprint, which asks the operator again and lists a recreate item.
<!-- SECTION:NOTES:END -->
