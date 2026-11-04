---
id: PAD-73.4
title: Remove Paddock's own project image builds
status: Done
assignee: []
created_date: '2026-11-04 09:32'
updated_date: '2026-11-04 15:07'
labels: []
dependencies:
  - PAD-73.3
documentation:
  - doc-7
parent_task_id: PAD-73
priority: medium
type: chore
ordinal: 77000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
With project kits, sbx builds a local kit's Dockerfile itself at create, using the host's buildx or a builder sandbox. Paddock's own pipeline then has nothing left to do: building in a builder sandbox, copying the build context through the ignore file (PAD-69), rebuilding on change (PAD-70), and `sbx template load`. The Templates page (PAD-72) may still be useful for images sbx keeps.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 No code path builds or loads a project image; the image build code and its tests are gone
- [x] #2 PAD-70 is archived or rewritten for kit rebuilds, with a note why
- [x] #3 backlog doc Custom images is replaced by how a project kit builds, or removed, and the docs that named it are updated
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Removed ImageBuild, BuildContext, HostDocker, the [images] section and StatusProbe.dockerPath, Project.imageTag, the image recreate item, and the builder exclusions; TemplateUsage now names images by what they are (old project image, kit build, agent template, other) with no project or sandbox lookups. Templates page and Log category follow (the 'Image build' category is 'Setup', what a create reports). doc-7 Custom images archived; Overview, Kits, UI, App config updated. PAD-2, PAD-69, PAD-70 archived with a note. Core: 527 tests pass on Linux. App changes are not compiled here.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Paddock no longer builds or loads project images: a project's own v3 kit has a dockerfile sbx builds at create. The image build pipeline, its tests, the [images] config section, Docker detection, and imageTag are gone; the Templates page classifies images by name. Docs and tickets that described image builds are archived or updated. Risk: the App side is not compiled on Linux; build on the Mac.
<!-- SECTION:FINAL_SUMMARY:END -->
