#!/usr/bin/env python3
"""離線 mock Jira Server 7.10，供 script 測試使用。
用法: mock-jira.py <port> <fixtures_dir> <log_dir>
POST/PUT 的 request body 會寫入 log_dir 供測試斷言。"""
import sys
import http.server
import pathlib

PORT = int(sys.argv[1])
FIX = pathlib.Path(sys.argv[2])
LOG = pathlib.Path(sys.argv[3])


class Handler(http.server.BaseHTTPRequestHandler):
    def _send(self, code, body=b"", ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/rest/api/2/myself":
            self._send(200, b'{"name": "tester"}')
        elif path == "/rest/api/2/issue/AUTH-401":
            self._send(401, b"{}")
        elif path == "/rest/api/2/issue/TEST-1":
            self._send(200, (FIX / "issue-TEST-1.json").read_bytes())
        elif path == "/rest/api/2/issue/TEST-2":
            self._send(200, (FIX / "issue-TEST-2.json").read_bytes())
        elif path == "/rest/api/2/search":
            self._send(200, (FIX / "search.json").read_bytes())
        elif path == "/rest/api/2/attachment/10001":
            self._send(200, (FIX / "attachment-10001.json").read_bytes())
        elif path == "/secure/attachment/10001/pods.png":
            self._send(200, b"PNGDATA", "image/png")
        else:
            self._send(404, b"{}")

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        (LOG / "last-post.json").write_bytes(self.rfile.read(length))
        if self.path == "/rest/api/2/issue/TEST-1/comment":
            self._send(201, b'{"id": "20001"}')
        else:
            self._send(404, b"{}")

    def do_PUT(self):
        length = int(self.headers.get("Content-Length", 0))
        (LOG / "last-put.json").write_bytes(self.rfile.read(length))
        if self.path == "/rest/api/2/issue/TEST-1":
            self._send(204)
        else:
            self._send(404, b"{}")

    def log_message(self, *args):
        pass


http.server.HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
