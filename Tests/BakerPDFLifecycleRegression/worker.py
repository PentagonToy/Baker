"""Authored protocol fixture. Performs no OCR and needs no model or screen access."""
import argparse
import json
import os
from pathlib import Path
import signal
import sys
import time

p = argparse.ArgumentParser()
for key in ['source', 'output', 'config']:
    p.add_argument('--' + key, type=Path)
a = p.parse_args()
config = json.loads(a.config.read_text())
Path(config['pid']).write_text(str(os.getpid()))
a.output.mkdir()
mode = config['mode']
if mode == 'cancel':
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    time.sleep(20)
if mode == 'flood':
    sys.stderr.write('x' * (9 * 1024 * 1024))
    sys.exit(2)
if mode == 'failure':
    sys.stderr.write('x' * 5000 + '\nfixture failure\n')
    sys.exit(2)
(a.output/'progress.json').write_text('invalid partial progress')
time.sleep(0.12)
(a.output/'progress.json').write_text(json.dumps({'page': 1, 'total': 1, 'phase': 'recognising'}))
time.sleep(0.35)
(a.output/'document.md').write_text('# Fixture\n\n$x+y$\n')
(a.output/'document.tex').write_text('\\[x+y\\]\n')
(a.output/'report.json').write_text(json.dumps({'pages': [{'page': 1, 'attached_labels': 0, 'unmatched_labels': [], 'character_count': 3}], 'warnings': []}))
