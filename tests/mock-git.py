#!/usr/bin/env python3
"""離線 mock GitLab / Azure DevOps API，供 pr-diff.sh 測試使用。
用法: mock-git.py <port> <fixtures_dir>
GitLab 路由驗 PRIVATE-TOKEN header；ADO 路由驗 Basic 認證（:PAT）。"""
import sys
import json
import base64
import http.server
import pathlib
import urllib.parse

PORT = int(sys.argv[1])
FIX = pathlib.Path(sys.argv[2])

GITLAB_TOKEN = "glpat-test"
ADO_BASIC = base64.b64encode(b":adopat-test").decode()

ADO_FILE_BASE = "replicas: 2\nimage: app:v1\n"
ADO_FILE_HEAD = "replicas: 4\nimage: app:v1\n"


class Handler(http.server.BaseHTTPRequestHandler):
    def _send(self, code, body=b"", ctype="application/json"):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        raw_path, _, raw_query = self.path.partition("?")
        query = urllib.parse.parse_qs(raw_query)

        if raw_path == "/ping":
            self._send(200, b"{}")
            return

        # ---- GitLab ----
        if raw_path.startswith("/api/v4/"):
            if self.headers.get("PRIVATE-TOKEN") != GITLAB_TOKEN:
                self._send(401, b'{"message":"401 Unauthorized"}')
                return
            page = query.get("page", ["1"])[0]
            if raw_path == "/api/v4/projects/group%2Fapp/merge_requests/123/diffs":
                if page == "1":
                    self._send(200, (FIX / "gitlab-diffs-p1.json").read_bytes())
                elif page == "2":
                    self._send(200, (FIX / "gitlab-diffs-p2.json").read_bytes())
                else:
                    self._send(200, b"[]")
                return
            if raw_path == "/api/v4/projects/big%2Frepo/merge_requests/9/diffs":
                if page == "1":
                    files = [
                        {
                            "old_path": "file-%02d.yaml" % i,
                            "new_path": "file-%02d.yaml" % i,
                            "new_file": False,
                            "deleted_file": False,
                            "renamed_file": False,
                            "diff": "@@ -1 +1 @@\n-a: %d\n+a: %d\n" % (i, i + 1),
                        }
                        for i in range(60)
                    ]
                    self._send(200, json.dumps(files))
                else:
                    self._send(200, b"[]")
                return
            self._send(404, b"{}")
            return

        # ---- Azure DevOps ----
        if "/_apis/git/" in raw_path:
            auth = self.headers.get("Authorization", "")
            if auth != "Basic " + ADO_BASIC:
                self._send(401, b'{"message":"401"}')
                return
            base = "/org/proj/_apis/git/repositories/repo"
            if raw_path == base + "/pullrequests/7":
                self._send(200, json.dumps({
                    "title": "bump replicas",
                    "lastMergeSourceCommit": {"commitId": "abc123"},
                    "lastMergeTargetCommit": {"commitId": "def456"},
                }))
                return
            if raw_path == base + "/pullrequests/7/iterations":
                self._send(200, json.dumps({"value": [{"id": 1}, {"id": 2}]}))
                return
            if raw_path == base + "/pullrequests/7/iterations/2/changes":
                self._send(200, json.dumps({"changeEntries": [
                    {"item": {"path": "/app/deploy.yaml"}, "changeType": "edit"},
                ]}))
                return
            if raw_path == base + "/items":
                version = query.get("versionDescriptor.version", [""])[0]
                if version == "def456":
                    self._send(200, ADO_FILE_BASE, "text/plain")
                elif version == "abc123":
                    self._send(200, ADO_FILE_HEAD, "text/plain")
                else:
                    self._send(404, b"{}")
                return
            self._send(404, b"{}")
            return

        self._send(404, b"{}")

    def log_message(self, *args):
        pass


http.server.HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
