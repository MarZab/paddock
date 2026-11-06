# shellcheck shell=bash
# Sourced by tasks (not run): keeps a task's whole output in a log an agent can read, as
# `mise run test` does (PAD-107). Usage: logged_run NAME COMMAND [ARGS...]
# The output, live and whole, also goes to .tmp/NAME-runs/<time>.log (gitignored) under a header
# with the commit, the command, and the exit status; NAME-runs/latest.log points at the newest and
# the newest 20 are kept. Returns the command's exit status.

logged_run() {
  local name="$1" runs log status
  shift
  runs=".tmp/$name-runs"
  mkdir -p "$runs"
  log="$runs/$(date +%Y-%m-%d_%H-%M-%S).log"
  ln -sf "$(basename "$log")" "$runs/latest.log"
  {
    echo "# $(date '+%Y-%m-%d %H:%M:%S') commit $(tools/tasks/version.sh commit) ($(tools/tasks/version.sh)) $(uname -sm)"
    echo "# mise run $name"
    "$@"
    status=$?
    echo "## $name exit $status"
    exit "$status"
  } 2>&1 | tee "$log"
  status="${PIPESTATUS[0]}"
  find "$runs" -maxdepth 1 -name '20*.log' -type f | sort -r | tail -n +21 | while read -r old; do rm -f "$old"; done
  echo "$name log: $log"
  return "$status"
}
