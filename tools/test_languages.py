#!/usr/bin/env python3
"""Check OCR selections, bundled model integrity and menu ordering without building the app."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
output = args.output.resolve()
if output == ROOT or ROOT in output.parents:
    parser.error('Keep generated evidence outside the repository')
output.mkdir(parents=True, exist_ok=True)
parts = ['Sources/BakerCore/BakerError.swift', 'Sources/BakerCore/OCRLanguages.swift', 'Sources/Baker/Preferences.swift', 'Tests/BakerLanguageRegression/main.swift']
source = '\n'.join((ROOT / p).read_text().replace('import BakerCore\n', '') for p in parts)
menu = (ROOT / 'Sources/Baker/MenuLayout.swift').read_text()
source += menu[menu.index('struct BakerMenuGroup'):menu.index('@MainActor private final class MenuLayoutDraft')]
source += r'''
let oldCaptureLayout = BakerMenuLayout(version: 3, groups: [], entries: ["capture": ["captureAll", "captureRegion"]], hidden: ["captureText"])
let captureGroup = BakerMenuGroup.all.first { $0.id == "capture" }!
check(oldCaptureLayout.orderedEntries(captureGroup).filter { $0 == "captureWindow" }.count == 1, "Existing menu layouts gain Window exactly once")
check(oldCaptureLayout.hidden.contains("captureText"), "New Window command preserves hidden commands")
var layout = BakerMenuLayout()
let capture = BakerMenuGroup.all.first { $0.id == "capture" }!
check(layout.move("captureAll", to: "captureFormula", group: "capture"), "Move down")
check(layout.orderedEntries(capture).last == "recordScreen", "Neighbour retained")
check(layout.orderedEntries(capture).firstIndex(of: "captureAll") == layout.orderedEntries(capture).firstIndex(of: "captureFormula").map { $0 + 1 }, "Dropped at destination")
check(layout.move("captureAll", to: "captureRegion", group: "capture"), "Move up")
check(layout.orderedEntries(capture).first == "captureAll", "Move to first")
let before = layout
check(!layout.move("openImage", to: "captureRegion", group: "capture"), "Reject cross-group")
check(!layout.move("captureAll", to: "captureRegion", group: "unknown"), "Reject unknown group")
check(!layout.move("captureAll", to: "captureAll", group: "capture"), "Self-drop is harmless")
check(layout == before, "Invalid drops preserve draft")
check(layout.move("recent", to: "capture"), "Group order changes")
check(layout.orderedGroups.first?.id == "recent", "Group moved to first")
let preferences = UserDefaults(suiteName: "Baker.LanguageRegression." + UUID().uuidString)!
layout.hidden.insert("captureText")
layout.save(to: preferences)
check(BakerMenuLayout.load(from: preferences) == layout, "Isolated preference round trip")
preferences.removeObject(forKey: BakerMenuLayout.preference)
print("Language and menu checks: \(checks)")
'''
script = output / 'languages-menu.swift'
script.write_text(source)
result = subprocess.run(['swift', str(script)], capture_output=True, text=True)
(output / 'regression.log').write_text(result.stdout + result.stderr)
print(result.stdout + result.stderr)
if result.returncode:
    raise SystemExit(result.returncode)
models = ROOT / 'Sources/BakerCore/Resources/Tessdata'
manifest = json.loads((models / 'SOURCE.json').read_text())
for name, expected in manifest['files'].items():
    data = (models / name).read_bytes()
    assert len(data) == expected['bytes'], name
    assert hashlib.sha256(data).hexdigest() == expected['sha256'], name
print('Verified', len(manifest['files']), 'pinned model/licence files')
