#!/usr/bin/env -S python3 -I
#MISE description="Capture sandboxd's socket traffic on the Mac: capture:socket probe, then capture:socket proxy [--swap]"
"""sandboxd socket capture spike. Run on the operator's Mac, from the repo root.

Finds out what sbx (the CLI and `sbx tui`) asks sandboxd over its Unix socket, so a
socket client for events and stats is written against real traffic, not the unofficial
spec (https://github.com/itbm/sbx-sdk, which describes sbx 0.34 and has neither).

Usage:
  mise run capture:socket probe [--sandbox NAME]
  mise run capture:socket proxy [--swap] [--sandbox NAME] [--no-tui] [--wait]
                             [--env NAME ...] [--raw-bytes N]

probe (safe, read-only, no proxy):
  - scans the sbx and sandboxd binaries for route and socket environment variable strings
  - runs read-only sbx commands with -D (debug) and keeps their stderr
  - sends GET requests straight to the socket: the routes in the unofficial spec plus
    guesses for events and stats (a streaming answer is read for a few seconds)
  - keeps what sandboxd appended to its daemon.log meanwhile

proxy: puts a logging proxy in front of sandboxd.sock and drives sbx through it.
  Default: the proxy listens on a temporary socket and sbx is pointed at it with
  environment variables (SBX_SOCKET and a few guesses, plus --env NAME). If sbx ignores
  them, the script says so and stops; then use --swap.
  --swap: renames the real socket aside and listens at its path, so every client (sbx,
  sbx tui, Paddock) goes through the proxy. Asks first. The socket is put back on exit;
  if the script is killed hard, it prints and saves the one `mv` that restores it.
  Do not restart sbx's daemon while swapped.
  Then: read-only sbx commands, `sbx events --json` until Enter (start or stop a sandbox
  in another terminal meanwhile), and `sbx tui` (open every panel, then quit it).
  --wait keeps the proxy up until Ctrl-C instead, for driving sbx or Paddock by hand.

Output (gitignored, may contain private paths and names): .tmp/captures/socket/<phase>-<time>/
  traffic.ndjson  one {"t", "conn", "dir", ...} per line: request, response, response_head,
                  stream (one per NDJSON/SSE line), response_end, raw, note
  routes.tsv      every method and path seen, with statuses, content types, and whether
                  an Authorization header was sent (the auth question)
  probe/, debug/, daemon-log.txt
Run mise run capture:fixtures on anything that becomes a fixture.

Never records a secret: Authorization, cookie, and token-like headers keep only their
scheme and length; token-, secret-, password-, and key-like JSON string values are
replaced; bodies on routes containing "secret" are withheld; raw (hijacked exec) streams
keep only byte counts unless --raw-bytes is given.

Stdlib only; runs on the python3 that ships with Xcode.
"""

import argparse
import collections
import http.client
import json
import os
import re
import select
import shutil
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent.parent
OUT_BASE = ROOT / ".tmp/captures/socket"
BODY_CAP = 256 * 1024
HEAD_CAP = 64 * 1024
SUN_PATH_MAX = 103  # macOS sockaddr_un.sun_path is 104 bytes including the NUL

READONLY_COMMANDS = [
    ("version", ["sbx", "version", "--json"]),
    ("daemon-status", ["sbx", "daemon", "status", "--format", "json"]),
    ("ls", ["sbx", "ls", "--json"]),
    ("policy-ls", ["sbx", "policy", "ls", "--json"]),
    ("policy-log", ["sbx", "policy", "log", "--json"]),
    ("policy-approval-ls", ["sbx", "policy", "approval", "ls", "--json"]),
    ("policy-profile-ls", ["sbx", "policy", "profile", "ls", "--json"]),
    ("template-ls", ["sbx", "template", "ls", "--json"]),
    ("settings-ls", ["sbx", "settings", "ls", "--json"]),
]
SANDBOX_COMMANDS = [
    ("ports", ["sbx", "ports", "{name}", "--json"]),
    ("policy-ls-sandbox", ["sbx", "policy", "ls", "{name}", "--json"]),
    ("policy-log-sandbox", ["sbx", "policy", "log", "{name}", "--json"]),
]

# GET only. From the unofficial spec, then guesses for what it lacks.
PROBE_ROUTES = [
    "/daemon/health", "/daemon/info", "/daemon/loglevel", "/daemon/diagnostics",
    "/sandbox", "/sandbox/{name}", "/sandbox/{name}/ports", "/runtime/{name}/session",
    "/policy/setup", "/policy/rules", "/policy/profiles", "/network/log",
    "/docker/images",
    # guesses
    "/events", "/v1/events", "/daemon/events", "/sandbox/events",
    "/stats", "/sandbox/stats", "/sandbox/{name}/stats", "/sandbox/{name}/metrics",
    "/metrics", "/daemon/metrics", "/policy/approvals", "/policy/approval",
    "/settings", "/templates", "/kits",
]
STREAM_SECONDS = 5

