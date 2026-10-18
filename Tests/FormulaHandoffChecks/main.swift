if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--reply" {
    FormulaHandoff.respond(on: NSPasteboard(name: NSPasteboard.Name(CommandLine.arguments[2])), latex: #"E = mc^{2}"#)
    exit(0)
}
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message); checks += 1
}
let identifier = UUID().uuidString
let value = "deerstalker-formula-" + identifier
let valid = URL(string: "baker://formula?pasteboard=" + value)!
check(FormulaHandoff.pasteboardName(valid)?.rawValue == value, "Private request accepted")
for invalid in ["baker://formula?pasteboard=general", "baker://formula?pasteboard=deerstalker-formula-invalid", "baker://formula?file=/tmp/formula.png",
                "https://formula?pasteboard=\(value)", "baker://formula/path?pasteboard=\(value)", "baker://formula?pasteboard=\(value)&pasteboard=general",
                "baker://user@formula?pasteboard=\(value)", "baker://formula:42?pasteboard=\(value)", "baker://formula?pasteboard=\(value)#fragment"] {
    check(FormulaHandoff.pasteboardName(URL(string: invalid)!) == nil, "Unsupported request refused")
}
check(FormulaHandoff.image(from: Data("bad image".utf8)) == nil, "Malformed image refused")
for latex in [#"E = mc^{2}"#, #"\frac{a}{b}"#, #"x^{2} + y^{2}"#, #"\alpha"#] {
    check(FormulaHandoff.isFormula(latex), "Formula accepted")
}
for prose in ["Deerstalker", #"\mathrm{Deersta}"#, #"\text{ordinary prose}"#, "Hello world"] {
    check(!FormulaHandoff.isFormula(prose), "Prose does not replace ordinary clipboard text")
}
let image = CGContext(data: nil, width: 60, height: 30, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!.makeImage()!
let png = NSMutableData()
let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
check(CGImageDestinationFinalize(destination), "Test PNG encoded")
check(FormulaHandoff.image(from: png as Data)?.width == 60, "Valid PNG decoded")
let oldCount = NSPasteboard.general.changeCount
let board = NSPasteboard(name: FormulaHandoff.pasteboardName(valid)!)
check(board.setData(png as Data, forType: .png), "Private pasteboard written")
check(board.data(forType: .png) == png as Data, "Private image delivered")
let child = Process()
child.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
child.arguments = ["-module-cache-path", URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("module-cache").path,
                   CommandLine.arguments[0], "--reply", value]
try child.run(); child.waitUntilExit()
check(child.terminationStatus == 0, "Independent responder exits cleanly")
_ = board.changeCount
let response = try JSONSerialization.jsonObject(with: board.string(forType: .string)!.data(using: .utf8)!) as! [String: String]
check(response["latex"] == #"E = mc^{2}"#, "Silent result returns through the private board")
board.releaseGlobally()
check(NSPasteboard.general.changeCount == oldCount, "General clipboard unchanged")
print("\(checks) formula handoff checks passed")
