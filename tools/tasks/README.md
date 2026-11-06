# tasks

mise file tasks (`[task_config]` in `mise.toml`): run them with `mise run <task>` (`mr <task>`), list them with `mise tasks`. A task's name is its path here without the extension, a folder becoming a prefix (`capture/cli.sh` is `capture:cli`); its description, dependencies, and arguments are the `#MISE` and `#USAGE` lines at its top. Every task runs from the repo root.

| Task | Runs on | Writes |
| --- | --- | --- |
| `generate`, `build`, `app`, `install` | the Mac (Xcode) | `Paddock.xcodeproj`, `.tmp/build/`; `install` also `/Applications/Paddock.app` |
| `test` | the Mac, or a sandbox from `tools/sandbox/paddock` (it builds in `~/.cache/paddock-build` there) | each run's output in `.tmp/test-runs/` (`latest.log`; the newest 20) |
| `lint`, `fmt` | the Mac, or a sandbox from `tools/sandbox/paddock` | nothing; `fmt` the Swift sources |
| `swift-linux` | CI (a sandbox from the kit has Swift already) | the Swift toolchain, through mise |
| `hang` | the Mac, while Paddock is stuck | `.tmp/hangs/` |
| `capture:cli` | the operator's Mac | raw sbx and llmman captures in `.tmp/captures/`, throwaway projects in `.tmp/capture-projects/` |
| `capture:socket` | the Mac | sandboxd socket captures in `.tmp/captures/socket/` |
| `capture:fixtures` | the Mac, after a capture | sanitized copies in `Packages/PaddockCore/Tests/PaddockCoreTests/Fixtures/` |
| `vendor:openui` | a dev machine with Node | `App/OpenUI/vendor/` and the OpenUI reference resource |
| `icon` | a dev machine with Node | `App/Assets.xcassets` |
| `sandbox:plan`, `sandbox:create`, `sandbox:run`, `sandbox:rm` | the Mac (sbx) | this repo's sandbox from `sbxenv.yaml`, through `tools/sandbox/run.sh` (the script Paddock writes into every project); `sandbox:create --replace` removes it first, which a kit change needs (`--force` while it is in use) |
| `clean` | anywhere | removes `.tmp/build`, `.tmp/test-runs`, `.tmp/capture-projects`, the packages' `.build`, and an old `build/`; `--all` also `.tmp/captures` and `.tmp/hangs`; `-n` only lists |
| `version` | anywhere with git | nothing; prints `yymmdd.N` (or `build`, `commit`), which `build` and `install` put into the app |

Helpers a task uses but that are no task are in `lib/`, not executable, so mise does not list them: `render-icon.js` (for `icon`) and `fake-anthropic.py` (a stand-in model server for `capture:cli kits`).

Everything a task writes for local use is under `.tmp/` (gitignored). The M0 capture's findings are backlog doc M0 findings; its sanitized output is the test fixtures. The icon's source is `App/AppIcon.svg`.
