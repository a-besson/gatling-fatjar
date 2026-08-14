#!/usr/bin/env python3
"""Tiny HTTP stub standing in for http://computer-database.gatling.io.

The simulations bundled in the fat jar target the public Gatling demo site.
Hitting it from CI would make the e2e run depend on a third-party host, so the
e2e script points that hostname at 127.0.0.1 and serves every route from here.
Any GET/POST answers 200 with a small HTML body, which is all the scenarios
need: they only assert on the default "status is 2xx" check.
"""

import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BODY = b"<html><body><h1>computer database stub</h1></body></html>"


class StubHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _respond(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(BODY)))
        self.end_headers()
        self.wfile.write(BODY)

    def do_GET(self):
        self._respond()

    def do_HEAD(self):
        self._respond()

    def do_POST(self):
        # Drain the request body so the connection stays reusable.
        length = int(self.headers.get("Content-Length") or 0)
        if length:
            self.rfile.read(length)
        self._respond()

    def log_message(self, fmt, *args):
        sys.stderr.write("[stub] " + (fmt % args) + "\n")


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 80
    server = ThreadingHTTPServer(("0.0.0.0", port), StubHandler)
    sys.stderr.write(f"[stub] listening on port {port}\n")
    sys.stderr.flush()
    server.serve_forever()


if __name__ == "__main__":
    main()
