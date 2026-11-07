---
id: PAD-130
title: >-
  Claude sessions on this Mac for projects with an sbxenv.yaml, and on project
  removal
status: In Progress
assignee: []
created_date: '2026-11-07 11:18'
updated_date: '2026-11-07 14:21'
labels:
  - agents
dependencies: []
type: feature
ordinal: 132000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PAD-127 keeps Claude's sessions in Paddock's data folder through a kit host-mount@1 and sbx create --mount, but only for projects without an sbxenv.yaml: sbx env create takes no --mount. An sbxenv.yaml likely names host mounts under a key of its own (Paddock refuses 'mounts' in a project's file); Paddock's overlay could carry it. Capture first (mise run capture:cli, a phase like sessions-hostmount with sbx env create and an overlay). Also: removing a project should offer to delete its sessions folder (ClaudeSessions.folder), without following links. (backlog doc Security rules, Claude sessions folder)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A capture shows how an sbxenv.yaml or Paddock's overlay mounts a kit's host-mount@1 folder, and that it survives a recreate through sbx env
- [x] #2 Projects with an sbxenv.yaml can keep Claude's sessions the same way, with the same checks and read-back
- [ ] #3 Removing a project offers to delete its sessions folder; links are removed as links
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-07 research (docs.docker.com/ai/sandboxes/configuration/environment-files, mounts; customize/use-kits): an environment file has a top-level mounts: map, kit-declared sandbox path -> existing host directory (relative to the declaring file); the target must match a host-mount@1 path of a selected kit; takes effect at create; overlays merge maps by key, later files win. So Paddock's overlay can carry the sessions kit and mounts: { /home/agent/.claude/projects: <folder> }; the project's own file keeps being refused for mounts (ProjectEnvironment.refusedKeys). The docs may be ahead of sbx 0.51.0: probe mise run capture:cli sessions-env.

2026-11-07 mise run capture:cli sessions-env (sbx 0.51.0): an overlay's kits plus top-level mounts: { /home/agent/.claude/projects: <folder> } is taken by sbx env plan and create; the folder is mounted rw, owned by agent, listed in sbx ls mounts, and a session survives rm --force plus env create. sbx also takes mounts: from a project's own file (Paddock refuses the key). Implemented: PaddockOverlay.mounts, ProjectRunner env path with the same prepare, kit, and read-back. Left: offering to delete the folder when a project is removed (AC 3).

2026-11-07: sessions on the Mac for projects with an sbxenv.yaml verified by the operator on the Mac (AC 1, 2). Left: AC 3, offering to delete the sessions folder when a project is removed.
<!-- SECTION:NOTES:END -->
