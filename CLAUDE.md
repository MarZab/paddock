# Paddock

Native macOS (SwiftUI) dashboard for Docker Sandboxes (sbx): one microVM per project folder, an agent (Claude Code or OpenCode in a terminal; OpenHands is deferred), a sandbox shell, and models through sbx's bundled llmman (its web UI is embedded), in one window. Design docs (the app as it is): `backlog/docs/`. Work still to do: Backlog.md tickets.

## Start here

Pick work from Backlog.md (`backlog task list --plain`, `backlog task view PAD-N --plain`) and read the docs it names (`backlog doc list --plain`, `backlog doc view doc-N`). **Fixtures come first:** capture real CLI output into `Packages/PaddockCore/Tests/PaddockCoreTests/Fixtures/` before writing any parser. Ask the operator to run commands on their Mac when needed; do not guess JSON shapes.

## Commands

- Dev tools: `mise install` (versions pinned in `mise.toml`; Xcode is installed separately)
- Tasks are mise file tasks in `tools/tasks` (`tools/tasks/README.md`; `mise tasks` lists them, `mr` is `mise run` where mise is activated). Helpers a task uses but that are no task go in `tools/tasks/lib`, not executable, so mise does not list them.
- Generate project: `mise run generate`
- First build in a fresh checkout: open `Paddock.xcodeproj`, build once, and approve SwiftTerm's build plugin (Trust & Enable). Never pass `-skipPackagePluginValidation`.
- Build: `mise run build`
- Install (Release build into `/Applications`, personal use, ad hoc signed): `mise run install`
- Tests: `mise run test` (arguments go to `swift test`, e.g. `--filter AppVersion`). Each run's whole output is kept in `.tmp/test-runs/` (`latest.log` is the newest): read it there when the operator ran the tests on the Mac.
- Lint / format: `mise run lint`, `mise run fmt`
- Captures (on the Mac): `mise run capture:cli readonly` (sbx and llmman CLI), `mise run capture:socket probe` (sandboxd socket), then `mise run capture:fixtures` for the sanitized fixtures
- Hang capture (on the Mac, while Paddock is stuck): `mise run hang [--dev] [--spindump]` (`--dev` for Paddock Dev), into `.tmp/hangs/`
- Local output and test workspaces mounted into sandboxes always live in `.tmp/` (gitignored): builds, test runs, captures, hang captures, trial projects. `mise run clean` removes builds, caches, and test runs (`--all` also captures; `-n` lists first); it fixes a SwiftPM cache from a moved checkout.
- Backlog: `backlog` (pinned in `mise.toml`); `backlog board` or `backlog browser` to look around
- In a sandbox on this repo (Linux, `sbxenv.yaml` and `tools/sandbox/paddock`; on the Mac, `mise run sandbox:plan`, `sandbox:create --replace`, `sandbox:run`, `sandbox:rm` work without Paddock): Swift's libraries are installed by the kit but not the toolchain; run `mise install` once for the Linux tools in `mise.toml` and `mise run swift-linux` once for Swift, then `mise run test` and `mise run lint`. Building the app (Xcode, xcodegen) and anything that needs sbx happen on the Mac.

## Backlog and commits

- Every change has a ticket. Search first (`backlog search "..." --plain`); create one if there is none, with a description and acceptance criteria a later agent can act on without this conversation.
- Every commit message starts with its ticket ID, then the conventional type: `PAD-12 feat(app): show the gateway's log`. A commit that spans tickets names the main one.
- Move the ticket to In Progress when work starts, check its acceptance criteria and set it Done (with a final summary) in the commit that finishes it, so the ticket and the code land together.
- The docs describe the app as it is. A commit that changes behavior updates the matching doc (`backlog doc update doc-N --content ...`) in the same commit. Anything found missing or unverified becomes a ticket, and the doc names it (`(PAD-N)`).
- Code comments point at docs by title: `(backlog doc Browser, OpenUI tabs)`.
- Use the `backlog` CLI for tasks, docs, and milestones; never edit their markdown files by hand.
- A change the operator would notice adds one line to `CHANGELOG.md` under Unreleased, in the same commit: `- PAD-N what changed.` Terse: one short sentence, no details (they are in the ticket); refactors and docs-only changes get none.

## Architecture rules

