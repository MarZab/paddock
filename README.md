# Paddock

A native macOS (SwiftUI) dashboard for [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) (`sbx`): one microVM per project folder, an agent (Claude Code or OpenCode) in a terminal, a sandbox shell, and local models through sbx's bundled llmman, in one window.

## Prerequisites

Paddock never installs or updates these. It detects them and shows the command for you to run.

| Tool | Needed for | Example install |
| --- | --- | --- |
| Docker Sandboxes (`sbx`, includes llmman), 0.51 or newer | everything | `brew install docker/tap/sbx` |
| Xcode 26 or newer | building Paddock | App Store or developer.apple.com |
| [mise](https://mise.jdx.dev) | the dev tools pinned in `mise.toml` | `brew install mise` |
| Node | mise installs the `backlog` CLI from npm | `mise use -g node@lts` |

Paddock needs **macOS 26 or newer on Apple Silicon** (voice uses SpeechAnalyzer; older macOS is not supported). Docker itself is not needed on the Mac.

## Setup

```sh
mise install        # xcodegen, swiftlint, swiftformat, shellcheck, backlog
mise run generate   # creates Paddock.xcodeproj from project.yml
```

Open `Paddock.xcodeproj` and build once. Xcode asks you to approve SwiftTerm's build plugin: choose Trust & Enable. Do not pass `-skipPackagePluginValidation`.

Then:

```sh
mise run build      # build the app
mise run app        # build and open Paddock Dev (the Debug build)
mise run install    # Release build into /Applications (personal use, ad hoc signed)
mise run test       # tests
mise run lint       # lint; `mise run fmt` formats
mise run clean      # remove builds, caches, and test runs in .tmp (--all: captures too)
```

Debug builds are a separate app, Paddock Dev (`Paddock Dev.app`, bundle ID `net.zabreznik.paddock.dev`, a purple icon), so `mise run app` quits only Paddock Dev and `mise run install` only the installed Paddock. The two can run side by side, with their own settings and macOS permissions (microphone, speech), but they share `~/.config/paddock` and the same sandboxes: don't open the same project in both, or their gateway ports and in-sandbox watchers clash.

If the window goes fuzzy or Paddock stops responding, run `mise run hang` before you quit it (`mise run hang --dev` for Paddock Dev; add `--spindump` for a `sudo spindump` as well). It writes the main thread's stacks, memory use, and recent logs to `.tmp/hangs/<time>/`. A force quit leaves no crash report, so this capture is the only record.

## Make it your own

Paddock builds ad hoc signed, with no developer account (`DEVELOPMENT_TEAM` is empty in `project.yml`). If you fork it, change the bundle ID prefix (`bundleIdPrefix` and the two `PRODUCT_BUNDLE_IDENTIFIER` values in `project.yml`, and the IDs named in this README) so your build has its own settings and macOS permissions, then run `mise run generate`.

## First run

1. `mise run app` (or `mise run install`), then open the app. The status button in the sidebar's title bar shows what is missing: yellow means a dependency such as `sbx` is absent or too old, and clicking it lists the checks with a copyable install command. Run the command in your own terminal and press Refresh.
2. Give agents their credentials with sbx, not Paddock: `sbx secret set ...` (see `sbx secret --help`). Paddock stores no secrets and never asks for an API key.
3. Press **New Project**, choose a folder (Paddock refuses your home folder, `/`, and folders with or inside credential directories such as `.ssh`, `.aws`, `.gnupg`, `Library`), pick Claude Code or OpenCode, and create. Paddock makes one sandbox for the folder, opens the agent in a terminal tab, and offers a sandbox shell.
4. A project may carry an `sbxenv.yaml` (sbx's environment file) that adds tools, network hosts and ports. Paddock shows its network and kit requests and asks you to confirm that exact version before anything is created.
5. Settings live in `~/.config/paddock/paddock.yaml` (File > Edit Paddock's Config; a missing file means the built-in defaults). It names agents, providers (an agent's default or a local model), kits and ports.
6. Local models run in llmman, which comes with sbx; its web UI is embedded in Paddock. An agent reaches a model only through Paddock's gateway, which forwards inference requests and nothing else, one port per project. Local models are enabled only while every llmman hardening check is green.

## Security model

Agents and everything in a sandbox or a project folder are untrusted. Only the folder you choose (and extra folders you add in Paddock, read-only by default) is mounted, the network is sbx's rules plus what you confirmed, and no sandbox content runs on the Mac except in the marked native tabs described in the design docs. The full rules are in `backlog/docs` (Security rules) and `CLAUDE.md`.

## Where things are

- `App/`: views and view models only.
- `Packages/PaddockCore/`: all logic, no UI imports.
- `backlog/docs/`: design docs describing the app as it is (`mise exec -- backlog doc list`).
- `backlog/tasks/`: the work still to do (`mise exec -- backlog task list --plain`).
- `CLAUDE.md`: rules for agents working on this repo, including the security rules.

## Contributing

Every change has a ticket in `backlog/tasks` and every commit message starts with its ticket ID (`PAD-12 feat(app): ...`); `CLAUDE.md` has the details. Capture real CLI output into the test fixtures before writing a parser. Inside a Paddock sandbox on this repo you can run the PaddockCore tests on Linux: `mise install`, `mise run swift-linux` once, then `mise run test`. Building the app needs Xcode on a Mac.

## License

MIT, see [LICENSE](LICENSE). Third-party code keeps its own license: the vendored OpenUI renderer in `App/OpenUI/vendor` (its `LICENSE` is next to it) and the Swift packages in `Package.resolved`.
