#!/usr/bin/env bash
#MISE description="Remove build output, caches, and test runs (--all also captures and hang captures)"
#USAGE flag "--all" help="also remove .tmp/captures and .tmp/hangs (raw captures, which fixtures are made from)"
#USAGE flag "-n --dry-run" help="list what would be removed, with sizes, and remove nothing"
# Never touches scratch/ (its folders may be Paddock projects with sandboxes) or a project in .tmp/
# other than the capture projects; those are the operator's to move or delete.
set -euo pipefail

ALL=0
DRY=0
for arg in "$@"; do
  case "$arg" in
    --all) ALL=1 ;;
    -n | --dry-run) DRY=1 ;;
    *) echo "unknown argument: $arg (usage: mise run clean [--all] [--dry-run])" >&2; exit 2 ;;
  esac
done

# Rebuilt by the next build, test, icon, or capture.
paths=(
  .tmp/build
  .tmp/test-runs
  .tmp/capture-projects
  Packages/PaddockCore/.build
  Packages/PaddockShell/.build
  build  # where build output went before .tmp/build
)
# In a Linux sandbox, mise run test builds on the sandbox's own disk.
if [ "$(uname -s)" = Linux ]; then
  paths+=("$HOME/.cache/paddock-build")
fi
if [ "$ALL" = 1 ]; then
  paths+=(.tmp/captures .tmp/hangs)
fi

removed=0
for path in "${paths[@]}"; do
  [ -e "$path" ] || continue
  size="$(du -sh "$path" 2>/dev/null | cut -f1)"
  if [ "$DRY" = 1 ]; then
    echo "would remove $path ($size)"
  else
    rm -rf "$path"
    echo "removed $path ($size)"
  fi
  removed=1
done
[ "$removed" = 1 ] || echo "nothing to remove"
if [ "$ALL" = 0 ] && { [ -e .tmp/captures ] || [ -e .tmp/hangs ]; }; then
  echo "kept .tmp/captures and .tmp/hangs (mise run clean --all removes them)"
fi
