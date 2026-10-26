import AppKit

var checks = 0
func check(_ result: Bool, _ message: String) {
    precondition(result, message); checks += 1
}
let capture = BakerMenuGroup.all.first { $0.id == "capture" }!
check(capture.entries.filter { $0.id == "recordScreen" }.count == 1, "One recording action inside Capture")
check(!BakerMenuGroup.all.contains { $0.id == "record" }, "No separate Record category")
var old = BakerMenuLayout()
old.version = 1; old.groups = ["recent", "record", "capture", "files"]
old.entries = ["capture": ["captureFormula", "captureAll"], "record": ["recordGIF", "recordVideo"]]
old.hidden = ["recordVideo", "recordGIF", "captureText"]
let migrated = old.migrated
check(migrated.version == 3 && !migrated.groups.contains("record"), "Old group migrated")
check(migrated.hidden == ["recordScreen", "captureText"], "Both hidden recording actions remain hidden")
check(migrated.entries["capture"] == old.entries["capture"], "Custom capture order preserved")
check(migrated.orderedEntries(capture).last == "recordScreen", "New command appended to saved capture order")
check(migrated.migrated == migrated, "Migration idempotent")
old.hidden.remove("recordGIF")
check(!old.migrated.hidden.contains("recordScreen"), "One formerly visible format keeps recording visible")
check(try JSONDecoder().decode(BakerMenuLayout.self, from: JSONEncoder().encode(migrated)) == migrated, "Preferences round trip")
let screen = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)
let local = CGRect(x: 100, y: 200, width: 500, height: 300)
let selection = RecordingPlacement.selection(local, on: screen)
check(selection == CGRect(x: -1820, y: -500, width: 500, height: 300), "Top-left display coordinates convert on negative-origin monitor")
for box in [selection, screen, CGRect(x: -1920, y: -1080, width: 10, height: 10), CGRect(x: -10, y: -10, width: 10, height: 10)] {
    let frame = RecordingPlacement.controls(selection: box, visible: screen, size: CGSize(width: 300, height: 246))
    check(screen.contains(frame), "Controls stay on selected monitor")
}
let below = RecordingPlacement.controls(selection: selection, visible: screen, size: CGSize(width: 300, height: 246))
check(below.maxY < selection.minY, "Controls prefer below the region")
let low = CGRect(x: -1820, y: -1070, width: 500, height: 300)
check(RecordingPlacement.controls(selection: low, visible: screen, size: CGSize(width: 300, height: 246)).minY > low.maxY, "Controls move above a bottom-edge region")

let recent = BakerMenuGroup.all.first { $0.id == "recent" }!
check(migrated.orderedEntries(recent).first == "openCaptureFolder", "Save folder first after old migration")
var v2 = BakerMenuLayout(); v2.version = 2; v2.entries["recent"] = ["showHistory", "openCaptureFolder", "showPreview"]
check(v2.migrated.orderedEntries(recent).prefix(3) == ["openCaptureFolder","showHistory","showPreview"], "v2 recent order migrates without disturbing other choices")
var current = v2.migrated; current.entries["recent"] = ["showPreview","openCaptureFolder"]
check(current.migrated == current, "A new custom order remains under user control")
print("Passed \(checks) recording menu and placement checks")
