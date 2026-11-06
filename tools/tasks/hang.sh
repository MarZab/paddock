#!/usr/bin/env bash
#MISE description="On the Mac: capture a stuck or broken Paddock into .tmp/hangs before killing it (--dev for Paddock Dev, --spindump for sudo spindump)"
# Captures a stuck or broken Paddock before it is killed (PAD-27): where the main thread is
# (sample), how much memory it holds and in what (footprint, vmmap, heap), what it and the window
# server logged, and Paddock's own log. A force quit leaves no crash report, so this is all there
# is to go on.
# Usage: mise run hang [--dev] [--spindump]   (spindump needs sudo; it also sees the window server)
# --dev captures Paddock Dev (the Debug build, `mise run app`, process "Paddock Dev") instead of the
# installed Paddock (process "Paddock").
# Writes to .tmp/hangs/<time>/ (gitignored) and prints the folder.
set -uo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "mise run hang runs on the Mac, where Paddock runs." >&2
  exit 1
fi

SPINDUMP=0
DEV=0
for arg in "$@"; do
  case "$arg" in
    --spindump) SPINDUMP=1 ;;
    --dev) DEV=1 ;;
    *) echo "unknown argument: $arg (usage: mise run hang [--dev] [--spindump])" >&2; exit 2 ;;
  esac
done

# The Debug build is "Paddock Dev" (.tmp/build/DerivedData/.../Debug/Paddock Dev.app), the installed one "Paddock".
PROC="Paddock"
[ "$DEV" = 1 ] && PROC="Paddock Dev"
PID="$(pgrep -x "$PROC" | head -n 1)"
if [ -z "$PID" ]; then
  if [ "$DEV" = 1 ]; then echo "Paddock Dev is not running." >&2; else echo "Paddock is not running (for Paddock Dev: mise run hang --dev)." >&2; fi
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/.tmp/hangs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
echo "Capturing Paddock (pid $PID) into $OUT"

# Each step goes on when one fails: a partial capture beats none.
step() {
  local name="$1"
  shift
  printf '  %-22s' "$name"
  if "$@"; then echo "ok"; else echo "failed (exit $?)"; fi
}

{
  date
  sw_vers
  sysctl -n hw.model
  ps -o pid,etime,%cpu,%mem,rss,vsz,command -p "$PID"
  echo
  # Memory pressure on the whole Mac: fuzzy rendering often means the GPU or memory ran short.
  memory_pressure -Q 2>/dev/null || true
  vm_stat
} > "$OUT/system.txt" 2>&1

# First, while the state is fresh: 10 s of every thread's stacks.
step "sample (10 s)" sample "$PID" 10 -file "$OUT/sample.txt"
step "footprint" sh -c "footprint '$PID' > '$OUT/footprint.txt' 2>&1"
# What the malloc memory is: counts and sizes per class, and a guess for blocks that are not
# objects (terminal scrollback, Data buffers), largest first.
step "heap" sh -c "heap -s -guessNonObjects '$PID' > '$OUT/heap.txt' 2>&1"
step "vmmap summary" sh -c "vmmap --summary '$PID' > '$OUT/vmmap.txt' 2>&1"
step "open files" sh -c "lsof -p '$PID' > '$OUT/lsof.txt' 2>&1"
step "child processes" sh -c "pgrep -lP '$PID' > '$OUT/children.txt' 2>&1 || true"
step "log (Paddock, 10 min)" sh -c "log show --last 10m --style compact --predicate 'process == \"$PROC\"' > '$OUT/log-paddock.txt' 2>&1"
step "log (WindowServer)" sh -c "log show --last 10m --style compact --predicate 'process == \"WindowServer\" AND messageType >= 16' > '$OUT/log-windowserver.txt' 2>&1"

# The stuck app's own log: one file per launch, named with its process id.
LOG=""
for file in "$HOME"/Library/Logs/Paddock/paddock-*-"$PID".log; do
  [ -e "$file" ] && LOG="$file"
done
if [ -n "$LOG" ]; then
  step "paddock log (tail)" sh -c "tail -n 500 '$LOG' > '$OUT/paddock.log'"
fi

# The newest Paddock crash or hang report, in case one exists from earlier.
REPORT=""
for file in "$HOME/Library/Logs/DiagnosticReports/$PROC"-*; do
  [ -e "$file" ] || continue
  if [ -z "$REPORT" ] || [ "$file" -nt "$REPORT" ]; then REPORT="$file"; fi
done
if [ -n "$REPORT" ]; then
  step "newest report" cp "$REPORT" "$OUT/"
fi

if [ "$SPINDUMP" = 1 ]; then
  step "spindump (sudo)" sudo spindump "$PID" 10 -file "$OUT/spindump.txt"
fi

echo "Done: $OUT"
