---
id: PAD-92
title: Split AppModel (1900 lines) and move Voice logic out of App/ into PaddockCore
status: To Do
assignee: []
created_date: '2026-11-04 18:43'
updated_date: '2026-11-04 18:54'
labels:
  - architecture
  - refactor
dependencies: []
priority: medium
type: chore
ordinal: 97000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Review 2026-11-04. CLAUDE.md says all logic lives in PaddockCore and App/ holds only views and view models. AppModel.swift (1910 lines) is one @Observable class with 147 members across sandboxes, ports, sync, terminals, resources, templates, watchers, voice, agent status, browser tabs, sbxenv confirmation, extra folders, and the gateway. App/Voice.swift (1835 lines) holds VoiceModel with watcher handling, answer routing and dictation logic (lines 556-1460) next to SwiftUI views, and audio/speech classes. Logic in App cannot be unit-tested without Xcode and cannot run in the Linux sandbox.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 AppModel keeps shared state and delegates each MARK area to a feature model in its own file (SandboxesModel, TemplatesModel, BrowserTabsModel, EnvironmentConfirmationModel, ExtraFoldersModel, GatewayModel) with the decisions inside PaddockCore services
- [ ] #2 VoiceModel's non-UI decisions (watcher line handling, answer routing, dictation state machine) move to PaddockCore/Voice with tests; App/Voice.swift keeps AVFoundation and Speech adapters and views, split into at least three files
- [ ] #3 No file in App/ over 800 lines; SwiftLint file_length and type_body_length enforce it
- [ ] #4 Behavior unchanged: the app builds and the existing tests pass
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Not started in the 2026-11-04 fix pass: no Swift toolchain in that sandbox, and this change is too large to make uncompiled.
<!-- SECTION:NOTES:END -->
