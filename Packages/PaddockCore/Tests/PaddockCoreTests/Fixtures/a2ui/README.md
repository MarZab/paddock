# A2UI v1.0 fixtures (PAD-146.1)

Real A2UI v1.0 messages in both directions, for interactive tabs (PAD-146). Taken from A2UI at tag
`v0.12.0+swift` (commit `0c08d86cc0437474d860533096a1fe127f133e71`, github.com/a2ui-project/a2ui),
which is Apache-2.0: its license is `LICENSE` here. Upstream files are copied unchanged.

## Agent to renderer (what `paddock ui` gets)

| File | Source |
| --- | --- |
| `examples/*.json` (43) | upstream `catalogs/basic/v1/examples/`: `{name, description, messages}`, with `createSurface`, `updateComponents`, `updateDataModel` |
| `agent/contact-form.jsonl` | upstream `specification/v1_0/test/cases/contact_form_example.jsonl`: a whole stream, one message per line, as an agent writes it |
| `agent/calls.jsonl` | the valid `callRendererFunction` cases of upstream `specification/v1_0/test/cases/call_function_message.json`, then the `deleteSurface` and the two `agentFunctionResponse` examples of `specification/v1_0/docs/a2ui_protocol.md` |
| `agent/media.json` | written for Paddock: Image, Video and AudioPlayer with https, sandbox-relative, `data:` and bound URLs, and an `openUrl` button |
| `agent/functions.json` | written for Paddock: the basic functions no upstream example calls (`numeric`, `not`, and `pluralize` on its own; two examples use it only inside a `formatString` expression) |

The two Paddock files have the examples' shape and were checked with A2UI's own Swift validator
(`MessageProcessor`, which rejected a wrong `variant` while they were written). `pluralize` was not
checked there: it crashes A2UI on Linux (Foundation's stringsdict), so it is checked on the Mac
(PAD-146.3).

`catalog.json` is upstream `catalogs/basic/v1/catalog.json`, the basic catalog (18 components, 14
functions; id `https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json`).

## Renderer to agent (what `paddock wait` prints)

| File | Source |
| --- | --- |
| `renderer/actions.jsonl` | captured from A2UI's Swift core (`mise run capture:a2ui`): every Button of every example pressed once, and the login example after typing |
| `renderer/checks.jsonl` | captured the same way: the presses of a Button whose `@checks` failed, which send a `VALIDATION_FAILED` error with the button's id as `path` instead of the action |
| `renderer/errors.jsonl` | captured the same way: the errors the core reports for an unknown catalog, an unknown component, a missing surface, a wrong property type, and an unknown version |
| `renderer/library-calls.jsonl` | captured the same way: what the core answers to each line of `agent/calls.jsonl` (`rendererFunctionResponse`), and the `callAgentFunction` it sends when a Text calls a function the renderer does not have |
| `renderer/calls.jsonl` | the valid cases of upstream `function_response.json` and `call_agent_function_message.json`, and the `error` with a `functionCallId` from `renderer_messages.json` (all in `specification/v1_0/test/cases/`) |

Seen in the capture:

- An unknown `version` is reported with `"version":"v0.9"` on the error itself, not `1.0`.
- A `Column` naming a child that never arrives reports nothing: the core waits for it.
- A `Button` whose action is a function call (`openUrl`) sends no message; only `event` actions do.
- `timestamp` is the core's clock when the button was pressed (ISO 8601, seconds).
- The agent may not call `openUrl` (`rendererOnly`): the core answers `INVALID_FUNCTION_CALL`.
- A function the catalog lacks becomes a `callAgentFunction` to the agent, with a fresh UUID as
  `functionCallId`, and the surface waits for an `agentFunctionResponse`.

On Linux the capture skips the examples that use `pluralize` (`functions`, `product-card`,
`recipe-card`); a capture on the Mac includes them.
