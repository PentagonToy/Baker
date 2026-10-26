import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let fixtures = URL(fileURLWithPath: CommandLine.arguments[2])
let files = FileManager.default
var checks = 0
func check(_ condition: Bool, _ label: String) {
    guard condition else { fatalError(label) }; checks += 1
}
let folder = output.appendingPathComponent("archive-\(UUID())")
let archive = RecordingArchive(directory: folder)
check(try archive.records().isEmpty, "Empty history")
var saved: [RecordingRecord] = []
for ext in ["mp4", "gif"] {
    let source = fixtures.appendingPathComponent("synthetic.\(ext)")
    let record = try archive.add(source); saved.append(record)
    let destination = folder.appendingPathComponent(record.fileName)
    check(files.fileExists(atPath: source.path), "Import preserves source")
    check(try Data(contentsOf: destination) == Data(contentsOf: source), "Exact copy")
    let raster = try archive.thumbnail(record)
    check(raster.width <= 640 && raster.height <= 640, "Bounded single-frame preview")
    check(record.isGIF == (ext == "gif"), "Media classification")
    check(record.fileName.hasPrefix(ext == "gif" ? "baker_gif_" : "baker_video_"), "Typed recording filename")
}
check(try RecordingArchive(directory: folder).records() == saved.reversed(), "History survives reopening")
try files.removeItem(at: folder.appendingPathComponent(saved[0].fileName))
check(try archive.records().count == 1, "Externally removed files omitted")
let linked = output.appendingPathComponent("linked.mp4")
try? files.removeItem(at: linked)
try files.createSymbolicLink(at: linked, withDestinationURL: fixtures.appendingPathComponent("synthetic.mp4"))
do { _ = try archive.add(linked); fatalError("Symlink accepted") } catch { checks += 1 }
let invalid = folder.appendingPathComponent(".baker-recordings.json")
try Data("invalid".utf8).write(to: invalid)
do { _ = try archive.add(fixtures.appendingPathComponent("synthetic.mp4")); fatalError("Damaged history overwritten") } catch { checks += 1 }
check(files.fileExists(atPath: folder.appendingPathComponent(saved[1].fileName).path), "Index failure preserves saved GIF")
check(try String(contentsOf: invalid, encoding: .utf8) == "invalid", "Damaged index preserved")
print("Passed \(checks) recording history checks")
