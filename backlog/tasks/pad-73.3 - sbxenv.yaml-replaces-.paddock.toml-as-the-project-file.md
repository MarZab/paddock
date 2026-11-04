---
id: PAD-73.3
title: sbxenv.yaml replaces .paddock.toml as the project file
status: In Progress
assignee: []
created_date: '2026-11-04 09:32'
updated_date: '2026-11-04 15:07'
labels: []
dependencies:
  - PAD-73.1
  - PAD-73.2
documentation:
  - doc-11
  - doc-14
  - doc-6
parent_task_id: PAD-73
priority: high
type: feature
ordinal: 76000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A project's sandbox setup should be `sbxenv.yaml` at the project root, plus its own v3 kit for anything `.paddock.toml` and the project Dockerfile do today. The operator can then run it with plain `sbx env run`, and Paddock reads the same file. Paddock adds its own part as an overlay file in its config dir (its kits, env, the sandbox name) and creates with `sbx env create <project>/sbxenv.yaml <overlay>`.

Field mapping:
- `agent` → `agent`
- `[image]` → the project's mixin kit
- `[network]` → the kit's `network-policy@2`
- `ports.publish` → `ports`
- `ports.hostServices` → `host-port@1`
- kit suggestions → `kits`

The provider choice already lives in Paddock's project file.

The agent can write this file, and it can do more than `.paddock.toml` could:
- run commands on the Mac (`lifecycle`, `secrets` with `command`)
- mount other paths (`additionalWorkspaces`, `mounts`, a `workspace` other than the folder)
- approve credential injection (`bindings`)

The security rule "Refuse a local kit inside a project folder" changes, by operator decision (2026-11-04): a project's own local kit is allowed once the operator has confirmed its exact contents. Any change to the kit means confirming again.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Paddock reads `sbxenv.yaml` with a typed Codable model and fixture tests (valid, missing, malformed, unknown key, path escape)
- [x] #2 A local kit outside the project folder, or one reached through `..` or a symlink, is refused
- [x] #3 CLAUDE.md security rules, and backlog docs Project config file, Security rules, Network policy, and Kits, describe the new file and the changed local-kit rule
- [x] #4 Paddock refuses a project file with `lifecycle`, `secrets` that run commands, `mounts`, or a `workspace` that is not the project folder, and always passes `--skip-host-commands` (each with a test); `additionalWorkspaces` is handled by PAD-73.5
- [ ] #5 Paddock's overlay keeps the project file's `name`, so `sbx env run` from a terminal and Paddock use one sandbox per folder; a sandbox created without Paddock's kits shows as a recreate item, not a second project
- [ ] #6 Adding a kit from the interface: a kit from sbx's published catalog (`docker.io/sbx/*`, `docker.io/docker/sbx-kit-*`, or a contrib name) is added to the project's `sbxenv.yaml` `kits`; a custom one (any other image, `git+`, or a local path outside the project) goes into paddock.toml `[kits]` and reaches the sandbox through the overlay. Paddock's own kits (status, setup, browser, voice, gateway, and the default-off mise) are always overlay choices
- [ ] #7 Per-host approval stays for runtime hosts: the sheet lists each kit host with Allow (default) or Decline; a declined host gets a sandbox deny right after `sbx env create`, before the agent starts, and Allow later removes that deny without a recreate. Install-phase hosts are confirmed with the kit as a whole, and the sheet says so
- [ ] #8 UI: Config opens `sbxenv.yaml` (and the kit folder); the Info tab shows project kits read-only and Paddock kits as choices, and lists host ports; the "in .paddock.toml" and suggestion rows on the Ports and Network views are gone
- [x] #9 The setup kit is removed (from the defaults, BuiltinKits, and docs); projects that chose it keep working, and their kit list drops it with a recreate item
- [x] #10 No legacy support (operator decision 2026-11-04): `.paddock.toml` reading, its approval flow, and TOMLKit are removed outright, with no conversion; this repo gets an `sbxenv.yaml` and kit written by hand
- [ ] #11 Paddock's overlay is a file in its config dir merged by sbx. Paddock writes the project file only on an operator action (create, add a kit), keeping its comments and order, and records the written file as confirmed
- [ ] #12 Paddock generates the project files, so agents need no setup kit (operator decision 2026-11-04): New Project offers "Create sbxenv.yaml" for a folder without one, writing `sbxenv.yaml` and a skeleton mixin kit at `tools/sandbox/<name>/`, recorded as confirmed. The files carry Paddock's rules as comments and link sbx's docs; the kit's agent-context holds the PAD-71 build-output guidance
- [ ] #13 The confirmation sheet is built from ProjectEnvironment, not from `sbx env plan`, which has no JSON output (PAD-73.1 capture, sbx 0.49.2). It shows kits, runtime and install hosts, host ports, published ports, and extra folders, next to sbx's global rules. The approval covers ProjectEnvironment.fingerprint, and a change asks again. After the operator confirms, Paddock runs `sbx env create … --skip-host-commands --force`: `--force` gives sbx's own approval of the workspaces, which Paddock's sheet has already covered
- [x] #14 Project kits may not use `host-port@1`: sbx 0.51 does not support it (PAD-73.1), so ProjectEnvironment refuses it, and host services stay sbx rules managed on the Ports page as today
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Core slice landed (not wired into the app): YAMLCoding (YAML 1.2 core schema, anchors/aliases/merge keys refused, via Yams 6.2), SbxEnvFile (strict, unknown keys are errors), SbxKitDescriptor (typed network-policy@1/@2 and host-port@1), ProjectEnvironment (every refusal from the ACs collected for the sheet: refused keys, Paddock-owned env, workspace, ports, catalog vs local vs custom kits, local kit capability allowlist, host checks via HostRules, host-port reserved ports, fingerprint over file and local kit files), PaddockOverlay (writer, quoted values, read-back test). Tests: ProjectEnvironmentTests.swift incl. the example project as Fixtures/config/sbxenv-example. Still open: the sheet, create through `sbx env create` with `--skip-host-commands`, approval storage, the add-kit path, setup kit, conversion, docs for security rules. These wait on the PAD-73.1 captures (plan JSON shape, create behaviour, deny over kit allow).

