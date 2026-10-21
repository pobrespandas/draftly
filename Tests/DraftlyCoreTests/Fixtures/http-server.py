"""Serve neutral HTTP fixtures on an ephemeral loopback port."""
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import socket
from urllib.parse import parse_qs, urlsplit


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        self.respond()

    def do_POST(self):
        self.respond()

    def do_HEAD(self):
        self.respond(head=True)

    def respond(self, head=False):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        target = urlsplit(self.path)
        print(json.dumps({"path": target.path, "method": self.command}), flush=True)
        if target.path == "/wait":
            self.connection.settimeout(10)
            try:
                disconnected = self.connection.recv(1) == b""
            except socket.timeout:
                disconnected = False
            print(json.dumps({"disconnected": disconnected}), flush=True)
            return
        if target.path == "/disconnect":
            self.close_connection = True
            return
        if target.path in ("/redirect", "/redirect-permanent"):
            self.send_response(301 if target.path == "/redirect-permanent" else 302)
            self.send_header("Location", "/json")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        status = 200
        content_type = "application/json; charset=utf-8"
        if target.path == "/latin1":
            data = "café".encode("iso-8859-1")
            content_type = "text/plain; charset=iso-8859-1"
        elif target.path == "/utf16-json":
            data = json.dumps({"text": "café 🐼"}, ensure_ascii=False).encode("utf-16le")
            content_type = "application/json; charset=utf-16le"
        elif target.path == "/bodyless":
            status, data = 204, b""
        elif target.path == "/error":
            status, data = 503, "Unavailable café 🐼".encode("utf-8")
        elif target.path == "/invalid-json":
            data = "{invalid café 🐼".encode("utf-8")
        elif target.path == "/echo":
            value = {"query": parse_qs(target.query, keep_blank_values=True),
                     "body": body.decode("utf-8"), "method": self.command,
                     "contentType": self.headers.get("Content-Type"),
                     "authorization": self.headers.get("Authorization"),
                     "custom": self.headers.get("X-Neutral")}
            data = json.dumps(value, ensure_ascii=False).encode("utf-8")
        else:
            data = json.dumps({"text": "café 🐼"}, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("X-Neutral", "yes")
        self.send_header("Set-Cookie", "neutral=fixture")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if not head:
            self.wfile.write(data)


with HTTPServer(("127.0.0.1", 0), Handler) as server:
    server.timeout = 10
    print(server.server_port, flush=True)
    while True:
        server.handle_request()
