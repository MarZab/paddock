#!/bin/bash
#MISE description="Capture sbx and llmman CLI output on the operator's Mac, for fixtures (the M0 capture)"
#USAGE arg "<phase>" help="readonly first, then lifecycle, models; v3 for sbx >= 0.51 kits and sbx env (PAD-73.1), kits for Paddock's own kits (PAD-73.2)" {
#USAGE   choices "readonly" "lifecycle" "models" "v3" "kits" "mounts"
#USAGE }
#USAGE arg "[parts]" help="kits only: a comma-separated choice of status, voice, browser, gateway, claude, opencode (all when left out)"
# M0 CLI contract spike. Run on the operator's Mac, from the repo root.
#
#   mise run capture:cli readonly    # safe: versions, status, lists, --help texts, llmman GETs
#   mise run capture:cli lifecycle   # creates throwaway sbx sandboxes (claude, builder), then removes them
#   mise run capture:cli mounts      # can a folder be added to an existing sandbox without a recreate? (throwaway sandboxes)
#   mise run capture:cli models      # enables sbx --model (asks), runs a tiny local model, probes llmman from inside
#
# Output goes to .tmp/captures/ (gitignored, outside the Swift package); throwaway projects to .tmp/capture-projects/.
# Run mise run capture:fixtures afterwards to refresh the committed, sanitized fixtures.
# Each capture writes <name>.json or <name>.txt (stdout), <name>.stderr (if any),
# and a line in _index.tsv with the exit code and command.
# Never captures secret values: only names, status codes, and public metadata.
#
# Compatible with the stock macOS bash 3.2.

set -u

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
# raw captures stay local (gitignored); mise run capture:fixtures writes the committed copies
FIX="$ROOT/.tmp/captures"
LLMMAN_BASE="${M0_LLMMAN_BASE:-http://127.0.0.1:17434}"
RUN_ID="m0$(date +%s)"
TESTDIR="$ROOT/.tmp/capture-projects/$RUN_ID"

mkdir -p "$FIX"
INDEX="$FIX/_index.tsv"
[ -f "$INDEX" ] || printf 'name\texit\tseconds\tcommand\n' > "$INDEX"

log() { printf '\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m!!  %s\033[0m\n' "$*"; }

# cap <name> <ext> <cmd...>: run a command, keep stdout/stderr/exit code.
cap() {
  local name="$1" ext="$2"; shift 2
  local out="$FIX/$name.$ext" err="$FIX/$name.stderr" start end rc
  start=$(date +%s)
  # stdin from /dev/null: a confirmation prompt fails fast instead of waiting invisibly
  "$@" > "$out" 2> "$err" < /dev/null
  rc=$?
  end=$(date +%s)
  [ -s "$err" ] || rm -f "$err"
  [ -s "$out" ] || rm -f "$out"
  printf '%s\t%s\t%s\t%s\n' "$name" "$rc" "$((end - start))" "$*" >> "$INDEX"
  printf '  %-40s exit=%s\n' "$name" "$rc"
  return $rc
}

# capture an NDJSON stream for N seconds
cap_stream() {
  local name="$1" secs="$2"; shift 2
  "$@" > "$FIX/$name.ndjson" 2> "$FIX/$name.stderr" &
  local pid=$!
  sleep "$secs"
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  [ -s "$FIX/$name.stderr" ] || rm -f "$FIX/$name.stderr"
  printf '%s\t%s\t%s\t%s\n' "$name" "stream" "$secs" "$*" >> "$INDEX"
  printf '  %-40s streamed %ss\n' "$name" "$secs"
}

confirm() {
  printf '%s [y/N] ' "$1"
  local a; read -r a
  [ "$a" = "y" ] || [ "$a" = "Y" ]
}

# GET only. Prints the body, then a trailing line "http=<code>".
http_get() {
  curl -sS -m 10 -w '\nhttp=%{http_code}\n' "$1"
}

# Print small files under a directory with key/token/secret/password values replaced.
# Character classes instead of sed's /I flag, which BSD sed (macOS) lacks.
redact() {
  sed -E 's/(([Kk][Ee][Yy]|[Tt][Oo][Kk][Ee][Nn]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd])[A-Za-z_]*"?[[:space:]]*[:=][[:space:]]*)[^[:space:],}]+/\1<hidden>/g' "$1"
}
dump_redacted() {
  find "$1" -type f -size -64k | while read -r f; do echo "## $f"; redact "$f"; done
}

# ---------------------------------------------------------------- readonly

