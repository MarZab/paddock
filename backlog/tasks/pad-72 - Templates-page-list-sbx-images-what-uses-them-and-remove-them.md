---
id: PAD-72
title: 'Templates page: list sbx images, what uses them, and remove them'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-03 16:57'
updated_date: '2026-11-03 17:01'
labels:
  - app
  - images
dependencies: []
ordinal: 72000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
sbx keeps every template image (agent templates of about 1 GB each, every paddock/<project> image Paddock built), and the operator has no way to see them in Paddock or to clear the ones nothing needs. sbx does not report which image a sandbox runs (backlog doc Custom images, Drift), so what uses an image comes from what Paddock knows: the tag each project file records (`imageTag`), the image builder's template (shell-docker), and that docker/sandbox-templates images are sbx's agent templates. Removing goes through `sbx template rm --force` after Paddock's own confirmation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A System page "Templates" in the sidebar lists `sbx template ls --json`: name, kind (agent template, project image, other), agent flavor, size, created, and what uses it; with a total size
- [ ] #2 What uses it: the projects whose recorded image tag is this image (with or without a sandbox), "Paddock's image builder" for shell-docker, sbx's agent sandboxes for agent templates, and "not known" for other images; the page says sbx does not report a sandbox's image
- [ ] #3 One or several images can be removed after a confirmation that names them, their size, and what each removal means (an agent template is downloaded again for the next sandbox of that agent; a project image is built again on the next create)
- [x] #4 An image a project's existing sandbox was created from cannot be removed (remove the sandbox first), and neither can shell-docker while an image build runs; the check runs again against fresh sbx lists right before removing
- [ ] #5 Removals and failures go to the Log; a failure shows in the status button
- [x] #6 Core logic (rows, users, what may be removed, the sbx commands) is in PaddockCore with fixture-based tests; backlog doc UI describes the page
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Core: TemplateUsage.rows (kind, users from Project.imageTag, builder template, blocked reason, notes), ProjectRunner.templateRows/removeTemplates (fresh re-check, sbx template rm --force each).
2. App: AppModel.templates/readTemplates/removeTemplates; TemplatesView (table, Remove... button and context menu, confirmation); sidebar System > Templates.
3. Tests with the template-ls fixture; doc UI.
4. On the Mac: build, try the page, remove an unused image, check what sbx does when a removed agent template is needed again.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Core done and tested (6 TemplateUsage tests, suite 522 pass). App code (TemplatesView.swift, AppModel Templates section, ContentView sidebar case) written but not compiled: SwiftUI builds only on the Mac. Still to check there: the page builds and works (AC 1, 3, 5), that sbx re-downloads a removed agent template by itself (the confirmation says so), and what a stopped sandbox does when its image is gone. Log entries use category Paddock.
<!-- SECTION:NOTES:END -->
