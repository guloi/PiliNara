import http.server, http.client, socketserver, sys, threading

TARGET = "github.com"

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("PROXY " + (fmt % args) + "\n")
        sys.stderr.flush()

    def _read_body(self):
        te = (self.headers.get("Transfer-Encoding") or "").lower()
        if "chunked" in te:
            buf = bytearray()
            while True:
                line = self.rfile.readline(65536).strip()
                if not line:
                    break
                try:
                    size = int(line.split(b";")[0], 16)
                except ValueError:
                    break
                if size == 0:
                    self.rfile.readline(65536)
                    break
                buf += self.rfile.read(size)
                self.rfile.read(2)
            return bytes(buf) if buf else None
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length) if length else None

    def _forward(self, method):
        body = self._read_body()
        conn = http.client.HTTPSConnection(TARGET, 443, timeout=600)
        skip = {"host", "connection", "proxy-connection", "transfer-encoding",
                "content-length", "expect", "accept-encoding"}
        headers = {k: v for k, v in self.headers.items() if k.lower() not in skip}
        headers["Accept-Encoding"] = "identity"
        if method == "POST" and "Git-Protocol" not in headers:
            pass
        try:
            conn.request(method, self.path, body=body, headers=headers)
            resp = conn.getresponse()
            self.send_response(resp.status)
            for k, v in resp.getheaders():
                if k.lower() in ("transfer-encoding", "connection", "content-length"):
                    continue
                self.send_header(k, v)
            self.send_header("Transfer-Encoding", "chunked")
            self.send_header("Connection", "close")
            self.end_headers()
            while True:
                chunk = resp.read(262144)
                if not chunk:
                    break
                self.wfile.write(b"%x\r\n" % len(chunk) + chunk + b"\r\n")
                self.wfile.flush()
            self.wfile.write(b"0\r\n\r\n")
            self.wfile.flush()
        except Exception as e:
            sys.stderr.write("PROXY ERROR %r\n" % (e,))
            sys.stderr.flush()
        finally:
            conn.close()
            self.close_connection = True

    def do_GET(self):
        self._forward("GET")

    def do_POST(self):
        self._forward("POST")

class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    Server(("127.0.0.1", port), Handler).serve_forever()
