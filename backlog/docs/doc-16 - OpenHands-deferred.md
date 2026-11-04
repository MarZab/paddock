---
id: doc-16
title: OpenHands (deferred)
type: specification
created_date: '2026-10-25 15:55'
updated_date: '2026-10-25 15:55'
---
Dropped from v1 in favor of two terminal agents, because it is much heavier (web UI, agent server, automation service, ingress proxy, about 370 Python packages installed at first start) and needs extra machinery. What M0 learned, for when it comes back:

- **Create:** `sbx run -d --name N -p HOSTPORT:8000 docker.io/sbx/openhands-canvas-kit:latest FOLDER` (kit as the first positional; sbx 0.49.2 warns that `--kit KIT openhands-canvas` is deprecated). On first start sbx asks interactively to **approve the kit's credentials** (`anthropic`, `openai`, `google`; 1 approve all, 2 review, 3 start without); Paddock's background session must surface that prompt in the UI rather than hide it. **`-d` does not start the kit's entrypoint**, so Paddock then runs the agent session itself (`sbx run --name N`) as a background PTY process it owns, and loads the web view once `GET http://localhost:HOSTPORT/health` is `200`. `sbx ports N --json`: `[{host_ip, host_port, sandbox_port, protocol}]`
- **Wiring to the gateway:** `openhands-canvas` is a `kind: sandbox` kit on `shell-docker` whose entrypoint `openhands-canvas-launch` starts Agent Canvas on `$PORT` (8000) and seeds the model with `PATCH /api/settings` (`agent_settings_diff.llm.{model, api_key}`, authorized by `X-Session-API-Key` from `~/.openhands/agent-canvas/api-key.txt`). Canvas does not read `LLM_*` variables. For a local model, Paddock sends the same PATCH with an OpenAI-compatible model, `base_url` pointing at the gateway, and the dummy key `paddock` (the gateway has no tokens; field names confirmed in M0). Default without the gateway: `anthropic/claude-opus-4-8`, key proxy-injected after `sbx secret set anthropic`.
- **Caveat:** the kit sets `NO_PROXY=localhost,127.0.0.1,host.docker.internal`, so it connects to `host.docker.internal` directly. In M0 a direct connection to llmman's port was still blocked, but whether an allowed direct connection still gets the HTTP path rule was not tested.
- **Not reachable yet:** with `-p 18000:8000`, `GET http://localhost:18000/health` from the host returned `000` although Agent Canvas was running. Its ingress listens on `localhost:8000` inside the VM, which may be loopback or IPv6 only, so sbx's IPv4 forward may not reach it. Untested fix ideas: publish `tcp6`, or run the ingress on `0.0.0.0`.
- **Startup:** about 15 seconds after first install; first install downloads several hundred MB.
- Spec: https://github.com/docker/sbx-kits-contrib/tree/main/openhands-canvas
