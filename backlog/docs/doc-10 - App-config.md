---
id: doc-10
title: App config
type: specification
created_date: '2026-10-25 15:55'
updated_date: '2026-11-07 10:25'
---
**Managed scope (closed list):** Paddock manages only the following and leaves every other sbx and llmman feature alone:

- sbx: sandboxes it created (create, run, stop, rm, ports, exec), per-sandbox policy rules it owns (including the gateway allow and the llmman deny), the mixin kits a project's sandbox is created with (chosen from `paddock.yaml`'s `[kits]`), and secrets it stores. Paddock does not use or change sbx's experimental `feature.model`.
- llmman: read-only health and model lists over its API, and the embedded web UI. Model downloads, deletions, and provider keys are done by the operator in llmman's own UI.
- Its own ModelGateway.

A feature is added to this list deliberately, with a ticket, never as a side effect. One operator-owned file, `~/.config/paddock/paddock.yaml` (or `$XDG_CONFIG_HOME/paddock/paddock.yaml` when set), describes the desired state in named sections. It is never inside a mounted folder, so agents cannot touch it. The UI edits it, and it can also be edited by hand.

```yaml
version: 1

models:
  gatewayPorts: [17480, 17579]
  maxBodyMB: 32
  maxConcurrentPerProject: 2

defaults:
  agent: claude
  provider: agent-default

providers:
  agent-default:
    kind: agentDefault
  local-qwen:
    kind: local
    model: "hf.co/unsloth/Qwen3.5-35B-A3B-GGUF:latest"

agents:
  claude:
    kind: claudeCode
  opencode:
    kind: openCode

ports:
  publishRange: [18000, 18999]
```

