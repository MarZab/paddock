---
id: PAD-49
title: 'Setup kit: teach agents .paddock.toml and project Dockerfiles'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-29 17:11'
updated_date: '2026-11-04 15:07'
labels:
  - agents
  - kits
  - images
dependencies: []
priority: medium
ordinal: 49000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Agents in a Paddock sandbox install tools by hand, which a recreate wipes, and do not know they can ask for an image, hosts, and ports through .paddock.toml. They should know how to write .paddock.toml and a Dockerfile with the project's dependencies, what Paddock checks and refuses, and that every change waits for the operator's confirmation. Agents learn about Paddock through kits' agentInstructions (backlog doc Kits, backlog doc Browser), so this is a builtin kit. Background: backlog doc Project config file, backlog doc Custom images; lessons from PAD-22 (small builder disk, small build context, BASH_ENV).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A builtin kit 'setup' (recommended for every agent) whose agentInstructions explain .paddock.toml (every key, what Paddock refuses, that changes wait for the operator) and how to write a project Dockerfile (base template, users, environment, network for the build, rebuild rules, size)
- [x] #2 The kit installs an example .paddock.toml and Dockerfile under /usr/local/share/paddock/examples for the agent to copy
- [x] #3 The example .paddock.toml decodes with ProjectConfig and its Dockerfile starts FROM a docker/sandbox-templates image (test)
- [x] #4 Kits and Project config file docs updated
- [ ] #5 Checked on the Mac: a new sandbox with the kit has the examples, and Claude Code and OpenCode see the instructions
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ProjectSetupKit (builtin 'setup', recommended, every agent): agentInstructions only, plus an install step writing example .paddock.toml and Dockerfile to /usr/local/share/paddock/examples.
2. Wire into BuiltinKit, defaultKits, BuiltinKits, the paddock.toml template comments.
3. Tests: example decodes with ProjectConfig and passes checkRequests, Dockerfile FROM a sandbox template, spec holds every piece; update KitsTests preselection.
4. Docs: Kits (Project setup section), Project config file.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Recommended for every agent, so new projects get it preselected; existing projects keep their kits (no recreate is pushed) and can add it on the Info tab's Kits row.
Tested on Linux: mise run test passes (466 + 29). Running swift and swiftlint in this sandbox needed libxml2.so.2, which Ubuntu 26.04 lacks (it has .so.16); a symlink in a temp folder on LD_LIBRARY_PATH worked. swiftlint here runs without the repo's config, so only the new files were checked; the YAML description line is long like VoiceKit's.

Amended after writing this repo's Dockerfile with them (PAD-22): pin what you add but keep the template's tag; a library a prebuilt tool needs from another Ubuntu release comes from that release's package, not a symlink; without Docker, check by running the RUN steps in the sandbox.

Operator feedback: the instructions should not say what a Dockerfile needs (packages, pinning, libraries); the agent works out its own setup. They now say only what Paddock and sbx need from it, and the example Dockerfile is a skeleton.

PAD-73.3 (2026-11-04) replaces this: Paddock will generate sbxenv.yaml and the project kit, and the setup kit is removed. Leave this open until that lands, then archive it as superseded.

Obsolete (PAD-73.3, 2026-11-04): the setup kit is removed. Paddock writes a project's sbxenv.yaml and kit itself (SandboxFiles), with its rules as comments and the build-output guidance as the kit's agent context.
<!-- SECTION:NOTES:END -->
