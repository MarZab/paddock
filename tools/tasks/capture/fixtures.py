#!/usr/bin/env -S python3 -I
#MISE description="Turn raw captures in .tmp/captures into sanitized test fixtures (--only NAME for some)"
"""Turn raw M0 captures into fixtures that are safe to commit.

Reads .tmp/captures/ (gitignored) and writes
sanitized copies to Fixtures/sbx/ and Fixtures/llmman/. Shapes and field names stay
exactly as captured; only private values change:

- the operator's home directory becomes /Users/operator
- sandbox names become project-a, project-b, ...
- workspace paths become /Users/operator/Projects/<sandbox name>
- hostnames that no sbx default rule allows become hostN.example.test
- custom template repositories become docker.io/library/custom-N
- long catalogs (llmman providers, events) are trimmed

Usage: mise run capture:fixtures [--only NAME]

--only NAME writes only the fixtures whose path contains NAME (say policy-log), so a new capture
does not rewrite fixtures other tests rely on.
"""

import fnmatch
import ipaddress
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent.parent
FIX = ROOT / "Packages/PaddockCore/Tests/PaddockCoreTests/Fixtures"
RAW = ROOT / ".tmp/captures"
HOME_RE = re.compile(r"/Users/[^/\"]+")
ONLY = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv[:-1] else None


def load_json(name):
    text = (RAW / name).read_text()
    # http_get appends "http=<code>" after the body
    text = re.sub(r"\nhttp=\d+\s*$", "", text.strip())
    return json.loads(text)


class Sanitizer:
    def __init__(self, sandboxes, default_resources):
        self.names = {}
        for i, sb in enumerate(sandboxes):
            self.names[sb["name"]] = "project-" + chr(ord("a") + i)
        self.default_resources = default_resources
        self.hosts = {}

    def name(self, value):
        m = re.fullmatch(r"m0\d+-(\w+)", value)
        if m:
            return "m0-" + m.group(1)
        return self.names.setdefault(value, "project-" + chr(ord("a") + len(self.names)))

    def is_public(self, host):
        bare = host.split(":")[0]
        if bare in ("localhost", "host.docker.internal"):
            return True
        # Loopback and private addresses say nothing about the operator; a public one (a server
        # the agent tried to reach) does, and becomes a documentation address (host()).
        if re.fullmatch(r"[\d.]+", bare):
            try:
                address = ipaddress.ip_address(bare)
            except ValueError:
                return True
            return address.is_private or address.is_loopback
        for pattern in self.default_resources:
            p = pattern.split(":")[0].replace("**.", "*.")
            if fnmatch.fnmatch(bare, p) or bare == p.lstrip("*."):
                return True
        return False

    def host(self, value):
        if self.is_public(value):
            return value
        prefix = ""
        m = re.match(r"^(\*\*?\.)", value)
        if m:
            prefix = m.group(1)
            value = value[len(prefix):]
        hostpart, _, port = value.partition(":")
        if hostpart not in self.hosts:
            if re.fullmatch(r"[\d.]+", hostpart):
                self.hosts[hostpart] = "203.0.113.%d" % (len(self.hosts) + 1)
            else:
                self.hosts[hostpart] = "host%d.example.test" % (len(self.hosts) + 1)
        return prefix + self.hosts[hostpart] + (":" + port if port else "")

    def text(self, value):
        value = HOME_RE.sub("/Users/operator", value)
        for real, fake in self.names.items():
            value = value.replace(real, fake)
        return value


def write(rel, data, ndjson=False):
    if ONLY and ONLY not in rel:
        return
    out = FIX / rel
    out.parent.mkdir(parents=True, exist_ok=True)
    if ndjson:
        out.write_text("".join(json.dumps(d, separators=(",", ":")) + "\n" for d in data))
    else:
        out.write_text(json.dumps(data, indent=2) + "\n")
    print("wrote", out.relative_to(ROOT))


