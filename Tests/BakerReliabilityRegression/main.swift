import Foundation
import CoreGraphics

Task { @MainActor in
    var checks = 0, failures: [String] = []
    func check(_ value: Bool, _ message: String) {
        checks += 1
        if !value { failures.append(message); print("FAIL", message) }
    }
    func response(_ value: String, status: Int32 = 0, diagnostic: String? = nil) throws -> FormulaRecognition {
        try decodeFormulaResponse(ProcessResult(status: status, output: Data(value.utf8), diagnostic: diagnostic))
    }
    do {
        let stdinFlags = fcntl(STDIN_FILENO, F_GETFD)
        let echo = try runProcess(URL(fileURLWithPath: "/bin/cat"), arguments: [], input: Data("hello".utf8))
        check(echo.output == Data("hello".utf8), "Owned stdin works")
        check(fcntl(STDIN_FILENO, F_GETFD) == stdinFlags, "Application stdin preserved")
        let failure = try runProcess(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "printf 'noise\\nRuntimeError: missing library\\n' >&2; exit 7"])
        check(failure.status == 7 && failure.output.isEmpty, "Non-zero status and stdout retained")
        check(failure.diagnostic == "RuntimeError: missing library", "Bounded stderr cause retained")
        let success = try runProcess(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "printf 'warning' >&2; printf 'ok'"])
        check(success.diagnostic == nil && success.output == Data("ok".utf8), "Successful output excludes diagnostic chatter")
        for redirection in ["", " >&2"] {
            do {
                _ = try runProcess(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "dd if=/dev/zero bs=1024 count=128" + redirection + " 2>/dev/null"], maximumOutputBytes: 1024)
                check(false, "Excessive output rejected")
            } catch let error as BakerError { check(error.code == .processOutputLimit, "Output bound carries typed failure") }
        }
        do {
            _ = try runProcess(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "dd if=/dev/zero bs=1024 count=16 2>/dev/null; exec /bin/sleep 5"], maximumOutputBytes: 1024)
            check(false,"Running noisy process stopped")
        } catch let error as BakerError { check(error.code == .processOutputLimit,"Active output limit stops the child") }
        do {
            _ = try runProcess(URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], timeout: 0.03)
            check(false, "Timeout rejected")
        } catch let error as BakerError { check(error.code == .processTimedOut, "Timeout carries typed failure") }
        do {
            _ = try runProcess(URL(fileURLWithPath: "/missing/baker-runtime"), arguments: [])
            check(false,"Missing runtime rejected")
        } catch let error as BakerError { check(error.code == .processLaunchFailed, "Launch failure carries typed cause") }
        let cancelled = Task.detached { try runProcess(URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"]) }
        try await Task.sleep(nanoseconds: 50_000_000); cancelled.cancel()
        do { _ = try await cancelled.value; check(false, "Cancelled process") }
        catch is CancellationError { check(true,"Cancellation stops process") }
        for _ in 0..<10 { _ = try runProcess(URL(fileURLWithPath: "/usr/bin/true"), arguments: []) }
        check(fcntl(STDIN_FILENO, F_GETFD) == stdinFlags, "Repeated process invocations preserve stdin")
        let sanitized = BakerError(message: "message", code: .recognitionFailed, diagnostic: "\u{001B}" + String(repeating: "a", count: 5000))
        check(sanitized.diagnostic!.count <= 1024 && !sanitized.errorDescription!.contains("\u{001B}"), "Diagnostics are bounded and strip control bytes")
        let parsed = try response(#"{"latex":"x _ { 2 }","confidence":0.8,"confidence_method":"geometric_mean_token_probability_v1","diagnostics":{"tokenCount":3,"ambiguousTokenCount":1,"minimumTokenProbability":0.5}}"#)
        check(parsed.latex == "x_{2}" && parsed.confidence == 0.8 && parsed.diagnostics?.tokenCount == 3, "Formula response retains source/score semantics")
        let plus = try response(#"{"latex":"x+1=0","model":"pp-formulanet-plus-s-fp32-ort-v1"}"#)
        check(plus.latex == "x+1=0" && plus.confidence == nil && plus.diagnostics == nil, "plus-S accepts valid source without a fabricated model score")
        for (wire, code) in [("formula_token_limit", BakerError.Code.formulaTokenLimit), ("recognition_timeout", .processTimedOut), ("model_not_ready", .modelNotReady), ("future_code", .recognitionFailed)] {
            do { _ = try response("{\"error\":\"test\",\"error_code\":\"" + wire + "\"}", status: 1); check(false,"Worker error rejected") }
            catch let error as BakerError { check(error.code == code, "Worker error classification: " + wire) }
        }
        do { _ = try response("not JSON", status: 1, diagnostic: "missing dependency"); check(false,"Malformed response") }
        catch let error as BakerError { check(error.code == .invalidResponse && error.errorDescription!.contains("missing dependency"), "Malformed JSON retains stderr cause") }
        do { _ = try response(#"{"latex":"x"}"#, status: 1); check(false,"Failure status cannot succeed") }
        catch let error as BakerError { check(error.code == .recognitionFailed,"Failure status checked") }
        do { _ = try response(#"{"latex":"   "}"#); check(false,"Whitespace-only formula rejected") }
        catch let error as BakerError { check(error.code == .recognitionFailed,"Empty normalised formula cannot succeed") }
        let unknown = try response(#"{"latex":"x","confidence":0.9,"confidence_method":"not-calibrated","diagnostics":{"tokenCount":3,"ambiguousTokenCount":1,"minimumTokenProbability":0.5}}"#)
        check(unknown.confidence == nil && unknown.diagnostics == nil,"Unsupported scores remain absent")
        let loader = ThumbnailRequests(), store = NSObject(), otherStore = NSObject(), id = UUID()
        let context = CGContext(data: nil,width: 8,height: 8,bitsPerComponent: 8,bytesPerRow: 32,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = context.makeImage()!
        var reads = 0
        let first = Task { try await loader.load(id, store: store) { reads += 1; try await Task.sleep(nanoseconds: 30_000_000); return image } }
        let second = Task { try await loader.load(id, store: store) { reads += 1; return image } }
        let a = try await first.value, b = try await second.value
        check(reads == 1 && a === b,"Concurrent reads coalesce into one bitmap")
        _ = try await loader.load(id, store: store) { reads += 1; return image }
        check(reads == 2,"Coalescer does not retain completed images")
        let obsolete = Task { try await loader.load(id, store: store) { try? await Task.sleep(nanoseconds: 100_000_000); return image } }
        await Task.yield()
        _ = try await loader.load(id, store: otherStore) { return image }
        do { _ = try await obsolete.value; check(false,"Old storage load cancelled") }
        catch is CancellationError { check(true,"Storage identity prevents stale thumbnail reuse") }
        let clearing = Task { try await loader.load(id, store: store) { try? await Task.sleep(nanoseconds: 100_000_000); return image } }
        await Task.yield(); loader.cancelAll()
        do { _ = try await clearing.value; check(false,"Clear cancels in-flight thumbnail") }
        catch is CancellationError { check(true,"Cache clear cancels pending images") }
        _ = try await loader.load(id, store: store) { return image }
        check(true,"Thumbnail loading recovers after clear")
    } catch { check(false, "Unexpected failure: " + error.localizedDescription) }
    print("RESULT", checks, "checks", failures.count, "failures")
    exit(failures.isEmpty ? 0 : 1)
}
RunLoop.main.run()
