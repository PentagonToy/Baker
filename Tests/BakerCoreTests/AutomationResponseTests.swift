import BakerCore
import XCTest

final class AutomationResponseTests: XCTestCase {
    func testResponseIdentityAndBoundedRegularFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("response.json"), id = UUID()
        func write(_ value: Any) throws {
            try JSONSerialization.data(withJSONObject: value).write(to: file)
        }
        try write(["id": id.uuidString, "ok": true, "total": 3])
        XCTAssertEqual(try AutomationResponse.read(file, requestID: id)["total"] as? Int, 3)
        XCTAssertThrowsError(try AutomationResponse.read(file, requestID: UUID()))
        try write(["id": id.uuidString, "ok": false, "error": "Not ready"])
        XCTAssertEqual(try AutomationResponse.read(file, requestID: id)["ok"] as? Bool, false)
        let link = folder.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertThrowsError(try AutomationResponse.read(link, requestID: id))
        XCTAssertThrowsError(try AutomationResponse.read(folder, requestID: id))
        for value: Any in [["ok": true], ["id": "invalid", "ok": true], ["id": id.uuidString], ["response"]] {
            try write(value)
            XCTAssertThrowsError(try AutomationResponse.read(file, requestID: id))
        }
        try Data("{broken".utf8).write(to: file)
        XCTAssertThrowsError(try AutomationResponse.read(file, requestID: id))
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(AutomationResponse.maximumBytes + 1))
        try handle.close()
        XCTAssertThrowsError(try AutomationResponse.read(file, requestID: id))
    }
}
