---
id: PAD-73
title: Move Paddock to sbx v3 kits and sbxenv.yaml
status: In Progress
assignee: []
created_date: '2026-11-04 09:31'
updated_date: '2026-11-04 10:15'
labels: []
dependencies: []
references:
  - 'https://docs.docker.com/ai/sandboxes/customize/'
  - 'https://docs.docker.com/ai/sandboxes/configuration/environment-files/'
  - 'https://github.com/docker/sandbox-kit-spec'
  - scratch/sandbox/v3/README.md
priority: high
type: feature
ordinal: 73000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
sbx 0.51 (2026-11-03) brings kit spec v3 and `sbxenv.yaml`, an environment file at a project root that `sbx env plan|run|create|rm` read on their own. A project set up that way runs without Paddock. Paddock should read the same file and overlay its own settings, instead of keeping its own `.paddock.toml` format and image builds.

Research (2026-11-04, docs only, nothing run on a Mac yet):
- v3 kits are `kind: workload` or `kind: mixin`. Each is a `<name>.yaml` with capabilities (`network-policy@2`, `lifecycle@1`, `agent-context@2`, `host-port@1`, `credential@1`, ...) and an optional `<name>.dockerfile`, which sbx builds at create.
- v1/v2 kits do not combine with v3, and the built-in agent names (`claude`, `opencode`) are still v2. Claude Code v3 is the workload `docker.io/docker/sbx-kit-claude`, agent name `sbx-kit-claude`.
- `sbx env` is experimental. Passing several files merges them: maps merge, lists concatenate, later scalars win.
- A worked example (an example sandbox ported from a v1 spec) is in `scratch/sandbox/v3/` on the operator's Mac. It is gitignored, so it may be missing in other checkouts; its README lists what is unverified.

The subtasks carry the work, in order.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every subtask is Done
- [ ] #2 A project with only an `sbxenv.yaml` (no `.paddock.toml`) opens, is confirmed, and runs in Paddock with its agent, kits, and gateway
<!-- AC:END -->