def main():
    if not RAW.is_dir():
        sys.exit("no raw captures in %s; run mise run capture:cli readonly first" % RAW)

    sandboxes = load_json("sbx-ls.json")
    policy = load_json("sbx-policy-ls.json")
    # public hostnames: what sbx's default network rules allow ("**" is the filesystem default, not a host)
    defaults = [r for rule in policy["rules"]
                if rule.get("provenance", {}).get("created_via") == "default" and rule["resource_type"] == "network"
                for r in rule["resources"] if r != "**"]
    s = Sanitizer(sandboxes, defaults)

    # sbx ls
    for sb in sandboxes:
        sb["name"] = s.name(sb["name"])
        sb["agent"] = sb["agent"] if sb["agent"] in ("claude", "codex", "shell", "opencode") else "claude"
        sb["workspaces"] = ["/Users/operator/Projects/" + sb["name"] for _ in sb["workspaces"]]
    write("sbx/ls.json", sandboxes)

    write("sbx/version.json", load_json("sbx-version.json"))

    daemon = load_json("sbx-daemon-status.json")
    write("sbx/daemon-status.json", {k: s.text(v) if isinstance(v, str) else v for k, v in daemon.items()})

    def clean_rule(rule):
        rule = dict(rule)
        rule["name"] = s.text(re.sub(r"m0\d+-", "m0-", rule["name"]))
        for key in ("scope", "applies_to", "sandbox_id"):
            if isinstance(rule.get(key), str) and rule[key].startswith("sandbox:"):
                rule[key] = "sandbox:" + s.name(rule[key][len("sandbox:"):])
            elif key == "sandbox_id" and key in rule:
                rule[key] = s.name(rule[key])
        rule["resources"] = [s.host(r) if rule["resource_type"] == "network" else r for r in rule["resources"]]
        return rule

    # keep every default rule, plus a sample of added, scoped, and provisioned ones
    picked, seen = [], set()
    for rule in policy["rules"]:
        kind = (rule.get("provenance", {}).get("created_via"), rule.get("origin"), rule["resource_type"])
        if kind[0] == "default" or kind not in seen or any(re.fullmatch(r"localhost:237[56]", r) for r in rule["resources"]):
            picked.append(clean_rule(rule))
            seen.add(kind)
    write("sbx/policy-ls.json", {"rules": picked})

    if (RAW / "sbx-policy-ls-model.json").exists():
        model_rules = load_json("sbx-policy-ls-model.json")["rules"]
        scoped = [clean_rule(r) for r in model_rules if r.get("scope", "").startswith("sandbox:m0")]
        write("sbx/policy-ls-model-sandbox.json", {"rules": scoped})

    if (RAW / "sbx-policy-ls-claude.json").exists():
        rules = load_json("sbx-policy-ls-claude.json")["rules"]
        scoped = [clean_rule(r) for r in rules if r.get("scope", "").startswith("sandbox:")]
        for r in scoped:
            for t in r.get("http_targets", []):
                t["host"] = s.host(t["host"])
        write("sbx/policy-ls-sandbox.json", {"rules": scoped})

    # sbx policy log: {"allowed": [...], "blocked": [...]}, entries keyed by sandbox name (sandbox_id)
    def clean_log(log):
        out = {}
        for kind in ("allowed", "blocked"):
            entries = []
            for entry in log.get(kind) or []:
                entry = dict(entry)
                bare = entry["host"].split(":")[0]
                entry["sandbox_id"] = s.name(entry["sandbox_id"])
                entry["host"] = s.host(entry["host"])
                if isinstance(entry.get("rule"), str):
                    entry["rule"] = s.text(entry["rule"].replace(bare, entry["host"].split(":")[0]))
                entries.append(entry)
            out[kind] = entries
        return out

    for raw, rel in [("sbx-policy-log.json", "sbx/policy-log.json"),
                     ("sbx-policy-log-claude.json", "sbx/policy-log-sandbox.json")]:
        if (RAW / raw).exists():
            write(rel, clean_log(load_json(raw)))

    # sbx policy approval ls: pending approvals; titles are `host:port` or `METHOD host/path`
    def clean_approval(approval):
        approval = dict(approval)
        approval["sandbox_name"] = s.name(approval["sandbox_name"])
        title = approval["title"]
        method, _, rest = title.rpartition(" ")
        host, slash, path = rest.partition("/")
        clean = s.host(host)
        approval["title"] = (method + " " if method else "") + clean + slash + path
        approval["detail"] = approval["detail"].replace(host.split(":")[0], clean.split(":")[0])
        return approval

    if (RAW / "sbx-policy-approval-ls-claude.json").exists():
        write("sbx/policy-approval-ls.json", [clean_approval(a) for a in load_json("sbx-policy-approval-ls-claude.json")])

    for raw, rel in [("sbx-ports-openhands.json", "sbx/ports.json")]:
        if (RAW / raw).exists():
            write(rel, load_json(raw))

    events, per_type = [], {}
    for line in (RAW / "sbx-events-idle.ndjson").read_text().splitlines():
        if not line.strip():
            continue
        ev = json.loads(line)
        if per_type.get(ev["type"], 0) >= 4:
            continue
        per_type[ev["type"]] = per_type.get(ev["type"], 0) + 1
        if "sandbox_name" in ev:
            ev["sandbox_name"] = s.name(ev["sandbox_name"])
        data = ev.get("data")
        if isinstance(data, dict) and "host" in data:
            data["host"] = s.host(data["host"])
            if isinstance(data.get("rule"), str):
                data["rule"] = s.text(data["rule"]).replace(data["host"], data["host"])
        events.append(ev)
    write("sbx/events-idle.ndjson", events, ndjson=True)

    for raw, rel in [("sbx-settings-feature-model.json", "sbx/settings-feature-model.json"),
                     ("sbx-settings-feature-model-after.json", "sbx/settings-feature-model-enabled.json"),
                     ("sbx-settings-providers.json", "sbx/settings-providers.json"),
                     ("sbx-settings-experimental.json", "sbx/settings-experimental.json"),
                     ("sbx-settings-ls.json", "sbx/settings-ls.json"),
                     ("sbx-rm-model.json", "sbx/rm.json")]:
        if (RAW / raw).exists():
            data = load_json(raw)
            if rel == "sbx/rm.json":
                for item in data:
                    item["name"] = s.name(item["name"])
            write(rel, data)

    # the list after `sbx template load` also has an image without a flavor
    after_load = RAW / "sbx-template-ls-after-load.json"
    templates = load_json(after_load.name if after_load.exists() else "sbx-template-ls.json")
    custom = {}
    for t in templates:
        if not t["repository"].startswith(("docker.io/docker/", "docker.io/paddock/")):
            custom.setdefault(t["repository"], "docker.io/library/custom-%d" % (len(custom) + 1))
            t["repository"] = custom[t["repository"]]
    write("sbx/template-ls.json", templates)

    sandboxd_fixtures(s, clean_rule, clean_log, clean_approval)

    # llmman
    for raw, rel in [("llmmanapi-version.json", "llmman/version.json"),
                     ("llmmanapi-tags.json", "llmman/tags-empty.json"),
                     ("llmmanapi-tags-after-model.json", "llmman/tags.json"),
                     ("llmmanapi-ps.json", "llmman/ps-empty.json"),
                     ("llmmanapi-node.json", "llmman/node.json"),
                     ("llmmanapi-shell-status.json", "llmman/shell-status.json"),
                     ("llmmanapi-v1-models.json", "llmman/v1-models-empty.json")]:
        if (RAW / raw).exists():
            write(rel, load_json(raw))
    providers = load_json("llmmanapi-providers.json")
    providers["providers"] = providers["providers"][:3]
    write("llmman/providers.json", providers)

    leftover = [str(p.relative_to(FIX)) for d in ("sbx", "llmman") for p in (FIX / d).rglob("*")
                if p.is_file() and any(h != "/Users/operator" for h in HOME_RE.findall(p.read_text()))]
    if leftover:
        sys.exit("home paths left in: " + ", ".join(leftover))


