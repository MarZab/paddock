# A2UI web fixtures (PAD-152)

A2UI 1.0 messages for CopilotKit's A2UI Playground catalog
(`https://copilotkit.ai/a2ui/catalogs/playground/v1`), which A2UI tabs render with CopilotKit's
React renderer in a web view (`App/A2UI`, built by `mise run vendor:a2ui-web`). Taken from
CopilotKit at the commit in `App/A2UI/VERSION` (MIT; `App/A2UI/THIRD_PARTY_LICENSES.txt`).

| File | Source |
| --- | --- |
| `catalog.json` | the playground's catalog as it serves it at `/catalog.json` (`scripts/export-catalog.ts`): 121 components, 16 functions |
| `agent/samples-<group>.jsonl` | the playground's own preview of every component (`src/a2ui/catalog/samples`), one `createSurface` with its components and data model each, as its component docs render them (`sampleOps`) |
| `agent/paddock-dashboard.jsonl` | written for Paddock: a Sankey, a bar chart, a bound text field, and a button whose action carries the field's value |
| `renderer/<fixture>.jsonl` | what the page sent back when `vendor:a2ui-web --check` rendered that fixture offline in Chromium and clicked every button: A2UI action messages, as CopilotKit's renderer builds them |

`--check` fails when a request leaves the page's own files, the page reports an error, or a surface
draws nothing; web images are answered as `./__media/...` (they go through the sandbox in the app).
