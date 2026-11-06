---
id: PAD-104
title: 'Calendar version from git, shown next to the status button'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-06 08:06'
updated_date: '2026-11-06 10:40'
labels:
  - app
dependencies: []
priority: low
ordinal: 109000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every build said 1.0 (build 1, or the commit count for mise run install), so the operator could not tell which build is running, or quote it in a ticket. A version of the form yymmdd.N, computed from git at build time, needs no manual bump: the day of the commit the build is from, and how many commits that day came before it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 mise run build and mise run install set the app's CFBundleShortVersionString to that version, CFBundleVersion to the commit count, and record the short commit hash (with -dirty for uncommitted changes)
- [x] #2 The sidebar shows the version next to the status button; its tooltip names the commit and says when the build had uncommitted changes
- [ ] #3 A build from Xcode without mise shows no number but says it is unversioned
- [x] #4 PaddockCore tests cover reading the version from the bundle info, and the UI doc describes it
- [x] #5 tools/tasks/version.sh (mise run version) prints yymmdd.N for HEAD: the commit day (this Mac's time zone) and N, the number of earlier first-parent commits that day (0 for the first); without git it prints 0.0
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. tools/tasks/version.sh (mise run version): version (yymmdd.N), build (commit count), commit (short hash, -dirty)
2. project.yml: Info.plist keys from MARKETING_VERSION, CURRENT_PROJECT_VERSION, PADDOCK_COMMIT; placeholders 0.0/0/empty
3. build and install tasks pass the three from the script
4. PaddockCore AppVersion reads the info dictionary (label, tooltip), with tests
5. VersionLabel next to StatusButton; doc-15 UI and CHANGELOG
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Script verified in the sandbox: 261106.4 for HEAD 81f2c45 (5th commit of the day), build 6, 0.0 and empty commit outside git; shellcheck clean. Not verified here: swift test and swiftlint (no Swift for linux/arm64 6.3.3 in this sandbox: mise 404s, and xcbeautify has no arm64 Linux build so mise run swift-linux fails), and the Mac build (xcodegen Info.plist keys, the label in the sidebar).

AppVersionTests pass on the Mac (09:43 run) and in Linux. Left: the Info.plist values from mise run build/install, and the label and tooltip in the app (AC 1-3).

Operator checked on the Mac 2026-11-06: the version shows next to the status button. Tooltip wording and the unversioned Xcode build (AC3) not checked.
<!-- SECTION:NOTES:END -->