# Environment variables that might point sbx at another socket. Unverified guesses apart
# from SBX_SOCKET (the SDK's); probe lists the ones the binary actually contains.
SOCKET_ENV_GUESSES = ["SBX_SOCKET", "SBX_DAEMON_SOCKET", "SANDBOXD_SOCKET", "SBX_HOST"]

SECRET_KEY_RE = re.compile(r"token|secret|passw|credential|api[_-]?key|private[_-]?key|^auth|cookie", re.I)
SECRET_TEXT_RE = re.compile(
    r"((?:key|token|secret|password|bearer)[A-Za-z_]*\"?\s*[:= ]\s*)[^\s,}\"]+", re.I)
STREAM_TYPES = ("ndjson", "jsonl", "json-seq", "event-stream", "x-json-stream", "stream+json")
RAW_TYPES = ("raw-stream", "multiplexed-stream")


def log(text):
    print("\033[1m==> %s\033[0m" % text, flush=True)


def warn(text):
    print("\033[33m!!  %s\033[0m" % text, flush=True)


def confirm(question):
    try:
        return input("%s [y/N] " % question).strip().lower() == "y"
    except EOFError:
        return False


# ---------------------------------------------------------------- redaction

def redact_header(name, value):
    lname = name.lower()
    if lname in ("authorization", "proxy-authorization") or SECRET_KEY_RE.search(lname):
        scheme = value.split(" ", 1)[0] if " " in value else ""
        return "<hidden%s len=%d>" % (" " + scheme if scheme else "", len(value))
    return value


def redact_json(value, key=""):
    if isinstance(value, dict):
        return {k: redact_json(v, k) for k, v in value.items()}
    if isinstance(value, list):
        return [redact_json(v, key) for v in value]
    # booleans and nulls stay: "auth_required": true is what we want to see
    if isinstance(value, (str, int, float)) and not isinstance(value, bool) and key and SECRET_KEY_RE.search(key):
        return "<hidden>"
    return value


def redact_text(text):
    return SECRET_TEXT_RE.sub(r"\1<hidden>", text)


def redact_query(query):
    if not query:
        return query
    parts = []
    for item in query.split("&"):
        k, sep, v = item.partition("=")
        parts.append(k + sep + ("<hidden>" if sep and SECRET_KEY_RE.search(k) else v))
    return "&".join(parts)


def decode_body(data, content_type, path):
    """A body as a JSON-ready field dict, redacted."""
    if not data:
        return {}
    if "secret" in path.lower():
        return {"body_withheld": "secret route", "body_bytes": len(data)}
    text = data.decode("utf-8", "replace")
    if "json" in content_type or text.lstrip()[:1] in ("{", "["):
        try:
            return {"body": redact_json(json.loads(text))}
        except ValueError:
            pass
    return {"body_text": redact_text(text)}


def decode_line(line, path):
    if "secret" in path.lower():
        return {"line_withheld": True, "bytes": len(line)}
    text = line.decode("utf-8", "replace").rstrip("\r")
    payload = text[5:].lstrip() if text.startswith("data:") else text
    try:
        return {"event": redact_json(json.loads(payload)), **({"sse": text[:5]} if payload is not text else {})}
    except ValueError:
        return {"text": redact_text(text)}


# ---------------------------------------------------------------- recorder

class Recorder:
    def __init__(self, out_dir, sandbox_names):
        self.start = time.monotonic()
        self.lock = threading.Lock()
        self.file = (out_dir / "traffic.ndjson").open("w")
        self.routes = collections.OrderedDict()
        self.names = sorted(sandbox_names, key=len, reverse=True)
        self.connections = 0

    def write(self, entry):
        entry = {"t": round(time.monotonic() - self.start, 3), **entry}
        with self.lock:
            self.file.write(json.dumps(entry, ensure_ascii=False) + "\n")
            self.file.flush()

    def template(self, path):
        for name in self.names:
            path = re.sub(r"(?<=/)%s(?=/|$)" % re.escape(name), "{name}", path)
        return path

    def route(self, method, path, headers):
        key = (method, self.template(path))
        with self.lock:
            r = self.routes.setdefault(key, {"count": 0, "statuses": set(), "types": set(), "auth": set()})
            r["count"] += 1
            r["auth"].add("yes" if any(k.lower() == "authorization" for k in headers) else "no")
        return key

    def route_response(self, key, status, content_type):
        with self.lock:
            r = self.routes.get(key)
            if r is not None:
                r["statuses"].add(str(status))
                if content_type:
                    r["types"].add(content_type.split(";")[0])

    def write_routes(self, path):
        with path.open("w") as f:
            f.write("method\tpath\tcount\tstatuses\tcontent_types\tauthorization_sent\n")
            for (method, p), r in self.routes.items():
                f.write("%s\t%s\t%d\t%s\t%s\t%s\n" % (
                    method, p, r["count"], ",".join(sorted(r["statuses"])),
                    ",".join(sorted(r["types"])), ",".join(sorted(r["auth"]))))

    def print_routes(self):
        if not self.routes:
            warn("no HTTP requests seen")
            return
        log("routes seen")
        for (method, p), r in self.routes.items():
            print("   %-6s %-50s x%-3d %s %s auth=%s" % (
                method, p, r["count"], ",".join(sorted(r["statuses"])) or "-",
                ",".join(sorted(r["types"])) or "-", ",".join(sorted(r["auth"]))))


