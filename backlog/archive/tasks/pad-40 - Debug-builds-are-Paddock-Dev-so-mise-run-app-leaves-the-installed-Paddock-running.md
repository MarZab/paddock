---
id: PAD-40
title: >-
  Debug builds are Paddock Dev, so mise run app leaves the installed Paddock
  running
status: Done
assignee: []
created_date: '2026-10-29 09:44'
updated_date: '2026-10-31 17:50'
labels: []
dependencies: []
priority: medium
type: chore
ordinal: 40000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
mise run app and mise run install both quit any app with bundle ID net.zabreznik.paddock and wait for every process named Paddock, because Debug and Release share the bundle ID. Running a dev build kills the installed one. Give Debug builds their own bundle ID (net.zabreznik.paddock.dev) and name (Paddock Dev), and make each task quit and wait for only its own bundle ID. Both apps still share ~/.config/paddock and the same sandboxes, so running both at once on the same project can clash (gateway ports, watchers).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Debug builds have bundle ID net.zabreznik.paddock.dev and show as Paddock Dev in the Dock and menu bar
- [x] #2 mise run app quits and waits only for Paddock Dev; mise run install only for the installed Paddock
- [x] #3 README says the two can run side by side and what they share
- [x] #4 Paddock Dev has its own icon (purple sky, AppIconDev) so it is told apart from the installed Paddock in the Dock
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Debug config overrides PRODUCT_BUNDLE_IDENTIFIER and APP_DISPLAY_NAME in project.yml; CFBundleName and CFBundleDisplayName come from APP_DISPLAY_NAME. PRODUCT_NAME stays Paddock (module name, .app name). mise tasks wait with 'application id ... is running' instead of pgrep -x Paddock, which matches both apps. Not yet built on the Mac.

2026-10-31 Mac check: Paddock Dev and the installed Paddock are separate apps and the installed one keeps running (AC 2). AC 1 fails: the Dock does not say Paddock Dev. Both bundles are named Paddock.app (PRODUCT_NAME stays Paddock), so the Dock likely uses the file name; menu bar name not yet checked.

2026-10-31 Menu bar already said Paddock Dev, the Dock did not: the Dock uses the file name. Debug now has PRODUCT_NAME 'Paddock Dev' (Paddock Dev.app, process 'Paddock Dev') with PRODUCT_MODULE_NAME Paddock; mise run app opens the new path; scripts/capture-hang.sh finds each app by its process name. Not built yet. Old Debug/Paddock.app in build/DerivedData is stale and can be deleted.

2026-10-31 Icon: scripts/render-icon.js also renders AppIconDev (purple sky) from design/app-icon.svg; Debug uses it through ASSETCATALOG_COMPILER_APPICON_NAME. Rendered here, not seen in the Dock yet.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Debug builds are Paddock Dev: bundle ID net.zabreznik.paddock.dev, Paddock Dev.app (process 'Paddock Dev'), a purple icon, so mise run app leaves the installed Paddock running and the Dock tells them apart. mise tasks wait on the bundle ID, capture-hang.sh finds each app by process name. Verified on the Mac 2026-10-31 (the Dock icon needed an lsregister refresh once because of macOS's icon cache).
<!-- SECTION:FINAL_SUMMARY:END -->