phase_readonly() {
  log "host"
  cap host-sw_vers txt sw_vers
  cap host-arch txt uname -m
  cap host-hw txt sysctl -n machdep.cpu.brand_string hw.memsize
  cap host-xcodebuild-version txt xcodebuild -version
  cap host-xcodegen-version txt xcodegen --version
  cap host-swift-version txt swift --version
  # shellcheck disable=SC2016  # expanded by zsh, not here
  cap host-login-path txt /bin/zsh -lc 'echo $PATH'
  cap host-which txt /bin/zsh -lc 'which -a sbx llmman curl jq'
  # where sbx came from, for the example install command
  cap brew-version txt brew --version
  # shellcheck disable=SC2016  # expanded by the inner shell
  cap sbx-binary txt /bin/sh -c 'ls -la "$(command -v sbx)"; realpath "$(command -v sbx)"'
  # shellcheck disable=SC2016
  cap brew-search txt /bin/zsh -lc 'for q in sbx docker-sandboxes llmman; do echo "## $q"; brew search "$q"; done'

  log "sbx"
  cap sbx-version json sbx version --json
  cap sbx-daemon-status json sbx daemon status --format json
  cap sbx-ls json sbx ls --json
  cap sbx-policy-ls json sbx policy ls --json
  cap sbx-settings-providers json sbx settings get model.providers --json
  cap sbx-settings-experimental json sbx settings get platform.allowExperimentalFeatures --json
  cap sbx-settings-feature-model json sbx settings get feature.model --json
  cap sbx-settings-ls json sbx settings ls --json
  cap sbx-template-ls json sbx template ls --json
  cap sbx-policy-profile-ls json sbx policy profile ls --json
  cap sbx-policy-log json sbx policy log --json
  cap sbx-policy-approval-ls json sbx policy approval ls --json
  cap_stream sbx-events-idle 5 sbx events --json

  log "sbx help texts"
  cap help-sbx txt sbx --help
  for sub in version daemon ls events policy run create exec ports stop rm settings secret template kit env cp; do
    cap "help-sbx-$sub" txt sbx "$sub" --help
  done
  cap help-sbx-daemon-status txt sbx daemon status --help
  cap help-sbx-daemon-restart txt sbx daemon restart --help
  cap help-sbx-policy-allow-network txt sbx policy allow network --help
  cap help-sbx-policy-deny-network txt sbx policy deny network --help
  cap help-sbx-policy-check txt sbx policy check --help
  cap help-sbx-policy-ls txt sbx policy ls --help
  cap help-sbx-policy-log txt sbx policy log --help
  cap help-sbx-policy-approval txt sbx policy approval --help
  cap help-sbx-policy-approval-ls txt sbx policy approval ls --help
  cap help-sbx-policy-approval-inspect txt sbx policy approval inspect --help
  cap help-sbx-policy-approval-respond txt sbx policy approval respond --help
  cap help-sbx-policy-profile txt sbx policy profile --help
  cap help-sbx-policy-rm txt sbx policy rm --help
  cap help-sbx-secret-set txt sbx secret set --help
  cap help-sbx-secret-set-custom txt sbx secret set-custom --help
  cap help-sbx-secret-ls txt sbx secret ls --help
  cap help-sbx-settings-get txt sbx settings get --help
  cap help-sbx-settings-set txt sbx settings set --help
  cap help-sbx-settings-unset txt sbx settings unset --help
  cap help-sbx-template-load txt sbx template load --help
  cap help-sbx-template-ls txt sbx template ls --help
  cap help-sbx-template-save txt sbx template save --help
  cap help-sbx-template-rm txt sbx template rm --help
  cap help-sbx-kit-builder txt sbx kit builder --help

  log "llmman: how sandboxd runs it (risk 4, 5)"
  cap llmman-processes txt /bin/sh -c "ps -axo pid,ppid,user,lstart,command | grep -iE '[l]lmman'"
  # walk each llmman's parent chain up to launchd, to see who starts it
  # shellcheck disable=SC2016  # expanded by the inner shell
  cap llmman-parents txt /bin/sh -c 'for p in $(pgrep -i llmman); do echo "## llmman $p"; while [ "$p" -gt 1 ]; do ps -o pid=,ppid=,user=,lstart=,command= -p "$p"; p=$(ps -o ppid= -p "$p" | tr -d " "); [ -n "$p" ] || break; done; done'
  cap llmman-all-listeners txt /bin/sh -c "lsof -nP -iTCP -sTCP:LISTEN | grep -iE 'llmman|17434'"
  cap launchd-sbx txt /bin/sh -c "launchctl list | grep -iE 'docker|sandbox|llmman'; ls -la \"$HOME/Library/LaunchAgents\" 2>/dev/null | grep -iE 'docker|sandbox|llmman'"
  # shellcheck disable=SC2016  # expanded by the inner shell
  cap llmman-listen txt /bin/sh -c 'for p in $(pgrep -i llmman); do lsof -nP -a -p "$p" -iTCP -sTCP:LISTEN; done'
  cap llmman-version-cli txt llmman --version
  cap help-llmman txt llmman --help

  log "sbx's model kits (to see what --model sets up for claude; key/token values hidden)"
  local kits="$HOME/Library/Application Support/com.docker.sandboxes/sandboxes/sandboxd/model-kits"
  cap sbx-model-kits-layout txt /usr/bin/find "$kits" -maxdepth 3
  cap sbx-model-kits-files txt dump_redacted "$kits"

  log "llmman files (names and line counts only, never contents)"
  cap llmman-data-layout txt /usr/bin/find "$HOME/.local/share/llmman" -maxdepth 2 -not -path "*/store/blobs/*"
  cap llmman-config-layout txt /bin/ls -la "$HOME/.config/llmman"
  cap llmman-prompts-count txt /bin/sh -c "wc -l < \"$HOME/.local/share/llmman/prompts.jsonl\""

  log "llmman API at $LLMMAN_BASE (GET only; /llmman/shell without upgrade is a status check)"
  cap llmmanapi-version json http_get "$LLMMAN_BASE/api/version"
  cap llmmanapi-tags json http_get "$LLMMAN_BASE/api/tags"
  cap llmmanapi-ps json http_get "$LLMMAN_BASE/api/ps"
  cap llmmanapi-node json http_get "$LLMMAN_BASE/llmman/node"
  cap llmmanapi-shell-status json http_get "$LLMMAN_BASE/llmman/shell"
  cap llmmanapi-providers json http_get "$LLMMAN_BASE/llmman/providers"
  cap llmmanapi-v1-models json http_get "$LLMMAN_BASE/v1/models"
  if grep -q '"enabled": *true' "$FIX/llmmanapi-shell-status.json" 2>/dev/null; then
    warn "llmman's web shell is ENABLED. Paddock will require LLMMAN_SHELL=off (see backlog doc Models)."
  fi
}

# ---------------------------------------------------------------- lifecycle

cleanup_sandboxes() {
  for n in "$RUN_ID-claude" "$RUN_ID-build" "$RUN_ID-model" "$RUN_ID-opencode"; do
    sbx rm --force "$n" >/dev/null 2>&1
  done
}

