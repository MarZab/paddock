#!/usr/bin/env bash
#MISE description="Run PaddockCore and PaddockShell tests; each run's output is kept in .tmp/test-runs"
# Arguments go to swift test in both packages (mise run test --filter AppVersion).
# The whole run, live output included, goes to .tmp/test-runs/<time>.log (gitignored), with
# latest.log pointing at it, so an agent can read a run made on the Mac. The newest 20 are kept.
set -uo pipefail

RUNS=.tmp/test-runs
mkdir -p "$RUNS"
LOG="$RUNS/$(date +%Y-%m-%d_%H-%M-%S).log"
ln -sf "$(basename "$LOG")" "$RUNS/latest.log"

# On Linux (a sandbox sharing this folder with the Mac), SwiftPM builds on the sandbox's own disk:
# a Linux build in Packages/*/.build replaces the Mac's build database and links.
scratch=()

# Each package gets PADDOCK_TEST_TIMEOUT seconds (default 600); a stuck test run is killed, with its
# children, and counts as a failure. macOS has no timeout(1), so a watchdog does it.
LIMIT="${PADDOCK_TEST_TIMEOUT:-600}"

# Test processes of this checkout (PAD-117): a timeout or an interrupt can leave a PackageTests.xctest
# behind with its parent gone, and it holds SwiftPM's build lock.
stop_tests() {
  local pids
  # Anchored at the start of the command line, so a shell that merely mentions the name is not matched.
  # On macOS SwiftPM runs them through swiftpm-testing-helper, in a process group of its own.
  pids="$(pgrep -f '^([^ ]*/xctest +|[^ ]*/swiftpm-testing-helper .*)?[^ ]*/(Packages/Paddock[A-Za-z]*/[.]build|[.]cache/paddock-build)/[^ ]*PackageTests[.]xctest' || true)"
  [ -z "$pids" ] && return 0
  echo "## stopping leftover test processes: $(echo "$pids" | tr '\n' ' ')"
  # shellcheck disable=SC2086
  kill -TERM $pids 2>/dev/null
  sleep 1
  # shellcheck disable=SC2086
  kill -KILL $pids 2>/dev/null || true
}
trap 'stop_tests; exit 130' INT TERM

limited() {
  set -m # the command gets its own process group, so the watchdog can kill all of it
  "$@" &
  local pid=$! watchdog heartbeat code
  # A line every 30 s while the run is silent, so a hang shows how long it has been quiet.
  (while sleep 30; do echo "## still running, $(date +%T)"; done) &
  heartbeat=$!
  # Before it kills, it reports what the run is stuck in (PAD-91).
  (sleep "$LIMIT"; echo "## timed out after ${LIMIT}s (PADDOCK_TEST_TIMEOUT)"
    bash tools/tasks/lib/hang-report.sh "$pid" "${LOG%.log}-hang"
    echo "## killing the run"; kill -TERM -- "-$pid" 2>/dev/null; sleep 5; kill -KILL -- "-$pid" 2>/dev/null
    stop_tests) &
  watchdog=$!
  wait "$pid"
  code=$?
  # Their groups, not just the subshells: a sleep left behind would hold the output open until it ends.
  kill -TERM -- "-$watchdog" "-$heartbeat" 2>/dev/null
  stop_tests
  wait "$watchdog" "$heartbeat" 2>/dev/null
  set +m
  return "$code"
}

stop_tests # one left by an earlier run

# Both packages run even when the first fails, so one log shows every failure.
run() {
  echo "# $(date '+%Y-%m-%d %H:%M:%S') commit $(tools/tasks/version.sh commit) ($(tools/tasks/version.sh))"
  echo "# $(swift --version 2>&1 | grep -m 1 'Swift version')"
  echo "# mise run test $*"
  status=0
  for package in PaddockCore PaddockShell; do
    echo
    echo "## $package"
    if [ "$(uname -s)" = Linux ]; then scratch=(--scratch-path "$HOME/.cache/paddock-build/$package"); fi
    # shellcheck disable=SC2016 # $0 and $@ are for the inner bash
    limited bash -c 'cd "Packages/$0" && exec swift test "$@"' "$package" ${scratch[@]+"${scratch[@]}"} "$@"
    code=$?
    echo "## $package exit $code"
    [ "$code" = 0 ] || status=1
  done
  return "$status"
}

# Every line gets the time of day it arrived: [14:03:07].
stamp() {
  if command -v perl >/dev/null 2>&1; then
    perl -MPOSIX -ne 'BEGIN { $| = 1 } print strftime("[%H:%M:%S] ", localtime), $_'
  else
    while IFS= read -r line; do printf '[%s] %s\n' "$(date +%T)" "$line"; done
  fi
}

run "$@" 2>&1 | stamp | tee "$LOG"
status="${PIPESTATUS[0]}"

# Keep the newest 20 runs.
find "$RUNS" -maxdepth 1 -name '20*.log' -type f | sort -r | tail -n +21 | while read -r old; do rm -f "$old"; done

echo "test log: $LOG"
exit "$status"
