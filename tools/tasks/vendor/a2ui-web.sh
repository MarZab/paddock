#!/bin/bash
#MISE description="Build Paddock's A2UI tab page (CopilotKit's renderer, the A2UI Playground's catalog) into App/A2UI"
# A2UI tabs (backlog doc Browser, interactive tabs; PAD-152) render with CopilotKit's Gen UI 2.0
# renderer and the A2UI Playground's catalog (121 components), which only exist as React code. This
# builds them into a static page the app loads offline in a web view: the playground's MIT source at
# one CopilotKit commit, its pnpm lockfile, and Paddock's host (tools/tasks/lib/a2ui-web), with Vite.
# Run from the repo root when bumping COMMIT; needs Node and network to GitHub and npm. The checkout
# and the build are in .tmp/vendor/a2ui-web (gitignored). Install-time analytics and telemetry are off.
#
#   mise run vendor:a2ui-web           # build and write App/A2UI
#   mise run vendor:a2ui-web --check   # also render the fixtures in a headless browser, offline

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
COMMIT="${A2UI_WEB_COMMIT:-7f7ba6ff6d1efa0ce83c74c2e28a4d11969daf00}"
PNPM="pnpm@10.33.4"
VITE="vite@7.3.8"
VITE_REACT="@vitejs/plugin-react@5.1.4"
WORK="$ROOT/.tmp/vendor/a2ui-web"
OUT="$ROOT/App/A2UI"
PLAYGROUND="$WORK/ck/examples/showcases/a2ui-playground"
export SCARF_ANALYTICS=false DO_NOT_TRACK=1 COPILOTKIT_TELEMETRY_DISABLED=true NEXT_TELEMETRY_DISABLED=1

if [ ! -d "$WORK/ck/.git" ]; then
  mkdir -p "$WORK"
  git clone --quiet --filter=blob:none --no-checkout https://github.com/CopilotKit/CopilotKit.git "$WORK/ck"
fi
git -C "$WORK/ck" sparse-checkout set examples/showcases/a2ui-playground
git -C "$WORK/ck" fetch --quiet --depth 1 origin "$COMMIT"
git -C "$WORK/ck" -c advice.detachedHead=false checkout --quiet --force "$COMMIT"
echo "==> CopilotKit $COMMIT"

cd "$PLAYGROUND"
git checkout --quiet -- package.json pnpm-lock.yaml
rm -rf paddock-host
npx --yes "$PNPM" install --frozen-lockfile --ignore-scripts --reporter=silent --store-dir "$WORK/pnpm-store"
npx --yes "$PNPM" add --save-dev --ignore-scripts --reporter=silent --store-dir "$WORK/pnpm-store" "$VITE" "$VITE_REACT"
cp -R "$ROOT/tools/tasks/lib/a2ui-web" paddock-host
NODE_OPTIONS=--max-old-space-size=6144 npx vite build --config paddock-host/vite.config.mts --logLevel warn

rm -rf "$OUT"
mkdir -p "$OUT"
cp -R paddock-host/dist/. "$OUT/"
# The playground's own preview of every component, as fixtures (PAD-152).
npx tsx --tsconfig tsconfig.json paddock-host/export-samples.ts "$ROOT/Packages/PaddockCore/Tests/PaddockCoreTests/Fixtures/a2ui-web/agent"
# The catalog as the playground serves it (/catalog.json), and the one its models read.
npx tsx --tsconfig tsconfig.json scripts/export-catalog.ts >/dev/null
cp src/a2ui/export/catalog.json "$ROOT/Packages/PaddockCore/Tests/PaddockCoreTests/Fixtures/a2ui-web/catalog.json"
cp src/a2ui/export/inference-catalog.json "$WORK/inference-catalog.json"
# What the page is built from, and every license of what is in it.
react_core="$(node -p "require('./node_modules/@copilotkit/react-core/package.json').version")"
printf 'CopilotKit %s (examples/showcases/a2ui-playground), @copilotkit/react-core %s, built by tools/tasks/vendor/a2ui-web.sh\n' "$COMMIT" "$react_core" > "$OUT/VERSION"
node "$ROOT/tools/tasks/lib/a2ui-web/licenses.mjs" "$PLAYGROUND" "$OUT/THIRD_PARTY_LICENSES.txt"
# The files the app may serve: the page loads nothing else (A2UIWebPolicy).
python3 -I "$ROOT/tools/tasks/lib/a2ui-web/manifest.py" "$OUT"
echo "==> $(du -sh "$OUT" | cut -f1) in $OUT ($(wc -c < "$OUT/host.js") bytes of host.js)"

# The headless check needs a Chromium: CHROMIUM, or Debian's at /usr/bin/chromium (apt install chromium).
if [ "${1:-}" = "--check" ]; then
  mkdir -p "$WORK/check"
  [ -d "$WORK/check/node_modules/playwright-core" ] || npm install --prefix "$WORK/check" --silent --no-audit --no-fund playwright-core@1.58.2
  A2UI_CHECK_MODULES="$WORK/check" A2UI_CHECK_SHOTS="$WORK" \
    node "$ROOT/tools/tasks/lib/a2ui-web/check.mjs" "$OUT" "$ROOT/Packages/PaddockCore/Tests/PaddockCoreTests/Fixtures/a2ui-web"
fi
