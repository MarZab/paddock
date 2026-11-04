---
id: doc-5
title: SbxService
type: specification
created_date: '2026-10-25 15:55'
updated_date: '2026-11-04 13:05'
---
Verified against sbx v0.49.2 help and output (M0).

| Action | Command |
|---|---|
| Version gate | `sbx version --json`: `{client:{version,revision}, server:{state,version,revision,api_version}}`. Require >= 0.51 (PAD-73.2) and `server.state == "running"`. |
| Daemon | `sbx daemon status --format json`: `{status, socket, logs}`; `sbx daemon restart` (only for llmman hardening, with confirmation) |
| List | `sbx ls --json`: array of `{name, id, agent, status, last_used_at, workspaces[], created_at}`, plus `ports[]` (`host_ip`, `host_port`, `sandbox_port`, `protocol`) on a sandbox with published ports. `created_at` is missing while sbx is still creating the sandbox (PAD-56), so the app shows its creation time as "-". |
| Live updates | `sbx events --json [TYPE...]`: NDJSON `{id, type, action, timestamp, sandbox_name, ...}`. It **replays current state on connect, then sends `{"type":"sync","action":"complete"}`**, so the sandbox list is built from events, with `sbx ls` only as a fallback. Types seen: `sandbox.lifecycle`, `sandbox.ports`, `policy.network`, `sync`. |
| Fast reads | sandboxd's socket (`sbx daemon status`'s `socket`), unauthenticated HTTP over a Unix socket, a private API captured on 0.49.2 (API 0.42.0) with `scripts/socket-capture.py`. Answers in 1 to 15 ms where an sbx command takes about 300 ms. Paddock sends only the GETs sbx sends for the same reads: `/daemon/health` (the gate: `status`, `api_version`), `/sandbox` (sbx renames `workspace` to `workspaces`), `/policy/network/rules?type=all` (sbx's own shape; for one sandbox, the global rules plus its own), `/policy/network/log` (`allowed_hosts`/`blocked_hosts`, `vm_name`, `count_since`, `since`; an empty `rule` is dropped), `/user-prompts` (NDJSON `requested` prompts, then `synced`), `/events` (the same lines as `sbx events`). `FallbackSbxReads` uses the CLI when the socket fails, for 60 s, and the status popover says which. A 503 from sandboxd (after sleep: "docker login service unavailable: the host is not fully awake") is the daemon busy, not the socket broken: the read throws it as is (the CLI would ask the same daemon), and a health check that got one is tried again on the next read. The app clears an error from a read it did by itself (sbx ls, a sandbox's rules) once the next read of the same kind works. Not mapped yet (PAD-19): `runtime_mounts` with a value, ports (only empty lists captured), stats (the TUI runs a shell one-liner per sandbox through `POST /sandbox/N/exec`). |
| Claude project | `sbx create --name N [--clone] [-t IMAGE] [-e KEY=VALUE]... [--deny-network R]... claude FOLDER` (`-e` carries the gateway variables; Paddock never passes `--model`) |
| OpenCode project | `sbx create --name N [--clone] [-t IMAGE] [-e KEY]... [--deny-network R]... opencode FOLDER` |
| Attach agent | `sbx run --name N` (in the terminal pane) |
| Shell | `sbx exec -it N bash` (in the terminal pane) |
| Ports | Publish with `-p` at **create time only** (ignored when re-attaching); later use `sbx ports N --publish/--unpublish`, list with `sbx ports N --json`. Binds loopback by default. |
| Stop / remove | `sbx stop N`, `sbx rm --force --json N` |
| Policy | `sbx policy ls [N] --json`: `{rules:[{id, scope ("global" or "sandbox:N"), applies_to, resource_type, decision, resources[], origin, status, provenance:{created_via}, actions[]}]}`; `sbx policy allow/deny network [--sandbox N] RESOURCES [--method M,...] [--path GLOB]` (HTTP rules); `check`, `rm` |
| Secrets | `... \| sbx secret set SERVICE [--sandbox N]` (stdin) |