# ---------------------------------------------------------------- HTTP/1.1 parsing

def parse_head(raw):
    lines = raw.decode("latin-1").split("\r\n")
    headers = []
    for line in lines[1:]:
        if ":" in line:
            k, v = line.split(":", 1)
            headers.append((k.strip(), v.strip()))
    return lines[0], headers


def header(headers, name):
    for k, v in headers:
        if k.lower() == name:
            return v
    return ""


class ConnState:
    def __init__(self, cid):
        self.cid = cid
        self.pending = collections.deque()  # (method, path, route key) per request, in order
        self.raw = False
        self.lock = threading.Lock()


class HttpSide:
    """Parses one direction of a proxied connection from a copy of its bytes."""

    def __init__(self, conn, is_request, rec, raw_bytes):
        self.conn, self.is_request, self.rec, self.raw_cap = conn, is_request, rec, raw_bytes
        self.label = "client" if is_request else "daemon"
        self.buf = bytearray()
        self.state = "head"
        self.raw_total = 0
        self.raw_head = bytearray()
        self.reset_message()

    def reset_message(self):
        self.msg = None
        self.body = bytearray()
        self.body_total = 0
        self.remaining = 0
        self.streaming = False
        self.line_buf = bytearray()
        self.lines = 0

    # -- input

    def feed(self, data):
        if self.conn.raw and self.state != "raw":
            self.go_raw()
        if self.state == "raw":
            self.take_raw(bytes(data))
            return
        self.buf += data
        while self.state != "raw" and self.step():
            if self.conn.raw and self.state != "raw":
                self.go_raw()
        if self.state == "raw" and self.buf:
            self.take_raw(bytes(self.buf))
            self.buf.clear()

    def eof(self):
        if self.conn.raw and self.state != "raw":
            self.go_raw()  # bytes sent after an upgrade request, before its answer
        if self.msg is not None:
            if self.state == "until_close":
                self.finish()
            else:
                self.finish(incomplete=True)
        if self.state == "raw" or self.raw_total:
            entry = {"conn": self.conn.cid, "dir": "raw", "from": self.label, "bytes": self.raw_total}
            if self.raw_head:
                entry["head"] = self.raw_head.decode("utf-8", "replace")
            self.rec.write(entry)
        elif self.buf:
            self.rec.write({"conn": self.conn.cid, "dir": "note", "from": self.label,
                            "note": "%d unparsed bytes at close" % len(self.buf)})

    # -- raw (hijacked exec, HTTP/2, or not HTTP at all)

    def go_raw(self):
        self.state = "raw"
        if self.buf:
            self.take_raw(bytes(self.buf))
            self.buf.clear()

    def take_raw(self, data):
        self.raw_total += len(data)
        room = self.raw_cap - len(self.raw_head)
        if room > 0:
            self.raw_head += data[:room]

    # -- state machine; returns True while it made progress

    def step(self):
        if self.state == "head":
            return self.step_head()
        if self.state == "hold":
            return False
        if self.state == "length":
            n = min(self.remaining, len(self.buf))
            if n == 0 and self.remaining:
                return False
            self.deliver(bytes(self.buf[:n]))
            del self.buf[:n]
            self.remaining -= n
            if self.remaining == 0:
                self.finish()
            return True
        if self.state == "chunk_size":
            i = self.buf.find(b"\r\n")
            if i < 0:
                return False
            size_text = bytes(self.buf[:i]).split(b";")[0].strip()
            del self.buf[:i + 2]
            try:
                self.remaining = int(size_text, 16)
            except ValueError:
                self.rec.write({"conn": self.conn.cid, "dir": "note", "note": "bad chunk size, going raw"})
                self.finish(incomplete=True)
                self.go_raw()
                return False
            self.state = "chunk_data" if self.remaining else "trailer"
            return True
        if self.state == "chunk_data":
            n = min(self.remaining, len(self.buf))
            if n == 0:
                return False
            self.deliver(bytes(self.buf[:n]))
            del self.buf[:n]
            self.remaining -= n
            if self.remaining == 0:
                self.state = "chunk_crlf"
            return True
        if self.state == "chunk_crlf":
            if len(self.buf) < 2:
                return False
            del self.buf[:2]
            self.state = "chunk_size"
            return True
        if self.state == "trailer":
            i = self.buf.find(b"\r\n")
            if i < 0:
                return False
            del self.buf[:i + 2]
            if i == 0:
                self.finish()
            return True
        if self.state == "until_close":
            if not self.buf:
                return False
            self.deliver(bytes(self.buf))
            self.buf.clear()
            return False
        return False

    def step_head(self):
        if not self.buf:
            return False
        if self.is_request and self.buf.startswith(b"PRI * HTTP/2.0"):
            self.rec.write({"conn": self.conn.cid, "dir": "note", "note": "HTTP/2 (h2c) connection, logged raw"})
            self.conn.raw = True
            self.go_raw()
            return False
        i = self.buf.find(b"\r\n\r\n")
        if i < 0:
            if len(self.buf) > HEAD_CAP:
                self.rec.write({"conn": self.conn.cid, "dir": "note", "from": self.label,
                                "note": "no HTTP head in %d bytes, logged raw" % len(self.buf)})
                self.conn.raw = True
                self.go_raw()
            return False
        start_line, headers = parse_head(bytes(self.buf[:i]))
        del self.buf[:i + 4]
        if self.is_request:
            self.request_head(start_line, headers)
        else:
            self.response_head(start_line, headers)
        return True

    def body_state(self, headers, default):
        if "chunked" in header(headers, "transfer-encoding").lower():
            return "chunk_size"
        length = header(headers, "content-length")
        if length.isdigit():
            self.remaining = int(length)
            return "length" if self.remaining else None
        return default

    def request_head(self, start_line, headers):
        parts = start_line.split(" ")
        method = parts[0]
        target = parts[1] if len(parts) > 1 else ""
        path, _, query = target.partition("?")
        key = self.rec.route(method, path, [k for k, _ in headers])
        with self.conn.lock:
            self.conn.pending.append((method, path, key))
        self.msg = {"conn": self.conn.cid, "dir": "request", "method": method, "path": path,
                    "query": redact_query(query),
                    "headers": [[k, redact_header(k, v)] for k, v in headers],
                    "_type": header(headers, "content-type").lower()}
        upgrade = "upgrade" in header(headers, "connection").lower() or header(headers, "upgrade")
        nxt = self.body_state(headers, None)
        if nxt is None:
            self.finish()
            if upgrade:
                self.state = "hold"  # bytes after an upgrade request wait for the answer
        else:
            self.state = nxt
            self.upgrade_after = bool(upgrade)

    def response_head(self, start_line, headers):
        parts = start_line.split(" ", 2)
        try:
            status = int(parts[1])
        except (IndexError, ValueError):
            status = 0
        with self.conn.lock:
            if 100 <= status < 200 and status != 101:
                method, path, key = self.conn.pending[0] if self.conn.pending else ("?", "?", None)
            else:
                method, path, key = self.conn.pending.popleft() if self.conn.pending else ("?", "?", None)
        ctype = header(headers, "content-type").lower()
        if key:
            self.rec.route_response(key, status, ctype)
        self.msg = {"conn": self.conn.cid, "dir": "response", "for": "%s %s" % (method, path),
                    "status": status, "reason": parts[2] if len(parts) > 2 else "",
                    "headers": [[k, redact_header(k, v)] for k, v in headers],
                    "_type": ctype, "_path": path}
        if 100 <= status < 200 and status != 101:
            self.finish()
            return
        if status == 101 or any(t in ctype for t in RAW_TYPES):
            self.finish()
            self.rec.write({"conn": self.conn.cid, "dir": "note", "note": "connection hijacked (%s), raw from here" % (status if status == 101 else ctype)})
            self.conn.raw = True
            return
        if method == "HEAD" or status in (204, 304):
            self.finish()
            return
        nxt = self.body_state(headers, "until_close")
        if nxt is None:
            self.finish()
            return
        self.state = nxt
        if nxt == "until_close" or any(t in ctype for t in STREAM_TYPES):
            self.streaming = True
            head = dict(self.msg, dir="response_head")
            head.pop("_type", None)
            head.pop("_path", None)
            self.rec.write(head)

    # -- bodies

    def deliver(self, data):
        self.body_total += len(data)
        if not self.streaming:
            room = BODY_CAP - len(self.body)
            if room > 0:
                self.body += data[:room]
            return
        self.line_buf += data
        while True:
            i = self.line_buf.find(b"\n")
            if i < 0:
                break
            line = bytes(self.line_buf[:i])
            del self.line_buf[:i + 1]
            if line.strip():
                self.lines += 1
                self.rec.write({"conn": self.conn.cid, "dir": "stream", "for": self.msg["for"],
                                **decode_line(line, self.msg.get("_path", ""))})

    def finish(self, incomplete=False):
        msg = self.msg
        if msg is None:
            self.state = "head"
            return
        ctype = msg.pop("_type", "")
        path = msg.pop("_path", msg.get("path", ""))
        if self.streaming:
            if self.line_buf.strip():
                self.lines += 1
                self.rec.write({"conn": self.conn.cid, "dir": "stream", "for": msg["for"], "partial": True,
                                **decode_line(bytes(self.line_buf), path)})
            self.rec.write({"conn": self.conn.cid, "dir": "response_end", "for": msg["for"],
                            "lines": self.lines, "body_bytes": self.body_total,
                            **({"incomplete": True} if incomplete else {})})
        else:
            msg.update(decode_body(bytes(self.body), ctype, path))
            msg["body_bytes"] = self.body_total
            if self.body_total > len(self.body):
                msg["body_truncated"] = True
            if incomplete:
                msg["incomplete"] = True
            self.rec.write(msg)
        hold = getattr(self, "upgrade_after", False)
        self.upgrade_after = False
        self.reset_message()
        self.state = "hold" if hold else "head"


