import Darwin
import Foundation

public struct ProcessResult {
    public let status: Int32
    public let output: Data
    public let diagnostic: String?
    public init(status: Int32, output: Data, diagnostic: String? = nil) {
        self.status = status; self.output = output; self.diagnostic = diagnostic
    }
}

/// Install before launch so even a process that exits immediately wakes its owner.
final class ProcessCompletion {
    private let process: Process
    private let completed = DispatchSemaphore(value: 0)
    init(_ process: Process) {
        self.process = process
        let completed = completed
        process.terminationHandler = { _ in completed.signal() }
    }
    func wait(for interval: TimeInterval) -> Bool { completed.wait(timeout: .now() + interval) == .success }
    func stopAndWait() {
        guard process.isRunning else { return }
        process.terminate()
        if !wait(for: 2), process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
    }
}

/// Read only a small tail even if the child has exceeded its log budget.
func processDiagnosticTail(_ url: URL) -> String? {
    guard let reader = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? reader.close() }
    guard let length = try? reader.seekToEnd() else { return nil }
    try? reader.seek(toOffset: length > 2048 ? length - 2048 : 0)
    guard let data = try? reader.read(upToCount: 2048) else { return nil }
    return String(decoding: data, as: UTF8.self).split(separator: "\n").last.map { String($0.suffix(500)) }
}

/// File-backed output prevents pipe deadlocks. Completion wakes immediately;
/// a short watchdog checks cancellation and output sizes without retaining logs.
public func runProcess(_ executable: URL, arguments: [String], timeout: TimeInterval = 180, input: Data? = nil,
                       environment: [String: String] = [:], maximumOutputBytes: Int = 8 * 1024 * 1024, inheritEnvironment: Bool = true) throws -> ProcessResult {
    guard timeout.isFinite, timeout > 0, timeout <= 7200, (1...16 * 1024 * 1024).contains(maximumOutputBytes) else {
        throw BakerError(message: "The process limits are invalid.", code: .configurationInvalid)
    }
    try Task.checkCancellation()
    let files = FileManager.default
    let directory = files.temporaryDirectory.appendingPathComponent("baker-process-" + UUID().uuidString)
    try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    defer { try? files.removeItem(at: directory) }
    let outputURL = directory.appendingPathComponent("stdout"), errorURL = directory.appendingPathComponent("stderr")
    files.createFile(atPath: outputURL.path, contents: nil); files.createFile(atPath: errorURL.path, contents: nil)
    let output = try FileHandle(forWritingTo: outputURL), errors = try FileHandle(forWritingTo: errorURL)
    defer { try? output.close(); try? errors.close() }
    let process = Process()
    let completion = ProcessCompletion(process)
    process.executableURL = executable; process.arguments = arguments
    if !inheritEnvironment { process.environment = environment }
    else if !environment.isEmpty { process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in override } }
    process.standardOutput = output; process.standardError = errors
    let inputHandle: FileHandle
    if let input {
        let inputURL = directory.appendingPathComponent("stdin")
        try input.write(to: inputURL); inputHandle = try FileHandle(forReadingFrom: inputURL)
    } else { inputHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: "/dev/null")) }
    process.standardInput = inputHandle
    defer { try? inputHandle.close() }
    func size(_ url: URL) throws -> UInt64 { try files.attributesOfItem(atPath: url.path)[.size] as? UInt64 ?? 0 }
    func excessiveOutput() throws -> Bool { try size(outputURL) > maximumOutputBytes || size(errorURL) > maximumOutputBytes }
    func diagnostic() -> String? { processDiagnosticTail(errorURL) }
    do { try process.run() }
    catch { throw BakerError(message: "The local recognition process could not start.", code: .processLaunchFailed, diagnostic: error.localizedDescription) }
    defer { completion.stopAndWait() }
    let deadline = ProcessInfo.processInfo.systemUptime + timeout
    while true {
        try Task.checkCancellation()
        if try excessiveOutput() { completion.stopAndWait(); throw BakerError(message: "The local process exceeded its output limit.", code: .processOutputLimit) }
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0 else {
            completion.stopAndWait(); throw BakerError(message: "The operation timed out. Try a smaller region.", code: .processTimedOut, diagnostic: diagnostic())
        }
        if completion.wait(for: min(0.1, remaining)) { break }
    }
    process.waitUntilExit()
    try Task.checkCancellation()
    guard try !excessiveOutput() else { throw BakerError(message: "The local process exceeded its output limit.", code: .processOutputLimit) }
    return ProcessResult(status: process.terminationStatus, output: try Data(contentsOf: outputURL), diagnostic: process.terminationStatus == 0 ? nil : diagnostic())
}
