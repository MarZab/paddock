---
id: PAD-127
title: Keep Claude's sessions and context across a sandbox recreate
status: Done
assignee: []
created_date: '2026-11-07 10:27'
updated_date: '2026-11-07 14:21'
labels:
  - sbx
  - agents
dependencies: []
type: spike
ordinal: 131000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Operator question 2026-11-07: a recreate (Sync, extra folders, kits) loses the agent's ~/.claude in the sandbox: sessions (claude --resume), history, settings it learned. sbx 0.51's rm keeps 'persistent volume@1 storage created with retention support' and reattaches it on a create with the same name and kit, and sbx kit add speaks of kit-owned volumes such as agent session state. mise run capture:cli sessions shows what the claude kit declares (sbx kit inspect) and whether a fake session survives Paddock's recreate (rm --force, create same name and agent), also with an extra folder added. If sbx keeps it, Paddock need do nothing but say so; if not, options are a Paddock kit declaring a volume@1 for ~/.claude/projects, or a host-mount@1 of a Paddock-owned per-project folder (Paddock's config dir, never a project folder). (backlog doc App config, Sync)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Captures of mise run capture:cli sessions are read: what the claude kit declares, and whether ~/.claude/projects and history.jsonl survive each recreate
- [x] #2 Either the docs say sessions survive a recreate (and when not: another sandbox name or agent kit), or a follow-up ticket keeps them, with the approach chosen by the operator
- [x] #3 A Claude Code project (no sbxenv.yaml) can keep its sessions in ${XDG_DATA_HOME:-~/.local/share}/paddock/sessions/<project>/claude: New Project switch, Info row with count, size, Show in Finder, Clear Sessions (confirmed)
- [x] #4 The folder is made and checked at every create (no link from Paddock's data folder down, FolderPolicy, never in the config folder), mounted with --mount through Paddock's host-mount@1 kit, read back from sbx ls, and recorded; Sync shows a recreate item when it differs
- [x] #5 Clearing never follows links; tests cover each check; CLAUDE.md, Security rules, UI and Sync docs, CHANGELOG updated
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-07 mise run capture:cli sessions (sbx 0.51.0, kit docker.io/sbx/claude@sha256:ea1bfdf8...): the claude kit declares no volume (sbx kit inspect: args, environment, AI file only); the only mount under ~/.claude is the read-only skills store. A fake ~/.claude/projects/paddock-probe/probe.jsonl and a history.jsonl line were gone after Paddock's recreate (rm --force, create same name and agent), with and without an extra folder; ~/.claude/projects itself was gone. So a recreate loses claude --resume sessions and history. Keeping them needs Paddock to: (a) declare a persistent volume@1 with retention in a Paddock kit for ~/.claude/projects (stays in sbx's storage; syntax not captured yet), or (b) host-mount@1 a Paddock-owned per-project folder on the Mac at ~/.claude/projects (sbx create --mount; a new kind of mount the security rules must allow).

Operator chose the sbx volume. Docs (docs.docker.com/ai/sandboxes/customize/author/capabilities, sandbox-kit-spec volume@1.md): capabilities: - type: com.docker.sandbox/volume@1, config: {path (absolute, required), size, tmpfs, mode}; block volumes are retained on rm by default, keyed on sandbox name and path, reattached on a create with the same name; create-time only (not sbx kit add); no sbx command removes them yet. Unknown until captured: whether the volume's root is writable by the agent (uid 1000). Probe: mise run capture:cli sessions-volume.

2026-11-07 mise run capture:cli sessions-volume (sbx 0.51.0): sbx kit validate accepts the mixin; sbx create mounts an ext4 volume (/dev/vdg) at ~/.claude/projects, owned by agent (uid 1000), writable (a fake session was written). But it is NOT retained: after sbx rm --force and a create with the same name and kit, the volume is fresh (only .sbx-volume-initialized and lost+found), with or without an extra folder; sbx rm --json reports only the sandbox removed. sbx settings ls has no retention setting. The docs' capability table marks volume@1 as Limited locally; retention does not work in 0.51.0. The sbx volume approach waits for sbx; the probe phase stays to recheck.

Operator's decision: an optional folder on the Mac, chosen when the project is created, in the project's own folder in Paddock's config: ~/.config/paddock/projects/<name>/claude-sessions, mounted at ~/.claude/projects through a Paddock kit's host-mount@1 and sbx create --mount. Needs a narrow security exception (a Paddock-made folder inside the config dir, checked for links at every create, never read by Paddock). Probe first: mise run capture:cli sessions-hostmount.

Revised with the operator: not in ~/.config (configuration only; no agent-writable mount inside Paddock's config dir, so that security rule keeps no exception). Sessions go to Paddock's data dir, XDG: ${XDG_DATA_HOME:-~/.local/share}/paddock/sessions/<project>/claude, made by Paddock (0700), FolderPolicy-checked at every create (not overlapping the config dir, no link anywhere in the path). Info gets a Claude sessions row: on/off, count and size, Show in Finder, Clear Sessions... (confirmed; warns when the agent runs; removes the contents without following links). Removing a project offers to delete its sessions folder. Option chosen in New Project; turning it on or off later is a recreate item.

Implemented on pr/2026-11-07. sbxenv.yaml projects and deleting the folder with a project: PAD-130. To verify on the Mac: build, New Project with the switch, a session, Recreate, claude --resume finds it, Clear Sessions.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Claude's sessions kept on this Mac across recreates through a Paddock kit's host-mount@1 and sbx create --mount, with folder checks, read-back, Sync item, and Clear Sessions; sbxenv.yaml projects in PAD-130. Verified by the operator on the Mac on 2026-11-07 (build, tests, and the behavior by hand).
<!-- SECTION:FINAL_SUMMARY:END -->
