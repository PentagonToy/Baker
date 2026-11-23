"""Check scrolling pixel fidelity, output limits and selection geometry using synthetic images."""
import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, required=True)
output = parser.parse_args().output.resolve()
if output == ROOT or ROOT in output.parents:
    parser.error("Keep generated evidence outside the repository")
output.mkdir(parents=True, exist_ok=True)
core = [ROOT / "Sources/BakerCore" / name for name in [
    "BakerError.swift", "CaptureRetention.swift", "CaptureSVG.swift", "CaptureArchive.swift",
    "ImageClipboard.swift", "ScrollStitcher.swift",
]]
source = "\n".join(path.read_text().replace("Bundle.module", "Bundle.main") for path in core)
service = (ROOT / "Sources/Baker/CaptureService.swift").read_text()
source += service[service.index("enum CaptureSelection"):service.index("struct CaptureRegion")]
session = (ROOT / "Sources/Baker/ScrollCaptureSession.swift").read_text()
source += session[session.index("struct ScrollAdvanceProgress"):session.index("/// The stream owns")]
input_source = (ROOT / "Sources/Baker/ScanTurnTarget.swift").read_text()
source += input_source[input_source.index("enum ScrollInputEvent"):input_source.index("/// Automatic input")]
source += """
let inputBounds = CGRect(x: -1000, y: 200, width: 800, height: 600)
let inputPoint = CGPoint(x: -700, y: 450)
let scrollEvent = ScrollInputEvent.make(pixels: 60, point: inputPoint, windowNumber: 123, bounds: inputBounds)!
let cocoaScroll = NSEvent(cgEvent: scrollEvent)!
assert(cocoaScroll.type == .scrollWheel && cocoaScroll.windowNumber == 123)
assert(cocoaScroll.locationInWindow == CGPoint(x: 300, y: 350))
assert(cocoaScroll.scrollingDeltaY == -60 && cocoaScroll.scrollingDeltaX == 0)
assert(cocoaScroll.hasPreciseScrollingDeltas)
assert(ScrollInputEvent.make(pixels: 60, point: .zero, windowNumber: 123, bounds: inputBounds) == nil)
assert(ScrollInputEvent.make(pixels: 60, point: inputPoint, windowNumber: 0, bounds: inputBounds) == nil)
assert(CaptureSelection.pixelScale(filter: 1, screen: 2) == 2)
assert(CaptureSelection.pixelScale(filter: 2, screen: 1) == 2)
assert(CaptureSelection.pixelScale(filter: 1, screen: 1) == 1)
var progress = ScrollAdvanceProgress()
assert(progress.isReady(height: 100, settled: false, overdue: 0))
assert(progress.observe(height: 100, rejected: false) == .advance)
assert(!progress.isReady(height: 100, settled: false, overdue: 0.1))
assert(progress.isReady(height: 100, settled: true, overdue: 0.1))
assert(progress.isReady(height: 100, settled: false, overdue: 0.6))
assert(progress.isReady(height: 140, settled: false, overdue: 0))
assert(progress.observe(height: 100, rejected: false) == .advance)
assert(progress.observe(height: 140, rejected: false) == .advance)
assert(!progress.isReady(height: 140, settled: false, overdue: 0))
assert(!progress.isReady(height: 120, settled: false, overdue: 0.1))
assert(progress.observe(height: 140, rejected: false) == .advance)
assert(progress.observe(height: 140, rejected: false) == .advance)
assert(progress.observe(height: 140, rejected: false) == .finished)
var rejectedProgress = ScrollAdvanceProgress()
assert(rejectedProgress.observe(height: 100, rejected: true) == .paused)
var noResponse = ScrollAdvanceProgress()
assert(noResponse.observe(height: 100, rejected: false) == .advance)
assert(noResponse.observe(height: 100, rejected: false) == .advance)
assert(noResponse.observe(height: 100, rejected: false) == .advance)
assert(noResponse.observe(height: 100, rejected: false) == .paused)
let bounds = CGRect(x: 0, y: 0, width: 1200, height: 900)
let rect = CGRect(x: 100, y: 200, width: 400, height: 300)
assert(CaptureSelection.adjusted(rect, delta: CGPoint(x: -200, y: 800), handle: nil, within: bounds)
    == CGRect(x: 0, y: 600, width: 400, height: 300))
for handle in CaptureSelection.resizeAnchors.indices {
    let adjusted = CaptureSelection.adjusted(rect, delta: CGPoint(x: 2000, y: -2000), handle: handle, within: bounds)
    assert(CaptureSelection.isValid(adjusted) && bounds.contains(adjusted))
}
print("36 scrolling input, selection, Retina and automatic-stop checks passed")
"""
source += (ROOT / "Tests/BakerScrollRegression/main.swift").read_text().replace("import BakerCore\n", "")
script = output / "scroll.swift"
script.write_text(source)
result = subprocess.run(["swift", str(script), str(output)], capture_output=True, text=True, timeout=180)
(output / "scroll.log").write_text(result.stdout + result.stderr)
print(result.stdout if result.returncode == 0 else result.stdout + result.stderr[-4000:])
raise SystemExit(result.returncode)