# ---------------------------------------------------------------- sockets

class ShortPaths:
    """Unix socket paths over macOS's 103-byte limit are reached through a symlink in /tmp."""

    def __init__(self):
        self.dir = tempfile.mkdtemp(prefix="sbxcap-", dir="/tmp")
        self.count = 0

    def short(self, path):
        if len(os.fsencode(path)) <= SUN_PATH_MAX:
            return path
        self.count += 1
        link = os.path.join(self.dir, "l%d" % self.count)
        os.symlink(path, link)
        return link

    def cleanup(self):
        shutil.rmtree(self.dir, ignore_errors=True)


def unix_connect(path, timeout=None):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    s.connect(path)
    return s


class Proxy:
    def __init__(self, listen_path, upstream_path, rec, raw_bytes):
        self.upstream, self.rec, self.raw_bytes = upstream_path, rec, raw_bytes
        self.listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        if len(os.fsencode(listen_path)) <= SUN_PATH_MAX:
            self.listener.bind(listen_path)
        else:
            # a symlink cannot be bound, so bind relative to the socket's directory
            cwd = os.getcwd()
            os.chdir(os.path.dirname(listen_path))
            try:
                self.listener.bind(os.path.basename(listen_path))
            finally:
                os.chdir(cwd)
        self.listener.listen(64)
        self.ino = os.stat(listen_path).st_ino
        self.ids = 0
        self.closed = False
        threading.Thread(target=self.accept_loop, daemon=True).start()

    def accept_loop(self):
        while not self.closed:
            try:
                client, _ = self.listener.accept()
            except OSError:
                return
            self.ids += 1
            self.rec.connections += 1
            threading.Thread(target=self.serve, args=(client, self.ids), daemon=True).start()

    def serve(self, client, cid):
        try:
            upstream = unix_connect(self.upstream)
        except OSError as e:
            self.rec.write({"conn": cid, "dir": "note", "note": "upstream connect failed: %s" % e})
            client.close()
            return
        conn = ConnState(cid)
        sides = {client: (upstream, HttpSide(conn, True, self.rec, self.raw_bytes)),
                 upstream: (client, HttpSide(conn, False, self.rec, self.raw_bytes))}
        open_ends = {client, upstream}
        try:
            while open_ends:
                readable, _, _ = select.select(list(open_ends), [], [], 1.0)
                for s in readable:
                    other, parser = sides[s]
                    try:
                        data = s.recv(65536)
                    except OSError:
                        data = b""
                    if not data:
                        open_ends.discard(s)
                        parser.eof()
                        try:
                            other.shutdown(socket.SHUT_WR)
                        except OSError:
                            open_ends.discard(other)
                        continue
                    try:
                        other.sendall(data)
                    except OSError:
                        open_ends.clear()
                    parser.feed(data)
        finally:
            client.close()
            upstream.close()

    def close(self):
        self.closed = True
        self.listener.close()