def sandboxd_fixtures(s, clean_rule, clean_log, clean_approval):
    """sandboxd's answers to the requests `sbx` sent in the newest `mise run capture:socket proxy --swap`
    run, next to what that sbx command printed, so tests can check the mapping against sbx itself.
    API 0.42 (the first capture) writes to sandboxd/, any later API to sandboxd/<major.minor>/
    (without the event streams)."""
    runs = sorted((RAW / "socket").glob("proxy-swap-*/traffic.ndjson"))
    if not runs:
        return
    run = runs[-1].parent
    # M0's throwaway sandboxes (m0<time>-claude) stay apart here: two of them in one log are two entries.
    m0_runs = {}

    def distinct_name(value, plain=s.name):
        m = re.fullmatch(r"m0(\d+)-(\w+)", value)
        if not m:
            return plain(value)
        return "m0-%s-%d" % (m.group(2), m0_runs.setdefault(m.group(1), len(m0_runs) + 1))
    s.name = distinct_name
    entries = [json.loads(line) for line in runs[-1].read_text().splitlines() if line.strip()]
    requests, answers, streams = {}, {}, {}
    for e in entries:
        if e["dir"] == "request":
            requests[e["conn"]] = e
        request = requests.get(e.get("conn"))
        if not request or "sbx-cli" not in dict(request["headers"]).get("User-Agent", ""):
            continue
        key = (request["method"], request["path"], request["query"])
        # the first request of each kind is the one the first sbx command sent (capture:socket order)
        if e["dir"] == "response":
            answers.setdefault(key, e)
        elif e["dir"] == "stream" and (key not in streams or streams[key][0] == e["conn"]):
            streams.setdefault(key, (e["conn"], []))[1].append(e["event"])

    def cli(name):
        return json.loads((run / name).read_text())

    health = answers[("GET", "/daemon/health", "")]["body"]
    api = ".".join(health["api_version"].split(".")[:2])
    folder = "sandboxd/" if api == "0.42" else "sandboxd/%s/" % api

    def check_leftovers():
        leftover = [str(p.relative_to(FIX)) for p in (FIX / folder).rglob("*")
                    if p.is_file() and any(h != "/Users/operator" for h in HOME_RE.findall(p.read_text()))]
        if leftover:
            sys.exit("home paths left in: " + ", ".join(leftover))

    def write_api(rel, data, ndjson=False):
        write(folder + rel.removeprefix("sandboxd/"), data, ndjson=ndjson)

    # Every path a sandbox names (its workspace, extra folders, sbxenv.yaml, mounts), the same way in
    # sandboxd's answer and sbx's output: a sandbox's workspace becomes /Users/operator/Projects/<its name>.
    sandboxes = answers[("GET", "/sandbox", "")]["body"]
    roots = sorted(((sb["workspace"], s.name(sb["name"])) for sb in sandboxes if sb.get("workspace")),
                   key=lambda r: -len(r[0]))

    def clean_path(path):
        for raw, name in roots:
            if path == raw or path.startswith(raw + "/"):
                return "/Users/operator/Projects/" + name + path[len(raw):]
        return s.text(path)

    def clean_spec(spec):
        """`path`, `path:ro`, or `host:target[:ro]` (sbx ls mounts)."""
        parts = spec.split(":")
        flag = [parts.pop()] if parts[-1] == "ro" else []
        return ":".join([clean_path(p) for p in parts] + flag)

    def clean_sandbox(sb):
        sb = dict(sb)
        sb["name"] = s.name(sb["name"])
        sb["agent"] = sb["agent"] if sb["agent"] in ("claude", "codex", "shell", "opencode") else "claude"
        sb["workspace"] = "/Users/operator/Projects/" + sb["name"]
        for key in ("working_dir", "effective_working_dir"):
            if sb.get(key):
                sb[key] = clean_path(sb[key])
        if "additional_workspaces" in sb:
            sb["additional_workspaces"] = [dict(w, dir=clean_path(w["dir"])) for w in sb["additional_workspaces"]]
        if "host_mounts" in sb:
            sb["host_mounts"] = [dict(m, host_path=clean_path(m["host_path"]), container_target=clean_path(m["container_target"]))
                                 for m in sb["host_mounts"]]
        labels = {k: s.text(v) for k, v in sb.get("labels", {}).items()}
        for k in ("com.docker.sandbox.name", "com.docker.sandbox.agent"):
            if k in labels:
                labels[k] = sb["name"] if k.endswith("name") else sb["agent"]
        if "com.docker.sandbox.workingDirectory" in labels:
            labels["com.docker.sandbox.workingDirectory"] = sb["workspace"]
        if "com.docker.sandbox.kit-workspace-dir" in labels:
            labels["com.docker.sandbox.kit-workspace-dir"] = sb["workspace"]
        if "com.docker.sandbox.kit-lock" in labels:
            labels["com.docker.sandbox.kit-lock"] = "{}"
        if "com.docker.sandbox.kits" in labels:
            labels["com.docker.sandbox.kits"] = "[]"
        sb["labels"] = labels
        return sb

    def clean_cli_sandbox(sb):
        sb = dict(sb)
        sb["name"] = s.name(sb["name"])
        sb["agent"] = sb["agent"] if sb["agent"] in ("claude", "codex", "shell", "opencode") else "claude"
        sb["workspaces"] = [clean_spec(w) for w in sb["workspaces"]]
        if "mounts" in sb:
            sb["mounts"] = [clean_spec(m) for m in sb["mounts"]]
        return sb

    def clean_hosts(log):
        out = {}
        for kind in ("allowed_hosts", "blocked_hosts"):
            renamed = [dict(h, sandbox_id=h["vm_name"]) for h in log.get(kind) or []]
            cleaned = clean_log({"allowed": renamed})["allowed"]
            out[kind] = [{**{k: v for k, v in h.items() if k != "sandbox_id"}, "vm_name": h["sandbox_id"]} for h in cleaned]
        return out

    write_api("sandboxd/daemon-health.json", health)
    write_api("sandboxd/sandbox.json", [clean_sandbox(sb) for sb in answers[("GET", "/sandbox", "")]["body"]])
    write_api("sandboxd/cli-ls.json", [clean_cli_sandbox(sb) for sb in cli("ls.out")])
    rules = answers[("GET", "/policy/network/rules", "type=all")]["body"]
    write_api("sandboxd/policy-network-rules.json", {**rules, "rules": [clean_rule(r) for r in rules["rules"]]})
    write_api("sandboxd/cli-policy-ls.json", {"rules": [clean_rule(r) for r in cli("policy-ls.out")["rules"]]})
    write_api("sandboxd/policy-network-log.json", clean_hosts(answers[("GET", "/policy/network/log", "")]["body"]))
    write_api("sandboxd/cli-policy-log.json", clean_log(cli("policy-log.out")))
    prompts = []
    for event in streams[("GET", "/user-prompts", "")][1]:
        prompts.append({**event, "prompt": clean_approval(event["prompt"])} if "prompt" in event else event)
    write_api("sandboxd/user-prompts.ndjson", prompts, ndjson=True)
    write_api("sandboxd/cli-policy-approval-ls.json", [clean_approval(a) for a in cli("policy-approval-ls.out")])

    # Later APIs keep only the answers paired with sbx output above; the events' shape is 0.42's.
    if api != "0.42":
        check_leftovers()
        return

    # The first `sbx events` stream: its replay is the log above; with its live events up to the last
    # log sbx read, it is that log too. The rest (a sandbox created and started) goes in events-more.
    events_conn = next(e["conn"] for e in entries if e["dir"] == "stream" and e["for"] == "GET /events")
    logs = [e for e in entries if e["dir"] == "response" and e["for"] == "GET /policy/network/log"
            and "sbx-cli" in dict(requests[e["conn"]]["headers"]).get("User-Agent", "")]
    cut = logs[-1]["t"]

    def clean_event(ev):
        ev = dict(ev)
        if "sandbox_name" in ev:
            ev["sandbox_name"] = s.name(ev["sandbox_name"])
        data = ev.get("data")
        if isinstance(data, dict) and "host" in data:
            data = dict(data)
            bare = data["host"].split(":")[0]
            data["host"] = s.host(data["host"])
            if isinstance(data.get("rule"), str):
                data["rule"] = s.text(data["rule"].replace(bare, data["host"].split(":")[0]))
            ev["data"] = data
        return ev

    stream = [e for e in entries if e["dir"] == "stream" and e.get("conn") == events_conn]
    write_api("sandboxd/events.ndjson", [clean_event(e["event"]) for e in stream if e["t"] <= cut], ndjson=True)
    write_api("sandboxd/events-more.ndjson", [clean_event(e["event"]) for e in stream if e["t"] > cut], ndjson=True)
    write_api("sandboxd/policy-network-log-later.json", clean_hosts(logs[-1]["body"]))

    check_leftovers()


if __name__ == "__main__":
    main()
