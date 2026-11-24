import Foundation
import Security
import BakerCore

struct AppInstallIdentity: Equatable, Sendable {
    let identifier: String
    let team: String
    let version: String
    let codeHash: Data
}

struct AppInstallPlan: Sendable {
    let destination: URL
    let staging: URL
    let incoming: AppInstallIdentity
    let previous: AppInstallIdentity?
}

/// A one-shot app copy. User documents, preferences and credentials are outside this transaction.
enum AppInstallation {
    static func isReadOnlyApplication(_ application: URL) -> Bool {
        application.isFileURL && application.pathExtension == "app"
            && (try? application.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) == true
    }

    static func identity(_ application: URL) throws -> AppInstallIdentity {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckNestedCode | kSecCSCheckAllArchitectures)
        guard SecRequirementCreateWithString("anchor apple generic and identifier \"local.baker.app\"" as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCreateWithPath(application as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else {
            throw BakerError(message: "Baker’s signature could not be verified. Download a fresh installer.", code: .integrityFailed)
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any],
              let identifier = values[kSecCodeInfoIdentifier as String] as? String, identifier == "local.baker.app",
              let team = values[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty,
              let hash = values[kSecCodeInfoUnique as String] as? Data,
              let version = Bundle(url: application)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              version.range(of: "\\A[0-9]+\\.[0-9]+\\.[0-9]+\\z", options: .regularExpression) != nil else {
            throw BakerError(message: "This is not a signed Baker application.", code: .integrityFailed)
        }
        return AppInstallIdentity(identifier: identifier, team: team, version: version, codeHash: hash)
    }

    static func existing(_ destination: URL, verify: (URL) throws -> AppInstallIdentity = identity) throws -> AppInstallIdentity? {
        let values: URLResourceValues
        do { values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return nil }
        guard values.isSymbolicLink != true, values.isDirectory == true else {
            throw BakerError(message: "Another item is using Baker’s location in Applications. Move it before installing.", code: .storageConflict)
        }
        return try verify(destination)
    }

    static func stage(source: URL, destination: URL, verify: (URL) throws -> AppInstallIdentity = identity) throws -> AppInstallPlan {
        let files = FileManager.default
        guard source.isFileURL, destination.isFileURL, source.pathExtension == "app", destination.lastPathComponent == "Baker.app",
              source.resolvingSymlinksInPath() != destination.resolvingSymlinksInPath() else {
            throw BakerError(message: "Choose a separate Applications location for Baker.", code: .invalidInput)
        }
        let sourceValues = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard sourceValues.isDirectory == true, sourceValues.isSymbolicLink != true else {
            throw BakerError(message: "Open a complete Baker application to install it.", code: .invalidInput)
        }
        let incoming = try verify(source)
        let previous = try existing(destination, verify: verify)
        if let previous {
            guard previous.identifier == incoming.identifier, previous.team == incoming.team else {
                throw BakerError(message: "The existing app has a different signing identity. Install Baker manually.", code: .integrityFailed)
            }
            guard incoming.version.compare(previous.version, options: .numeric) != .orderedAscending else {
                throw BakerError(message: "A newer Baker is already installed. Open it from Applications.", code: .invalidState)
            }
        }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".Baker-install-\(UUID().uuidString).app")
        do {
            try files.copyItem(at: source, to: staging)
            guard try verify(staging) == incoming else {
                throw BakerError(message: "The copied app did not match the installer. Try downloading Baker again.", code: .integrityFailed)
            }
        } catch {
            try? files.removeItem(at: staging)
            throw error
        }
        return AppInstallPlan(destination: destination, staging: staging, incoming: incoming, previous: previous)
    }

    /// Returns the previous app's backup, retained until the new app launches successfully.
    static func commit(_ plan: AppInstallPlan, verify: (URL) throws -> AppInstallIdentity = identity) throws -> URL? {
        guard try verify(plan.staging) == plan.incoming,
              try existing(plan.destination, verify: verify) == plan.previous else {
            throw BakerError(message: "Baker changed while installing. Open the installer again.", code: .storageConflict)
        }
        let files = FileManager.default
        if plan.previous != nil {
            let backup = ".Baker-previous-\(UUID().uuidString).app"
            // Preserve the backup on failure, including a failed relaunch. Never change quarantine.
            _ = try files.replaceItemAt(plan.destination, withItemAt: plan.staging, backupItemName: backup,
                options: [.usingNewMetadataOnly, .withoutDeletingBackupItem])
            return plan.destination.deletingLastPathComponent().appendingPathComponent(backup)
        }
        try files.moveItem(at: plan.staging, to: plan.destination)
        return nil
    }
}
