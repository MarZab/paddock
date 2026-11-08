---
id: PAD-136
title: >-
  Extra folders: unticking Read-only is refused with a false ~/Library/Logs
  error
status: Done
assignee:
  - '@claude'
created_date: '2026-11-08 16:14'
updated_date: '2026-11-08 16:16'
labels:
  - bug
  - security
dependencies: []
ordinal: 138000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Unticking Read-only on an ordinary extra folder (seen with ~/Projects/2026/cloudflare-template) fails with "<folder> stays read-only: it is inside ~/Library/Logs", although the folder is nowhere near Logs, so no extra folder can be made writable from Info. The guard in AppModel.setExtraFolder used ExtraFolders.readOnly, which says how a folder will be mounted, as if it said whether the change is allowed. It also let a writable request through for a folder inside Logs. The decision lived in App/, which has no tests.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An extra folder outside ~/Library/Logs can be switched to writable and back to read-only
- [x] #2 A folder inside ~/Library/Logs, also through a link, cannot be switched to writable; asking for read-only is allowed
- [x] #3 The decision lives in PaddockCore, is what AppModel.setExtraFolder uses, and has tests
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Add ExtraFolders.allows(readOnly:path:policy:), built on ExtraFolders.readOnly so there is one rule. 2. Use it in AppModel.setExtraFolder. 3. Test ordinary, Logs and linked-into-Logs folders. 4. Confirm the tests fail against the old logic.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
New tests failed against the old logic (3 issues) and pass with the fix. Full suite: 591 + 36 passed on two consecutive runs; lint 0 violations. One earlier full run failed in ExternalShell theHostScriptStartsTheShellInTheProjectFolder (exec exit 126), unrelated to this change; passed 5/5 alone and in both later full runs. App/ was not built here (Linux); the checkbox was not exercised on the Mac.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
AppModel.setExtraFolder used ExtraFolders.readOnly (how a folder is mounted) as if it said whether a change is allowed, so every ordinary extra folder was refused with a false ~/Library/Logs error. Added ExtraFolders.allows(readOnly:path:policy:) in PaddockCore, used it in AppModel, and tested ordinary, Logs and linked-into-Logs folders. Risk: the one-line App/ change still needs a Mac build and a click on the checkbox.
<!-- SECTION:FINAL_SUMMARY:END -->
