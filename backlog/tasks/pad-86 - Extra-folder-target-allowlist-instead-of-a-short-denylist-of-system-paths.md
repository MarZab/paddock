---
id: PAD-86
title: Extra-folder target allowlist instead of a short denylist of system paths
status: In Progress
assignee: []
created_date: '2026-11-04 18:43'
updated_date: '2026-11-04 18:54'
labels:
  - security
  - environment
dependencies: []
priority: medium
type: task
ordinal: 91000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Review 2026-11-04. checkExtraFolders refuses a target only when it equals one of 17 system paths (systemTargets) or sits under /proc or /sys. /home/agent/.claude, /usr/local/bin, /etc/profile.d, /home/agent/.ssh and so on pass, so an extra folder (operator-confirmed, but the agent writes the file proposing it) can shadow the status, voice and browser kit scripts or the agent's own settings inside the sandbox, which are what Paddock's tab marks, voice ask banner and show tabs trust. The mount is the operator's folder, but the surprise is the sandbox path.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A target must be under /workspace, /mnt or the project's own mount path; everything else is a problem shown in the confirmation sheet
- [ ] #2 Prefix and component-wise checks with .. and double slashes in tests (ProjectEnvironmentTests)
- [ ] #3 Project config file doc states the rule
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Allowlist in ProjectEnvironment.isAllowedTarget (/workspace /mnt /srv /data and the Mac home), test extraFolderTargetsAreAnAllowlist, doc updated. NOT compiled. Check that sbx's default mount path (host path) still works for targets under home.
<!-- SECTION:NOTES:END -->
