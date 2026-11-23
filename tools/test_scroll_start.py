"""Check Auto Scroll startup, focus transfer and rapid pause/resume without sending input."""
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
session = (ROOT / "Sources/Baker/ScrollCaptureSession.swift").read_text()
action = session[session.index("    func toggleAutoScroll()"):session.index("    private func advanceAutomatically(")]
action = action.replace("NSWorkspace", "TestWorkspace").replace("ScanTurnTarget", "TestTurnTarget")
source = """
import Foundation
import CoreGraphics

enum ProbeError: Error, LocalizedError {
    case focus
    var errorDescription: String? { "Focus did not transfer" }
}
@MainActor final class TestApplication {
    let processIdentifier: Int32 = 7
    var activations = 0
    var transfersFocus = true
    var didActivate: (() -> Void)?
    func activate() {
        activations += 1
        if transfersFocus { TestWorkspace.shared.frontmostApplication = self }
        let callback = didActivate; didActivate = nil; callback?()
    }
}
@MainActor final class TestWorkspace {
    static let shared = TestWorkspace()
    var frontmostApplication: TestApplication?
}
@MainActor struct TestTurnTarget {
    init(application: TestApplication, region: Int, point: CGPoint?, expectedWindow: CGRect?, expectedTitle: String?) throws {
        guard TestWorkspace.shared.frontmostApplication === application else { throw ProbeError.focus }
    }
}
struct ScrollAdvanceProgress {}
@MainActor final class Harness {
    enum State { case capturing, finishing }
    var state = State.capturing
    var count = 1
    var autoRequests = 0
    var autoScrolling = false
    var autoTarget: TestTurnTarget?
    var autoSetupTask: Task<Void, Never>?
    var targetApplication: TestApplication?
    var region: Int? = 1
    var caption = ""
    var message = ""
    var lastAutoIssue: String?
    var autoProgress = ScrollAdvanceProgress()
    var autoRejected = false
    var nextAutoScrollAt: TimeInterval = 0
    var inputs = 0
    init(_ application: TestApplication) { targetApplication = application }
    func advanceAutomatically(now: TimeInterval, settled: Bool) { inputs += 1 }
""" + action + """
}
@MainActor func run() async throws {
    let app = TestApplication(), ready = Harness(TestApplication())
    ready.targetApplication = app
    TestWorkspace.shared.frontmostApplication = nil
    ready.toggleAutoScroll()
    await ready.autoSetupTask?.value
    assert(app.activations == 1 && ready.inputs == 1 && ready.autoScrolling)
    assert(ready.autoSetupTask == nil && ready.lastAutoIssue == nil)

    let cancelledApp = TestApplication(), cancelled = Harness(TestApplication())
    cancelled.targetApplication = cancelledApp
    cancelled.toggleAutoScroll()
    let cancelledTask = cancelled.autoSetupTask
    cancelled.toggleAutoScroll()
    await cancelledTask?.value
    assert(cancelledApp.activations == 0 && cancelled.inputs == 0 && !cancelled.autoScrolling)

    let pendingApp = TestApplication(), pending = Harness(TestApplication())
    pending.targetApplication = pendingApp; pendingApp.transfersFocus = false
    TestWorkspace.shared.frontmostApplication = nil
    await withCheckedContinuation { continuation in
        pendingApp.didActivate = { continuation.resume() }
        pending.toggleAutoScroll()
    }
    let oldTask = pending.autoSetupTask
    pending.toggleAutoScroll()
    pendingApp.transfersFocus = true
    pending.toggleAutoScroll()
    let newTask = pending.autoSetupTask
    await newTask?.value; await oldTask?.value
    assert(pendingApp.activations == 2 && pending.inputs == 1 && pending.autoScrolling)
    assert(pending.autoSetupTask == nil && pending.lastAutoIssue == nil)

    let finishedApp = TestApplication(), finished = Harness(TestApplication())
    finished.targetApplication = finishedApp
    finished.toggleAutoScroll(); finished.state = .finishing
    await finished.autoSetupTask?.value
    assert(finishedApp.activations == 0 && finished.inputs == 0)

    let deniedApp = TestApplication(), denied = Harness(TestApplication())
    denied.targetApplication = deniedApp; deniedApp.transfersFocus = false
    TestWorkspace.shared.frontmostApplication = nil
    denied.toggleAutoScroll()
    await denied.autoSetupTask?.value
    assert(!denied.autoScrolling && denied.inputs == 0)
    assert(denied.lastAutoIssue == "Focus did not transfer")
    print("8 Auto Scroll focus/start/pause/resume checks passed")
}
Task { @MainActor in
    do { try await run(); exit(0) } catch { print(error); exit(1) }
}
dispatchMain()
"""
script = output / "scroll-start.swift"
script.write_text(source)
result = subprocess.run(["swift", str(script)], capture_output=True, text=True, timeout=60)
(output / "scroll-start.log").write_text(result.stdout + result.stderr)
print(result.stdout if result.returncode == 0 else result.stdout + result.stderr[-4000:])
raise SystemExit(result.returncode)
