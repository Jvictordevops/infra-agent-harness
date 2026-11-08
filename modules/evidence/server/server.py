"""Server of the evidence module, for bin/clip and bin/evidence. TLS + token (header X-Clip-Token).

Clipboard (one slot, memory only, never logged or written to disk):
  PUT /clip                  store text            GET /clip      return it and empty the slot
Evidence store (on disk under $CLIP_DATA, one package per evidence folder):
  GET    /ev/<work>/                     list packages: [{name, size, sha256}]
  PUT    /ev/<work>/<folder>.tar.zst     upload (streamed to disk; 409 if it already exists: evidence is immutable)
  GET    /ev/<work>/<folder>.tar.zst     download
  DELETE /ev/<work>/                     delete the whole work (on close, after archiving)
GET /health  "ok" without token
"""
import hashlib
import hmac
import json
import os
import re
import shutil
import ssl
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CONF = os.environ.get("CLIP_CONF", "/etc/clip")
DATA = os.environ.get("CLIP_DATA", "/data")
BIND = os.environ.get("CLIP_BIND", "0.0.0.0")
PORT = int(os.environ.get("CLIP_PORT", "8443"))
MAX_CLIP = 1_000_000
MAX_PKG = 2 * 1024**3
CHUNK = 1024**2
TOKEN = open(f"{CONF}/token", encoding="ascii").read().strip().encode()
NAME = r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}"
RE_WORK = re.compile(rf"^/ev/({NAME})/$")
RE_PKG = re.compile(rf"^/ev/({NAME})/({NAME}\.tar\.zst)$")

slot = b""
lock = threading.Lock()


def work_dir(work):
    d = os.path.join(DATA, work)
    return d if ".." not in work else None


class Handler(BaseHTTPRequestHandler):
    server_version = "clip"
    sys_version = ""
    protocol_version = "HTTP/1.1"

    def _reply(self, code, body=b"", ctype="text/plain; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self):
        return hmac.compare_digest(self.headers.get("X-Clip-Token", "").encode(), TOKEN)

    def _length(self):
        try:
            return int(self.headers.get("Content-Length") or 0)
        except ValueError:
            return -1

    # ------------------------------------------------------------------ GET
    def do_GET(self):
        global slot
        if self.path == "/health":
            return self._reply(200, b"ok\n")
        if not self._authorized():
            return self._reply(401)
        if self.path == "/clip":
            with lock:
                out, slot = slot, b""
            return self._reply(200, out)
        m = RE_WORK.match(self.path)
        if m:
            d = work_dir(m.group(1))
            items = []
            if d and os.path.isdir(d):
                for f in sorted(os.listdir(d)):
                    if f.endswith(".tar.zst"):
                        p = os.path.join(d, f)
                        sha = open(p + ".sha256", encoding="ascii").read().strip() if os.path.exists(p + ".sha256") else ""
                        items.append({"name": f, "size": os.path.getsize(p), "sha256": sha})
            return self._reply(200, json.dumps(items).encode(), "application/json")
        m = RE_PKG.match(self.path)
        if m:
            p = os.path.join(DATA, m.group(1), m.group(2))
            if not os.path.isfile(p):
                return self._reply(404)
            self.send_response(200)
            self.send_header("Content-Type", "application/zstd")
            self.send_header("Content-Length", str(os.path.getsize(p)))
            self.end_headers()
            with open(p, "rb") as fh:
                shutil.copyfileobj(fh, self.wfile, CHUNK)
            return None
        return self._reply(404)

    # ------------------------------------------------------------------ PUT
    def do_PUT(self):
        global slot
        if not self._authorized():
            return self._reply(401)
        n = self._length()
        if self.path == "/clip":
            if n < 0 or n > MAX_CLIP:
                return self._reply(413)
            with lock:
                slot = self.rfile.read(n)
            return self._reply(200, b"ok\n")
        m = RE_PKG.match(self.path)
        if not m:
            return self._reply(404)
        if n <= 0 or n > MAX_PKG:
            return self._reply(413)
        d = os.path.join(DATA, m.group(1))
        p = os.path.join(d, m.group(2))
        if os.path.exists(p):
            return self._reply(409, b"exists\n")
        os.makedirs(d, exist_ok=True)
        tmp = p + ".part"
        h = hashlib.sha256()
        left = n
        with open(tmp, "wb") as fh:
            while left > 0:
                chunk = self.rfile.read(min(CHUNK, left))
                if not chunk:
                    break
                fh.write(chunk)
                h.update(chunk)
                left -= len(chunk)
        if left:
            os.remove(tmp)
            return self._reply(400, b"incomplete\n")
        os.replace(tmp, p)
        with open(p + ".sha256", "w", encoding="ascii") as fh:
            fh.write(h.hexdigest())
        return self._reply(201, (h.hexdigest() + "\n").encode())

    do_POST = do_PUT

    # ------------------------------------------------------------------ DELETE
    def do_DELETE(self):
        if not self._authorized():
            return self._reply(401)
        m = RE_WORK.match(self.path)
        if not m:
            return self._reply(404)
        d = os.path.join(DATA, m.group(1))
        if os.path.isdir(d):
            shutil.rmtree(d)
        return self._reply(200, b"deleted\n")

    def log_message(self, fmt, *args):  # method + path + status only, never the content
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))


ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.minimum_version = ssl.TLSVersion.TLSv1_2
ctx.load_cert_chain(f"{CONF}/server.crt", f"{CONF}/server.key")
httpd = ThreadingHTTPServer((BIND, PORT), Handler)
httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
httpd.serve_forever()