# ---------------------------------------------------------------- sbx helpers

def sbx_json(argv, env=None):
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=30, env=env, stdin=subprocess.DEVNULL)
        return json.loads(p.stdout) if p.returncode == 0 else None
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None


def daemon_paths():
    status = sbx_json(["sbx", "daemon", "status", "--format", "json"])
    if not status or not status.get("socket"):
        sys.exit("sbx daemon status --format json gave no socket path; is sbx installed and the daemon running?")
    if status.get("status") != "running":
        sys.exit("sandboxd is not running (status %r); start it with `sbx daemon start`" % status.get("status"))
    return status["socket"], status.get("logs")


def sandbox_names():
    listing = sbx_json(["sbx", "ls", "--json"]) or []
    return [s["name"] for s in listing if isinstance(s, dict) and s.get("name")]


def run_logged(name, argv, out_dir, env=None, timeout=60):
    out = out_dir / (name + ".out")
    err = out_dir / (name + ".stderr")
    try:
        with out.open("w") as o, err.open("w") as e:
            p = subprocess.run(argv, stdout=o, stderr=e, stdin=subprocess.DEVNULL, env=env, timeout=timeout)
        rc = p.returncode
    except subprocess.TimeoutExpired:
        rc = "timeout"
    for f in (out, err):
        if f.exists() and f.stat().st_size == 0:
            f.unlink()
    print("   %-28s exit=%s" % (name, rc))
    return rc


