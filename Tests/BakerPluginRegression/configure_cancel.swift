@MainActor func cancelSetupCheck() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("setup-cancel-" + UUID().uuidString)
    let files = FileManager.default
    try files.createDirectory(at: root, withIntermediateDirectories: true)
    let package = root.appendingPathComponent("package")
    try files.createDirectory(at: package, withIntermediateDirectories: true)
    try files.copyItem(at: URL(fileURLWithPath: CommandLine.arguments[3]), to: package.appendingPathComponent("worker.py"))
    let marker = root.appendingPathComponent("started.json")
    let manifest: [String: Any] = ["schema": 1, "id": "example.cancel", "name": "Cancellation", "version": "1",
        "executable": "baker-python", "arguments": ["{plugin}/worker.py", "configure-wait", marker.path],
        "operations": ["formula"], "configuration": true]
    try JSONSerialization.data(withJSONObject: manifest).write(to: package.appendingPathComponent("plugin.json"))
    let digest = try OCRPluginPackage.digest(package), python = URL(fileURLWithPath: CommandLine.arguments[2])
    let task = Task.detached {
        try OCRPluginRunner.run(folder: package, approvedDigest: digest, python: python, dataDirectory: root.appendingPathComponent("state"), operation: "configure")
    }
    let deadline = Date().addingTimeInterval(5)
    while !files.fileExists(atPath: marker.path) {
        guard Date() < deadline else { task.cancel(); throw BakerError(message: "Fixture did not start", code: .invalidState) }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    let value = try JSONSerialization.jsonObject(with: Data(contentsOf: marker)) as! [String: Int]
    task.cancel()
    do { _ = try await task.value; fatalError("Setup cancellation ignored") } catch is CancellationError {}
    precondition(kill(Int32(value["pid"]!), 0) == -1 && errno == ESRCH)
    print("Interactive setup cancellation passed; listener-owning child was reaped")
}
Task { @MainActor in do { try await cancelSetupCheck(); exit(0) } catch { print(error); exit(1) } }
dispatchMain()
