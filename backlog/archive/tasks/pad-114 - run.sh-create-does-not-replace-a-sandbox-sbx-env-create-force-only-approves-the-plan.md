---
id: PAD-114
title: >-
  run.sh create does not replace a sandbox: sbx env create --force only approves
  the plan
status: Done
assignee:
  - '@claude'
created_date: '2026-11-06 08:54'
updated_date: '2026-11-06 08:59'
labels:
  - tooling
  - sandbox
dependencies: []
priority: medium
ordinal: 119000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
tools/sandbox/run.sh, and the template Paddock writes into every project (SandboxFiles.runScript), said create passes --force and so REPLACES a sandbox of that name, and the repo copy required --replace for it (PAD-95). sbx's --force only applies the plan without asking: mise run sandbox:create --replace on the Mac failed with "sandbox paddock already exists" (2026-11-06), so a kit change could not be applied that way.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The template and this repo's run.sh say what --force does and that create fails when the sandbox exists; the repo copy no longer asks for a --replace that guards nothing
- [x] #2 mise run sandbox:create --replace removes the sandbox (sbx env rm) and then creates it; without the flag it only creates
- [x] #3 ProjectEnvironment and SandboxFiles tests pass
- [x] #4 mise run sandbox:create --replace --force and sandbox:rm --force remove a sandbox that is in use; run.sh passes what follows its command to sbx
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
On the Mac, --replace stopped at sbx env rm: the sandbox was in use (this session). run.sh now passes the arguments after its command to sbx (template too); sandbox:create takes --force with --replace, sandbox:rm takes --force. Checked with a stand-in sbx, with and without an overlay; 37 ProjectEnvironment and SandboxFiles tests pass.

SandboxGuide (the notes every sandbox gets through the status kit) said create and run replace the sandbox; it now says run attaches, create fails while it exists, and rm (--force while in use) comes first and ends the agent's sandbox. Paddock rewrites its own kits at each create, so new sandboxes get it; projects keep the run.sh they have (Paddock never overwrites a project's files).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
sbx env create --force approves the plan; it never replaced a sandbox. The template and the repo's run.sh say so, the repo copy drops its --replace check, and mise run sandbox:create --replace runs sandbox rm and then create. Checked with a stand-in sbx (rm, then create; no flag: create only; unknown argument: exit 2) and the ProjectEnvironment and SandboxFiles tests (37 pass). Projects keep their old run.sh until Paddock writes it again (it never replaces an existing file).
<!-- SECTION:FINAL_SUMMARY:END -->
