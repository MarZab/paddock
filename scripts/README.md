# scripts

Run them through `mise run <task>` (see `mise.toml`); each is listed with where it runs and what it writes.

| Script | Runs on | Writes |
| --- | --- | --- |
| `m0-capture.sh` | the operator's Mac | raw captures in `m0/raw/` (ignored); sanitized ones go to the test fixtures through `sanitize-fixtures.py` |
| `sanitize-fixtures.py` | the Mac, after a capture | `Packages/PaddockCore/Tests/PaddockCoreTests/Fixtures/` |
| `socket-capture.py` | the Mac | sandboxd socket captures, to the fixtures |
| `m0-fake-anthropic.py` | the Mac, during a capture | nothing (a fake model server) |
| `gateway-trial.sh` | the Mac | `scratch/trial` (ignored) |
| `capture-hang.sh` | the Mac, while Paddock is stuck | `scratch/hangs/` |
| `openui-vendor.sh` | a dev machine with Node | `App/OpenUI/vendor/` and the OpenUI reference resource |
| `render-icon.js` | a dev machine with Node | `App/Assets.xcassets` |
| `install-swift.sh` | a Linux sandbox or CI | the Swift toolchain, through mise |

`m0/` holds the findings and fixtures of the M0 capture (backlog doc M0 findings); `design/` the icon source.
