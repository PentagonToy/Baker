import AppKit
import BakerCore

/// An explicit user action waits for normal shutdown before launching the same installed app.
enum AppReopen {
    static func arguments(application: URL, processID: Int32) throws -> [String] {
        guard application.isFileURL, application.pathExtension == "app", processID > 1 else {
            throw BakerError(message: "Reopening is available from an installed Baker app.", code: .invalidState)
        }
        // Pass paths as positional arguments, never interpolate them into shell source.
        let script = "i=0; while [ \"$i\" -lt 300 ]; do if ! kill -0 \"$1\" 2>/dev/null; then exec /usr/bin/open \"$2\"; fi; i=$((i+1)); /bin/sleep 0.2; done; exit 1"
        return ["-c", script, "baker-reopen", String(processID), application.path]
    }
    static func schedule(application: URL = Bundle.main.bundleURL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = try arguments(application: application, processID: ProcessInfo.processInfo.processIdentifier)
        process.standardInput = FileHandle.nullDevice; process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        do { try process.run() }
        catch { throw BakerError(message: "Baker could not prepare to reopen. Quit and open it from Applications.", code: .processLaunchFailed) }
    }
}