phase_lifecycle() {
  log "will create sandboxes $RUN_ID-claude and $RUN_ID-build on folder $TESTDIR, then remove them"
  confirm "Proceed?" || return 0
  mkdir -p "$TESTDIR" && echo "m0 test" > "$TESTDIR/README.md"
  trap cleanup_sandboxes EXIT

  "$(command -v sbx)" events --json > "$FIX/sbx-events-lifecycle.ndjson" 2> "$FIX/sbx-events-lifecycle.stderr" &
  local ev=$!

  log "gateway plumbing: a throwaway local HTTP server stands in for Paddock's gateway (risk 4)"
  local gw=17480
  mkdir -p "$TESTDIR/www/v1" && echo "allowed" > "$TESTDIR/www/v1/ok.txt" && echo "should be blocked" > "$TESTDIR/www/other.txt"
  /usr/bin/python3 -m http.server "$gw" --bind 127.0.0.1 --directory "$TESTDIR/www" > "$FIX/gw-test-server.log" 2>&1 &
  local gwpid=$!
  sleep 1

  log "claude sandbox: per-sandbox denies (risk 9), -e variables (risk 5), HTTP rule (risk 4)"
  # the bare -e form takes the value from this process's environment, like the gateway token will
  PADDOCK_M0_SECRET="not-a-real-secret" cap sbx-create-claude txt sbx create --name "$RUN_ID-claude" \
    --deny-network localhost:5432 --deny-network localhost:17434 \
    -e PADDOCK_M0_VAR=hello -e PADDOCK_M0_SECRET claude "$TESTDIR"
  cap sbx-policy-allow-gw txt sbx policy allow network --sandbox "$RUN_ID-claude" "localhost:$gw" --method GET --path '/v1/**'
  cap sbx-policy-ls-claude json sbx policy ls "$RUN_ID-claude" --json
  # shellcheck disable=SC2016  # expanded inside the sandbox
  cap sbx-exec-claude-env txt sbx exec "$RUN_ID-claude" /bin/sh -c 'echo "VAR=${PADDOCK_M0_VAR:-unset} SECRET=${PADDOCK_M0_SECRET:+set}"'
  cap sbx-exec-claude-denied-5432 txt sbx exec "$RUN_ID-claude" /bin/sh -c "curl -sS -m 5 http://host.docker.internal:5432/ 2>&1; echo; echo exit=\$?"
  cap sbx-exec-claude-llmman-direct txt sbx exec "$RUN_ID-claude" /bin/sh -c "curl -sS -m 5 http://host.docker.internal:17434/llmman/shell 2>&1; echo; echo exit=\$?"
  cap sbx-exec-claude-gw-allowed txt sbx exec "$RUN_ID-claude" /bin/sh -c "curl -sS -m 5 -w '\nhttp=%{http_code}\n' http://host.docker.internal:$gw/v1/ok.txt 2>&1"
  cap sbx-exec-claude-gw-other-path txt sbx exec "$RUN_ID-claude" /bin/sh -c "curl -sS -m 5 -w '\nhttp=%{http_code}\n' http://host.docker.internal:$gw/other.txt 2>&1"
  cap sbx-exec-claude-gw-post txt sbx exec "$RUN_ID-claude" /bin/sh -c "curl -sS -m 5 -X POST -d x -w '\nhttp=%{http_code}\n' http://host.docker.internal:$gw/v1/ok.txt 2>&1"
  # a host no rule decides: does sbx publish a pending approval for it? (then list and inspect it)
  cap sbx-exec-claude-unknown-host txt sbx exec "$RUN_ID-claude" /bin/sh -c "curl -sS -m 10 -o /dev/null -w 'http=%{http_code}\n' https://example.org/ 2>&1"
  cap sbx-policy-approval-ls-claude json sbx policy approval ls --json
  # shellcheck disable=SC2016  # expanded by the inner shell
  cap sbx-policy-approval-inspect-claude json /bin/sh -c 'id=$(sbx policy approval ls -q 2>/dev/null | head -n1); [ -n "$id" ] && sbx policy approval inspect "$id" --json'
  kill "$gwpid" 2>/dev/null; wait "$gwpid" 2>/dev/null
  # after the allowed and denied requests above, so the log has both
  cap sbx-policy-log-claude json sbx policy log "$RUN_ID-claude" --json
  cap sbx-ls-with-claude json sbx ls --json
  cap sbx-exec-claude-pwd txt sbx exec "$RUN_ID-claude" /bin/sh -c 'pwd; ls -la; id'
  cap sbx-stop-claude txt sbx stop "$RUN_ID-claude"
  cap sbx-ls-claude-stopped json sbx ls --json
  # do -e variables survive a stop and start?
  # shellcheck disable=SC2016  # expanded inside the sandbox
  cap sbx-exec-claude-env-after-restart txt sbx exec "$RUN_ID-claude" /bin/sh -c 'echo "VAR=${PADDOCK_M0_VAR:-unset} SECRET=${PADDOCK_M0_SECRET:+set}"'
  cap sbx-stop-claude-again txt sbx stop "$RUN_ID-claude"

  log "builder: build a Dockerfile inside a sandbox, no host Docker"
  mkdir -p "$TESTDIR/build" && printf 'FROM scratch\nCOPY README.md /README.md\n' > "$TESTDIR/build/Dockerfile.sandbox"
  cp "$TESTDIR/README.md" "$TESTDIR/build/"
  # sbx requires a read/write primary workspace, so the builder mounts nothing and the
  # build context is copied in; the builder cannot write to the project at all
  cap sbx-create-builder txt sbx create --name "$RUN_ID-build" shell
  cap sbx-cp-context-in txt sbx cp "$TESTDIR/build" "$RUN_ID-build:/tmp/ctx"
  cap sbx-exec-builder-build txt sbx exec "$RUN_ID-build" /bin/sh -c \
    "cd /tmp/ctx && ls -la && docker build -t paddock/m0:test -f Dockerfile.sandbox . && docker save -o /tmp/image.tar paddock/m0:test && ls -la /tmp/image.tar"
  cap sbx-cp-builder txt sbx cp "$RUN_ID-build:/tmp/image.tar" "$ROOT/.tmp/capture-projects/image.tar"
  cap sbx-template-load txt sbx template load "$ROOT/.tmp/capture-projects/image.tar"
  cap sbx-template-ls-after-load json sbx template ls --json
  cap sbx-rm-builder json sbx rm --force --json "$RUN_ID-build"
  cap sbx-template-rm txt sbx template rm --force paddock/m0:test
  rm -f "$ROOT/.tmp/capture-projects/image.tar"

  log "remove"
  cap sbx-rm-claude json sbx rm --force --json "$RUN_ID-claude"
  sleep 3
  kill "$ev" 2>/dev/null; wait "$ev" 2>/dev/null
  [ -s "$FIX/sbx-events-lifecycle.stderr" ] || rm -f "$FIX/sbx-events-lifecycle.stderr"
  cap sbx-ls-after-rm json sbx ls --json
}

