---
id: PAD-144
title: 'One Paddock window: no New Window that duplicates the main window'
status: In Progress
assignee: []
created_date: '2026-11-21 19:06'
updated_date: '2026-11-21 19:08'
labels: []
dependencies: []
type: bug
ordinal: 146000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Paddock's main scene is a WindowGroup, so File > New Window (Cmd-N) opened a second window over the same AppModel: every project, tab, and terminal shown twice, terminal views moving between windows. Paddock is one window: remove the New Window command (CommandGroup(replacing: .newItem)). Not a Window scene: that quits the app, and every session, when its window closes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 There is no New Window item and Cmd-N opens no second main window
- [ ] #2 Closing the window and clicking the Dock icon opens it again
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Removed File > New Window with CommandGroup(replacing: .newItem); kept the WindowGroup. Lint clean; not built or run on the Mac yet (the sandbox is Linux).
<!-- SECTION:NOTES:END -->
