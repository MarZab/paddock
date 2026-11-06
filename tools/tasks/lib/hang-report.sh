#!/usr/bin/env bash
# What a test run that timed out was stuck in (PAD-91), printed before the watchdog kills it.
# Usage: hang-report.sh <pid of the run> <folder for the stack samples>
# Lists every process below the run with its age and command line (a stuck test's child shows
# which script it ran), then samples the test processes' stacks on macOS: the test functions
# still on a stack are the ones that hang. The full samples go to the folder; the log gets the
# frames from the test target.
set -uo pipefail

root="$1"
out="$2"
mkdir -p "$out"

echo "## hang report: processes below the run"
table="$(ps -axo pid=,ppid=,etime=,command=)"
pids="$(printf '%s\n' "$table" | awk -v root="$root" '
  { parent[$1] = $2; line[$1] = $0; order[NR] = $1 }
  END {
    keep[root] = 1
    do {
      added = 0
      for (i = 1; i <= NR; i++) { p = order[i]; if (!(p in keep) && (parent[p] in keep)) { keep[p] = 1; added = 1 } }
    } while (added)
    for (i = 1; i <= NR; i++) { p = order[i]; if (p in keep) print p }
  }')"
for p in $pids; do printf '%s\n' "$table" | awk -v p="$p" '$1 == p { print "##   " $0 }'; done

# The test processes: SwiftPM's helper on macOS, the xctest binary on Linux (not swift-test
# itself, whose name swiftpm-testing-helper's would otherwise match).
tests="$(for p in $pids; do printf '%s\n' "$table" | awk -v p="$p" '$1 == p && /PackageTests/ && $4 !~ /\/swift-(test|build)$/ { print $1 }'; done)"
[ -n "$tests" ] || { echo "## hang report: no test process found"; exit 0; }
if ! command -v sample >/dev/null 2>&1; then
  echo "## hang report: no sample(1) here, no stacks"
  exit 0
fi
for t in $tests; do
  file="$out/sample-$t.txt"
  sample "$t" 3 -file "$file" >/dev/null 2>&1 || { echo "## hang report: sample of $t failed"; continue; }
  echo "## hang report: test frames in the stacks of $t (full sample: $file)"
  grep -E '\(in Paddock[A-Za-z]*PackageTests\)' "$file" \
    | sed -E 's/^[ +!:|]*[0-9]+ //; s/ +\(in Paddock[A-Za-z]*PackageTests\).*//' \
    | sort | uniq -c | sort -rn | head -40 | sed 's/^/##   /'
done
