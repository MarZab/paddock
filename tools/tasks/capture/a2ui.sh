#!/bin/bash
#MISE description="Capture renderer-to-agent messages from the real A2UI Swift core into PaddockCore's A2UI fixtures (PAD-146.1)"
# Runs on the Mac or in a sandbox from tools/sandbox/paddock (Swift and network to github.com).
# Builds A2UI's own Swift core at the pinned release with a small capture tool (lib/a2ui-capture.swift),
# feeds it the agent-side fixtures, and writes what the core sends back:
#
#   Fixtures/a2ui/renderer/actions.jsonl   every Button of every example and Paddock fixture, pressed once
#   Fixtures/a2ui/renderer/checks.jsonl    the presses whose button checks failed (an error, not an action)
#   Fixtures/a2ui/renderer/errors.jsonl    the errors the core reports for malformed agent messages
#   Fixtures/a2ui/renderer/library-calls.jsonl  what the core answers to agent/calls.jsonl, and a call it
#                                          sends the agent for a function it does not have
#
# On Linux A2UICore's Combine is swapped for OpenCombine (lib/a2ui-capture-patch.py), and pluralize
# crashes there (Foundation's stringsdict), so examples that use it are captured only on the Mac.
# The checkout and build are in .tmp/captures/a2ui (gitignored); on Linux the build is in
# ~/.cache/paddock-build/a2ui-capture, like mise run test.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
TAG="${A2UI_TAG:-v0.12.0+swift}"
WORK="$ROOT/.tmp/captures/a2ui"
FIX="$ROOT/Packages/PaddockCore/Tests/PaddockCoreTests/Fixtures/a2ui"
SRC="$WORK/src"
OUT="$WORK/out"
if [ "$(uname)" = Linux ]; then
  PLATFORM=linux
  SCRATCH="$HOME/.cache/paddock-build/a2ui-capture"
else
  PLATFORM=mac
  SCRATCH="$WORK/build"
fi

rm -rf "$SRC" "$OUT"
mkdir -p "$WORK" "$OUT"
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$TAG" https://github.com/a2ui-project/a2ui.git "$SRC"
echo "## A2UI $TAG at $(git -C "$SRC" rev-parse HEAD)"
mkdir -p "$SRC/capture/Capture"
cp "$ROOT/tools/tasks/lib/a2ui-capture.swift" "$SRC/capture/Capture/main.swift"
python3 -I "$ROOT/tools/tasks/lib/a2ui-capture-patch.py" "$SRC" "$PLATFORM"
swift build --package-path "$SRC" --scratch-path "$SCRATCH" --product Capture
BIN="$(swift build --package-path "$SRC" --scratch-path "$SCRATCH" --show-bin-path)/Capture"

"$BIN" errors "$OUT/errors.jsonl"
"$BIN" calls "$FIX/agent/calls.jsonl" "$OUT/calls.jsonl"
"$BIN" typed "$FIX/examples/login-form.json" "$OUT/actions-typed.jsonl"
for example in "$FIX"/examples/*.json "$FIX"/agent/*.json; do
  name="$(basename "$example" .json)"
  "$BIN" actions "$example" "$OUT/actions-$name.jsonl" || echo "## $name: the capture tool failed (exit $?), skipped"
done

# One file, sorted, so a capture on another day changes only the timestamps.
cat "$OUT"/actions-*.jsonl | grep '^{"action"' | sort -u > "$FIX/renderer/actions.jsonl"
cat "$OUT"/actions-*.jsonl | grep -v '^{"action"' | sort -u > "$FIX/renderer/checks.jsonl"
cp "$OUT/errors.jsonl" "$FIX/renderer/errors.jsonl"
cp "$OUT/calls.jsonl" "$FIX/renderer/library-calls.jsonl"
echo "## wrote $(wc -l < "$FIX/renderer/actions.jsonl") actions, $(wc -l < "$FIX/renderer/checks.jsonl") failed checks and $(wc -l < "$FIX/renderer/errors.jsonl") errors to $FIX/renderer"
