# Interactive tabs in Paddock: A2UI

`paddock ui FILE` puts an interactive tab next to your terminal, drawn on the operator's screen
from A2UI v1.0 messages with the A2UI Playground's catalog (CopilotKit's Gen UI 2.0 components
plus charts, maps, data views, inputs, and domain cards). Use it for a decision, an approval,
values, or a result that is clearer shown than told.

## How it works here

- **The file:** one A2UI message per line (JSONL), or one JSON array of them. Every message has
  `"version": "1.0"`. Paths in it (pictures, links) are relative to the file's folder.
- **A surface:** start with `createSurface`, the catalog `https://copilotkit.ai/a2ui/catalogs/playground/v1`
  (the only one), its components inline (the one with id `root` first, parents before children)
  and its `dataModel`. A component is `{"id": "...", "component": "Name", ...its props}`;
  children are listed by id. Use your own surface ids; one surface per question.
- **More later:** `paddock ui tab-a3f9 more.jsonl` adds messages to the open tab:
  `updateComponents` (same id replaces a component), `updateDataModel` (`path`, `value`),
  `deleteSurface`. What the operator typed stays.
- **Values:** every prop takes a literal, `{"@path": "/a/b"}` (a JSON Pointer into the surface's
  data model), or a function call `{"@call": "formatNumber", "args": {...}}`. Bind an input's
  `value` to a path: what the operator types lands there.
- **Answers:** a Button's `onClick` is `{"event": {"name": "approve", "context": {"notes": {"@path": "/notes"}}}}`.
  `paddock wait tab-a3f9` then prints
  `the operator's tab sent: {"version":"1.0","action":{"name":"approve","surfaceId":"...","sourceComponentId":"...","timestamp":"...","context":{"notes":"..."}}}`.
  Paths in `context` are read at the click: put everything you need in it. Run `paddock wait`
  again for the next answer.
- **Mistakes:** what the renderer refuses or cannot draw comes back the same way as an A2UI
  `error` (`VALIDATION_FAILED`, `RENDER_FAILED`, ...: the component and why); a message Paddock
  refused as `{"paddock":"refused","line":N,"reason":"..."}`. Send the fix to the same tab
  (`updateComponents` with the same ids).
- **Pictures, video, audio:** an http(s) URL is fetched in this sandbox, under its network rules;
  a relative path is read from beside the file. At most 40 MB each. Embedded players
  (`VideoEmbed`) show a link instead. Maps draw shapes and markers without map tiles.
- **Links** (a Button's `href`, Markdown links, `openUrl`): an http(s) URL opens in this sandbox's
  browser (the browser kit), a relative path opens that file in a tab on the operator's screen.
  Nothing opens on the operator's Mac.
- **Limits:** 512 KB a message, 8 MB a tab (then open a new one), 20 components a surface is plenty.
- Never ask for passwords, tokens, or keys, not even in an `obscured` field: answers are logged
  in this sandbox.

## A small one

```jsonl
{"version":"1.0","createSurface":{"surfaceId":"deploy","catalogId":"https://copilotkit.ai/a2ui/catalogs/playground/v1","dataModel":{"env":"staging","notes":""},"components":[{"id":"root","component":"Card","child":"body"},{"id":"body","component":"Column","gap":3,"children":["title","env","notes","go"]},{"id":"title","component":"Heading","text":"Deploy","subtitle":"Choose where the build goes"},{"id":"env","component":"RadioGroup","label":"Environment","value":{"@path":"/env"},"options":[{"label":"Staging","value":"staging"},{"label":"Production","value":"prod"}]},{"id":"notes","component":"TextField","label":"Notes","value":{"@path":"/notes"}},{"id":"go","component":"Button","label":"Deploy","variant":"primary","onClick":{"event":{"name":"deploy","context":{"env":{"@path":"/env"},"notes":{"@path":"/notes"}}}}}]}}
```
