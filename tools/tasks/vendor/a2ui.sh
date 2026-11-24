#!/bin/bash
#MISE description="Generate the A2UI reference agents get (paddock ui) with A2UI's own agent SDK, at the A2UI release PaddockA2UI pins"
# Writes Packages/PaddockCore/Sources/PaddockCore/Resources/a2ui-reference.md, which the browser kit
# installs in sandboxes as /usr/local/share/paddock/a2ui.md (backlog doc Browser, interactive tabs):
# Paddock's rules (tools/tasks/lib/a2ui-reference-rules.md), then the v1.0 basic catalog's schemas
# as A2UI's Python agent SDK writes them for a model. Run from the repo root when bumping A2UI
# (Packages/PaddockA2UI/Package.swift), with the same tag. Needs Python 3 and network to GitHub and
# PyPI; the checkout and the venv are in .tmp/vendor/a2ui (gitignored).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
TAG="${A2UI_TAG:-v0.12.0+swift}"
WORK="$ROOT/.tmp/vendor/a2ui"
OUT="$ROOT/Packages/PaddockCore/Sources/PaddockCore/Resources/a2ui-reference.md"

rm -rf "$WORK"
mkdir -p "$WORK"
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$TAG" https://github.com/a2ui-project/a2ui.git "$WORK/src"
echo "==> A2UI $TAG at $(git -C "$WORK/src" rev-parse HEAD)"
python3 -m venv "$WORK/venv"
"$WORK/venv/bin/pip" install --quiet "$WORK/src/python/a2ui_core" "$WORK/src/python/a2ui_agent"
"$WORK/venv/bin/python" -I "$ROOT/tools/tasks/lib/a2ui-reference.py" "$ROOT/tools/tasks/lib/a2ui-reference-rules.md" "$TAG" > "$OUT.new"
mv "$OUT.new" "$OUT"
echo "==> $(wc -c < "$OUT") bytes in $OUT"
