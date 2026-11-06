---
id: PAD-105
title: 'mise tasks as files in tools/tasks, and mr for mise run'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-06 08:10'
updated_date: '2026-11-06 08:49'
labels:
  - tooling
dependencies: []
priority: low
ordinal: 110000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The mise tasks were inline strings in mise.toml (multi-line shell in TOML, outside shellcheck), and most only called a script in scripts/. As mise file tasks in tools/tasks, each task is one linted script with its description, dependencies and arguments in its own header, and mise.toml keeps only tools and settings. mr saves typing mise run in the dev sandbox.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every task that was in mise.toml is an executable file in tools/tasks with its description, dependencies and arguments in #MISE and #USAGE lines; mise.toml has no [tasks.*] sections and includes tools/tasks
- [x] #2 Names say what a task does, grouped by folder: capture:cli (was m0), capture:socket (was socket), capture:fixtures (sanitize-fixtures.py, now a task), vendor:openui (was openui-vendor); app, build, fmt, generate, hang, icon, install, lint, swift-linux, test keep theirs
- [x] #3 mise run lint shellchecks tools/tasks and its folders
- [x] #4 References to the moved or renamed scripts and tasks (code comments, the status checks hint, CLAUDE.md, tools/tasks/README.md replacing scripts/README.md, docs) use the new names
- [x] #5 mise.toml defines the shell alias mr for mise run ([shell_alias]), so any shell where mise is activated has it
- [x] #6 Moved scripts keep their history (git mv) and still find the repo root; scripts/ is gone: version.sh is the version task, and helpers that are no task (render-icon.js, fake-anthropic.py) are in tools/tasks/lib, not executable, so mise does not list them
- [x] #7 mise run sandbox:plan, sandbox:create, sandbox:run and sandbox:rm run tools/sandbox/run.sh (unchanged, as Paddock writes it); sandbox:create still needs --replace
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. tools/tasks with [task_config] includes; inline tasks become .sh files; task scripts git mv from scripts/ (extensions kept, mise drops them from names)
2. Namespaces by folder: capture/{cli.sh,socket.py,fixtures.py}, vendor/openui.sh
3. ROOT paths one or two levels deeper; python tasks run with python3 -I via env -S
4. [shell_alias] mr = "mise run"
5. Update references in code, CLAUDE.md, docs (doc-4, 5, 8, 9, 17), README in tools/tasks
6. The gateway trial is removed separately (operator asked to remove task and product)
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Verified in the sandbox (mise 2026.5.2): mise tasks lists all 14 under their new names, capture:cli shows its #USAGE arguments, capture:fixtures runs; each moved script resolves the repo root; shellcheck over scripts, tools/tasks and its folders, tools/sandbox is clean; bash -ic alias mr prints mise run. Any mise run in this arm64 sandbox first tries to install xcbeautify, which has no linux/arm64 build (MISE_DISABLE_TOOLS=xcbeautify gets past it); that was so before this change.

sandbox:* tasks: mise tasks lists them; sandbox:create without --replace stops with run.sh's message; sandbox:plan reaches sbx (not installed in the sandbox, so checked only that far).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
mise tasks are files in tools/tasks (mise.toml includes the folder and has only tools, settings, and [shell_alias] mr = "mise run"). Names say what a task does: capture:cli (was m0), capture:socket, capture:fixtures (sanitize-fixtures.py, now a task), vendor:openui, version, sandbox:plan/create/run/rm over tools/sandbox/run.sh; helpers that are no task are in tools/tasks/lib, not executable. scripts/ is gone. References in code, CLAUDE.md, docs, and the status checks hint use the new names. Checked in a sandbox: mise tasks lists them all, arguments and --help work, each moved script finds the repo root, shellcheck is clean, mr is an alias in interactive bash.
<!-- SECTION:FINAL_SUMMARY:END -->
