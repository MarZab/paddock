"""Writes App/A2UI/manifest.json (tools/tasks/vendor/a2ui-web.sh): every file the A2UI tab's page
may load, with its MIME type, and nothing else. The app serves only these (A2UIWebPolicy).

    python3 -I manifest.py APP_A2UI_FOLDER
"""
import json
import os
import sys

TYPES = {
    ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript", ".css": "text/css",
    ".woff2": "font/woff2", ".woff": "font/woff", ".ttf": "font/ttf", ".otf": "font/otf",
    ".svg": "image/svg+xml", ".png": "image/png", ".jpg": "image/jpeg", ".gif": "image/gif", ".webp": "image/webp",
    ".json": "application/json", ".wasm": "application/wasm",
}
root = sys.argv[1]
files = {}
for folder, _, names in os.walk(root):
    for name in names:
        rel = os.path.relpath(os.path.join(folder, name), root).replace(os.sep, "/")
        ext = os.path.splitext(name)[1].lower()
        if rel in ("manifest.json", "VERSION", "THIRD_PARTY_LICENSES.txt") or ext not in TYPES:
            continue
        files[rel] = TYPES[ext]
with open(os.path.join(root, "manifest.json"), "w") as out:
    json.dump({"files": dict(sorted(files.items()))}, out, indent=1, sort_keys=True)
    out.write("\n")
print(f"==> {len(files)} files in manifest.json")