def stream_until_enter(argv, out_path, env=None, prompt="press Enter to stop"):
    with out_path.open("w") as o, out_path.with_suffix(".stderr").open("w") as e:
        p = subprocess.Popen(argv, stdout=o, stderr=e, stdin=subprocess.DEVNULL, env=env)
        try:
            input("   %s " % prompt)
        except EOFError:
            time.sleep(10)
        p.terminate()
        try:
            p.wait(5)
        except subprocess.TimeoutExpired:
            p.kill()


class DaemonLog:
    def __init__(self, path):
        self.path = Path(path) if path else None
        self.offset = self.path.stat().st_size if self.path and self.path.exists() else None

    def save(self, out_path):
        if self.offset is None:
            return
        with self.path.open("rb") as f:
            f.seek(self.offset)
            data = f.read(8 * 1024 * 1024)
        out_path.write_text(redact_text(data.decode("utf-8", "replace")))


def output_dir(phase):
    d = OUT_BASE / ("%s-%s" % (phase, time.strftime("%Y%m%d-%H%M%S")))
    d.mkdir(parents=True, exist_ok=False)
    return d


# ---------------------------------------------------------------- probe

ROUTE_RES = [
    re.compile(rb"(?:GET|POST|PUT|DELETE|PATCH|HEAD) /[A-Za-z0-9_{}./:-]{2,100}"),
    re.compile(rb"/(?:v[0-9.]+/)?(?:sandbox|sandboxes|daemon|policy|policies|network|runtime|docker|events?|stats|metrics|"
               rb"settings|secrets?|templates?|kits?|mcp|models?|llm[a-z]*|volumes?|approvals?|ports|env|skills)"
               rb"(?:/[A-Za-z0-9_{}.:-]+){0,6}"),
]
ENV_RE = re.compile(rb"(?<![A-Z0-9_])(?:SBX|SANDBOXD|DOCKER_SANDBOX(?:ES)?)_[A-Z0-9_]{2,40}")


def binaries():
    found = []
    sbx = shutil.which("sbx")
    if sbx:
        found.append(os.path.realpath(sbx))
    try:
        ps = subprocess.run(["ps", "-axo", "comm="], capture_output=True, text=True, timeout=10).stdout
        for line in ps.splitlines():
            if "sandboxd" in line and line.startswith("/") and os.path.realpath(line) not in found:
                found.append(os.path.realpath(line))
    except (OSError, subprocess.TimeoutExpired):
        pass
    return found


def scan_binary(path, out_dir):
    try:
        data = Path(path).read_bytes()
    except OSError as e:
        warn("cannot read %s: %s" % (path, e))
        return
    routes = set()
    for rx in ROUTE_RES:
        routes.update(m.decode("latin-1") for m in rx.findall(data))
    envs = sorted(set(m.decode() for m in ENV_RE.findall(data)))
    base = re.sub(r"[^A-Za-z0-9.-]", "_", os.path.basename(path))
    (out_dir / ("strings-routes-%s.txt" % base)).write_text("# %s\n%s\n" % (path, "\n".join(sorted(routes))))
    (out_dir / ("strings-env-%s.txt" % base)).write_text("# %s\n%s\n" % (path, "\n".join(envs)))
    interesting = sorted(r for r in routes if re.search(r"event|stat|metric|watch|subscribe", r))
    print("   %s: %d route-like strings, %d env names" % (path, len(routes), len(envs)))
    for r in interesting[:40]:
        print("     route  %s" % r)
    for e in envs:
        if "SOCK" in e or "HOST" in e:
            print("     env    %s" % e)


