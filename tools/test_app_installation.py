"""Check app-copy transactions in temporary folders without installing or launching an app."""
import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--signed-app", type=Path, help="Also verify an existing signed Baker app without changing it")
arguments = parser.parse_args()
output = arguments.output.resolve()
if output == ROOT or ROOT in output.parents:
    parser.error("Keep generated evidence outside the source tree")
output.mkdir(parents=True, exist_ok=True)
source = (ROOT / "Sources/BakerCore/BakerError.swift").read_text()
source += (ROOT / "Sources/Baker/AppInstallation.swift").read_text().replace("import BakerCore\n", "")
source += r'''
let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString)
let files = FileManager.default
try files.createDirectory(at: root, withIntermediateDirectories: true)
var checks = 0
func check(_ value: @autoclosure () throws -> Bool, _ label: String) throws {
    guard try value() else { fatalError(label) }; checks += 1
}
func rejects(_ label: String, _ action: () throws -> Void) throws {
    do { try action() } catch { checks += 1; return }; fatalError(label)
}
func fixture(_ path: String, version: String = "1.2.0", team: String = "fixture-team", text: String = "original") throws -> URL {
    let app = root.appendingPathComponent(path)
    try files.createDirectory(at: app, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: ["version": version, "team": team]).write(to: app.appendingPathComponent("identity.json"))
    try Data(text.utf8).write(to: app.appendingPathComponent("payload"))
    return app
}
func mockIdentity(_ url: URL) throws -> AppInstallIdentity {
    let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url.appendingPathComponent("identity.json"))) as! [String: String]
    return AppInstallIdentity(identifier: "local.baker.app", team: value["team"]!, version: value["version"]!, codeHash: try Data(contentsOf: url.appendingPathComponent("payload")))
}
func payload(_ app: URL) throws -> String { try String(contentsOf: app.appendingPathComponent("payload"), encoding: .utf8) }
func destination(_ name: String) throws -> URL {
    let folder = root.appendingPathComponent(name)
    try files.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appendingPathComponent("Baker.app")
}
let incoming = try fixture("source/Baker.app", version: "1.3.0", text: "new")
let first = try destination("first")
let firstPlan = try AppInstallation.stage(source: incoming, destination: first, verify: mockIdentity)
try check(!files.fileExists(atPath: first.path), "Staging must not change the target")
try check(try payload(firstPlan.staging) == "new", "Staged app copies the payload")
let firstBackup = try AppInstallation.commit(firstPlan, verify: mockIdentity)
try check(firstBackup == nil && (try payload(first)) == "new", "First install commits without a backup")
try check(try payload(incoming) == "new", "The source app remains intact")

let update = try fixture("update/Baker.app")
let updatePlan = try AppInstallation.stage(source: incoming, destination: update, verify: mockIdentity)
let backup = try AppInstallation.commit(updatePlan, verify: mockIdentity)!
try check(try payload(update) == "new" && payload(backup) == "original", "Update retains the complete previous app")
try check(!files.fileExists(atPath: updatePlan.staging.path), "Committed staging no longer remains")

let newer = try fixture("newer/Baker.app", version: "1.10.0")
try rejects("Downgrade must be refused") { _ = try AppInstallation.stage(source: incoming, destination: newer, verify: mockIdentity) }
try check(try payload(newer) == "original", "Downgrade refusal preserves the installed app")
let foreign = try fixture("foreign/Baker.app", team: "another-team")
try rejects("A different signer must be refused") { _ = try AppInstallation.stage(source: incoming, destination: foreign, verify: mockIdentity) }
try check(try payload(foreign) == "original", "A different signer's files remain intact")

let changed = try fixture("changed/Baker.app")
let changedPlan = try AppInstallation.stage(source: incoming, destination: changed, verify: mockIdentity)
try Data("changed during staging".utf8).write(to: changed.appendingPathComponent("payload"))
try rejects("A concurrent update must be refused") { _ = try AppInstallation.commit(changedPlan, verify: mockIdentity) }
try check(try payload(changed) == "changed during staging", "Concurrent edits are preserved")

let corrupted = try destination("corrupted")
let corruptPlan = try AppInstallation.stage(source: incoming, destination: corrupted, verify: mockIdentity)
try Data("corrupted copy".utf8).write(to: corruptPlan.staging.appendingPathComponent("payload"))
try rejects("A changed staging app must be refused") { _ = try AppInstallation.commit(corruptPlan, verify: mockIdentity) }
try check(!files.fileExists(atPath: corrupted.path), "Corrupt staging never becomes the installed app")

let failedCopy = try destination("failed-copy")
try rejects("A mismatched copied signature must be refused") {
    _ = try AppInstallation.stage(source: incoming, destination: failedCopy) { url in
        let original = try mockIdentity(url)
        return url == incoming ? original : AppInstallIdentity(identifier: original.identifier, team: original.team,
            version: original.version, codeHash: Data("changed copy".utf8))
    }
}
try check(!files.fileExists(atPath: failedCopy.path), "Failed verification leaves no installed app")
try check(try files.contentsOfDirectory(atPath: failedCopy.deletingLastPathComponent().path).isEmpty,
    "Failed verification removes its own incomplete staging app")
try check(try payload(incoming) == "new", "Failed verification preserves the source")

let appeared = try destination("appeared")
let appearedPlan = try AppInstallation.stage(source: incoming, destination: appeared, verify: mockIdentity)
_ = try fixture("appeared/Baker.app", text: "another installation")
try rejects("A new target appearing during copy must be refused") { _ = try AppInstallation.commit(appearedPlan, verify: mockIdentity) }
try check(try payload(appeared) == "another installation", "Another installation is preserved")

let linked = try destination("linked")
try files.createSymbolicLink(at: linked, withDestinationURL: root.appendingPathComponent("missing.app"))
try rejects("Dangling destination links must be refused") { _ = try AppInstallation.stage(source: incoming, destination: linked, verify: mockIdentity) }
let sourceLink = root.appendingPathComponent("source-link.app")
try files.createSymbolicLink(at: sourceLink, withDestinationURL: incoming)
try rejects("Source links must be refused") { _ = try AppInstallation.stage(source: sourceLink, destination: first, verify: mockIdentity) }
try rejects("Installing over the source must be refused") { _ = try AppInstallation.stage(source: incoming, destination: incoming, verify: mockIdentity) }
try rejects("Unsigned apps must fail the real verifier") { _ = try AppInstallation.identity(incoming) }
try check(!AppInstallation.isReadOnlyApplication(URL(string: "https://example.invalid/Baker.app")!), "Remote URLs are not installers")
try check(!AppInstallation.isReadOnlyApplication(root), "Ordinary folders are not installers")

if CommandLine.arguments.count == 3 {
    let actual = try AppInstallation.identity(URL(fileURLWithPath: CommandLine.arguments[2]))
    try check(actual.identifier == "local.baker.app" && !actual.team.isEmpty && !actual.codeHash.isEmpty,
        "The real Security verifier accepts the supplied Developer ID app")
}
print("\(checks) app installation checks passed")
'''
script = output / "installation.swift"
script.write_text(source)
command = ["swift", str(script), str(output)]
if arguments.signed_app:
    command.append(str(arguments.signed_app.resolve()))
result = subprocess.run(command, text=True, capture_output=True, timeout=120)
(output / "checks.log").write_text(result.stdout + result.stderr)
print(result.stdout if result.returncode == 0 else result.stderr[-5000:])
raise SystemExit(result.returncode)
