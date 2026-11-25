"""The A2UI reference agents read before their first interactive tab (tools/tasks/vendor/a2ui-web.sh).

Paddock's rules (reference-head.md) first, then the playground catalog's own design rules and
every component and function as a one-line signature, from the catalog its models read
(inference-catalog.json). The full JSON schemas would be some 200 KB, too much to read before a
tab: the signatures keep names, types, enums, and what is required. The example in
reference-head.md is also written as a fixture, so the headless check renders it.

    python3 -I reference.py INFERENCE_CATALOG HEAD OUT FIXTURE
"""

import json
import re
import sys

BINDINGS = {"common_types.json#/$defs/DataBinding", "common_types.json#/$defs/FunctionCall"}
REFS = {
    "common_types.json#/$defs/Action": "Action",
    "common_types.json#/$defs/ChildList": "[id]",
    "common_types.json#/$defs/ComponentId": "id",
    "common_types.json#/$defs/DynamicValue": "any",
    "common_types.json#/$defs/DynamicString": "string",
    "common_types.json#/$defs/DynamicNumber": "number",
    "common_types.json#/$defs/DynamicBoolean": "boolean",
}


def type_of(schema, depth=0):
    """A short type: string, number, "a"|"b", {x, y?}[], Action, [id], ..."""
    if not isinstance(schema, dict):
        return "any"
    if "$ref" in schema:
        return REFS.get(schema["$ref"], schema["$ref"].rsplit("/", 1)[-1])
    if "const" in schema:
        return json.dumps(schema["const"])
    if "enum" in schema:
        return "|".join(json.dumps(v) for v in schema["enum"])
    for key in ("anyOf", "oneOf"):
        if key in schema:
            options = [o for o in schema[key] if o.get("$ref") not in BINDINGS]
            names = []
            for option in options:
                name = type_of(option, depth)
                if name not in names:
                    names.append(name)
            return "|".join(names) or "any"
    kind = schema.get("type")
    if isinstance(kind, list):
        return "|".join(kind)
    if kind == "array":
        item = type_of(schema.get("items", {}), depth)
        return f"({item})[]" if "|" in item else f"{item}[]"
    if kind == "object":
        properties = schema.get("properties")
        if not properties or depth >= 2:
            return "object"
        required = set(schema.get("required", []))
        fields = [f"{name}{'' if name in required else '?'}: {type_of(value, depth + 1)}" for name, value in properties.items()]
        return "{" + ", ".join(fields) + "}"
    return kind or "any"


def sentence(text):
    text = re.sub(r"\s+", " ", text or "").strip()
    return text


def component_line(name, schema):
    required = set(schema.get("required", []))
    props = []
    for prop, value in schema.get("properties", {}).items():
        if prop == "component":
            continue
        line = f"{prop}{'' if prop in required else '?'}: {type_of(value)}"
        note = sentence(value.get("description", ""))
        props.append(f"  - {line}" + (f": {note}" if note else ""))
    head = f"- **{name}**: {sentence(schema.get('description', ''))}"
    return "\n".join([head] + props)


def function_line(name, schema):
    args = schema.get("properties", {}).get("args", {})
    required = set(args.get("required", []))
    params = ", ".join(f"{a}{'' if a in required else '?'}: {type_of(v)}" for a, v in args.get("properties", {}).items())
    returns = schema.get("returnType", "")
    return f"- `{name}({params})`{' -> ' + returns if returns else ''}: {sentence(schema.get('description', ''))}"


def main():
    catalog_path, head_path, out_path, fixture_path = sys.argv[1:5]
    with open(catalog_path, encoding="utf-8") as f:
        catalog = json.load(f)
    with open(head_path, encoding="utf-8") as f:
        head = f.read().rstrip() + "\n"
    example = re.search(r"```jsonl\n(.*?)```", head, re.S)
    if not example:
        sys.exit("reference-head.md has no ```jsonl example")
    for line in example.group(1).splitlines():
        json.loads(line)
    with open(fixture_path, "w", encoding="utf-8") as f:
        f.write(example.group(1))

    parts = [
        head,
        "## The catalog's design rules\n",
        re.sub(r"^## Design rules\s*", "", catalog.get("instructions", "")).strip() + "\n",
        f"## Components ({len(catalog['components'])})\n",
        "Props are `name: type`; `?` marks an optional one. Every prop also takes `{\"@path\": ...}` or "
        "`{\"@call\": ...}`. `[id]` is a list of child ids (or `{\"componentId\": id, \"path\": \"/list\"}` "
        "to repeat one per item of a data model list); `Action` is `{\"event\": {\"name\", \"context\"?, "
        "\"userMessage\"?}}` or `{\"functionCall\": {...}}`. Every component may also have `accessibility` "
        "(`label`, `description`).\n",
        "\n".join(component_line(name, schema) for name, schema in catalog["components"].items()) + "\n",
        f"## Functions ({len(catalog.get('functions', {}))})\n",
        "Called as `{\"@call\": \"name\", \"args\": {...}}` wherever a value goes; they run in the renderer.\n",
        "\n".join(function_line(name, schema) for name, schema in catalog.get("functions", {}).items()) + "\n",
    ]
    text = "\n".join(parts).replace("—", "-")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"==> {len(text.encode())} bytes of agent reference in {out_path}")


if __name__ == "__main__":
    main()