- **Defaults:** the sections the New Project sheet starts from. Each must name a defined section, and a missing `paddock.yaml` (or one with only `"version": 1`) means exactly the example's built-in defaults.
- **Validation:** the gateway port range may not include `2375`, `2376`, or `17434` or overlap `ports.publishRange`, and host-service ports may not be reserved or gateway ports; unknown keys are reported in the UI, not ignored silently; an unknown `kind` or a `local` provider without a `model` is an error.
- **Providers:** `agentDefault` = no gateway (the agent's default provider through its own account, shown as "default provider", e.g. Claude Code with Anthropic); `local` = through the gateway, pinned to `model` (the name as llmman's `/api/tags` reports it). An installed model needs no section: the New Project sheet lists every model in llmman's store that no section names, and the project stores it as provider `local:MODEL` (`AppConfig.provider(named:)`), a `local` provider like any other. Hosted models through llmman are out of scope for v1.
- **Keeping state in line:** there is no automatic reconcile loop. `GatewayHost.sync` keeps one gateway listener per project that uses a local model; the status checks rerun on launch, on Refresh, and when the app comes to the front; sandbox states follow sbx's events (and `sbx ls` when the events missed a change). Differences in sbx go through Sync below, which the operator applies. Whether Paddock should re-apply its own per-sandbox rules without asking is PAD-20.
- **Where state lives (sbx first):** sbx is the only store for a sandbox's published ports, host services, and network allow and deny rules; Paddock reads them from sbx and changes them there, and never copies them into a file. The project file (`~/.config/paddock/projects/NAME.json`) holds only what sbx cannot: name, folder, agent (a project exists before its sandbox and is created again from these), provider, clone mode, gateway port, Paddock's kits, extra folders, the fingerprint of the `sbxenv.yaml` the operator confirmed and the hosts they declined, the fingerprint and kits its sandbox was created from (sbx does not report them), and the suggestions the operator chose to ignore. `sbxenv.yaml` in the project folder is the project's own setup (see Project config file); sbx applies it at create, and Paddock its denies for declined hosts right after. Older project files with `ports`, `network`, `policy`, `approvedConfigHash`, or `imageTag` keys still load; those keys are ignored.
- **Ownership:** the app shows every sbx sandbox and manages the ones with a project file. New projects are named after their folder by default (lowercased, reduced to sbx's characters, `-2` when taken; `project-<name>` when sbx would refuse the bare name; only a suggestion; sbx naming rules apply). Projects from before PAD-74 keep their `paddock-` names. Projects are one list: every project file and every other sbx sandbox, which appears as a project built from what sbx reports (its id is sbx's sandbox id). The first action that needs a file (start, stop, Apply, approval) writes it once with the name, folder, and agent; ports and rules need none. The Info tab warns about a folder FolderPolicy would refuse; missing Docker API or llmman denies are "not denied" rows under Ports. Kit-based sandboxes keep sbx's agent name and can be managed but not recreated. Paddock never changes global rules on its own; operator actions in its interface may.
- **Sync:** with sbx the only store, `SandboxSync` lists few differences, each with **Apply** (sbx changes): the sandbox is missing (create), its folder, agent, extra folders, or kits differ from the project file, or it was created from another confirmed `sbxenv.yaml` than the current one (recreate, confirmed first); a recreate is the only way to change a sandbox's extra folders: sbx 0.51 refuses new workspaces on an existing sandbox, through `sbx run --name` ("can't be given new workspaces"), `sbx create`, and `sbx env create` alike, PAD-126, `mise run capture:cli mounts`), Paddock's denies for its own services are missing (one item), or the gateway rule is missing. sbx's own kit rules (`created_via: provisioned`) are left alone. Nothing is ever saved back into a file. They show under Needs attention, with an `sbxenv.yaml` to confirm, except Paddock's missing service denies: those are a suggestion on the Info tab ("Deny the sandbox access to Paddock's services", Apply, Ignore). Ignore keeps it hidden for that project (`ignoredSuggestions` in its project file). Beside it, sbx's **approval requests** for the sandbox (`sbx policy approval ls --json`: what the agent tried that no rule decided, a host or an HTTP request, newest first), each "Wants to reach TITLE" with the answers sbx offers (Allow, which adds sbx's own approval rule, and Dismiss), sent with `sbx policy approval respond ID --option OPTION` (`ApprovalRequests`). Requests for Paddock's own services (llmman, the gateway ports) are not offered. Dismiss also goes into the project's `ignoredSuggestions` (by title), because sbx asks again when the agent tries again; answering waits only on that request's buttons, gives up after 20 seconds, and takes the request off the list once sbx took the answer. On the Network page, a "no rule" host with a pending request is answered the same way. The Info tab is marked while a difference, a suggestion, or a "not denied" port is open.
- **Project ports:** each project's Info tab lists its ports: what sbx publishes and the host services its sandbox allows (in effect), and "not denied" ports, with open, copy URL, remove, and deny. "Not denied" marks a port Paddock always denies (Docker API, llmman, another project's gateway) that the sandbox can still reach through a global or sandbox allow; Deny adds the sandbox's missing denies. The Network page lists every rule (see UI).
- **Host rules:** the Network page (with a project's sandbox selected, from its Info tab's shortcut) lists the allows and denies the sandbox has in sbx and the hosts it reached that no rule names, with Allow, Deny, or Remove per host. A change goes straight to sbx (`ProjectRunner.setHostRule`: deny first, never removing a deny for Paddock's services, never touching sbx's kit rules); Remove leaves the host to sbx's global rules. This Mac's own hosts (`localhost`, `host.docker.internal`) are refused there and go through Ports.
- **Removing ports:** a published port or host service is removed in sbx (unpublished, or its allow removed and the port denied); there is no disabled state. sbx's own global rules are never changed by Paddock; the operator can remove one from the Network page (confirmed first) or manage them with the sbx CLI. Paddock sandboxes deny global loopback allows anyway unless the sandbox allows them.
- Decoded by `AppConfig` with fixture tests, including unknown keys and bad versions.
- **Format:** `paddock.yaml` is YAML (the 1.2 core schema, as sbx reads its own files), hand-edited, and read by Paddock as JSON data, so the typed models and unknown-key checks are the same as for any JSON. A section whose keys are all commented out counts as absent, and a kit with no keys (`gh:`) counts as an empty section. Paddock writes to it only when the operator adds a kit from the interface: the kit is inserted at the end of the `kits:` block (or a new block is added), and nothing else changes, comments included. A project's `sbxenv.yaml` is YAML too, read the same way (PAD-76: TOMLKit is gone). Paddock's own project files, which it writes, are JSON.
