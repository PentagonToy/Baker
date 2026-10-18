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
board.releaseGlobally()
check(NSPasteboard.general.changeCount == oldCount, "General clipboard unchanged")
print("\(checks) formula handoff checks passed")
