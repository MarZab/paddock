---
id: doc-3
title: Models
type: specification
created_date: '2026-10-25 15:55'
updated_date: '2026-10-25 15:55'
---
**What it is** ([llmmanorg/llmman](https://github.com/llmmanorg/llmman), Rust, Apache-2.0):

- Installed with sbx at `Sbx.app/Contents/MacOS/llmman` (operator: v0.1.571). sbx's daemon (`sbx daemon start`, detached, parent launchd) runs it as `llmman serve`, as the operator's user, at daemon start (even if `--model` is never used), and stops it with the daemon. It inherits the daemon's environment.
- Serves the Ollama, OpenAI (`/v1/chat/completions`, `/v1/responses`), and Anthropic (`/v1/messages`) APIs, plus its own `/llmman/*` API and a web UI. **Verified (M0 round 2): sbx's llmman listens on `127.0.0.1:17434` only and has no API keys** (every route answers without one), so any local process can use it, including pull and delete. That is why sandboxes must never reach this port directly.
- Engines: llama.cpp for GGUF models; `mlx_lm.server` for safetensors models on macOS (MLX). Each loaded model runs as its own subprocess on a random loopback port and unloads after `keep_alive` (default 5 minutes).
- Files: model store `~/.local/share/llmman/store` (OCI layout), engines under `~/.local/share/llmman/<tool>/<version>/` (operator already has `llama.cpp/b11669`, `uv/0.12.13`, `mlx-lm/0.31.3-py3.13`), config `~/.config/llmman/llmman.conf` (not created yet; it would hold provider keys set from the UI), `prompts.jsonl` and `usage.jsonl` beside the store (not created yet, so no requests so far).
- **Not sandboxed:** it runs as the operator with full file and network access. Paddock accepts this (llmman is part of sbx) and does not try to wrap it.

**Reuse llmman's UI.** The Models pane is a WKWebView on llmman's own web UI (models: search, pull, delete; chat; providers; servers; settings). Paddock does not build its own model manager. Paddock's native parts are small:

- `LlmmanAPI` (typed, fixture-tested, read-mostly): `GET /api/version`, `/api/tags` (installed models, for the project model picker), `/api/ps` (loaded models and `expires_at`, for the status popover), `/llmman/node` (memory), `GET /llmman/shell` (status only, never an upgrade).
- `LlmmanHealth`: the hardening checks below, shown behind the status button. `LlmmanHealthEvaluator` is pure (fixture-tested); `LlmmanHealthChecker` gathers the inputs (`/api/version` for the PID, `/llmman/shell`, `lsof -nP -a -p PID -iTCP -sTCP:LISTEN -F n`, the size of `prompts.jsonl`). Anything it cannot observe is red. The gateway trial runs the same checks and refuses to start on red.

**Hardening (each check is a badge; any red check blocks embedding the UI and creating projects that use local models):**

1. **Web shell off.** llmman's web UI includes a shell on the host as the operator (`/llmman/shell`), on by default in plain llmman, and it accepts any client that sends no `Origin` header. Only the environment variable `LLMMAN_SHELL=off` turns it off (no config-file key). **sbx already sets it:** M0 round 2 got `{"enabled":false,"reason":"LLMMAN_SHELL is off"}`. Paddock keeps checking on every launch and after each `sbx daemon restart`, because a future sbx version could change this; if it is ever on, the check is red and Paddock tells the operator (it does not try to fix sbx's environment itself).
2. **Prompt history** (verified on: sbx does not set `LLMMAN_NOHISTORY`): llmman writes the last user message of every request, including every agent request through the gateway, to `~/.local/share/llmman/prompts.jsonl` (owner-readable only). Paddock shows a yellow badge with the file's size and a "Clear history" action, Clear history works. An opt-in "Restart sbx with prompt history off" action (`sbx daemon restart` with `LLMMAN_NOHISTORY=1` in its environment, after operator confirmation) is not built: whether the variable reaches llmman that way is open (PAD-13).
3. **Loopback only:** llmman listens on `127.0.0.1` / `::1` only (`lsof -nP -iTCP -sTCP:LISTEN` for the llmman PID). A wildcard or LAN bind is red.
4. **Not reachable from sandboxes:** llmman's port is denied for every Paddock sandbox. This is why Paddock does not use sbx's `--model` (see below) and runs its own gateway instead.

**Why not sbx's `--model`** (verified in M0 round 3):

- `sbx run --model M` (not available on `sbx create`) provisions a per-sandbox rule `allow localhost:17434` (`created_via: provisioned`, plain TCP) and sets `ANTHROPIC_BASE_URL=http://host.docker.internal:17434`. The sandbox then reaches **llmman's whole API without a key**: from inside, `/api/version`, `/api/tags`, `/llmman/providers`, `/llmman/node`, and `/llmman/shell` all answered `200`. So a `--model` sandbox can pull any model (an attacker-chosen GGUF parsed on the host), delete or push models, and set or spend llmman's provider keys. Only the web shell is off.
- Without `--model`, sbx keeps sandboxes away from llmman (default deny, verified).
