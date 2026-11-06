#!/usr/bin/env bash
#MISE description="Lint Swift sources and shell scripts; each run's output is kept in .tmp/lint-runs"
set -uo pipefail
# shellcheck source=tools/tasks/lib/logged.sh
. tools/tasks/lib/logged.sh

lint() {
  local status=0
  swiftlint lint --strict || status=1
  shellcheck tools/tasks/*.sh tools/tasks/*/*.sh tools/sandbox/*.sh || status=1
  return "$status"
}

logged_run lint lint
