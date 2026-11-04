---
id: doc-11
title: Project config file
type: specification
created_date: '2026-10-25 15:55'
updated_date: '2026-11-04 18:53'
---
A project's own setup is sbx's environment file, `sbxenv.yaml` at the project root, plus the project's own v3 kits (PAD-73). A project set up this way runs with plain `sbx env run`, without Paddock. Paddock reads the same files, checks them, has the operator confirm them, and adds its own part from a file of its own (the overlay). A project without `sbxenv.yaml` is created with `sbx create` and Paddock's kits only, as before.

```yaml
schemaVersion: "1"
name: shop
agent: claude
workspace: .
kits:
  - docker.io/sbx/mise:2026.5.2
  - ./tools/sandbox/shop
ports:
  - { sandbox: 3000, host: 3000 }
sandboxOptions:
  cpus: 4
```

- **The operator's choices stay Paddock's.** The agent, provider, Paddock's kits, extra folders, and clone mode live in the project file in Paddock's config dir (backlog doc ProjectStore). `name` and `agent` in `sbxenv.yaml` only pre-fill the New Project sheet; Paddock always creates the sandbox under the project's name and with the project's agent.
- **Config** (the Info tab's folder row) opens `sbxenv.yaml` in the default editor. When the folder has none, it first writes one and a kit for the project (`SandboxFiles`, below). New Project offers the same ("Create sbxenv.yaml and a kit for this project", off by default); a folder that has one says Paddock uses it.
- **Untrusted input:** the agent can write to this folder. A project file never sets the agent's provider, Paddock's kits, or extra folders the operator did not confirm, and nothing in it runs on the Mac.

## Reading and checking

- **Reading** (`SbxEnvFile`, `YAMLCoding`): YAML read with the 1.2 core schema, as sbx's Go reader does (`yes` and `on` stay strings). Anchors, aliases, merge keys, and duplicate keys are refused. `schemaVersion` must be the string `"1"`. Every key Paddock does not know is an error, never skipped.
- **Refused in a project file** (`ProjectEnvironment`):
  - `lifecycle` (it runs commands on the Mac)
  - `secrets`, `bindings`, `registries` (secrets belong to sbx and the operator)
  - `mounts`
  - `mcp` and `args` (not checked yet)
  - a `workspace` that is not the project folder
  - `sandboxOptions` other than `cpus`, `memory`, `pullPolicy`
  - `env` names Paddock owns (`PADDOCK_`, `SBX_CRED_`, `ANTHROPIC_`, `OPENAI_`, `OPENCODE_`)
  - published ports on llmman's port, a gateway port, or the Docker API ports, or bound anywhere but 127.0.0.1
- **Kits:** sbx's published kits (`docker.io/sbx/NAME`, `docker.io/docker/sbx-kit-NAME`) and the project's own local kits (`./path`, a real folder inside the project, no `..` or links). Any other kit is custom and belongs in the operator's paddock.yaml.
- **A project's own kit** (`SbxKitDescriptor`, `<folder>/<folder>.yaml`) must be a v3 mixin with no links among its files. It may only ask for these capabilities:
  - network-policy, lifecycle, agent-context, agent-skill(s)
  - port, volume, resources, long-running
  - dockerd, privileged, git-identity

  Credentials, the SSH agent, host mounts, the kit registry, and anything else are refused. Allowed hosts are checked like host rules: never this Mac, never `**` or `*`. `host-port@1` is refused: sbx 0.51 does not support it (PAD-73.1), so this Mac's ports stay sbx rules that Paddock manages. A kit's lifecycle hooks run inside the sandbox, never on the Mac.
- **Extra folders** (`additionalWorkspaces`, PAD-73.5): resolved from the project folder with links followed, then checked by FolderPolicy like a project folder. The project folder itself is refused, and so is a mount target that is relative or a system folder. A folder that is another project's is marked.
- **Fingerprint:** SHA-256 over the file and every file of each local kit. The operator's confirmation covers exactly this.
- Paddock reads the file again on Refresh, when the app comes to the front, and right before a create (`AppModel.readProjectFiles`); views use what was read last.

## Confirming

- **Confirmation sheet** (`EnvironmentReview`, `ConfigConfirmSheet`): before a create, when the file was never confirmed or its fingerprint changed, the operator confirms it in one sheet, built from Paddock's own checks (`sbx env plan` prints text only, which Paddock does not parse):
  - what Paddock refuses, in red; the sheet cannot be confirmed until the file is fixed
  - the kits, each marked sbx's or the project's own (built at create)
  - **the hosts the agent may reach**: each runtime allow of the project's kits, with its methods and paths, the kit asking for it, and the global rule that allows it already, if one does. Each has a checkbox: unchecking declines it.
  - the hosts its kits deny, and the hosts open while its kits install (confirmed with the file as a whole)
  - extra folders (read-only or writable, another project's folder marked), published ports, and the environment variables it sets
- Confirm records the fingerprint (`Project.approvedEnvironment`) and the declined hosts (`Project.declinedHosts`, only hosts the sheet offered). Create, and a new session on a project without a sandbox, wait for it; Start does not (a sandbox runs as it was created). A file never confirmed, or changed, shows "sbxenv.yaml is new or changed" under Needs attention with Review.
- **Declining a host** is a sandbox deny applied right after the create: a sandbox deny beats a kit's allow (PAD-73.1), so a declined host stays blocked whatever the kit says. Review (the Info tab's Project kits row) opens the sheet again; with the file the sandbox was created from, a change of the declined hosts applies at once, a deny added or lifted (`ProjectRunner.setHostRule`), with no recreate.
- **Changes need a recreate.** sbx reads the file and kits only at create. When the confirmed fingerprint differs from the one the sandbox was created from (`Project.sandboxEnvironment`), Sync lists a recreate item (backlog doc App config, Sync). A recreate checks the file before it removes anything.

## Creating

- `ProjectRunner.create` with an `sbxenv.yaml`: refuses a file with refused entries or one not confirmed in this version (before sbx is asked anything), checks the extra folders again, writes the overlay, and runs `sbx env create <project>/sbxenv.yaml <overlay> --name NAME --skip-host-commands --force [--clone]`. `--skip-host-commands`: nothing from a project file runs on the Mac. `--force`: sbx's own approval of the workspaces, which the operator gave in Paddock's sheet. Then, before any agent session: Paddock's denies (llmman's port, other projects' gateway ports) and the declined hosts as sandbox denies (`sbx env create` takes no `--deny-network`), then the gateway's HTTP rule.
- **Overlay** (`PaddockOverlay`): `<config>/projects/<name>.sbxenv.yaml`, owner-only, in Paddock's config dir where agents cannot reach it. It has the same agent, the project folder as an absolute `workspace`, Paddock's kits, the operator's extra folders as `additionalWorkspaces`, and Paddock's environment (the gateway's variables). sbx merges the two files: maps by key, lists concatenated, the later file's scalars winning. Every value is written as a quoted string. Paddock never writes the project's file for this, so `sbx env run` in a terminal keeps working without Paddock, and the gateway's port and model never land where the agent can change them.

## Adding a kit

The kit field (New Project, the Info tab's Kits) adds one of sbx's catalog kits (a contrib kit's name such as `mise`, or a `docker.io/sbx/...` reference) to the project's `sbxenv.yaml` `kits:` when the project has one (`ProjectKitFile`): lines are only added, comments stay, and the change needs a confirmation and a recreate like any edit. Anything else, and any kit for a project without the file, goes to paddock.yaml (backlog doc Kits).

## Generated files

`SandboxFiles` writes a project's files when the operator asks (Config, New Project). It writes `sbxenv.yaml` with the sandbox's name, the agent, `workspace: "."`, and the project kit; sbx's own agents name their workload kit themselves (`claude` is `docker.io/sbx/claude`), so none is listed for them. It also writes the kit at `tools/sandbox/<kit>/<kit>.yaml`: a v3 mixin with `agent-context@1` (the version sbx's own kits use; @1 and @2 do not compose) and a `version`, since sbx refuses an unversioned `provides`. Both files carry Paddock's rules as comments, built from the same lists the checks use, and link sbx's docs. The kit's agent context says how the sandbox is defined and holds the build-output guidance (PAD-71), so agents need no setup kit. Existing files are never overwritten. Generated files pass the checks above.

This repository's own `sbxenv.yaml` and `tools/sandbox/paddock-dev` are a fuller example (a test checks Paddock accepts them).



## Check to use (PAD-84, PAD-86)

`ProjectRunner.create` reads the file and its local kits again after `sbx env create`; if the fingerprint differs from the confirmed one, the new sandbox is removed and the create fails (`environmentChangedDuringCreate`). This detects a swap rather than preventing it: sbx reads the project folder itself. An extra folder's `target` must be under `/workspace`, `/mnt`, `/srv`, `/data`, or the operator's home (an allowlist, `ProjectEnvironment.isAllowedTarget`); anything else is a problem in the confirmation sheet.
