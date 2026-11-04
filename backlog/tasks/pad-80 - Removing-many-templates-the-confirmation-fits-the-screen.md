---
id: PAD-80
title: 'Removing many templates: the confirmation fits the screen'
status: In Progress
assignee: []
created_date: '2026-11-04 14:24'
updated_date: '2026-11-04 14:24'
labels: []
dependencies: []
priority: low
type: bug
ordinal: 85000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Choosing many images on the Templates page (PAD-72) and pressing Remove showed a confirmation that listed every image, one line each, taller than the screen (operator, 2026-11-04).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The confirmation lists at most 8 images by name, size, and note; more are summed up as "and N more (size)"; the title keeps the count and total size
- [x] #2 The cut is in PaddockCore with a test
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TemplateUsage.confirmationList names at most 8, or all of 9, and returns the rest. TemplatesText.message adds "And N more (size)." Tested in TemplateUsageTests. The App part is not compiled here; check the dialog on the Mac to close AC1.
<!-- SECTION:NOTES:END -->
