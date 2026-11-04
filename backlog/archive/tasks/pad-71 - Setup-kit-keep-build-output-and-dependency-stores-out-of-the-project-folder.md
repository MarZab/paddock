---
id: PAD-71
title: 'Setup kit: keep build output and dependency stores out of the project folder'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-03 16:50'
updated_date: '2026-11-03 16:50'
labels:
  - kits
dependencies: []
ordinal: 71000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The project folder is shared with the Mac (virtiofs), so node_modules, pnpm stores, and .NET bin/obj written there cost Mac disk writes through the file-sharing layer, and a Linux sandbox and the Mac then share platform-specific output (native Node modules, build output) that breaks on the other side. sbx sandboxes cannot mount a tmpfs (no CAP_SYS_ADMIN, checked in a sandbox 2026-11-03), but the sandbox's own disk is local to the VM. Tools can point their output there through environment variables set only in the sandbox (/etc/sandbox-persistent.sh from the Dockerfile), leaving the Mac's builds unchanged. Agents should know this pattern when they set up a project.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The setup kit's agent instructions have a section on keeping build output and dependency stores out of the project folder: why (Mac disk writes, platform clashes), how (sandbox-only environment in /etc/sandbox-persistent.sh from the Dockerfile, a path under the agent's home), and the trade-offs (lost on recreate, the sandbox disk's size)
- [x] #2 It gives the .NET (UseArtifactsOutput, ArtifactsPath) and pnpm (store and virtual store dirs) patterns, tells the agent to verify each setting took effect, and says that node_modules itself stays in the project
- [x] #3 ProjectSetupKitTests check the section is in the kit
- [x] #4 backlog doc Kits, Project setup, mentions it
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The setup kit's agent instructions gain "Keep build output out of the project folder": why (writes go through to the Mac's disk; Linux and Mac output clash in a shared folder), how (sandbox-only environment in /etc/sandbox-persistent.sh from the Dockerfile, paths under the agent's home), .NET (UseArtifactsOutput, ArtifactsPath) and pnpm (store and virtual store dirs, node_modules stays as links) examples, a check that each setting took effect, and the trade-offs (lost on recreate, small disk, no tmpfs). ProjectSetupKitTests check it; backlog doc Kits mentions it, and now also the ignore file (PAD-69). The kit spec was dumped and its YAML block checked by indentation (no YAML parser here). Not verified on the Mac: that an agent sees the new section (PAD-49).
<!-- SECTION:FINAL_SUMMARY:END -->
