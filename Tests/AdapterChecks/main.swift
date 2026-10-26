import Foundation

struct FormulaRecognition { let latex: String; let confidence: Double?; var model = "test-engine" }
var checks = 0, calls = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message); checks += 1 }
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let image = directory.appendingPathComponent("input.png")
try Data([137, 80, 78, 71]).write(to: image)
func request(version: Int = 1, id: String = "request-1", operation: String = "formula", path: String? = nil) throws -> [String: Any] {
    let data = try JSONSerialization.data(withJSONObject: ["version": version, "id": id, "operation": operation, "image": path ?? image.path])
    let output = FormulaAdapter.reply(data) { url in
        check(url.path == image.path, "Only the validated local input reaches the engine")
        calls += 1; return FormulaRecognition(latex: "E = mc^{2}", confidence: 0.91)
    }
    return try JSONSerialization.jsonObject(with: output) as! [String: Any]
}
let result = try request()
check(result["version"] as? Int == 1 && result["id"] as? String == "request-1", "Version and caller id returned")
check((result["result"] as? [String: Any])?["latex"] as? String == "E = mc^{2}", "Structured LaTeX result")
check(result["error"] == nil && calls == 1, "Success calls engine once")
for invalid in [try request(version: 2), try request(id: ""), try request(id: String(repeating: "x", count: 129)),
                try request(operation: "unknown"), try request(path: "relative.png"), try request(path: directory.path), try request(path: "/no-such-adapter-image.png")] {
    check(invalid["error"] is String && invalid["result"] == nil, "Invalid request returns an error, without a result")
}
check(calls == 1, "Invalid requests never run recognition")
for data in [Data("not JSON".utf8), Data(repeating: 65, count: 65537)] {
    let response = FormulaAdapter.reply(data) { _ in preconditionFailure("Unexpected engine call") }
    let value = try JSONSerialization.jsonObject(with: response) as! [String: Any]
    check(value["error"] is String, "Malformed or oversized request refused")
}
print("\(checks) generic adapter checks passed")
