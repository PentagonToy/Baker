import BakerCore
import XCTest

final class CoreTests: XCTestCase {
    func testLanguageSelectionPreservesOrderAndBounds() {
        XCTAssertEqual(OCRLanguages.normalized(["invalid", "fi-FI", "fi-FI", "en-US"]), ["fi-FI", "en-US"])
        XCTAssertEqual(OCRLanguages.normalized([]), ["en-US"])
        XCTAssertEqual(OCRLanguages.normalized(OCRLanguages.choices.map(\.0)).count, OCRLanguages.maximumActive)
        XCTAssertEqual(OCRLanguages.setting("en-US", enabled: false, in: ["en-US"]), ["en-US"])
    }

    func testExplicitChildEnvironmentIsIsolated() throws {
        let name = "BAKER_TEST_PARENT_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        setenv(name, "authored-test-value", 1)
        defer { unsetenv(name) }
        let result = try runProcess(
            URL(fileURLWithPath: "/usr/bin/env"), arguments: [],
            environment: ["BAKER_TEST_CHILD": "allowed"], inheritEnvironment: false)
        XCTAssertEqual(result.status, 0)
        // Keep unexpected inherited values out of failure diagnostics.
        XCTAssertTrue(String(decoding: result.output, as: UTF8.self) == "BAKER_TEST_CHILD=allowed\n")
    }

    func testInvalidProcessLimitsFailBeforeLaunch() {
        for timeout in [0.0, -1, .infinity, .nan, 7201] {
            XCTAssertThrowsError(
                try runProcess(URL(fileURLWithPath: "/does-not-exist"), arguments: [], timeout: timeout)
            ) {
                XCTAssertEqual(($0 as? BakerError)?.code, .configurationInvalid)
            }
        }
        for limit in [0, -1, 16 * 1024 * 1024 + 1] {
            XCTAssertThrowsError(
                try runProcess(URL(fileURLWithPath: "/does-not-exist"), arguments: [], maximumOutputBytes: limit)
            ) {
                XCTAssertEqual(($0 as? BakerError)?.code, .configurationInvalid)
            }
        }
    }
}
