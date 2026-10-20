"""Serve three neutral XML-RPC replies on an ephemeral loopback port."""
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import sys


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        print(json.dumps({"path": self.path, "contentType": self.headers.get("Content-Type"),
                          "body": body.decode("utf-8")}), flush=True)
        if self.path == "/wait":
            self.connection.settimeout(10)
            disconnected = self.connection.recv(1) == b""
            print(json.dumps({"disconnected": disconnected}), flush=True)
            return
        if self.path == "/fault":
            reply = ('<methodResponse><fault><value><struct>'
                     '<member><name>faultCode</name><value><int>42</int></value></member>'
                     '<member><name>faultString</name><value><string>Denied café 🐼</string></value></member>'
                     '</struct></value></fault></methodResponse>')
        elif self.path == "/invalid":
            reply = '<methodResponse><params/><params/></methodResponse>'
        else:
            reply = ('<methodResponse><params><param><value><string>'
                     '<![CDATA[café 🐼 <&]]></string></value></param></params></methodResponse>')
        data = reply.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/xml; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


with HTTPServer(("127.0.0.1", 0), Handler) as server:
    server.timeout = 10
    print(server.server_port, flush=True)
    for _ in range(1 if "--wait" in sys.argv else 3):
        server.handle_request()
