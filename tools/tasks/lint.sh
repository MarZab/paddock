#!/usr/bin/env bash
#MISE description="Lint Swift sources and shell scripts"
set -euo pipefail
swiftlint lint --strict
shellcheck tools/tasks/*.sh tools/tasks/*/*.sh tools/sandbox/*.sh
