#!/usr/bin/env python3
"""A stand-in for Paddock's model gateway in `mise run capture:cli kits` (PAD-73.2): answers Anthropic's
Messages API with one fixed reply, streamed or not, and logs each request's method, path, and
which auth header came (never its value) to the file given, one JSON line each.

Usage: python3 -I tools/tasks/lib/fake-anthropic.py PORT LOGFILE
"""

import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1])
LOG = sys.argv[2]
REPLY = "pong from the fake gateway"


def log(entry):
    with open(LOG, "a") as f:
        f.write(json.dumps(entry) + "\n")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _send_json(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        log({"method": "GET", "path": self.path})
        if self.path.startswith("/v1/models"):
            self._send_json(200, {"data": [{"id": "m0-model", "type": "model", "display_name": "m0"}], "has_more": False})
        else:
            self._send_json(404, {"type": "error", "error": {"type": "not_found_error", "message": "m0"}})

    def do_POST(self):
        length = int(self.headers.get("content-length") or 0)
        body = self.rfile.read(length) if length else b"{}"
        try:
            request = json.loads(body)
        except ValueError:
            request = {}
        log({
            "method": "POST",
            "path": self.path,
            "auth": [h for h in ("authorization", "x-api-key") if self.headers.get(h)],
            "model": request.get("model"),
            "stream": bool(request.get("stream")),
        })
        if not self.path.startswith("/v1/messages"):
            self._send_json(404, {"type": "error", "error": {"type": "not_found_error", "message": "m0"}})
            return
        if self.path.startswith("/v1/messages/count_tokens"):
            self._send_json(200, {"input_tokens": 10})
            return
        message = {
            "id": "msg_m0", "type": "message", "role": "assistant", "model": request.get("model", "m0-model"),
            "stop_reason": "end_turn", "stop_sequence": None,
            "usage": {"input_tokens": 10, "output_tokens": 5},
        }
        if not request.get("stream"):
            self._send_json(200, {**message, "content": [{"type": "text", "text": REPLY}]})
            return
        self.send_response(200)
        self.send_header("content-type", "text/event-stream")
        self.end_headers()
        events = [
            ("message_start", {"type": "message_start", "message": {**message, "content": [], "stop_reason": None,
                                                                    "usage": {"input_tokens": 10, "output_tokens": 0}}}),
            ("content_block_start", {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}),
            ("content_block_delta", {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": REPLY}}),
            ("content_block_stop", {"type": "content_block_stop", "index": 0}),
            ("message_delta", {"type": "message_delta", "delta": {"stop_reason": "end_turn", "stop_sequence": None},
                               "usage": {"output_tokens": 5}}),
            ("message_stop", {"type": "message_stop"}),
        ]
        for name, data in events:
            self.wfile.write(f"event: {name}\ndata: {json.dumps(data)}\n\n".encode())
            self.wfile.flush()


ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
