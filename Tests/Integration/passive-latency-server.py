import json
import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from datetime import datetime, timezone

ROOT = Path(os.environ["CLASHBAR_PASSIVE_TEST_ROOT"])
CLOUDFLARE = "https://www.cloudflare.com/cdn-cgi/trace"
GOOGLE = "https://www.gstatic.com/generate_204"
START = time.time() - 30
PROXY_READS = 0


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *arguments):
        pass

    def do_GET(self):
        global PROXY_READS
        with (ROOT / "requests.jsonl").open("a") as stream:
            stream.write(json.dumps(self.path) + "\n")
        if self.path == "/version":
            body = {"version": "passive-fixture", "meta": True}
        elif self.path == "/configs":
            body = {"mode": "rule"}
        elif self.path == "/rules":
            body = {"rules": [{"type": "Match", "proxy": "Main US"}]}
        elif self.path == "/proxies":
            PROXY_READS += 1
            failed = PROXY_READS >= 3
            stamp = datetime.fromtimestamp(START + (5 if failed else 0), timezone.utc).isoformat()
            success = {"time": stamp, "delay": 0 if failed else 170}
            body = {"proxies": {
                "Main US": {"name": "Main US", "type": "URLTest", "now": "美国三", "all": ["美国三"], "testUrl": CLOUDFLARE},
                "美国三": {"name": "美国三", "type": "Vless", "alive": False, "history": [{"time": stamp, "delay": 0}],
                          "extra": {CLOUDFLARE: {"alive": not failed, "history": [success]},
                                    GOOGLE: {"alive": False, "history": [{"time": stamp, "delay": 0}]}}}
            }}
        else:
            self.send_error(500, "Unexpected request: passive mode must not initiate tests")
            return
        data = json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


ROOT.mkdir(parents=True, exist_ok=True)
server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
(ROOT / "port").write_text(str(server.server_port))
server.serve_forever()