def probe_get(sock_path, path, name):
    class UnixHTTP(http.client.HTTPConnection):
        def connect(self):
            self.sock = unix_connect(sock_path, timeout=10)

    target = path.replace("{name}", name) if name else path
    if "{name}" in target:
        return {"path": path, "skipped": "no sandbox"}
    c = UnixHTTP("localhost")
    try:
        c.request("GET", target, headers={"Accept": "application/json"})
        r = c.getresponse()
        ctype = (r.getheader("content-type") or "").lower()
        result = {"path": target, "status": r.status,
                  "headers": [[k, redact_header(k, v)] for k, v in r.getheaders()]}
        chunked = (r.getheader("transfer-encoding") or "").lower() == "chunked"
        if any(t in ctype for t in STREAM_TYPES) or (chunked and r.getheader("content-length") is None and r.status == 200 and "json" not in ctype):
            # a stream: read for a few seconds
            c.sock.settimeout(1)
            data = bytearray()
            deadline = time.monotonic() + STREAM_SECONDS
            while time.monotonic() < deadline and len(data) < BODY_CAP:
                try:
                    piece = r.read1(65536)
                except (socket.timeout, TimeoutError):
                    continue
                if not piece:
                    break
                data += piece
            result["stream_lines"] = [decode_line(l, target) for l in bytes(data).split(b"\n") if l.strip()]
            result["streamed_seconds"] = STREAM_SECONDS
        else:
            data = r.read(BODY_CAP + 1)
            result.update(decode_body(data[:BODY_CAP], ctype, target))
            result["body_bytes"] = len(data)
        return result
    except (OSError, http.client.HTTPException) as e:
        return {"path": target, "error": str(e)}
    finally:
        c.close()


def cmd_probe(args):
    sock, logs = daemon_paths()
    out = output_dir("probe")
    dlog = DaemonLog(logs)
    names = [args.sandbox] if args.sandbox else sandbox_names()
    name = names[0] if names else None
    short = ShortPaths()
    try:
        log("scanning binaries for routes and environment variables")
        bins = binaries()
        if not bins:
            warn("found neither sbx nor a running sandboxd binary")
        for b in bins:
            scan_binary(b, out)

        log("GET requests straight to %s" % sock)
        probe_dir = out / "probe"
        probe_dir.mkdir()
        sock_short = short.short(sock)
        summary = []
        for path in PROBE_ROUTES:
            res = probe_get(sock_short, path, name)
            fname = re.sub(r"[^A-Za-z0-9]+", "-", path.replace("{name}", "NAME")).strip("-") or "root"
            (probe_dir / (fname + ".json")).write_text(json.dumps(res, indent=2, ensure_ascii=False) + "\n")
            status = res.get("status", res.get("error", res.get("skipped")))
            extra = " (%d stream lines)" % len(res["stream_lines"]) if "stream_lines" in res else ""
            print("   %-32s %s%s" % (path, status, extra))
            summary.append({"path": path, "status": status})

        log("read-only sbx commands with -D (debug log on stderr)")
        debug = out / "debug"
        debug.mkdir()
        cmds = READONLY_COMMANDS + ([(n, [a.replace("{name}", name) for a in argv]) for n, argv in SANDBOX_COMMANDS] if name else [])
        for n, argv in cmds:
            run_logged(n, [argv[0], "-D"] + argv[1:], debug)
        log("sbx -D events --json")
        stream_until_enter(["sbx", "-D", "events", "--json"], debug / "events.out",
                           prompt="streaming events; start or stop a sandbox elsewhere if you like, then press Enter")
        dlog.save(out / "daemon-log.txt")
    finally:
        short.cleanup()
    log("done: %s" % out.relative_to(ROOT))
    print("   next: mise run capture:socket proxy (add --swap if sbx ignores the env variables)")


# ---------------------------------------------------------------- proxy

class Swap:
    """Moves the real socket aside and puts the proxy at its path; always undone on exit."""

    def __init__(self, sock_path, out_dir):
        self.orig = sock_path
        self.moved = os.path.join(os.path.dirname(sock_path), ".paddock-real.sock")
        self.recovery = out_dir / "RESTORE.sh"
        self.active = False

    def check(self):
        st = os.stat(self.orig)
        if not stat.S_ISSOCK(st.st_mode):
            sys.exit("%s is not a socket" % self.orig)
        if os.path.exists(self.moved):
            sys.exit("%s exists: an earlier run did not restore the socket. Check it, then:\n  mv %s %s"
                     % (self.moved, sh_quote(self.moved), sh_quote(self.orig)))

    def move_aside(self):
        self.recovery.write_text("#!/bin/sh\n# undo mise run capture:socket proxy --swap\nrm -f %s && mv %s %s\n"
                                 % (sh_quote(self.orig), sh_quote(self.moved), sh_quote(self.orig)))
        os.rename(self.orig, self.moved)
        self.active = True
        warn("socket moved aside; if this script dies, restore it with: sh %s" % sh_quote(str(self.recovery)))

    def restore(self, proxy_ino):
        if not self.active:
            return
        try:
            if os.path.lexists(self.orig):
                st = os.lstat(self.orig)
                if proxy_ino is not None and st.st_ino == proxy_ino:
                    os.unlink(self.orig)
                else:
                    # the daemon made a new socket meanwhile (restart): keep it, drop the old one
                    warn("%s was replaced while swapped (daemon restart?); keeping the new one" % self.orig)
                    os.unlink(self.moved)
                    self.active = False
                    return
            os.rename(self.moved, self.orig)
            self.active = False
            log("socket restored")
        except OSError as e:
            warn("could not restore the socket: %s; run: sh %s" % (e, sh_quote(str(self.recovery))))


