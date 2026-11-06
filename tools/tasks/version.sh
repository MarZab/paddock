#!/usr/bin/env bash
#MISE description="Print this build's version (yymmdd.N from git), or its build number or commit"
#USAGE arg "[what]" help="version (default), build (the commit count), or commit (short hash, -dirty with uncommitted changes)" {
#USAGE   choices "version" "build" "commit"
#USAGE }
# Paddock's version for a build of HEAD (backlog doc UI, Version): yymmdd.N, the day of the commit
# (this machine's time zone) and N, how many earlier commits on the first-parent line that day
# (0 for the first), so 261106.2 is the third commit of 6 November 2026. Nothing to bump by hand.
#
#   mise run version          the version, 0.0 outside git
#   mise run version build    the commit count (CFBundleVersion), 0 outside git
#   mise run version commit   the short hash, with -dirty for uncommitted changes, empty outside git
set -euo pipefail

cd "$(dirname "$0")/../.."

if ! git rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
  case "${1:-version}" in
    build) echo 0 ;;
    commit) echo ;;
    *) echo 0.0 ;;
  esac
  exit 0
fi

case "${1:-version}" in
  build)
    git rev-list --count HEAD
    ;;
  commit)
    hash="$(git rev-parse --short HEAD)"
    if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
      hash="$hash-dirty"
    fi
    echo "$hash"
    ;;
  version)
    days="$(git log --first-parent --format=%cd --date=format-local:%y%m%d HEAD)"
    day="$(head -n 1 <<<"$days")"
    # Commit dates on the first-parent line run newest first, so that day's commits lead the list.
    same_day="$(grep -c -x "$day" <<<"$days")"
    echo "$day.$((same_day - 1))"
    ;;
  *)
    echo "usage: mise run version [version|build|commit]" >&2
    exit 2
    ;;
esac
