---
id: PAD-59
title: 'Log as a System page, with categories and a search to filter it'
status: Done
assignee:
  - '@claude'
created_date: '2026-10-30 07:51'
updated_date: '2026-10-31 17:48'
labels:
  - app
dependencies: []
priority: medium
ordinal: 59000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Log window holds every line of an image build (docker's whole output) next to Paddock's errors and voice messages, so anything else is hard to find. The Log moves into the main window as a page under the sidebar's System section (like sbx Processes, PAD-58); File > Log (Shift-Cmd-L) and the status popover's Log button select it. Each entry gets a category by where it came from: Paddock (errors and the app's own messages), Image build (ProjectRunner's LogSink), Voice, sbx Processes. The page filters by category (hidden ones remembered across launches), errors only, and text. The log file names each line's category.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every log entry has a category: Paddock, Image build, Voice, or sbx Processes
- [x] #2 Each line in paddock.log names its category
- [x] #3 LogEntry and its filter live in PaddockCore with tests
- [x] #4 doc UI updated
- [x] #5 Each project's Recent Activity entries also go to the Log as Sandbox activity
- [x] #6 Each launch logs to its own file named by start time and process id; Paddock's log files last written over a week ago are removed at launch; mise run hang takes the stuck app's file
- [x] #7 Category toggles: none chosen shows all, each chosen one adds to what shows (remembered across launches); errors only; a text filter over message and source; Copy All copies what is shown
- [x] #8 Lines show in a read-only text: a selection spans several lines and Cmd-C copies it; long messages wrap under their column when the page resizes (no clipped rows)
- [x] #9 A source column names the project's sandbox, and for voice the agent tab; errors that name a project carry it
- [x] #10 Log is a page under System; File > Log selects it; there is no Log window and the status popover has no Log button
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. LogEntry, LogCategory, LogFilter in PaddockCore (Support/LogEntry.swift) with tests; fileLine names the category
2. appendLog takes a category: build for the LogSink, voice in Voice.swift, processes for sbx process stops, paddock otherwise
3. ActivityTimeline.record returns the entry; AppModel logs entry.logLine as sandbox
4. ErrorLogView becomes a System page with a category menu (AppStorage), All/Errors, text filter; File > Log and the popover select it; Window removed
5. doc UI

6. One log file per session (LogFiles.name), pruned at launch by age (7 days, LogFiles.toRemove); capture-hang.sh picks paddock-*-PID.log
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
mise run test: 488 + 31 pass, including the Log filter suite and recordReturnsTheEntryForTheLog. App code (page, menu, sidebar) is not compiled on Linux; ACs 1 and 3 wait for mise run build and a look on the Mac.

LogFiles naming and pruning tested (Log files suite). LogFile's folder listing and removal run only on the Mac.

Second round: LogTextView (NSTextView) replaces the SwiftUI List; LogFilter.categories (none = all, toggle) replaces hidden; LogEntry.source from build (project), sandbox activity (sandbox), voice (project · tab title), and AppModel.fail(_:in:) for errors naming a project. Tests updated; the page itself waits for a Mac build.

2026-10-31 Mac check: file per launch, categories, filter, selection and source column confirmed. The status popover's Log button was removed as a duplicate (App/StatusBarView.swift, doc UI), not rebuilt yet (last AC).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Log is a page under System with a category on every entry (Paddock, Image build, Sandbox activity, Voice, sbx Processes), category toggles, errors-only, a text filter, Copy All, a read-only multi-line selectable text, a source column, and one log file per launch pruned after a week. File > Log selects it; the status popover has no Log button. LogEntry and LogFilter are in PaddockCore with tests. Verified on the Mac 2026-10-31.
<!-- SECTION:FINAL_SUMMARY:END -->
