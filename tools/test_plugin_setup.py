"""Check the reusable setup helper using fake credentials and loopback HTTP only."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import threading
import time
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.parse import urlencode, urlsplit
from urllib.request import Request, urlopen

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('setup', root / 'examples/ocr-plugin/setup.py')
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)

class Store:
    saved = None
    def save(self, session):
        self.saved = session

with tempfile.TemporaryDirectory(prefix='baker-setup-test-') as folder:
    descriptor = Path(folder) / 'window.json'
    store, result = Store(), []
    def authenticate(email, password):
        assert email == 'test@example.invalid' and password == 'synthetic-password'
        return 'synthetic-session'
    with patch.dict(os.environ, {'BAKER_PLUGIN_SETUP_FILE': str(descriptor)}), patch.object(setup.subprocess, 'run', side_effect=AssertionError('Browser must remain closed')):
        worker = threading.Thread(target=lambda: result.append(setup.run(store, authenticate, announce=False)), daemon=True)
        worker.start()
        deadline = time.monotonic() + 5
        while not descriptor.exists():
            assert time.monotonic() < deadline
            time.sleep(0.01)
        raw = descriptor.read_text()
        url = json.loads(raw)['url']
        assert url.startswith('http://127.0.0.1:') and len(urlsplit(url).path) > 32
        assert descriptor.stat().st_mode & 0o777 == 0o600
        assert 'password' not in raw and 'session' not in raw
        with urlopen(url, timeout=3) as response:
            body = response.read()
            assert b'autocomplete="username"' in body and b'autocomplete="current-password"' in body
            assert response.headers['Cache-Control'] == 'no-store'
            assert response.headers['Referrer-Policy'] == 'same-origin'
        data = urlencode({'email': 'test@example.invalid', 'password': 'synthetic-password'}).encode()
        for origin in ['https://example.invalid', 'null']:
            bad = Request(url, data=data, headers={'Origin': origin})
            try:
                urlopen(bad, timeout=3)
                raise AssertionError('Foreign or opaque origin accepted')
            except HTTPError as error:
                assert error.code == 403 and store.saved is None
        with urlopen(Request(url, data=data, headers={'Origin': 'http://' + urlsplit(url).netloc}), timeout=3) as response:
            assert b'synthetic' not in response.read()
        worker.join(3)
        assert not worker.is_alive() and result == [True] and store.saved == 'synthetic-session'
print('Reusable popup helper passed: atomic descriptor, no browser, AutoFill hints, origin rejection and fake sign-in; no external network or Keychain access')
