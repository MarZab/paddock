---
id: doc-1
title: Overview
type: specification
created_date: '2026-10-25 15:55'
updated_date: '2026-11-06 08:33'
---
## Goal

A native macOS app that runs local coding agents safely from one window:

- **Docker Sandboxes (sbx)** microVMs, one per project folder.
- **Models through sbx's bundled llmman** (local models with llama.cpp or MLX), with llmman's own web UI embedded for model management. Agents reach models only through **Paddock's model gateway**, which forwards inference requests and nothing else.
- **Agent per project:** Claude Code or OpenCode (both built-in sbx agents), in an embedded terminal. OpenHands is deferred (doc: OpenHands (deferred), PAD-21).
- **Sandbox shell:** a terminal inside the sandbox.

**Trust model:**

- **Trusted:** Paddock, sbx (sandboxd), and llmman, which ships with sbx and is started by sandboxd on the host. Paddock does not sandbox llmman; it checks that llmman is hardened (see Models).
- **Untrusted:** agents, everything inside a sandbox, and every file in a project folder (including `sbxenv.yaml` and the project's own kits).
- Agents only ever see the folder the operator picks. Their network is sbx's global rules plus the hosts their kits ask for, the project's own `sbxenv.yaml` kits once the operator confirmed them, and they reach models **only through Paddock's model gateway**, never by connecting to llmman's port directly.

**Non-goals for v1:** App Store distribution, cloud sandboxes, multiple users, OpenHands (deferred), a native model manager (llmman's UI is reused), sandboxing the model server.

## Host prerequisites

- macOS 26+ (Apple Silicon; voice uses SpeechAnalyzer), Xcode 26+ (developed with Xcode 26.6 and Swift 6.3.3)
- sbx >= 0.51 (the JSON output shape changed in 0.48; from 0.51 the built-in agents are v3 kits, and Paddock's kits are v3 to combine with them, PAD-73.2; operator has v0.51.0). llmman comes with it.
- Dev tools via `mise install` (see `mise.toml`)

## Dependencies are the operator's job

The app never installs, updates, or downloads dependencies (no bundled binaries, no installer scripts, no auto-update). It only detects them:

- On launch, `DependencyCheck` (PaddockCore) resolves each required binary through the ProcessRunner lookup paths and checks its minimum version.
- Anything missing or too old turns the status button yellow and opens its checks, with the reason, the required version, and a copyable example install command. The operator runs it in their own terminal and clicks Refresh.
- Example commands are documentation only, never executed by the app. They live in one table in PaddockCore (`DependencyCheck`) so the README (PAD-14) and the UI stay in sync:

| Dependency | Min version | Example install |
|---|---|---|
| sbx (Docker Sandboxes, includes llmman) | 0.51 | `brew install docker/tap/sbx` (a cask: `/opt/homebrew/bin/sbx` links into `Caskroom/sbx/<version>/Sbx.app`) |
| XcodeGen (dev only) | - | `mise install` or `brew install xcodegen` |

- Docker on the host is **not** needed (images are built inside a sandbox), and neither is a separate model server.
- llmman downloads its own engines (llama.cpp from GitHub, `uv` and `mlx-lm` from PyPI) when sandboxd starts it. That is sbx's behavior, not Paddock's.

## Repo layout

```
paddock/
  project.yml                 XcodeGen spec (app target, hardened runtime, no App Sandbox)
  mise.toml                   Dev tools (including the backlog CLI) and tasks
  CLAUDE.md                   Agent instructions
  backlog/                    Backlog.md: these docs, tickets (PAD-N), milestones
  App/                        SwiftUI views and view models (AppModel), app entry, windows
    OpenUI/                   Host page and vendored OpenUI renderer for interactive tabs
  Packages/PaddockCore/       All logic, no UI, unit-tested with `swift test`
    Sources/PaddockCore/
      Process/                ProcessRunner, BinaryLocator, LineStreamer
      Setup/                  DependencyCheck, StatusProbe
      Config/                 AppConfig (paddock.yaml), Kits, PaddockPaths
      Models/                 LlmmanAPI, LlmmanHealth, LlmmanModels, LlmmanWebPolicy
      Gateway/                ModelGateway, GatewayRoutes, GatewayHost (one listener per project)
      Sbx/                    SbxService, SbxReads, FallbackSbxReads, Sandboxd/ (socket reads),
                              SbxEventStream, PolicyPlanner, HostPattern
      Environment/            SbxEnvFile (sbxenv.yaml), ProjectEnvironment (its checks), EnvironmentReview,
                              PaddockOverlay, SandboxFiles, ProjectKitFile, SbxKitDescriptor
      Projects/               ProjectStore, NewProject, ProjectRunner, SandboxSync, Ports, PortsTable,
                              RulesTable, HostRules, ApprovalRequests, ActivityTimeline, ExternalShell
      Agents/                 AgentLaunch, ClaudeGateway, KitFile, NodeKit, BrowserKit, BrowserActivity, VoiceKit,
                              BrowserShow, BrowserCapture, BrowserWebPolicy, NativeShowPolicy, OpenUIPolicy
      Voice/                  VoiceMessage, SpokenText, VoiceKeywords (and VoiceChoice, BracketedPaste), SpeechQueue
      Security/               FolderPolicy, ExtraFolders
      Support/                JSON and YAML coding, SemanticVersion, LogEntry
      Resources/              openui-reference.md (installed in sandboxes)
    Tests/PaddockCoreTests/
      Fixtures/               Real sbx, sandboxd, and llmman output from the operator's Mac (sanitized)
  Packages/PaddockShell/      Reusable sandbox shell SDK: PaddockShellCore, PaddockShellUI, CPaddockPTY
  tools/tasks/                mise file tasks (build, test, lint, version, capture:cli, capture:socket, ...); lib/ holds their helpers
  tools/sandbox/paddock/      This repo's own sbx kit (with sbxenv.yaml at the root)
  .tmp/                       Local output (test runs, hang and M0 captures) and test workspaces mounted into sandboxes (gitignored)
```

## Docs

One doc per part of the app, each describing what the app does today. Work that is missing or unverified is a ticket (`backlog task list --plain`), and the docs name the ticket where it matters.

- **Overview** (this doc), **ProcessRunner**, **Models** (llmman and its hardening), **ModelGateway** (with agent wiring), **SbxService** (commands, socket reads, events), **Network policy**, **Kits**, **Browser** (Playwright, show, and interactive tabs), **App config** (paddock.yaml, where state lives, Sync), **Project config file** (sbxenv.yaml), **PaddockShell**, **ProjectStore**, **Security rules**, **UI**, **Voice**, **OpenHands (deferred)**, **M0 findings** (what the CLI contract spike verified, and references).

## Status

What works today, by the original milestones:

| # | Scope | State |
|---|---|---|
| M0 | CLI contract spike: sbx JSON shapes, llmman's address, auth, and hardening, `--model` reachability, HTTP rules, `-e`, custom images, per-sandbox denies, sbx's model kits | Done. Fixtures committed; findings in M0 findings |
| M1 | App shell, ProcessRunner, DependencyCheck, AppConfig, status | Done 2026-10-24 |
| M2 | LlmmanAPI, LlmmanHealth checks, embedded llmman UI | Done 2026-10-24: badges correct on the Mac, the UI loads, its shell tab is blocked, Clear history works |
| M2.5 | ModelGateway: routes, one port per project, pinning, limits, streaming, metadata log; sbx HTTP rules per sandbox | Done 2026-10-24 with the gateway trial, and in the app since M3. The metadata log is not shown yet (PAD-11) |
| M3 | Projects: create, start, stop, remove; PolicyPlanner; ports in both directions; events | Done: project files, New Project sheet, live states from events and sandboxd's socket, the gateway in the app, ports on the Info tab, the Network and Filesystem pages, approval requests |
| M3.5 | A project's own setup, approval on change | Since PAD-73: sbx's `sbxenv.yaml` and the project's own v3 kits, confirmed in a sheet (each host may be declined), created with `sbx env create` and Paddock's overlay. Paddock's image builds and `.paddock.toml` are gone. Written and tested on Linux; the app side is not built on the Mac yet (PAD-73.3) |
| M4 | Agent pane and PaddockShell (SDK and terminal tabs) | Done 2026-10-24, with split view, tab drag, titles, Open in Terminal |
| M5 | Claude Code and OpenCode, agent default and local through the gateway | Claude Code through the gateway verified with the trial; OpenCode end to end is PAD-3, model quality PAD-4, thinking variants PAD-5 |
| M5.5 | Kits per project and the browser tab | Written, fixture-tested, and used live (Playwright tab, show tabs, captures, annotations, interactive OpenUI tabs). Open checks: PAD-6, kit hosts before create PAD-7, kit arguments PAD-8 |
| M6 | Polish | Crash Reports in the status popover exists. Open: login item PAD-9, menu bar extra PAD-10, log drawer PAD-11, settings PAD-12, prompt history off PAD-13, README PAD-14, PaddockShell DocC PAD-15, crash analysis PAD-16 to PAD-18 |
| M7 | OpenHands | Deferred: PAD-21 |
| M8 | Voice: push-to-talk, agents that speak and ask, dictation words | PaddockCore and the voice kit written and tested on Linux; the app side written, not built yet. Mac checks PAD-34; hands-free PAD-38, announcements PAD-39 |