# ---------------------------------------------------------------- mounts

# Whether a folder can be added to a sandbox that exists (sbx 0.51's secret help speaks of "mounts
# added to a running sandbox later"; no command says how). Each try is followed by sbx ls and a
# look from inside, so the captures show what each did. Throwaway sandboxes, removed at the end.
phase_mounts() {
  local dir="$TESTDIR/mounts" cli="$RUN_ID-mnt" env="$RUN_ID-mntenv"
  log "will create sandboxes $cli and $env in $dir, try to add a folder to each, then remove them"
  confirm "Proceed?" || return 0
  mkdir -p "$dir/project" "$dir/extra-a" "$dir/extra-b" "$dir/env/project" "$dir/env/extra"
  echo "project" > "$dir/project/README.md"
  echo "extra a" > "$dir/extra-a/marker.txt"
  echo "extra b" > "$dir/extra-b/marker.txt"
  echo "env extra" > "$dir/env/extra/marker.txt"
  trap 'sbx rm --force "$RUN_ID-mnt" >/dev/null 2>&1; sbx rm --force "$RUN_ID-mntenv" >/dev/null 2>&1' EXIT
  cap mounts-sbx-version json sbx version --json

  # what the sandbox sees of both extra folders
  look() {
    cap "mounts-$1-ls" json sbx ls --json
    cap "mounts-$1-inside" txt sbx exec "$2" /bin/sh -c \
      "for f in '$dir/extra-a' '$dir/extra-b' '$dir/env/extra'; do echo \"## \$f\"; ls -la \"\$f\" 2>&1; cat \"\$f/marker.txt\" 2>&1; done"
  }

  log "1. the CLI: create with one extra folder, then name the sandbox again with two"
  cap mounts-create txt sbx create --name "$cli" shell "$dir/project" "$dir/extra-a:ro"
  look created "$cli"
  cap mounts-run-again txt sbx run --name "$cli" --detach shell "$dir/project" "$dir/extra-a:ro" "$dir/extra-b:ro"
  look after-run "$cli"
  cap mounts-create-again txt sbx create --name "$cli" shell "$dir/project" "$dir/extra-a:ro" "$dir/extra-b:ro"
  look after-create "$cli"

  log "2. sbx env: create from a file, add a workspace to it, plan, and apply"
  cat > "$dir/env/project/sbxenv.yaml" <<YAML
schemaVersion: "1"
name: $env
agent: shell
workspace: .
YAML
  cap mounts-env-create txt sbx env create "$dir/env/project/sbxenv.yaml" --skip-host-commands --force
  look env-created "$env"
  cat >> "$dir/env/project/sbxenv.yaml" <<YAML
additionalWorkspaces:
  - { path: ../extra, readOnly: true }
YAML
  cap mounts-env-plan txt sbx env plan "$dir/env/project/sbxenv.yaml"
  cap mounts-env-plan-json json sbx env plan "$dir/env/project/sbxenv.yaml" --json
  cap mounts-env-apply txt sbx env create "$dir/env/project/sbxenv.yaml" --skip-host-commands --force
  look env-applied "$env"

  log "remove"
  cap mounts-rm json sbx rm --force --json "$cli" "$env"
  trap - EXIT
}

# ---------------------------------------------------------------- models

# Runs inside the sandbox. Prints base-URL variables (values) and key variables (names only),
# then probes llmman's non-model routes with GETs. Never sends a WebSocket upgrade.
write_probe() {
  cat > "$1" <<'EOF'
#!/bin/sh
echo "## model env (key values hidden)"
env | grep -iE 'base_url|_host=|model|provider' | grep -viE 'key|token|secret' | sort
env | grep -iE 'key|token|secret' | sed -E 's/=.*/=<hidden>/' | sort
for base in "${ANTHROPIC_BASE_URL:-}" "${OPENAI_BASE_URL:-}" http://host.docker.internal:17434; do
  [ -n "$base" ] || continue
  root=$(printf '%s' "$base" | sed -E 's#(https?://[^/]+).*#\1#')
  echo "## probes against $root"
  for path in /api/version /api/tags /llmman/shell /llmman/providers /llmman/node; do
    printf '%-20s ' "$path"
    curl -sS -m 8 -o /tmp/probe.out -w '%{http_code}' "$root$path" 2>&1
    printf '  %s\n' "$(head -c 160 /tmp/probe.out 2>/dev/null | tr '\n' ' ')"
  done
done
EOF
}

