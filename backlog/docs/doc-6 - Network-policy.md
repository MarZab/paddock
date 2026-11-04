---
id: doc-6
title: Network policy
type: specification
created_date: '2026-10-25 15:55'
updated_date: '2026-11-04 15:05'
---
M0 found **81 global allow rules** on the operator's machine, all applying to every sandbox. They include sbx defaults (`**.github.com`, `**.amazonaws.com`, `**.googleapis.com`, and more) and rules the operator added for other projects, such as `localhost:5432`, `localhost:6379`, and `localhost:2375` (the Docker Engine API port). The proxy maps these to the **host's** loopback: from a sandbox, `host.docker.internal:5432` reached the host's Postgres. Defaults also include `filesystem:read **` and `filesystem:write **`, so sbx itself would mount any folder.

Paddock used to give each sandbox only a named policy section, denying every global allow outside it per sandbox (about 270 deny rules per sandbox on the operator's Mac). That was dropped: the global rules are the operator's and stay in effect for every sandbox. Instead (`PolicyPlanner`):

- **Effective network = sbx's global rules + the kits' rules.** The agent's kit, Paddock's kits, and a project's `sbxenv.yaml` kits each add their hosts (sbx shows them as one `kit:<sandbox>` rule, plus `kit:<sandbox>:http:N` for method- or path-bound entries). A project's kits take effect only after the operator confirmed the file; each runtime host the operator declined becomes a sandbox deny right after the create (a sandbox deny beats a kit's allow; backlog doc Project config file).
- **Paddock's own services, always:** llmman's port (`localhost:17434` and `host.docker.internal:17434`) is denied for every Paddock sandbox: agents reach models only through the gateway. When a global rule reaches the gateway ports (`localhost`, `**`), the other projects' gateway ports are denied too. Nothing else is denied on Paddock's account. It *suggests* denying the Docker API and cloud metadata for any sandbox that can reach them, as disabled rows in the Network table with Deny (`RulesTable.suggestedDenies`); the operator decides.
- **Drift:** a missing service deny (say after a global rule changed) shows as a difference with Apply.
- Paddock never changes global rules on its own; they belong to the operator, whose actions in Paddock's interface may change them (confirmed when they affect every sandbox).
- FolderPolicy is the only guard on mounts, because sbx allows mounting any path.
