---
id: PAD-41
title: Shell on this Mac as a terminal tab; new tabs open only from the tab bar's +
status: Done
assignee: []
created_date: '2026-10-29 09:48'
updated_date: '2026-10-31 17:39'
labels: []
dependencies: []
priority: medium
type: feature
ordinal: 41000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The tab bar's + menu offers New Agent Session and New Shell (in the sandbox) and New Shell on This Mac: the operator's login shell in the project folder, in a Paddock tab marked with a laptop icon and titled mac, mac 2. It needs no sandbox. The toolbar's Shells menu no longer opens tabs; it keeps Sandbox Shell in Terminal, Shell on This Mac in Terminal (renamed from Shell in the Project Folder), and Show in Finder. backlog doc UI, Project view.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 + menu has Sandbox and This Mac sections; New Shell on This Mac opens a login shell in the project folder
- [x] #2 A Mac shell tab opens for a project without a sandbox
- [x] #3 The Shells toolbar menu has no New Shell Tab and offers Shell on This Mac in Terminal
- [x] #4 SandboxShellSession runs a Mac shell as /bin/sh with the folder and shell as arguments (test)
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The tab bar's + menu has Sandbox and This Mac sections; New Shell on This Mac opens a login shell in the project folder, with or without a sandbox, and the Shells toolbar menu no longer has New Shell Tab. Verified on the Mac 2026-10-31.
<!-- SECTION:FINAL_SUMMARY:END -->
