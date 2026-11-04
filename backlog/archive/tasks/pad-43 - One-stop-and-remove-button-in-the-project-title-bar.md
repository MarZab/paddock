---
id: PAD-43
title: One stop and remove button in the project title bar
status: Done
assignee: []
created_date: '2026-10-29 10:26'
updated_date: '2026-10-31 17:39'
labels:
  - app
dependencies: []
priority: medium
type: feature
ordinal: 43000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The title bar had separate Stop, Remove (sandbox), and Remove Project buttons depending on state. Merge them into one split button: a click takes the mildest step possible now (Stop when running, else Remove Sandbox, else Remove Project); the arrow and a right click list every step the project can take, and each step does the earlier ones first (AppModel.tearDown chains stop, remove, forget, each after the previous succeeded). Remove steps confirm with a message that says what happens. Create and Start stay separate. backlog doc UI, Project view.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 One button replaces Stop, Remove, and Remove Project; its click is the mildest possible step
- [x] #2 Its menu and right click list Stop, Remove Sandbox, Remove Project as far as the state allows
- [x] #3 Remove Project on a running project stops it, removes the sandbox, and deletes the project file in one action, each step after the previous succeeded
- [x] #4 Remove steps ask for confirmation with what they will do; Stop does not
- [x] #5 UI doc updated
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Written, not built yet (no Xcode here). Menu with primaryAction plus contextMenu in the toolbar; whether right click on a toolbar item reaches the contextMenu on macOS 26 needs checking on the Mac.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
One split button replaces Stop, Remove, and Remove Project: the click is the mildest step, the menu and right click list the steps the state allows, Remove steps confirm and Stop does not. Verified on the Mac 2026-10-31, including right click on the toolbar item.
<!-- SECTION:FINAL_SUMMARY:END -->
