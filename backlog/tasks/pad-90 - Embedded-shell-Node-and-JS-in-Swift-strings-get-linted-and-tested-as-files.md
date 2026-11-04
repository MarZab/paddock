---
id: PAD-90
title: 'Embedded shell, Node and JS in Swift strings get linted and tested as files'
status: To Do
assignee: []
created_date: '2026-11-04 18:43'
updated_date: '2026-11-04 18:54'
labels:
  - architecture
  - tooling
  - kits
dependencies: []
priority: medium
type: task
ordinal: 95000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Review 2026-11-04. Paddock's kit scripts (AgentStatusKit, VoiceKit, BrowserKit, BrowserShow's Node script, SandboxWatchers, SandboxTop, SandboxFiles' run.sh) are long Swift raw strings. mise run lint runs shellcheck on scripts/*.sh only, so the code that runs inside every sandbox and parses untrusted data is unlinted, and tools/sandbox/run.sh is not covered either. BrowserShow.script alone is hundreds of lines of Node.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each embedded script lives in a resource file (Resources/kits/*.sh, *.js) loaded by Bundle.module and installed as before, with the kit recorded hash unchanged in meaning (Project.sandboxKits)
- [ ] #2 mise run lint runs shellcheck on those and on tools/sandbox/*.sh, and node --check on the .js files
- [ ] #3 Existing kit tests still pass; one test per script checks it is installed byte for byte
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Not started in the 2026-11-04 fix pass: no Swift toolchain in that sandbox, and this change is too large to make uncompiled.
<!-- SECTION:NOTES:END -->
