---
id: PAD-73.1
title: Capture sbx 0.51 v3 and sbx env output on the Mac
status: In Progress
assignee: []
created_date: '2026-11-04 09:31'
updated_date: '2026-11-04 12:49'
labels: []
dependencies: []
parent_task_id: PAD-73
priority: high
type: spike
ordinal: 74000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Fixtures come first (CLAUDE.md). Nothing about v3 kits or `sbx env` has been run, and the docs disagree in places. The Hub page for `docker/sbx-kit-claude` says it fails with `agent "claude" is already registered`, while the 0.51 notes suggest that is fixed. `sbx kit add` on v3 sandboxes is also described differently in two places. The shapes Paddock will parse are unknown: whether `sbx env plan` has JSON output, and what `sbx ls --json` reports for a v3 sandbox (its kits?).

Use `scratch/sandbox/v3/` (or a copy under `scratch/` per the test-workspace rule) as the test project. Its README lists six checks in order.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 sbx >= 0.51 version output is captured as a fixture next to `Fixtures/sbx/version.json`
- [x] #2 `sbx env plan` output (JSON if it has a JSON mode) for a project file with a local mixin kit, and for one with an error, is captured under `Fixtures/sbx/`
- [x] #3 `sbx ls --json` for a sandbox made by `sbx env create` is captured, and the fixture notes whether it names its kits and env file
- [ ] #4 The README checks in `scratch/sandbox/v3/` are answered: kit dir loads, sbx-kit-claude loads, mixin ENV reaches the agent Bash tool, `${{ kit.env.WORKSPACE_DIR }}` expands, host-port@1 reaches a Mac loopback service, the permission mode can be changed
- [x] #5 Merging two explicit files (project plus overlay) is checked: kits concatenate, `--skip-host-commands` skips `lifecycle`, and whether `~/.sbxenv.yaml` is skipped
- [x] #6 Findings are written into backlog doc M0 findings
- [x] #7 `additionalWorkspaces` is checked and captured: `sbx ls --json` `workspaces` with an extra folder, read-only and writable (how `readOnly` shows), where it is mounted inside (same path, or `target`), with `--clone`, and what a relative path resolves to
- [ ] #8 What `sbx env plan` and `sbx env run` with only the project file do to a sandbox created with the project file plus an overlay (attach, report a difference, or recreate) is recorded
- [x] #9 `${{ kit.env.WORKSPACE_DIR }}` expands in lifecycle `files` content, and the lifecycle startup hooks' output and duration are visible to the client (for a progress view)
- [x] #10 Kit network rules: how they show in `sbx policy ls --json` for a v3 sandbox, whether a sandbox deny overrides a kit allow, and whether lifecycle startup hooks run during `sbx env create` before Paddock can add denies
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Capture phase written: `mise run m0 v3` (scripts/m0-capture.sh phase_v3). It builds a throwaway project in scratch/m0/<run>/v3 (sbxenv.yaml with the v3 Claude workload, a probe mixin using network-policy@2 incl. a bounded entry, host-port@1, lifecycle files/install/startup, agent-context@2, a FROM scratch dockerfile with ENV; two extra folders ro/rw; an overlay; a broken file), and captures plans (text, --json, --format json), create with --skip-host-commands --force, sbx ls/policy ls/ports, env and files inside, network probes incl. a sandbox deny over a kit allow, the plan without the overlay, stop/start hooks, a v3 mixin on built-in claude, and env rm. Raw output lands in m0/raw/v3-*; sanitize-fixtures.py has no v3 rules yet, to be written once the shapes are seen. Set M0_CLAUDE_KIT to try another workload reference.

First run (2026-11-04, operator Mac, sbx v0.49.2, kit builder sandbox-kit 3.0.0-m.11):
- `sbx env` and local v3 kits exist on 0.49.2 already. The build used the Mac's Docker Desktop buildx.
- The probe kit failed to build: sbx requires a version on every `provides` entry (`name@x.y.z` or a top-level `version:`), which kit.schema.json does not require. Fixed in the probe, the example project, and SandboxFiles; ProjectEnvironment now reports it. Nothing after create ran, because no sandbox existed.
- `sbx env plan` has no `--json` or `--format`: text only, so Paddock cannot parse it (CLAUDE.md).
- The plan lists workspaces as "needs your approval". sbx keeps its own approval record, and `--force` approves for one run.
- The plan says "this plan runs commands on this machine" for `lifecycle`. With `--skip-host-commands` that section is left out and the command did not run (marker file absent).
- An unknown key fails as `<file>:3:1: unknown field "notAField"`.
- sbxenv `ports` show as `3000/tcp4 host: 18998`.
- The v3 mixin on built-in claude failed at the same build step, so v2/v3 mixing is still untested.
Next: upgrade sbx to 0.51 (`brew upgrade docker/tap/sbx`) and run `mise run m0 v3` again.

Second run (2026-11-04, sbx v0.51.0, API 0.49.0): the probe kit now builds (2s, cached afterwards as sbx-kit-src:probe-<hash>).
- Create failed at kit resolution: `capabilities[2].config.files[0].content: final container environment has no variable "WORKSPACE_DIR"`. So `${{ kit.env.NAME }}` is filled from the final image's environment when the sandbox is built, and WORKSPACE_DIR is not in it. The kits-v2 migration table's `${WORKDIR}` -> `${{ kit.env.WORKSPACE_DIR }}` does not hold. The probe and the example project now read `$WORKSPACE_DIR` from the shell in a startup hook; the probe dumps the startup env to check that it is set.
- sbx 0.51 prints `claude — now ships as a kit; resolving docker.io/sbx/claude:latest` for the built-in agent. The built-in claude is a v3 kit now, so `agent: claude` may replace `sbx-kit-claude`, and Paddock's v2 kits on top of it may no longer combine (PAD-73.2).
- `sbx env plan` is still text only. The plan without the overlay matches the plan with the project file alone.
Next: run `mise run m0 v3` again.

Third run (sbx 0.51.0): the probe built, then kit resolution refused `host-port@1` with "required capability selection rejected ... unsupported capability type com.docker.sandbox/host-port@1", although the schema has it. Removed from the example project, SandboxFiles, and ProjectEnvironment's allowlist (now refused). The probe keeps it as `optional: true`, to see whether sbx skips an optional capability it lacks. The v3 mixin on the built-in claude (docker.io/sbx/claude:latest) failed the same way, so mixing is still unseen. Next: run `mise run m0 v3` again.

Fourth run (sbx 0.51.0) created the sandbox; the results are in backlog doc M0 findings, "fourth run". The fixtures are saved and sanitized:
- Fixtures/sbx/ls-v3.json and policy-ls-v3-sandbox.json, with decode tests in SbxV3ShapeTests. The policy fixture surfaced PAD-77.
- version-0.51.json.
- env-plan-overlay.txt, env-plan-after-overlay-create.txt, env-plan-broken.stderr.txt, and env-create.txt: plan text, for reference only.
AC 9 is answered in the negative: `${{ kit.env.WORKSPACE_DIR }}` does not expand (sbx refuses it). Startup progress shows only in `sbx env create`'s text output, plus /var/log/sbx-kit-startup.log in the sandbox.
Still open:
- AC 4: changing the permission mode. sbx's claude kit seeds bypassPermissions.
- AC 8: `sbx env run` with the project file alone against an overlay-made sandbox. The plan only says "needs your approval".
- Extra folder `target`, and clone mode.
The script now also removes the -v2mix sandbox; an earlier run left m01793796184-v2mix behind on the Mac.
<!-- SECTION:NOTES:END -->
