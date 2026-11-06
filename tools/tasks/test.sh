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

# Both packages run even when the first fails, so one log shows every failure.
run() {
  echo "# $(date '+%Y-%m-%d %H:%M:%S') commit $(tools/tasks/version.sh commit) ($(tools/tasks/version.sh))"
  echo "# $(swift --version 2>&1 | grep -m 1 'Swift version')"
  echo "# mise run test $*"
  status=0
  for package in PaddockCore PaddockShell; do
    echo
    echo "## $package"
    (cd "Packages/$package" && swift test "$@")
    code=$?
    echo "## $package exit $code"
    [ "$code" = 0 ] || status=1
  done
  return "$status"
}

run "$@" 2>&1 | tee "$LOG"
status="${PIPESTATUS[0]}"

# Keep the newest 20 runs.
find "$RUNS" -maxdepth 1 -name '20*.log' -type f | sort -r | tail -n +21 | while read -r old; do rm -f "$old"; done

echo "test log: $LOG"
exit "$status"
