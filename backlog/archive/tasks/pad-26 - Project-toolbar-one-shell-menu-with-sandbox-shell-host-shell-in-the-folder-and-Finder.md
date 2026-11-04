---
id: PAD-26
title: >-
  Project toolbar: one shell menu with sandbox shell, host shell in the folder,
  and Finder
status: Done
assignee:
  - '@claude'
created_date: '2026-10-27 13:44'
updated_date: '2026-10-31 17:39'
labels:
  - app
dependencies: []
priority: medium
type: feature
ordinal: 26000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The title bar's Open in Terminal button becomes a menu: Sandbox Shell in Terminal (sbx exec -it N bash, as before), New Shell Tab (in the app), Host Shell in the project folder (the operator's login shell on the Mac, cd'd to the folder, through a .command file like ExternalShell), and Show in Finder.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The toolbar shows one terminal icon whose menu has all four actions
- [x] #2 The host shell starts in the project folder, with the folder single-quoted in the script (test)
- [x] #3 Sandbox items are disabled without a sandbox or sbx; host shell and Finder always work
- [x] #4 doc UI describes the menu
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Host script test passes (quoting, cwd). Toolbar menu not built yet; needs a Mac build.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The title bar's terminal button is one menu with the sandbox shell, host shell in the project folder, and Finder; sandbox items are disabled without a sandbox or sbx. Host script quoting is tested; menu verified on the Mac 2026-10-31.
<!-- SECTION:FINAL_SUMMARY:END -->
