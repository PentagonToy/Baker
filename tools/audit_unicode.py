#!/usr/bin/env python3
"""Audit existing formula fixtures and optional saved OCR outputs without running models."""
import argparse
import html
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--cases', type=Path, help='Repeat an existing audit input set unchanged')
parser.add_argument('--authored', type=Path, help='Existing JSONL manifest with formula targets')
parser.add_argument('--predictions', type=Path, help='Existing JSONL OCR predictions; not gold labels')
args = parser.parse_args()
output = args.output.resolve()
if output == ROOT or ROOT in output.parents:
    parser.error('Keep generated evidence outside the repository')
output.mkdir(parents=True, exist_ok=True)
rows = {}
def add(source, origin):
    if not source:
        return
    rows.setdefault(source, {'source': source, 'origins': []})['origins'].append(origin)

for suite in ['BakerRegression', 'BakerFormulaRegression', 'BakerPreviewRegression', 'BakerKeynoteRegression', 'BakerUnicodeRegression']:
    path = ROOT / 'Tests' / suite / 'main.swift'
    if not path.exists():
        continue
    text = path.read_text()
    # These suites use single-line raw Swift literals; include negative fixtures explicitly.
    for match in re.finditer(r'#"([^\n]*?)"#', text):
        source = match.group(1)
        if '\\' in source or '^' in source or '_' in source:
            add(source, f'{path.relative_to(ROOT)}:{text[:match.start()].count(chr(10)) + 1}')
for path, key in [(args.authored, 'target'), (args.predictions, 'prediction')]:
    if path:
        for line in path.read_text().splitlines():
            row = json.loads(line)
            if key == 'prediction' or row.get('kind') == 'formula':
                add(row.get(key, ''), f'{path}:{row["id"]}')
if args.cases:
    rows = {row['source']: row for row in json.loads(args.cases.read_text())}
(output / 'cases.json').write_text(json.dumps(list(rows.values()), ensure_ascii=False, indent=2))
source = '\n'.join((ROOT / p).read_text() for p in ['Sources/BakerCore/LatexWhitespace.swift', 'Sources/BakerCore/UnicodeMath.swift'])
source += r'''
let cases = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [[String: Any]]
var results: [[String: Any]] = []
for row in cases {
    let source = row["source"] as! String
    let plain = UnicodeMath.convert(source), styled = UnicodeMath.convert(source, italicVariables: true)
    results.append(["source": source, "plain": plain.text, "styled": styled.text,
        "warnings": styled.warnings, "plainWarnings": plain.warnings, "origins": row["origins"]!])
}
FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]))
'''
script = output / 'audit.swift'
script.write_text(source)
result = subprocess.run(['swift', str(script), str(output / 'cases.json')], capture_output=True, text=True)
(output / 'compiler.log').write_text(result.stderr)
if result.returncode:
    raise SystemExit(result.stderr)
results = json.loads(result.stdout)
(output / 'results.json').write_text(json.dumps(results, ensure_ascii=False, indent=2))
parts = ['<!doctype html><meta charset="utf-8"><title>Baker Unicode audit</title>',
         '<style>body{font:15px system-ui;margin:24px;background:#f5f0e6}table{border-collapse:collapse;width:100%}td,th{padding:12px;border:1px solid #bbb;vertical-align:top}pre{white-space:pre-wrap;overflow-wrap:anywhere;max-width:580px}.math{font:24px "STIX Two Math","Latin Modern Math",serif}</style>',
         '<h1>Baker Unicode audit</h1><p>Targeted fixtures include malformed and intentionally unsupported syntax. Saved OCR predictions are inputs, not correctness labels. Font appearance in this browser is not destination-app paste validation.</p>',
         '<table><tr><th>Source</th><th>Unicode (italic variables)</th><th>Warnings</th></tr>']
for row in results:
    parts.append('<tr><td><pre>' + html.escape(row['source']) + '</pre></td><td class="math">' + html.escape(row['styled']) + '</td><td>' + html.escape('; '.join(row['warnings'])) + '</td></tr>')
parts.append('</table>')
(output / 'review.html').write_text('\n'.join(parts))
print(f"Audited {len(results)} unique inputs in plain and italic-variable modes; {sum(bool(row['warnings']) for row in results)} have explicit warnings (including negative fixtures).")