SandboxFiles (Environment/SandboxFiles.swift) generates sbxenv.yaml and the project kit, with Paddock's rules as comments from the same constants ProjectEnvironment checks against, the PAD-71 guidance as the kit's agent-context, and a .paddock.toml conversion that lists what it leaves for the operator (Dockerfile, kit suggestions, provider). Generated output passes ProjectEnvironment (tests). Not wired into New Project or the convert action yet; the workload reference (docker.io/docker/sbx-kit-claude:2.1.316, agent sbx-kit-claude) is a parameter until PAD-73.1 confirms it loads.

Removed the .paddock.toml conversion from SandboxFiles (operator: no legacy converters).

sbx 0.51 mounts the project's sbxenv.yaml read-only inside the sandbox, so the agent cannot change it from in there. The local kit folder stays writable, so the fingerprint and confirmation are still needed. Kit hosts appear in `sbx policy ls` as one rule, `kit:<sandbox>`, which holds every kit's hosts (the workload's Anthropic hosts included), plus `kit:<sandbox>:http:N` for bounded entries. A sandbox deny beats them, which confirms the per-host decline design.

Wired in (2026-11-04):
- Create: ProjectRunner.create checks and needs the confirmed fingerprint (ProjectRunError.environmentNeedsApproval), writes PaddockOverlay (agent, absolute workspace, Paddock's kits, gateway env, extra folders), runs sbx env create <file> <overlay> --name N --skip-host-commands --force [--clone], then Paddock's denies plus Project.declinedHosts as sandbox denies, then the gateway rule. Recreate checks the file before removing. Start needs no confirmation. Project records approvedEnvironment, declinedHosts, sandboxEnvironment; SandboxSync lists an environment recreate item.
- Sheet: EnvironmentReview (core, tested) and ConfigConfirmSheet: refusals, kits, runtime hosts with a checkbox each (global allow named), kit denies, install hosts, extra folders, ports, env names. Review button on the Info tab's Project kits row; changing declines on an unchanged file applies denies in place (setHostRule).
- Add kit: ProjectKitFile adds catalog kits to the project's sbxenv.yaml (text insertion, tested), others to paddock.yaml; a file confirmed before the addition stays confirmed.
- Generated files: Config writes sbxenv.yaml and a kit when there is none; New Project offers it. Both record the written files as confirmed. sbx's own agents need no workload kit in the file (SandboxFiles.Input.workload is optional).
- Removed: .paddock.toml (ProjectConfig, ConfigReview, suggestions in ports, rules, host rules, Kits.preselected suggestions), this repo's .paddock.toml and Dockerfile (now sbxenv.yaml and tools/sandbox/paddock-dev, checked by a test), examples/claude-mise-playwright.
Not done: AC5 (the overlay passes --name with Paddock's project name; a sandbox made by sbx env run under the file's name is a separate sbx sandbox, not a recreate item), AC8's 'and the kit folder' (Config opens sbxenv.yaml only). The App side is not compiled here: AC6, 7, 8, 11, 12, 13 wait for a build and a run on the Mac.
<!-- SECTION:NOTES:END -->
