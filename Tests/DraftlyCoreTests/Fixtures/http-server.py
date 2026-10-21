"""Serve neutral HTTP fixtures on an ephemeral loopback port."""
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import socket
import xml.etree.ElementTree as ET
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
        xml_encodings = {"/xml-latin1": "iso-8859-1", "/xml-utf16": "utf-16",
                         "/xml-utf16le": "utf-16le", "/xml-utf16be": "utf-16be"}
        xml_path = target.path.removesuffix("-no-charset")
        if xml_path in xml_encodings:
            encoding = xml_encodings[xml_path]
            xml = ('<?xml version="1.0" encoding="' + encoding + '"?>'
                   '<methodResponse><params><param><value><string>'
                   'café &amp; mañana</string></value></param></params></methodResponse>')
            data = xml.encode(encoding)
            content_type = "text/xml" if target.path.endswith("-no-charset") else "text/xml; charset=" + encoding
        elif target.path == "/xml-echo":
            request = ET.fromstring(body)
            response = ET.Element("methodResponse")
            response.append(request.find("params"))
            data, content_type = ET.tostring(response, encoding="utf-8"), "text/xml"
        elif target.path in ("/xml-fault", "/xml-malformed-fault"):
            code = int(parse_qs(target.query).get("code", ["42"])[0])
            xml = ('<methodResponse><fault><value><struct>'
                   '<member><name>faultCode</name><value><int>' + str(code) + '</int></value></member>'
                   '<member><name>faultString</name><value><string>Denied café 🐼</string></value></member>'
                   '</struct></value></fault></methodResponse>')
            if target.path == "/xml-malformed-fault":
                xml = xml.replace("<int>", "<string>").replace("</int>", "</string>")
            data, content_type = xml.encode("utf-8"), "text/xml"
        elif target.path in ("/xml-malformed-array", "/xml-malformed-struct", "/xml-http-failure"):
            value = {
                "/xml-malformed-array": "<array><unexpected/></array>",
                "/xml-malformed-struct": "<struct><unexpected><name>key</name><value>discarded</value></unexpected></struct>",
                "/xml-http-failure": "<string>HTTP failure body</string>"
            }[target.path]
            data = ('<methodResponse><params><param><value>' + value
                    + '</value></param></params></methodResponse>').encode("utf-8")
            content_type = "text/xml"
            if target.path == "/xml-http-failure":
                status = 503
        elif target.path == "/latin1":
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
