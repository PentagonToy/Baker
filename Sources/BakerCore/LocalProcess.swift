import Darwin
import Foundation

public struct ProcessResult {
    public let status: Int32
    public let output: Data
}

/// File-backed output prevents pipe deadlocks. A private directory is removed on exit.
public func runProcess(_ executable: URL, arguments: [String], timeout: TimeInterval = 180, input: Data? = nil) throws -> ProcessResult {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("baker-process-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                          attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: directory) }
    let outputURL = directory.appendingPathComponent("stdout")
    let errorURL = directory.appendingPathComponent("stderr")
    FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    FileManager.default.createFile(atPath: errorURL.path, contents: nil)
    let output = try FileHandle(forWritingTo: outputURL)
    let errors = try FileHandle(forWritingTo: errorURL)
    defer { try? output.close(); try? errors.close() }
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = errors
    let inputHandle: FileHandle
    if let input {
        let inputURL = directory.appendingPathComponent("stdin")
        try input.write(to: inputURL)
        inputHandle = try FileHandle(forReadingFrom: inputURL)
    } else { inputHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: "/dev/null")) }
    process.standardInput = inputHandle
    // Only close handles owned by this invocation, never the application's stdin.
    defer { try? inputHandle.close() }
    try process.run()
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning && Date() < deadline && !Task.isCancelled { Thread.sleep(forTimeInterval: 0.05) }
    if process.isRunning {
        process.terminate()
        let grace = Date().addingTimeInterval(2)
        while process.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
        if Task.isCancelled { throw CancellationError() }
        throw BakerError(message: "The operation timed out. Try a smaller region.")
    }
    process.waitUntilExit()
    try Task.checkCancellation()
    return ProcessResult(status: process.terminationStatus, output: try Data(contentsOf: outputURL))
}
