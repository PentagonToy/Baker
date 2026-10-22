import Foundation

public struct BakerError: LocalizedError, Sendable {
    public enum Code: String, CaseIterable, Sendable {
        case operationFailed, cancelled, invalidInput, unsupportedFormat, unsupportedSystem, invalidState
        case configurationInvalid, permissionDenied, fileAccessDenied, insufficientSpace, resourceLimit
        case storageFailed, storageConflict, clipboardFailed, captureFailed, recordingFailed, exportFailed
        case downloadFailed, integrityFailed, previewFailed, previewUnsupported
        case processLaunchFailed, processTimedOut, processOutputLimit
        case modelNotReady, invalidResponse, recognitionFailed, formulaTokenLimit
    }
    public enum Recovery: String, Sendable {
        case retry, chooseInput, chooseLocation, reduceInput, reopenHistory, wait
        case formulaSettings, pdfSettings, captureSettings, advancedSettings, systemPermissions, updateApp, none
        public var suggestion: String? {
            switch self {
            case .retry: return "Try the operation again."
            case .chooseInput: return "Choose another file or capture a clearer region."
            case .chooseLocation: return "Choose a writable folder in Settings → General."
            case .reduceInput: return "Use a smaller region or split the document."
            case .reopenHistory: return "Reopen Baker before saving more results."
            case .wait: return "Wait for the current operation to finish."
            case .formulaSettings: return "Check recognition in Settings → Formula."
            case .pdfSettings: return "Check the engine in Settings → Advanced → Offline Model."
            case .captureSettings: return "Check text languages in Settings → Capture."
            case .advancedSettings: return "Check runtime overrides in Settings → Advanced."
            case .systemPermissions: return "Check Baker’s Screen Recording access in macOS System Settings."
            case .updateApp: return "Install the latest complete Baker app."
            case .none: return nil
            }
        }
    }
    public let message: String
    public let code: Code
    public let diagnostic: String?
    public let recovery: Recovery
    public var isRetryable: Bool { Self.retryable.contains(code) }
    private static let retryable: Set<Code> = [.downloadFailed, .processTimedOut, .clipboardFailed, .captureFailed, .previewFailed]

    public init(message: String, code: Code, diagnostic: String? = nil, recovery: Recovery? = nil) {
        self.message = message; self.code = code
        self.recovery = recovery ?? Self.defaultRecovery(for: code)
        let detail = diagnostic.map { String($0.suffix(1024)).filter { !$0.isASCII || !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t" }) } }
        self.diagnostic = detail.flatMap { $0.isEmpty ? nil : $0 }
    }
    /// Keep diagnostics available to developers, separately from the normal UI message.
    public var errorDescription: String? { diagnostic.map { message + "\n" + $0 } ?? message }
    public var recoverySuggestion: String? { recovery.suggestion }
    public var userDescription: String { message }

    private static func defaultRecovery(for code: Code) -> Recovery {
        switch code {
        case .cancelled, .operationFailed, .previewUnsupported: return .none
        case .invalidInput, .unsupportedFormat, .recognitionFailed: return .chooseInput
        case .unsupportedSystem: return .updateApp
        case .invalidState: return .wait
        case .configurationInvalid, .processLaunchFailed, .invalidResponse: return .advancedSettings
        case .permissionDenied: return .systemPermissions
        case .fileAccessDenied, .storageFailed, .insufficientSpace, .exportFailed: return .chooseLocation
        case .storageConflict: return .reopenHistory
        case .resourceLimit, .processOutputLimit, .formulaTokenLimit: return .reduceInput
        case .modelNotReady, .integrityFailed: return .formulaSettings
        case .downloadFailed, .clipboardFailed, .captureFailed, .previewFailed, .processTimedOut: return .retry
        case .recordingFailed: return .captureSettings
        }
    }
    /// Preserve typed failures; classify system failures by domain/code, never by prose.
    public static func wrapping(_ error: Error, fallback: Code = .operationFailed) -> Self {
        if let failure = error as? Self { return failure }
        if error is CancellationError { return Self(message: "Operation cancelled.", code: .cancelled) }
        let system = error as NSError
        var code = fallback
        if system.domain == NSURLErrorDomain {
            code = system.code == NSURLErrorCancelled ? .cancelled : .downloadFailed
        } else if system.domain == NSCocoaErrorDomain {
            switch system.code {
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError: code = .fileAccessDenied
            case NSFileWriteOutOfSpaceError: code = .insufficientSpace
            case NSFileReadNoSuchFileError, NSFileWriteFileExistsError: code = .storageFailed
            case NSUserCancelledError: code = .cancelled
            default: break
            }
        } else if system.domain == NSPOSIXErrorDomain {
            switch system.code {
            case Int(POSIXErrorCode.EACCES.rawValue), Int(POSIXErrorCode.EPERM.rawValue): code = .fileAccessDenied
            case Int(POSIXErrorCode.ENOSPC.rawValue): code = .insufficientSpace
            default: break
            }
        }
        return Self(message: error.localizedDescription, code: code)
    }
}