def sh_quote(s):
    return "'" + s.replace("'", "'\\''") + "'"


def cmd_proxy(args):
    sock, logs = daemon_paths()
    names = sandbox_names()
    if args.sandbox and args.sandbox not in names:
        names.append(args.sandbox)
    name = args.sandbox or (names[0] if names else None)
    out = output_dir("proxy-swap" if args.swap else "proxy")
    rec = Recorder(out, names)
    dlog = DaemonLog(logs)
    short = ShortPaths()
    swap = Swap(sock, out) if args.swap else None
    proxy = None

    def on_signal(signum, _frame):
        raise SystemExit("signal %d" % signum)

    for sig in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, on_signal)

    env = None
    try:
        if swap:
            swap.check()
            print("This renames sandboxd's socket and listens at its path until the script ends:\n"
                  "  %s\nEvery sbx client (sbx, sbx tui, Paddock) goes through the proxy meanwhile.\n"
                  "Do not restart sbx's daemon while it runs." % sock)
            if not confirm("Swap the socket?"):
                sys.exit("not swapped")
            swap.move_aside()
            upstream = short.short(swap.moved)
            proxy = Proxy(sock, upstream, rec, args.raw_bytes)
        else:
            listen = os.path.join(short.dir, "proxy.sock")
            proxy = Proxy(listen, short.short(sock), rec, args.raw_bytes)
            env = dict(os.environ)
            for var in SOCKET_ENV_GUESSES + args.env:
                env[var] = "unix://" + listen if var.endswith("HOST") else listen
        log("proxy up; traffic goes to %s" % (out / "traffic.ndjson").relative_to(ROOT))

        if not args.swap:
            run_logged("check-ls", ["sbx", "ls", "--json"], out, env=env)
            if rec.connections == 0:
                warn("sbx did not connect through the proxy: it ignores %s." % ", ".join(SOCKET_ENV_GUESSES + args.env))
                print("   Run probe and look in strings-env-*.txt for the real variable (then --env NAME), or use --swap.")
                return

        if args.wait:
            log("proxy running; use sbx%s in another terminal, Ctrl-C to stop" % (" or Paddock" if args.swap else " with the same environment"))
            try:
                while True:
                    time.sleep(1)
            except KeyboardInterrupt:
                print()
            return

        log("read-only sbx commands")
        cmds = READONLY_COMMANDS + ([(n, [a.replace("{name}", name) for a in argv]) for n, argv in SANDBOX_COMMANDS] if name else [])
        for n, argv in cmds:
            run_logged(n, argv, out, env=env)

        log("sbx events --json")
        stream_until_enter(["sbx", "events", "--json"], out / "events.out", env=env,
                           prompt="streaming; start or stop a sandbox in another terminal, then press Enter")

        if not args.no_tui:
            log("sbx tui: open every panel (sandboxes, network, filesystem, stats), wait a few seconds on each, then quit")
            if confirm("Start sbx tui now?"):
                try:
                    subprocess.run(["sbx", "tui"], env=env)
                except KeyboardInterrupt:
                    pass
    finally:
        if proxy:
            proxy.close()
        if swap:
            swap.restore(proxy.ino if proxy else None)
        time.sleep(0.3)  # let connection threads write their last entries
        rec.write_routes(out / "routes.tsv")
        dlog.save(out / "daemon-log.txt")
        short.cleanup()
        rec.print_routes()
        log("done: %s" % out.relative_to(ROOT))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="phase", required=True)
    p = sub.add_parser("probe", help="read-only: binary strings, direct GETs, sbx -D")
    p.add_argument("--sandbox", help="sandbox for per-sandbox routes (default: the first in sbx ls)")
    x = sub.add_parser("proxy", help="logging proxy in front of sandboxd.sock")
    x.add_argument("--swap", action="store_true", help="put the proxy at the real socket path (asks first)")
    x.add_argument("--sandbox", help="sandbox for per-sandbox commands (default: the first in sbx ls)")
    x.add_argument("--no-tui", action="store_true", help="skip sbx tui")
    x.add_argument("--wait", action="store_true", help="only run the proxy until Ctrl-C")
    x.add_argument("--env", action="append", default=[], metavar="NAME",
                   help="another environment variable to point at the proxy socket")
    x.add_argument("--raw-bytes", type=int, default=0, metavar="N",
                   help="keep the first N bytes of hijacked raw streams (default 0: counts only)")
    args = ap.parse_args()
    if shutil.which("sbx") is None:
        sys.exit("sbx is not on PATH")
    {"probe": cmd_probe, "proxy": cmd_proxy}[args.phase](args)


if __name__ == "__main__":
    main()