- All logic lives in `Packages/PaddockCore` (no UI imports). `App/` only contains views and view models.
- Swift 6 with strict concurrency. Services are `actor`s; view models are `@Observable` and `@MainActor`.
- Shell out only through the `ProcessRunner` protocol. Tests use a fake runner that returns fixtures.
- sbx: use `--json` / `--format json` only. Never parse human-readable tables. Require sbx >= 0.51 (its built-in agents are v3 kits, and so are Paddock's; PAD-73.2).
- sbx reads (`SbxReads`: sandboxes, rules, network log, approvals, events) may come from sandboxd's socket instead (`SandboxdReads`, GET only, through `SandboxdTransport`), only while `/daemon/health` reports a captured API version; `FallbackSbxReads` answers with the CLI otherwise. Every command that changes something stays an sbx command. Socket shapes come from `tools/tasks/capture/socket.py`, with fixtures next to the CLI output for the same request.
- Models: use sbx's bundled llmman. Do not build a model manager; embed llmman's web UI. Paddock's own llmman code is read-mostly (`/api/version`, `/api/tags`, `/api/ps`, `/llmman/node`, `GET /llmman/shell` status). Agents get models only through Paddock's ModelGateway; never pass sbx `--model` (it opens llmman's whole API to the sandbox).
- Every CLI or API response gets a typed `Codable` model and a fixture-based test.
- No dependency management: the app never installs or updates sbx, Docker, model servers, or anything else. It detects them and shows example `brew` commands for the operator to run.
- No force unwraps. Surface errors in the status bar and log drawer.

## Security rules (non-negotiable, each needs a test)

- Only the operator-chosen project folder, and extra folders the operator added in Paddock (read-only unless switched), are ever mounted into a sandbox. sbx allows mounting any path by default, so FolderPolicy is the only guard: every extra folder passes it like a project folder, when added and again at every create, and may not overlap the project folder or another extra folder (`ExtraFolders`). Nothing in a project folder can add one.
- A sandbox's network is sbx's global rules plus the hosts of its project's `sbxenv.yaml` kits, which take effect only after the operator confirmed the file (and the project's own kits, by fingerprint) in a sheet that shows them next to the global rules; each runtime host the operator declines becomes a sandbox deny. Paddock refuses a project file that runs commands on the Mac (`lifecycle`), sets secrets or credentials, names a kit that is neither sbx's catalog nor the project's own, or asks a capability Paddock does not accept (`ProjectEnvironment`). Paddock adds rules of its own only to protect its own services: always deny llmman's port, and deny other projects' gateway ports whenever an allow reaches them. Paddock never changes sbx's global rules on its own (not in Sync or any automatic step). The exception is the operator: an action they take in Paddock's interface may change sbx, global rules included, with a confirmation when it affects every sandbox.
- Reject project folders that are `$HOME` or `/`, contain or sit inside `.ssh`, `.aws`, `.gnupg`, `Library`, or the other `FolderPolicy.sensitiveEntries`.
- Reject project folders that are, contain, or are inside Paddock's config dir (`~/.config/paddock` or its XDG override).
- Agents reach models only through the ModelGateway: loopback listener, route allowlist (`/v1/messages`, `/v1/chat/completions`, `/v1/responses`, `/v1/models`), one listener port per project (the port identifies the project; there are no gateway tokens), model pinning, upstream fixed to llmman. Each sandbox also gets an sbx HTTP rule for its own gateway port only (`--method POST,GET --path '/v1/**'`) and a deny for llmman's port. No `sbxenv.yaml` port, kit host, or host rule may name llmman's port or a gateway port, and two projects never share one.
- The gateway never logs request or response bodies or headers.
- Embed llmman's web UI and allow local models only while every llmman hardening check is green, especially `GET /llmman/shell` returning `{"enabled": false}`. Never open the shell's WebSocket.
- Paddock's kits come only from `paddock.yaml` `kits`, and a local one there may not be inside a project folder. A project's `sbxenv.yaml` may name only sbx's catalog kits and its own local kits inside its folder, and those are confirmed by the operator with the file.
- The browser an agent drives runs inside its sandbox, never on the Mac. The Playwright and show tabs' web views keep no data and may reach only the dashboard's loopback origin.
- Content from a sandbox renders on the Mac only in a native show tab: the agent asked for it (`paddock --native`), the tab is marked by color, and nothing loads until the operator opens it. It loads only the shown file's folder through `paddock-file://`, never the network.
- An interactive tab (`paddock ui`) renders the agent's OpenUI Lang document as data with OpenUI's renderer vendored in the app: no code from the sandbox runs, the page loads only the app's renderer files, never the network, and opens nothing on the Mac. What the page sends back is checked before it reaches the sandbox.
- Restart sbx's daemon (for llmman hardening) only after operator confirmation.
- Paddock stores no secrets and manages no agent logins or API keys: those belong to sbx (`sbx secret`). Gateway sandboxes use a fixed dummy key (`paddock`). Never log a secret or pass one in argv.
- App Sandbox stays off; Hardened Runtime stays on.

## Style

- No em dashes in code comments, docs, or UI strings; use hyphens.

<!-- BACKLOG.MD GUIDELINES START -->
<!-- backlog.md-instructions-version: 1.54.0 -->
<CRITICAL_INSTRUCTION>

## Backlog.md Workflow

This project uses Backlog.md for task and project management.

**At the beginning of each conversation in this project, run `backlog instructions overview` before answering or taking action. Re-read it only if you have not read it yet in the current conversation.**

Use the overview to decide whether to search, read, create, or update Backlog tasks.

Before task lifecycle actions, read the matching detailed guide:
- `backlog instructions task-creation` before creating or splitting tasks
- `backlog instructions task-execution` before planning, changing status or assignee, adding a plan or implementation notes, or implementing task work
- `backlog instructions task-finalization` before checking acceptance criteria, writing final summaries, or moving tasks to terminal statuses

Use `backlog <command> --help` before running unfamiliar commands. Help shows options, fields, and examples.

Do not edit Backlog task, draft, document, decision, or milestone markdown files directly. Use the `backlog` CLI so metadata, relationships, and history stay consistent.

</CRITICAL_INSTRUCTION>
<!-- BACKLOG.MD GUIDELINES END -->
