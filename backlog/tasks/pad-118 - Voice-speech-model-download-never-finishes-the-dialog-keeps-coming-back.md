---
id: PAD-118
title: 'Voice: speech model download never finishes, the dialog keeps coming back'
status: Done
assignee: []
created_date: '2026-11-07 07:56'
updated_date: '2026-11-07 14:21'
labels:
  - voice
dependencies: []
documentation:
  - doc-18
type: bug
ordinal: 122000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Operator report: clicking Listen shows 'Download the speech model?', Download does nothing visible, and the next Listen asks again. SpeechListener treated every AssetInventory status other than .installed as needs download (.unsupported and .downloading too); download() did nothing when assetInstallationRequest returned nil; the download showed no progress, logged nothing on success, and listening did not start afterwards, so a download still running looked like it never happened and Download started another one. (backlog doc Voice)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Each AssetInventory status is handled: .supported asks to download, .downloading says it is still downloading (no second dialog, no second download), .unsupported reports the language as unsupported with its locale
- [x] #2 Download shows its progress in the voice popup, logs start (with the locale) and finish, and starts listening into the same target when done
- [x] #3 A download that macOS has nothing to install for while the model is still not installed is logged as an error with the status, not dropped
- [x] #4 Voice doc and CHANGELOG updated
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. SpeechListener: handle each AssetInventory status; download reports progress and throws when the model is still not installed.
2. VoiceModel: one download at a time, progress in the popup, log start/end, listen into the asked target after.
3. Voice doc + CHANGELOG. Build and try on the Mac before Done.
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The speech model download handles each AssetInventory status on its own, shows its progress in the voice popup, logs start and end, and starts listening when done. Verified by the operator on the Mac on 2026-11-07 (build, tests, and the behavior by hand).
<!-- SECTION:FINAL_SUMMARY:END -->
