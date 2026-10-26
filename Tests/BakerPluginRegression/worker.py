import json
import os
from pathlib import Path
import sys
import time
r = json.load(sys.stdin)
mode = sys.argv[1]
response = {'schema': 1, 'id': r['id'], 'ok': True}
if mode == 'configure-wait':
    import socket
    with socket.socket() as server:
        server.bind(('127.0.0.1', 0)); server.listen(1)
        marker = Path(sys.argv[2]); temporary = marker.with_suffix('.tmp')
        temporary.write_text(json.dumps({'pid': os.getpid(), 'port': server.getsockname()[1]})); temporary.replace(marker)
        time.sleep(60)
if mode == 'timeout':
    time.sleep(30)
if mode == 'wrong-id':
    response['id'] = 'wrong'
if mode == 'environment' and (os.environ.get('BAKER_PLUGIN_TEST_PARENT_ONLY') or os.environ.get('BAKER_PLUGIN_API_KEY')):
    response['ok'] = False
if r['operation'] == 'configure' and ('input' in r or 'output' in r or os.environ.get('BAKER_PLUGIN_API_KEY')):
    response['ok'] = False
if mode == 'failure':
    response['ok'] = False
if r['operation'] == 'formula':
    response['latex'] = '' if mode == 'empty' else 'x^2+1=0'
    if mode == 'oversize':
        response['latex'] = 'x' * 9000
    if mode == 'key' and os.environ.get('BAKER_PLUGIN_API_KEY') != 'synthetic-test-key':
        response['ok'] = False
if r['operation'] == 'pdf':
    out = Path(r['output']['directory'])
    ext = 'md' if r['output']['format'] == 'markdown' else 'tex'
    response['output'] = f'result.{ext}'
    (out / 'assets').mkdir()
    (out / 'assets/figure.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg"/>')
    (out / response['output']).write_text('# Test\n![Figure](assets/figure.svg)')
    if mode == 'symlink-output':
        (out / 'link').symlink_to('/etc/hosts')
print(json.dumps(response))