phase_models() {
  cap sbx-settings-experimental-before json sbx settings get platform.allowExperimentalFeatures --json
  cap sbx-settings-feature-model-before json sbx settings get feature.model --json
  log "this enables sbx's experimental model feature, downloads a tiny model (~0.5 GB), and runs one sandbox"
  # feature.model is a JSON setting {enabled, variant, variantPayload}, not a bool;
  # platform.allowExperimentalFeatures already defaults to true
  confirm "Set feature.model to {\"enabled\":true}?" || return 0
  cap sbx-settings-set-feature-model txt sbx settings set feature.model '{"enabled":true,"variant":"","variantPayload":""}'
  cap sbx-settings-feature-model-after json sbx settings get feature.model --json
  sleep 6
  cap help-sbx-run-model-enabled txt sbx run --help
  cap help-sbx-create-model-enabled txt sbx create --help

  local model="${M0_MODEL:-unsloth/Qwen3.5-0.8B-GGUF}"
  confirm "Create a claude sandbox with --model $model (downloads it if needed)?" || return 0
  mkdir -p "$TESTDIR" && echo "m0 test" > "$TESTDIR/README.md"
  trap cleanup_sandboxes EXIT
  if ! cap sbx-create-model txt sbx create --name "$RUN_ID-model" --model "$model" claude "$TESTDIR"; then
    cap sbx-run-model txt sbx run -d --name "$RUN_ID-model" --model "$model" claude "$TESTDIR"
  fi
  cap sbx-policy-ls-model json sbx policy ls "$RUN_ID-model" --json

  log "risk 3: what can a --model sandbox reach on llmman?"
  write_probe "$TESTDIR/probe.sh"
  cap sbx-exec-model-probe txt sbx exec "$RUN_ID-model" /bin/sh "$TESTDIR/probe.sh"
  cap llmmanapi-ps-after-model json http_get "$LLMMAN_BASE/api/ps"
  cap llmmanapi-tags-after-model json http_get "$LLMMAN_BASE/api/tags"
  cap llmmanapi-shell-status-after json http_get "$LLMMAN_BASE/llmman/shell"
  # risk 4: does sbx's llmman keep prompt history?
  cap llmman-prompts-count-after txt /bin/sh -c "wc -l < \"$HOME/.local/share/llmman/prompts.jsonl\""

  cap sbx-rm-model json sbx rm --force --json "$RUN_ID-model"

  log "round 5: how sbx configures opencode for a local model (we copy the approach for the gateway)"
  cap sbx-run-opencode-model txt sbx run -d --name "$RUN_ID-opencode" --model "$model" opencode "$TESTDIR"
  cap sbx-exec-opencode-env txt sbx exec "$RUN_ID-opencode" /bin/sh -c "env | grep -iE 'opencode|base_url|model|provider' | sed -E 's/((KEY|TOKEN|SECRET)[A-Z_]*=).*/\1<hidden>/' | sort"
  cap sbx-exec-opencode-config-files txt sbx exec "$RUN_ID-opencode" /bin/sh -c "ls -la ~/.config/opencode ~/.local/share/opencode 2>&1; for f in ~/.config/opencode/*.json ~/.config/opencode/*.jsonc; do [ -f \"\$f\" ] && { echo \"## \$f\"; sed -E 's/(\"(apiKey|api_key|token|key)\"[[:space:]]*:[[:space:]]*)\"[^\"]*\"/\1\"<hidden>\"/' \"\$f\"; }; done; true"
  local kits="$HOME/Library/Application Support/com.docker.sandboxes/sandboxes/sandboxd/model-kits"
  cap sbx-model-kits-files-after txt dump_redacted "$kits"
  cap sbx-rm-opencode json sbx rm --force --json "$RUN_ID-opencode"
  trap - EXIT
  rm -f "$TESTDIR/probe.sh"
  if confirm "Turn the model feature off again (sbx settings unset feature.model)?"; then
    cap sbx-settings-unset-feature-model txt sbx settings unset feature.model
  fi
}

# ---------------------------------------------------------------- v3 (PAD-73.1)

# A throwaway project for sbx env and v3 kits: sbxenv.yaml with the v3 Claude workload, a local
# mixin that touches every capability Paddock will read, two extra folders, and an overlay
# outside the project. Kept in $TESTDIR so it can be inspected after the run.
write_v3_project() {
  local dir="$1" port="$2"
  mkdir -p "$dir/project/probe" "$dir/extra-ro" "$dir/extra-rw" "$dir/overlay"
  echo "m0 v3 test" > "$dir/project/README.md"
  echo "read-only extra" > "$dir/extra-ro/README.md"
  cat > "$dir/project/sbxenv.yaml" <<EOF
schemaVersion: "1"
name: $RUN_ID-v3
agent: sbx-kit-claude
workspace: .
additionalWorkspaces:
  - { path: ../extra-ro, readOnly: true }
  - { path: ../extra-rw }
kits:
  - ${M0_CLAUDE_KIT:-docker.io/docker/sbx-kit-claude:2.1.316}
  - ./probe
ports:
  - { sandbox: 3000, host: 18998 }
lifecycle:
  initialize:
    - name: host marker
      command: touch "$dir/host-command-ran"
EOF
  cat > "$dir/project/probe/probe.yaml" <<EOF
# syntax=docker/sandbox-kit:3
schemaVersion: "3"
kind: mixin
displayName: Paddock M0 probe
version: "0.1.0"
provides: [paddock-m0-probe]
capabilities:
  - type: com.docker.sandbox/network-policy@2
    config:
      install:
        allow: [example.org]
      runtime:
        allow:
          - example.com
          - { hosts: [httpbin.org], methods: [GET], paths: ["/get"] }
  # sbx 0.51 refuses host-port@1 as required ("unsupported capability type"); optional, to see
  # whether an optional capability sbx lacks is skipped.
  - { type: com.docker.sandbox/host-port@1, optional: true, config: { host: $port } }
  - type: com.docker.sandbox/lifecycle@1
    config:
      files:
        - path: /tmp/paddock-m0/static.txt
          content: "written by lifecycle files"
      install:
        - description: install-phase network
          command: [sh, -c, "date +%s > /tmp/paddock-m0-install; curl -sS -m 8 -o /dev/null -w 'org=%{http_code}\\\\n' https://example.org/ >> /tmp/paddock-m0-install 2>&1; true"]
      startup:
        - description: startup timing
          command: [sh, -c, "mkdir -p /tmp/paddock-m0; date +%s >> /tmp/paddock-m0-startup; env | sort > /tmp/paddock-m0/startup-env.txt"]
  - type: com.docker.sandbox/agent-context@2
    config:
      content: Paddock M0 probe kit.
EOF
  cat > "$dir/project/probe/probe.dockerfile" <<'EOF'
FROM scratch
COPY marker.txt /opt/paddock-m0/marker.txt
ENV PADDOCK_M0_IMAGE_ENV=probe \
    PATH=/opt/paddock-m0/bin
EOF
  echo "from the probe kit" > "$dir/project/probe/marker.txt"
  cat > "$dir/overlay/sbxenv.yaml" <<EOF
schemaVersion: "1"
agent: sbx-kit-claude
env:
  PADDOCK_M0_OVERLAY: "1"
EOF
  # a broken project file, for the error shape
  mkdir -p "$dir/broken"
  printf 'schemaVersion: "1"\nagent: sbx-kit-claude\nnotAField: 1\n' > "$dir/broken/sbxenv.yaml"
}

