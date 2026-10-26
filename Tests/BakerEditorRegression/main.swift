import AppKit

var checks = 0
func check(_ condition: Bool, _ message: String) {
    precondition(condition, message); checks += 1
}

@MainActor func run() throws {
    let expected = ["#000000", "#E69F00", "#56B4E9", "#009E73", "#F0E442", "#0072B2", "#D55E00", "#CC79A7", "#FFFFFF"]
    check(CaptureColour.allCases.map(\.rawValue) == expected, "Eight Okabe–Ito values plus white")
    for colour in CaptureColour.allCases {
        let rgb = colour.nsColor.usingColorSpace(.sRGB)!
        let hex = String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
        check(hex == colour.rawValue && rgb.alphaComponent == 1, "Exact opaque sRGB palette value")
    }
    let context = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 256,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.8, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
    let source = context.makeImage()!
    let editor = CaptureEditorState(image: source)
    editor.mask()
    check(editor.tool == .rectangle && editor.filled && editor.selectedColour == .white, "Mask preset is white and opaque")
    let mask = CaptureMark(tool: .rectangle, points: [CGPoint(x: 16, y: 12), CGPoint(x: 48, y: 36)], colour: .white, width: 4, filled: true)
    editor.add(mask)
    let result = try editor.rendered()
    check(result.width == 64 && result.height == 48, "Edits retain source resolution")
    let pixels = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 256,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    pixels.draw(result, in: CGRect(x: 0, y: 0, width: 64, height: 48))
    let bytes = pixels.data!.assumingMemoryBound(to: UInt8.self)
    let centre = (24 * 64 + 32) * 4
    check((0..<4).allSatisfy { bytes[centre + $0] == 255 }, "Masked pixels are solid opaque white")
    check(bytes[0] < 250 && bytes[2] > bytes[0], "Unmasked image remains present")
    editor.undo(); check(editor.marks.isEmpty && editor.redoMarks.count == 1, "Undo retains a redo mark")
    editor.redo(); check(editor.marks.count == 1 && editor.redoMarks.isEmpty, "Redo restores mark")
    editor.undo(); editor.add(mask); check(editor.redoMarks.isEmpty, "New drawing clears redo")
    editor.add(CaptureMark(tool: .crop, points: [.zero, CGPoint(x: 32, y: 24)], colour: .white, width: 2))
    let cropped = try editor.rendered()
    check(cropped.width == 32 && cropped.height == 24, "Cropping keeps pixel geometry")
    editor.reset(); check(editor.marks.isEmpty && editor.redoMarks.isEmpty, "Reset clears both histories")

    let size = CGSize(width: 1920, height: 1080), rect = CGRect(x: 20, y: 40, width: 600, height: 400)
    let area = RepeatCaptureArea(displayIdentity: "display-A", displaySize: size, rect: rect)
    check(area.isValid && area.matches(identity: "display-A", size: size), "Valid saved display-local rectangle")
    check(!area.matches(identity: "display-B", size: size), "Never follow pointer onto a different display")
    check(!area.matches(identity: "display-A", size: CGSize(width: 1080, height: 1920)), "Rotation or display-size change rejected")
    for invalid in [CGRect(x: -1, y: 0, width: 10, height: 10), CGRect(x: 1910, y: 10, width: 20, height: 20), CGRect(x: 1, y: 1, width: 1, height: 1), CGRect.null] {
        check(!RepeatCaptureArea(displayIdentity: "display-A", displaySize: size, rect: invalid).isValid, "Out-of-bounds or invalid region rejected")
    }
    let suite = "baker-repeat-regression-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    check(RepeatCaptureArea.load(defaults: defaults) == nil, "No selection by default")
    area.save(defaults: defaults)
    check(RepeatCaptureArea.load(defaults: defaults) == area, "Rectangle persists independently of image history")
    var future = area; future.version = 99
    defaults.set(try JSONEncoder().encode(future), forKey: RepeatCaptureArea.preference)
    check(RepeatCaptureArea.load(defaults: defaults) == nil, "Unsupported saved version rejected")
    defaults.set(Data(repeating: 0, count: 5000), forKey: RepeatCaptureArea.preference)
    check(RepeatCaptureArea.load(defaults: defaults) == nil, "Oversized saved data rejected")
    if let screen = NSScreen.main, let identity = RepeatCaptureArea.identity(of: screen) {
        let region = CaptureRegion(screen: screen, rect: CGRect(x: 0, y: 0, width: 20, height: 20))
        let live = RepeatCaptureArea(region: region)!
        check(live.displayIdentity == identity && live.resolve()?.rect == region.rect, "Actual display identity resolves without capture")
        check(live.resolve(screens: []) == nil, "Disconnected display is unavailable")
    }
    check(CaptureShortcuts.actions.map(\.0).prefix(7) == ["area", "scroll", "text", "formula", "video", "gif", "all"], "Existing hot-key numeric IDs remain stable")
    check(CaptureShortcuts.actions.last?.0 == "repeat", "Repeat Area has a separately configurable shortcut")
    print("Passed \(checks) editor/palette/repeat-area checks")
}
Task { @MainActor in
    do { try run(); exit(0) } catch { print(error); exit(1) }
}
dispatchMain()
