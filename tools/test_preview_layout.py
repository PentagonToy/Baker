"""Check display-height and fixed preview limits without capturing the screen."""
import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
out = parser.parse_args().output.resolve()
if out == ROOT or ROOT in out.parents:
    parser.error('Keep generated evidence outside the repository')
out.mkdir(parents=True, exist_ok=True)
source = (ROOT / 'Sources/Baker/CaptureOverlayController.swift').read_text()
helper = source[source.index('enum CaptureStackLayout'):source.index('@MainActor')]
tests = '''
func check(_ height: CGFloat, _ limit: Int, _ expected: Int, _ cards: [CGFloat] = Array(repeating: 166, count: 20)) {
    let actual = CaptureStackLayout.capacity(heights: cards, availableHeight: height, limit: limit)
    guard actual == expected else { fatalError("Unexpected preview capacity: \\(actual), expected \\(expected)") }
}
check(650, 0, 3)
check(1000, 0, 5)
check(2000, 0, 11)
check(2000, 3, 3)
check(656, 0, 3, [166, 300, 166])
check(655, 0, 2, [166, 300, 166])
check(1000, 0, 0, [])
check(100, 0, 0)
print("8 adaptive preview layout checks passed")
'''
script = out / 'layout.swift'
script.write_text('import Foundation\n' + helper + tests)
result = subprocess.run(['swift', str(script)], capture_output=True, text=True, timeout=60)
(out / 'layout.log').write_text(result.stdout + result.stderr)
print(result.stdout + result.stderr)
raise SystemExit(result.returncode)