phase_v3() {
  local name="$RUN_ID-v3" port=19123 dir="$TESTDIR/v3"
  log "will build a v3 test project in $dir, create sandbox $name from it with an overlay, probe it, and remove it"
  confirm "Proceed?" || return 0
  write_v3_project "$dir" "$port"
  local project="$dir/project/sbxenv.yaml" overlay="$dir/overlay/sbxenv.yaml"
  trap 'sbx rm --force "$RUN_ID-v3" >/dev/null 2>&1; sbx rm --force "$RUN_ID-v2mix" >/dev/null 2>&1' EXIT

  log "version and help"
  cap v3-sbx-version json sbx version --json
  if grep -qE '"version": "v0\.(4[0-9]|50)\.' "$FIX/v3-sbx-version.json" 2>/dev/null; then
    warn "sbx is older than 0.51: agent-context@2 in the probe kit may be refused (brew upgrade docker/tap/sbx)"
  fi
  for sub in plan run create exec rm; do cap "help-sbx-env-$sub" txt sbx env "$sub" --help; done
  cap help-sbx-kit txt sbx kit --help
  cap help-sbx-kit-add txt sbx kit add --help

  log "plans (nothing changes)"
  cap v3-env-plan txt sbx env plan "$project"
  cap v3-env-plan-json json sbx env plan "$project" --json
  cap v3-env-plan-format-json json sbx env plan "$project" --format json
  cap v3-env-plan-overlay txt sbx env plan "$project" "$overlay"
  cap v3-env-plan-overlay-json json sbx env plan "$project" "$overlay" --json
  cap v3-env-plan-broken txt sbx env plan "$dir/broken/sbxenv.yaml"
  cap v3-env-plan-broken-json json sbx env plan "$dir/broken/sbxenv.yaml" --json

  log "create with the overlay; host commands skipped (a marker file shows whether they ran)"
  /usr/bin/python3 -m http.server "$port" --bind 127.0.0.1 --directory "$dir/project" > "$FIX/v3-host-port-server.log" 2>&1 &
  local srv=$!
  "$(command -v sbx)" events --json > "$FIX/v3-events-create.ndjson" 2> /dev/null &
  local ev=$!
  cap v3-env-create txt sbx env create "$project" "$overlay" --skip-host-commands --force
  date +%s > "$dir/create-returned"
  [ -e "$dir/host-command-ran" ] && warn "a lifecycle host command ran despite --skip-host-commands"
  cap v3-host-command-ran txt /bin/sh -c "ls -la '$dir/host-command-ran' 2>&1; true"

  log "what sbx reports for a v3 sandbox"
  cap v3-sbx-ls json sbx ls --json
  cap v3-policy-ls json sbx policy ls "$name" --json
  cap v3-ports json sbx ports "$name" --json

  log "inside: env, files, timing, folders"
  # shellcheck disable=SC2016  # expanded inside the sandbox
  cap v3-exec-env txt sbx exec "$name" /bin/sh -c 'echo "IMAGE_ENV=${PADDOCK_M0_IMAGE_ENV:-unset} OVERLAY=${PADDOCK_M0_OVERLAY:-unset} WORKSPACE_DIR=${WORKSPACE_DIR:-unset}"; echo "PATH=$PATH"; ls -la /opt/paddock-m0 2>&1'
  # shellcheck disable=SC2016
  cap v3-exec-bash-env txt sbx exec "$name" bash -lc 'echo "login IMAGE_ENV=${PADDOCK_M0_IMAGE_ENV:-unset} PATH=$PATH"; echo "BASH_ENV=${BASH_ENV:-unset}"; ls -la /etc/sandbox-persistent.sh 2>&1'
  cap v3-exec-files txt sbx exec "$name" /bin/sh -c 'cat /tmp/paddock-m0/static.txt; echo; echo startup-env:; cat /tmp/paddock-m0/startup-env.txt; echo install:; cat /tmp/paddock-m0-install; echo startup:; cat /tmp/paddock-m0-startup; true'
  cap v3-create-returned txt cat "$dir/create-returned"
  cap v3-exec-mounts txt sbx exec "$name" /bin/sh -c "pwd; mount | grep -E 'extra|project' ; ls -la '$dir/extra-ro' '$dir/extra-rw' 2>&1; touch '$dir/extra-ro/w' 2>&1 && echo ro-writable || echo ro-refused; touch '$dir/extra-rw/w' 2>&1 && echo rw-writable || echo rw-refused"
  cap v3-exec-claude-settings txt sbx exec "$name" /bin/sh -c "command -v claude; ls -la ~/.claude 2>&1; sed -E 's/((key|token|secret)[A-Za-z_]*\"?[[:space:]]*:[[:space:]]*)\"[^\"]*\"/\1\"<hidden>\"/' ~/.claude/settings.json 2>&1; true"
  cap v3-exec-kit-files txt sbx exec "$name" /bin/sh -c 'ls -laR /usr/share/sandbox/kit 2>&1 | head -60'

  log "network: kit allow, bounded allow, unlisted host, host port, then a sandbox deny over the kit allow"
  local probe="curl -sS -m 8 -o /dev/null -w '%{http_code}\n'"
  cap v3-net-kit-allowed txt sbx exec "$name" /bin/sh -c "$probe https://example.com/ 2>&1; true"
  cap v3-net-bounded-get txt sbx exec "$name" /bin/sh -c "$probe https://httpbin.org/get 2>&1; true"
  cap v3-net-bounded-other txt sbx exec "$name" /bin/sh -c "$probe https://httpbin.org/anything 2>&1; true"
  cap v3-net-unlisted txt sbx exec "$name" /bin/sh -c "$probe https://example.net/ 2>&1; true"
  cap v3-net-install-only txt sbx exec "$name" /bin/sh -c "$probe https://example.org/ 2>&1; true"
  cap v3-net-host-port txt sbx exec "$name" /bin/sh -c "curl -sS -m 5 http://127.0.0.1:$port/README.md 2>&1; curl -sS -m 5 http://localhost:$port/README.md 2>&1; true"
  cap v3-policy-deny-kit-host txt sbx policy deny network --sandbox "$name" example.com
  cap v3-net-kit-allowed-after-deny txt sbx exec "$name" /bin/sh -c "$probe https://example.com/ 2>&1; true"
  cap v3-policy-ls-after-deny json sbx policy ls "$name" --json
  kill "$srv" 2>/dev/null; wait "$srv" 2>/dev/null

  log "the project file alone against the sandbox the overlay made (plan only)"
  cap v3-env-plan-without-overlay txt sbx env plan "$project"
  cap v3-env-plan-without-overlay-json json sbx env plan "$project" --json

  log "stop and start: do startup hooks run again?"
  cap v3-stop txt sbx stop "$name"
  cap v3-exec-after-start txt sbx exec "$name" /bin/sh -c 'cat /tmp/paddock-m0-startup; true'

  log "a v3 mixin on the built-in claude agent (expected to fail; the error is the capture)"
  cap v3-create-v2-mix txt sbx create --name "$RUN_ID-v2mix" --kit "$dir/project/probe" claude "$dir/project"

  log "remove"
  cap v3-rm-v2mix json sbx rm --force --json "$RUN_ID-v2mix"
  cap v3-env-rm txt sbx env rm "$project" "$overlay" --force
  sleep 2
  kill "$ev" 2>/dev/null; wait "$ev" 2>/dev/null
  cap v3-sbx-ls-after-rm json sbx ls --json
  trap - EXIT
  log "the test project stays in $dir for a look; remove it with rm -rf"
}

