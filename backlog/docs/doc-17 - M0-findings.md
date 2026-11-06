---
id: doc-17
title: M0 findings
type: specification
created_date: '2026-10-25 15:55'
updated_date: '2026-11-06 08:21'
---
## Open risks

1. ~~How OpenCode gets its provider config.~~ Answered: `OPENCODE_CONFIG_CONTENT` (sbx's own `--model` kit uses it). Still open: tool calling quality with the chosen local model (PAD-3).
2. ~~Claude Code without sbx's model kit.~~ Answered: copy the kit's environment and its install command that pre-approves the key and repeats the onboarding flags (see Wiring). Verified end to end with the gateway trial (2026-10-24, sbx 0.49.2): Claude Code in a sandbox answers through the gateway, the dummy key needs no approval prompt, and tool calls work (it read a file and ran a search, even on a 0.8B model, whose answers are weak). Reusing a sandbox works, with the port read back from its HTTP rule. Still open: answer quality and long context with a useful local model (PAD-4; Claude assumes a 200k context for unknown model names), and OpenCode through the gateway (PAD-3).
3. ~~How sandboxes reach llmman with `--model`.~~ Answered: a per-sandbox TCP allow for `localhost:17434`, giving the whole API. Hence the gateway.
4. ~~HTTP policy rules in practice.~~ Verified (round 4): a sandbox reaches a port on the host through `host.docker.internal`, and the per-sandbox rule `allow --method GET --path '/v1/**'` is enforced by sbx (stored as `resource_type: "http"`). `GET /v1/ok.txt` returned `200`; `GET /other.txt` and `POST /v1/ok.txt` never reached the server and got `403 Approval required`. Paddock must deny such approval requests for its sandboxes (or they pile up as pending approvals).
5. ~~`-e` variables.~~ Verified: `-e KEY=VALUE` and the bare `-e KEY` (value from the `sbx` process's environment) both reach the sandbox and survive a stop and start.
6. **llmman auto-pull:** whether a chat request for a model that is not in the store makes llmman download it. Pinning prevents agent-chosen names either way. Handled: `ProjectRunner` creates, starts, or recreates a project on a local model only while llmman's `/api/tags` lists that model (`checkModel`), and refuses when llmman does not answer.
7. ~~Prompt history.~~ Answered: sbx's llmman **does** keep it (`prompts.jsonl` appeared with 2 lines after round 3/4; sbx does not set `LLMMAN_NOHISTORY`). Still open (PAD-13): whether `LLMMAN_NOHISTORY=1 sbx daemon restart` (run with the variable in the CLI's environment) reaches llmman, and whether a daemon restart interrupts running sandboxes. Until then, Paddock shows the file's size and offers to clear it.
8. ~~Custom images from a builder sandbox.~~ Verified end to end (round 4b): context in with `sbx cp`, `docker build` and `docker save` inside, `sbx cp` out, `sbx template load`, and the image is listed as `docker.io/paddock/m0:test`. It has **no `flavor`** (no sbx label), so Paddock must not rely on `flavor` for images it builds; it records the agent itself. `sbx template rm` needs `--force` without a terminal.
9. ~~Whether per-sandbox `--deny-network` beats a global allow.~~ Verified: with `--deny-network localhost:5432` and `--deny-network localhost:17434`, both answered `Blocked by local rule` from inside the sandbox, although `localhost:5432` is allowed globally.

Resolved: token exposure in `sbx secret set` (stdin), custom images (`-t` plus `template load`; base images `docker/sandbox-templates:<flavor>`), llmman's address and auth (`127.0.0.1:17434`, no keys), who starts llmman (`sbx daemon start`), and the web shell (off, set by sbx).

## References

- Docker Sandboxes usage: https://docs.docker.com/ai/sandboxes/usage/
- Structured output and v0.48 changes: https://docs.docker.com/ai/sandboxes/workflows/automation/
- Local and hosted models (`--model`, llmman, `model.providers`): https://docs.docker.com/ai/sandboxes/configuration/models/
- Reaching host services from a sandbox: https://docs.docker.com/ai/sandboxes/workflows/development/
- llmman: https://github.com/llmmanorg/llmman (docs/api.md, docs/configuration.md, docs/webui.md, docs/backends.md)
- OpenCode (built-in sbx agent): https://opencode.ai/docs/
- Unofficial sandboxd API spec (reference only): https://github.com/itbm/sbx-sdk

## sbx env and v3 kits (PAD-73.1, first run 2026-11-04, sbx 0.49.2)

- `sbx env plan|run|create|exec|rm` and local v3 kits work on 0.49.2. sbx builds a local kit at create with the Mac's Docker buildx (Docker Desktop here).
- **A kit's `provides` needs a version:** `name@x.y.z`, or a top-level `version:`. sbx's kit builder refuses the kit otherwise, even though kit.schema.json allows it.
- **`sbx env plan` is text only** (no `--json`, no `--format`). Paddock's confirmation sheet comes from its own checks (`ProjectEnvironment`).
- **sbx has its own approvals:**
  - Workspaces are "present, not recorded as applied, needs your approval".
  - `lifecycle` host commands are flagged as running on this machine.
  - `--force` approves for one run. `--skip-host-commands` leaves host commands out, and they do not run.
- **Errors** name the file, line, and column: `sbxenv.yaml:3:1: unknown field "notAField"`.
- **sbx 0.51** (second run): the kit builds and is cached as `sbx-kit-src:<kit>-<hash>`.
  - `${{ kit.env.NAME }}` comes from the final image's environment, filled in when the sandbox is built. `WORKSPACE_DIR` is not in it, and sbx refuses a kit that uses it. Kits read `$WORKSPACE_DIR` from the shell in a startup hook instead.
  - `host-port@1` is refused when required: "unsupported capability type", although kit.schema.json has it. So this Mac's ports cannot come from a kit, and `sbx policy allow network localhost:N` stays.
  - The built-in `claude` agent now resolves to a v3 kit, `docker.io/sbx/claude:latest` (PAD-73.2).
- **sbx 0.51, fourth run: a sandbox from `sbx env create <project> <overlay> --skip-host-commands --force`** (fixtures `ls-v3.json`, `policy-ls-v3-sandbox.json`, `version-0.51.json`, and the `env-*.txt` plan text, kept for reference, never parsed):
  - **Merging:** the overlay's `env` reached the sandbox and the kit lists concatenated. Explicit paths skip `~/.sbxenv.yaml` (`sbx env plan --help`).
  - **Workspaces:**
    - `readOnly: true` is enforced ("Read-only file system").
    - Extra folders mount at their host path. Relative paths resolve from the file's folder.
    - **sbx mounts `sbxenv.yaml` itself read-only** inside the project, so the agent cannot change it from the sandbox. The kit folder stays writable.
    - `sbx ls --json` gains `ports` and `mounts`. `workspaces` lists the project first, then the extras (`:ro` when read-only), then the env file (`:ro`). It does not name the kits.
  - **Image environment:**
    - The mixin's `ENV` reaches every process, with PATH appended.
    - `/etc/sandbox-persistent.sh` exists (empty) with `BASH_ENV` pointing at it.
    - `WORKSPACE_DIR`, `SANDBOX_NAME`, and `SBX_AGENT` are set at start.
  - **Hooks:**
    - Install hooks run once at create, with the install-phase hosts open (example.org 200). Those hosts are closed afterwards (403).
    - Startup hooks run at create, before `create` returns, and on every start.
    - Logs go to `/var/log/sbx-kits` and `/var/log/sbx-kit-startup.log`.
  - **Network:**
    - A kit's runtime allow works (200), and an unlisted host is 403.
    - A bounded entry (GET `/get` on httpbin.org) allows that path and refuses another (403).
    - **A sandbox deny (`sbx policy deny network --sandbox N host`) beats a kit allow (403).** So per-host decline works.
  - **Policy list:**
    - All kits' hosts, the workload's Anthropic hosts included, are one allow rule named `kit:<sandbox>` (`provisioned`, not editable).
    - Each bounded entry is an `http` rule `kit:<sandbox>:http:N` with `methods` and `http_targets`.
    - **The implicit `default-deny-all` rule is listed without `policy_id` or `provenance`** (PAD-77).
  - **Optional capabilities:** an `optional: true` capability sbx does not support (host-port@1) is skipped silently.
  - **Built-in claude:** `claude` is the v3 kit `docker.io/sbx/claude`, and it combines with a local v3 mixin (`sbx create --kit <dir> claude <folder>` worked, agent `claude`).
  - **sbx's Claude kit** seeds `~/.claude/settings.json`:
    - `permissions.defaultMode: bypassPermissions`
    - its own hooks (`sbx-claude-hook` on Stop, StopFailure, UserPromptSubmit, Notification) and a status line
  - **Default size:** 18 CPUs and 32 GiB of memory on this Mac.
  - **The plan for the project file alone,** against the sandbox the overlay made, marks the sandbox, kits, and ports "present, not recorded as applied, needs your approval". It does not mention the overlay's env.
- **Paddock's kits on sbx 0.51** (`mise run capture:cli kits`, first try): two refusals.
  - `agent-context@2 is not selected: this kit set uses com.docker.sandbox/agent-context@1, and the two cannot compose`. sbx's claude and playwright kits use @1.
  - `duplicate kit name "opencode"`: a local kit is named after its folder, and the built-in `opencode` is a kit (`docker.io/sbx/opencode:latest`).
  - Both are fixed (`paddock-<kit>` folders, @1).
  - Without OpenAI credentials, sbx warns that opencode starts logged out (`sbx secret set openai`).
- **Paddock's kits on sbx 0.51, third try** (each kit alone, with progress):
  - `status`, `voice`, and the gateway kit each created a sandbox. The browser kit failed.
  - **The agent images have no Node:**
    - `npm: not found` (Paddock's browser kit).
    - `env: 'node': No such file or directory` (sbx's own Playwright kit, `docker.io/sbx/playwright:1.61.1`, on `claude`).
    - The status and voice hooks report success only because their Node step falls back to a warning.
    - Neither sbx nor Docker publishes a Node kit, so Paddock ships `node` (backlog doc Kits).
  - **Gateway without a kit:** `claude` with environment only (`ANTHROPIC_AUTH_TOKEN=paddock` and the base URL) answered through a stand-in gateway (`tools/tasks/lib/fake-anthropic.py`). It sent `Authorization`, not `x-api-key`, with no prompt in `-p` mode. sbx's claude kit had set `hasCompletedOnboarding`.
  - **sbx's own Claude hook** (`/usr/local/bin/sbx-claude-hook`, 14 KB, on Stop, StopFailure, UserPromptSubmit, Notification) shows nothing in `sbx events`: a run produced only lifecycle, port, and network events. Its content is not read yet.
  - **OpenCode with `paddock-status`:** created. sbx's opencode kit runs OpenCode 2.0.29. `OPENCODE_DISABLE_AUTOUPDATE` came from Paddock's old opencode kit, so without it OpenCode may offer its own upgrades (not checked).
- **Paddock's kits on sbx 0.51, fourth try** (with the node kit):
  - `status` and `voice` install, and their Node steps now run (25-45 ms instead of the 7 ms of a missing node).
  - The browser kit got through npm (`playwright-cli`, 43 s) and sbx's Playwright apt step (33 s).
  - It then failed on `playwright-cli install --skills claude`: `EROFS: read-only file system, mkdir '/home/agent/.claude/skills/playwright-cli'`. sbx mounts its shared agent-skills folder there read-only, so that step is best-effort now.
  - **sbx's own Claude hook** (`sbx-claude-hook`) forwards Stop, Notification, and prompt events, and the status line, as MCP `tools/call`s to the sbx Desktop app through the sandbox's MCP gateway (`MCP_GATEWAY_URL`). Paddock cannot read that, so it keeps its status kit. On the operator's Mac the Homebrew cask's `Sbx.app` only wraps the CLI (opening it shows nothing), and no sbx Desktop app is installed. The hook finds no server and does nothing (2026-11-04).
  - OpenCode (sbx's kit, 2.0.29) leaves `OPENCODE_DISABLE_AUTOUPDATE` unset. Paddock sets it at create.
- **Paddock's kits on sbx 0.51, all working** (`mise run capture:cli kits browser,claude`, 2026-11-04), on `claude` with node, playwright, browser, status, and voice, plus the gateway as environment:
  - Node v26.13.0 and npm 11.20.0, once the node kit also copied libatomic.so.1.
  - All seven Paddock commands are on PATH: paddock, the browser and voice watchers, paddock-agent-state, paddock-agent-watch, paddock-voice, and playwright-cli.
  - Paddock's 12 Claude hooks are merged into settings.json beside sbx's own.
  - `paddock-agent-state` writes its session file.
  - The dashboard answers on 38323 with its `/index.html?ws=...` redirect.
  - The kit's `port@1` is published on both `127.0.0.1` and `::1`, `protocol: "tcp"` (fixture `ports-v3-dashboard.json`).
  - playwright-cli's skill went to `~/.agents/skills` only, since `~/.claude/skills` is read-only.
- **Not seen yet:**
  - `sbx env run` with only the project file, against a sandbox an overlay made
  - `target` for an extra folder
  - clone mode
  - whether Paddock's v2 kits still combine with the built-in claude, which is now v3 (PAD-73.2)
