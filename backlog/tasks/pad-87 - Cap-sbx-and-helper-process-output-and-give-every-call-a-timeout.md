---
id: PAD-87
title: Cap sbx and helper process output and give every call a timeout
status: In Progress
assignee: []
created_date: '2026-11-04 18:43'
updated_date: '2026-11-04 18:54'
labels:
  - security
  - reliability
  - process
dependencies: []
priority: medium
type: task
ordinal: 92000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Review 2026-11-04. FoundationProcessRunner reads stdout and stderr with readToEnd with no size cap and no deadline (cancellation is the only way out); Foundation's Process also inherits Paddock's whole environment when environment is nil. 'sbx exec' output comes from the sandbox (watchers, show tab reads, Top), so a sandbox can make the Mac process buffer arbitrary amounts of data (BrowserShow reads cap at 20 MB in the sandbox script, which Paddock does not enforce on the Mac side). PAD-28 fixed thread starvation, not unbounded buffers.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ProcessRunner.run takes a max output size (default a few MB) and a timeout, with typed errors; callers that need big output (show tab reads) pass their own limit
- [ ] #2 Mac-side checks of NativeShowPolicy.maxFileBytes and OpenUIPolicy.maxDocumentBytes on the data received, not only in the sandbox script
- [ ] #3 Default environment for sbx calls is an allowlist (PATH, HOME, DOCKER_*, SBX_*, proxy variables); document which
- [ ] #4 Tests with a fake runner and a real process that prints past the cap and one that hangs
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
FoundationProcessRunner(maxOutputBytes: 64 MB, timeout: 15 min) with ProcessLimitError; tests in ProcessRunnerTests. NOT compiled. Open: AC3 (environment allowlist) and AC2 (Mac-side size checks on show/OpenUI data: ProjectRunner already checks show reads) not done; the allowlist risks breaking DOCKER_HOST/proxy variables and needs the Mac.
<!-- SECTION:NOTES:END -->