# ---------------------------------------------------------------- kits (PAD-73.2)

# Paddock's own kits in their v3 form (written by PaddockCore's tests), on the built-in claude
# and opencode agents of sbx >= 0.51: does sbx take them, and does each do its job?
# kits [PARTS]: PARTS is a comma-separated choice of status, voice, browser (each kit alone),
# gateway (no kit, environment only), claude (every kit together), opencode; all when empty.
wanted() {
  [ -z "${M0_ONLY:-}" ] && return 0
  case ",$M0_ONLY," in *",$1,"*) return 0 ;; *) return 1 ;; esac
}

# After a create failed: the end of sbx's daemon log (key and token values hidden), and stop.
kits_failed() {
  local name="$1"
  # shellcheck disable=SC2016  # expanded by the inner shell
  cap "$name-daemon-log" txt /bin/sh -c 'log=$(sbx daemon status --format json | sed -n "s/.*\"logs\": *\"\([^\"]*\)\".*/\1/p"); [ -f "$log" ] && tail -n 150 "$log"'
  redact "$FIX/$name-daemon-log.txt" > "$FIX/$name-daemon-log.redacted.txt" 2>/dev/null
  rm -f "$FIX/$name-daemon-log.txt"
  warn "$name failed; stopping (see $FIX/$name.stderr and $name.txt)"
}

