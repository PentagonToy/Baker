"""One foreground, loopback-only login session. Stops after login, cancel or five minutes."""
from html import escape
from http.server import HTTPServer, BaseHTTPRequestHandler
import secrets
import os
import json
from pathlib import Path
import subprocess
import time
from urllib.parse import parse_qs


def page(message='', done=False):
    body = '<p>Saved. Return to Baker and choose Test Connection.</p>' if done else '''

<form method="post"><label>Email<input name="email" type="email" autocomplete="username" required maxlength="320"></label>
<label>Password<input name="password" type="password" autocomplete="current-password" required maxlength="2048"></label>
<button type="submit">Sign in</button><p style="font-size:12px">Session saved securely in Keychain.</p></form>'''
    return ('''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Baker · Plugin setup</title><style>body{background:#1f2429;color:#e8ebee;font:15px system-ui;margin:0 auto;max-width:420px;padding:24px}main{padding:0}h1{font-size:22px;margin:0 0 20px}p{line-height:1.5;color:#c7ccd2}label{display:block;margin:14px 0}input{box-sizing:border-box;display:block;width:100%;padding:10px;margin-top:6px;background:#1f2429;color:#e8ebee;border:1px solid #59636c;border-radius:7px}button{width:100%;padding:11px;background:#edba68;color:#1f2429;border:0;border-radius:8px;font-weight:600}.error{color:#edba68}</style><main><h1>Sign in</h1>'''
            + ('<p class="error">'+escape(message)+'</p>' if message else '') + body + '</main></html>').encode()


def run(store, authenticate, announce=True):
    path = '/' + secrets.token_urlsafe(32)
    finished = False

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args): pass

        def permitted(self, post=False):
            host = '127.0.0.1:' + str(self.server.server_port)
            origin = self.headers.get('Origin')
            return self.path == path and self.headers.get('Host') == host and (not post or origin in (None, 'http://'+host))

        def respond(self, body, status=200):
            self.send_response(status)
            for key, value in [('Content-Type', 'text/html; charset=utf-8'), ('Cache-Control', 'no-store'),
                               ('Referrer-Policy', 'same-origin'), ('X-Content-Type-Options', 'nosniff'),
                               ('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'")]:
                self.send_header(key, value)
            self.send_header('Content-Length', str(len(body))); self.end_headers()
            try: self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError): pass

        def do_GET(self):
            self.respond(page() if self.permitted() else b'Not found', 200 if self.permitted() else 404)

        def do_POST(self):
            nonlocal finished
            if not self.permitted(post=True): self.respond(b'Forbidden', 403); return
            try:
                size = int(self.headers.get('Content-Length', '0'))
                if not 0 < size <= 16384: raise ValueError('size')
                form = parse_qs(self.rfile.read(size).decode('utf-8'), max_num_fields=4)
                email, password = form.get('email', [''])[0].strip(), form.get('password', [''])[0]
                if not email or len(email) > 320 or not password or len(password) > 2048: raise ValueError('fields')
                session = authenticate(email, password)
                store.save(session)
            except Exception:
                self.respond(page('Sign-in or Keychain storage failed. Check your details and unlock Keychain, then retry.')); return
            self.respond(page(done=True)); finished = True

    class LoopbackServer(HTTPServer):
        def get_request(self):
            connection, address = super().get_request()
            connection.settimeout(5)
            return connection, address
        def handle_error(self, request, address): pass

    with LoopbackServer(('127.0.0.1', 0), Handler) as server:
        server.timeout = 1
        url = 'http://127.0.0.1:' + str(server.server_port) + path
        descriptor = os.environ.get('BAKER_PLUGIN_SETUP_FILE')
        if descriptor:
            target = Path(descriptor)
            temporary = target.with_suffix('.tmp')
            temporary.write_text(json.dumps({'url': url}))
            temporary.chmod(0o600)
            temporary.replace(target)
        else:
            subprocess.run(['/usr/bin/open', url], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if announce: print('Opened a private local setup page. Complete sign-in there. This window stops after five minutes.', flush=True)
        deadline = time.monotonic() + 300
        while not finished and time.monotonic() < deadline:
            server.handle_request()
    return finished
