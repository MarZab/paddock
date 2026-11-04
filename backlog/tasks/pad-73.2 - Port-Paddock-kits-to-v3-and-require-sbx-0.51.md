---
id: PAD-73.2
title: Port Paddock kits to v3 and require sbx 0.51
status: In Progress
assignee: []
created_date: '2026-11-04 09:31'
updated_date: '2026-11-04 14:17'
labels: []
dependencies:
  - PAD-73.1
documentation:
  - doc-8
  - doc-4
parent_task_id: PAD-73
priority: high
type: feature
ordinal: 75000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
v3 kits do not combine with v1/v2 ones, so a project on the v3 Claude workload cannot get the status, setup, browser, voice, opencode, or gateway kits as they are built today (v2, on the built-in agents). sbx's own playwright kit has a v3 build (`docker.io/sbx/playwright`).

Notes for the worker:
- The gateway's rule (POST and GET to `/v1/**` on its own port only) may fit `network-policy@2` entries with `methods` and `paths`. It is not checked whether a host entry can carry a port; if it cannot, keep the sbx rule Paddock adds today.
- llmman's port deny must stay.
- OpenCode needs a v3 workload, or Paddock's own if there is none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Each of Paddock's kits is a v3 mixin (or workload where it must be) and passes `kit.schema.json` in a test
- [ ] #2 A Claude Code project and an OpenCode project are created on v3 workloads with the status and setup kits, and agent state reaches the app
- [x] #3 A local-model project still reaches models only through its own gateway port; llmman's port stays denied (security tests updated)
- [x] #4 Paddock requires sbx >= 0.51 and says so when it is older
- [x] #5 backlog doc Kits, ModelGateway, and Security rules describe the v3 kits; existing v2 sandboxes show as needing a recreate
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Setup kit after the move (operator asked 2026-11-04 whether it is still needed): keep it, but as a v3 mixin with only agent-context (no install step, no example files on disk). It teaches what sbx docs cannot: what Paddock refuses in sbxenv.yaml and project kits (ProjectEnvironment), that changes need confirmation and a recreate, and the PAD-71 build-output guidance. The .paddock.toml and Dockerfile teaching goes.

Superseded (2026-11-04): the setup kit is removed instead of ported. Paddock generates sbxenv.yaml and the project kit with Paddock's rules as comments and the build-output guidance in the kit's agent-context (PAD-73.3). Agents read sbx's online docs for the formats; docs.docker.com must be reachable for that.

From the PAD-73.1 fourth run (sbx 0.51): the built-in `claude` is the v3 kit docker.io/sbx/claude (agent name stays `claude`), and a local v3 mixin combines with it. So the workload can be plain `claude`, not docker.io/docker/sbx-kit-claude. It follows that Paddock's current v2 kits on `claude` may fail to create on 0.51; check this first. sbx's Claude kit installs its own Claude hooks (`sbx-claude-hook` on Stop, StopFailure, UserPromptSubmit, Notification) and a status line. Paddock's status kit has to merge beside them, and their reporting could replace part of it.

Ported (2026-11-04), not yet run on the Mac:
- gateway, opencode, status, browser, and voice are v3 mixins: `<config>/kits/<name>/<name>.yaml` (KitFile.file), with `version: 1.0.0` and `provides: [paddock-<name>]`.
- Environment goes through args with `env`; network through network-policy@2 (browser only); the dashboard through port@1; hooks through lifecycle@1; instructions through agent-context@2.
- Install hooks name the environment they need (PATH, HOME, proxies) and write out /home/agent.
- The gateway's .config.json is written at start (it needs WORKSPACE_DIR), once.
- The setup kit is removed; KitSelection.removed drops it from projects that chose it.
- playwright and mise now point at sbx's v3 builds (sbx/playwright:1.61.1, sbx/mise:2026.5.2, pinned by digest). An entry without source names docker.io/sbx/<name>.
- The minimum sbx is 0.51.
All five pass kit.schema.json: run `PADDOCK_DUMP_KITS=<dir> swift test --filter dumpTheKitsWhenAsked`, then validate outside the tests. Next: `mise run m0 kits` on the Mac.

m0 kits, second try (2026-11-04, sbx 0.51.0):
- opencode + paddock-opencode + paddock-status created. The status plugin is in place and OPENCODE_DISABLE_AUTOUPDATE=1 is set.
- OpenCode reports v2.0.29, not the pinned 2.1.4. sbx's v3 opencode kit ships OpenCode 2 itself, and the kit's install did not replace it; the next run captures the install log. The kit may no longer be needed.
- claude + playwright + browser + status + voice + gateway failed: "error: failed to apply kit to sandbox", with no detail under --no-progress.
- The capture now tries each kit alone, with progress, keeps sbx's daemon log tail (redacted) on a failure, and collects /var/log/sbx-kits from the sandboxes.

Operator (2026-11-04): ship no custom kit that is not needed.
- Removed: the opencode kit. sbx 0.51's own opencode kit ships OpenCode 2, and projects drop it through KitSelection.removed. The paddock-gateway trial passes no kit for OpenCode.
- Under test (`mise run m0 kits`):
  - The gateway with environment only: ANTHROPIC_AUTH_TOKEN in place of the pre-approved API key, against scripts/m0-fake-anthropic.py.
  - sbx's own `sbx-claude-hook` and `sbx events`, to see whether sbx reports agent state, which could replace the status kit.
- Kept: browser (playwright-cli, paddock, watcher, dashboard) and voice (paddock-voice); sbx has nothing for either.

Third m0 kits run (2026-11-04), results in backlog doc M0 findings:
- The agent images have no Node, so the browser kit and sbx's Playwright kit fail at install, and the status and voice hooks silently do nothing. Added the `node` kit (NodeKit, `node:24.22.2-bookworm-slim` by digest, FROM scratch recipe). status, browser, and playwright need it; chosenKits adds missing needs for older projects.
- The gateway kit is removed. ClaudeGateway sets ANTHROPIC_AUTH_TOKEN=paddock plus the quiet settings at create; checked with claude -p against scripts/m0-fake-anthropic.py.
- sbx's own Claude hook reports nothing through `sbx events`, so the status kit stays for now. The next run reads the hook's content.
Remaining kits: node, status, voice, browser (plus sbx's playwright and mise).

Fourth m0 kits run: status and voice work with node. The browser kit failed only on `playwright-cli install --skills claude` (~/.claude/skills is sbx's read-only shared skills mount), so that step is best-effort now. Shipping the skill through agent-skill@1 (an in-image skill directory) is a possible follow-up. sbx-claude-hook talks only to the sbx Desktop app over the MCP gateway, so the status kit stays. OPENCODE_DISABLE_AUTOUPDATE=1 is now set at create for OpenCode.

Fifth m0 kits run: Node 26 needs libatomic.so.1, which the agents' images lack ("node: error while loading shared libraries: libatomic.so.1"), so npm and sbx's Playwright install failed. Node 24 did not need it. The node kit now copies libatomic.so.1 from the same image into /usr/lib/<triplet>. The Dockerfile is not built outside the Mac (there is no Docker in the dev sandbox).

Sixth m0 kits run (browser,claude) passed. With node, playwright, browser, status, voice, and the gateway environment on sbx 0.51's claude, everything installed and ran; see backlog doc M0 findings. AC1: the four kits pass kit.schema.json (dumped by a test, validated outside it) and sbx accepted them. AC3: GatewayPolicy drops Authorization (test), and llmman's port deny is unchanged. AC2 waits on Paddock itself on the Mac: create a Claude and an OpenCode project and see agent state in the app.
<!-- SECTION:NOTES:END -->