phase_kits() {
  # Stops at the first sandbox that is not created; the EXIT trap removes what was.
  local dir="$TESTDIR/kits" claude="$RUN_ID-kits" opencode="$RUN_ID-kits-oc"
  local playwright="docker.io/sbx/playwright:1.61.1@sha256:d60c965e2ee124128e611f9ea95ea36e240c1db8dd3017f890622c5091492287"
  log "will write Paddock's kits to $dir, create $claude (claude) and $opencode (opencode) with them, probe, and remove both"
  confirm "Proceed?" || return 0
  mkdir -p "$dir/project" && echo "m0 kits test" > "$dir/project/README.md"
  trap 'for n in kits kits-oc k-status k-voice k-browser k-gwenv; do sbx rm --force "$RUN_ID-$n" >/dev/null 2>&1; done' EXIT
  log "writing the kits (swift test, PaddockCore)"
  # A build folder of its own: the package's .build may come from another checkout's path
  # (its module cache then refuses to load), and this run should not touch it.
  PADDOCK_DUMP_KITS="$dir/config" cap kits-dump txt swift test --package-path "$ROOT/Packages/PaddockCore" \
    --scratch-path "$ROOT/.tmp/capture-projects/swift-build" --filter dumpTheKitsWhenAsked
  local kits="$dir/config/kits"
  if [ ! -f "$kits/paddock-status/paddock-status.yaml" ]; then
    warn "the kits were not written (see $FIX/kits-dump.stderr); stopping"
    trap - EXIT
    return 1
  fi
  cap kits-files txt /bin/sh -c "ls -la '$kits'/*"
  cap kits-sbx-version json sbx version --json

  log "each kit alone on claude, with sbx's progress (the failing one names itself)"
  local set label
  local node="$kits/paddock-node"
  for set in "status:$node $kits/paddock-status" "voice:$node $kits/paddock-status $kits/paddock-voice" \
             "browser:$node $playwright $kits/paddock-browser"; do
    label="${set%%:*}"
    wanted "$label" || continue
    local args=()
    for kit in ${set#*:}; do args+=(--kit "$kit"); done
    if ! cap "kits-alone-$label" txt sbx create --name "$RUN_ID-k-$label" "${args[@]}" claude "$dir/project"; then
      kits_failed "kits-alone-$label"
      return 1
    fi
    # shellcheck disable=SC2016  # expanded inside the sandbox
    cap "kits-alone-$label-logs" txt sbx exec "$RUN_ID-k-$label" /bin/sh -c 'find /var/log/sbx-kits -type f | while read -r f; do echo "## $f"; tail -n 30 "$f"; done; echo "## startup"; tail -n 30 /var/log/sbx-kit-startup.log 2>&1; echo "## hooks"; grep -c paddock /home/agent/.claude/settings.json'
    sbx rm --force "$RUN_ID-k-$label" >/dev/null 2>&1
  done

  if wanted gateway; then
  log "the gateway without a kit: environment only, against a fake gateway on this Mac"
  local fake=17478 gwenv="$RUN_ID-k-gwenv"
  /usr/bin/python3 -I "$ROOT/tools/tasks/lib/fake-anthropic.py" "$fake" "$FIX/kits-fake-gateway.ndjson" > /dev/null 2>&1 &
  local fakepid=$!
  "$(command -v sbx)" events --json > "$FIX/kits-gwenv-events.ndjson" 2> /dev/null &
  local evpid=$!
  rm -f "$FIX/kits-fake-gateway.ndjson"
  if ! cap kits-gwenv-create txt sbx create --name "$gwenv" \
    -e ANTHROPIC_BASE_URL="http://host.docker.internal:$fake" -e ANTHROPIC_AUTH_TOKEN=paddock \
    -e ANTHROPIC_MODEL=m0-model -e ANTHROPIC_SMALL_FAST_MODEL=m0-model -e SBX_CRED_ANTHROPIC_MODE=none \
    -e CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 -e CLAUDE_CODE_AUTO_MODE_SERVER=0 -e CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1 \
    claude "$dir/project"; then
    kill "$evpid" "$fakepid" 2>/dev/null
    kits_failed kits-gwenv-create
    return 1
  fi
  cap kits-gwenv-allow txt sbx policy allow network --sandbox "$gwenv" "localhost:$fake" --method GET,POST --path '/v1/**'
  cap kits-gwenv-claude txt sbx exec "$gwenv" bash -lc 'timeout 120 claude -p "Reply with the word pong." 2>&1; echo "exit=$?"'
  # shellcheck disable=SC2016  # expanded inside the sandbox
  cap kits-gwenv-claude-files txt sbx exec "$gwenv" /bin/sh -c 'grep -o "customApiKeyResponses[^]]*]" /home/agent/.claude.json /home/agent/.claude/.config.json 2>&1; echo; grep -o "\"hasCompletedOnboarding\": *[a-z]*" /home/agent/.claude.json /home/agent/.claude/.config.json 2>&1; true'
  cap kits-sbx-claude-hook txt sbx exec "$gwenv" /bin/sh -c 'ls -la /usr/local/bin/sbx-claude-hook; head -n 400 /usr/local/bin/sbx-claude-hook'
  sleep 2
  kill "$evpid" "$fakepid" 2>/dev/null; wait "$evpid" "$fakepid" 2>/dev/null
  sbx rm --force "$gwenv" >/dev/null 2>&1
  fi

  if wanted claude; then
  log "claude with node, playwright, browser, status, and voice (the gateway as environment)"
  if ! cap kits-create-claude txt sbx create --name "$claude" \
    --kit "$node" --kit "$playwright" --kit "$kits/paddock-browser" --kit "$kits/paddock-status" --kit "$kits/paddock-voice" \
    -e ANTHROPIC_BASE_URL=http://host.docker.internal:17480 -e ANTHROPIC_AUTH_TOKEN=paddock -e SBX_CRED_ANTHROPIC_MODE=none \
    claude "$dir/project"; then
    kits_failed kits-create-claude
    return 1
  fi
  cap kits-ls json sbx ls --json
  cap kits-ports-claude json sbx ports "$claude" --json
  cap kits-policy-claude json sbx policy ls "$claude" --json
  # shellcheck disable=SC2016  # expanded inside the sandbox
  cap kits-claude-bins txt sbx exec "$claude" /bin/sh -c 'node --version; npm --version; for b in paddock paddock-browser-watch paddock-agent-state paddock-agent-watch paddock-voice paddock-voice-watch playwright-cli; do printf "%s: " "$b"; command -v "$b" || echo missing; done; grep -c paddock-agent-state /home/agent/.claude/settings.json'
  # shellcheck disable=SC2016  # expanded inside the sandbox
  cap kits-claude-env txt sbx exec "$claude" /bin/sh -c 'env | grep -E "^(PLAYWRIGHT_MCP_|PWTEST_|ANTHROPIC_BASE_URL|SBX_CRED_ANTHROPIC_MODE|CLAUDE_CODE_|ANTHROPIC_API_KEY)" | sed -E "s/(API_KEY=).*/\1<set>/" | sort'
  cap kits-claude-settings txt sbx exec "$claude" /bin/sh -c 'cat /home/agent/.claude/settings.json; echo; echo "config:"; cat /home/agent/.claude/.config.json 2>&1'
  # shellcheck disable=SC2016  # expanded inside the sandbox
  cap kits-claude-logs txt sbx exec "$claude" /bin/sh -c 'find /var/log/sbx-kits -type f | while read -r f; do echo "## $f"; tail -n 20 "$f"; done; echo "## startup"; tail -n 40 /var/log/sbx-kit-startup.log 2>&1'
  cap kits-claude-dashboard txt sbx exec "$claude" /bin/sh -c 'sleep 3; curl -sS -m 5 -o /dev/null -w "%{http_code} %{redirect_url}\n" http://127.0.0.1:38323/ 2>&1; true'
  cap kits-claude-state txt sbx exec "$claude" /bin/sh -c 'paddock-agent-state working claude m0-session; ls -la /tmp/paddock-agent/sessions 2>&1; cat /tmp/paddock-agent/sessions/*.json 2>&1'
  fi

  if wanted opencode; then
  log "opencode (sbx's own kit, OpenCode 2) with the status kit"
  if ! cap kits-create-opencode txt sbx create --name "$opencode" --kit "$kits/paddock-node" --kit "$kits/paddock-status" opencode "$dir/project"; then
    kits_failed kits-create-opencode
    return 1
  fi
  # shellcheck disable=SC2016  # expanded inside the sandbox
  cap kits-opencode-logs txt sbx exec "$opencode" /bin/sh -c 'find /var/log/sbx-kits -type f | while read -r f; do echo "## $f"; tail -n 40 "$f"; done'
  # shellcheck disable=SC2016  # expanded inside the sandbox
  cap kits-opencode-version txt sbx exec "$opencode" /bin/sh -c 'opencode --version 2>&1; echo "OPENCODE_DISABLE_AUTOUPDATE=${OPENCODE_DISABLE_AUTOUPDATE:-unset}"; ls -la /home/agent/.config/opencode/plugins 2>&1'
  fi

  log "remove"
  wanted claude && cap kits-rm-claude json sbx rm --force --json "$claude"
  wanted opencode && cap kits-rm-opencode json sbx rm --force --json "$opencode"
  trap - EXIT
}

case "${1:-}" in
  readonly) phase_readonly ;;
  lifecycle) phase_lifecycle ;;
  models) phase_models ;;
  v3) phase_v3 ;;
  kits) M0_ONLY="${2:-}" phase_kits || exit 1 ;;
  mounts) phase_mounts ;;
  *) echo "usage: $0 readonly|lifecycle|models|v3|kits [status,voice,browser,gateway,claude,opencode]|mounts"; exit 2 ;;
esac
log "done. Fixtures in $FIX"
