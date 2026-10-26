var checks = 0
func check(_ value: Bool, _ message: String) { precondition(value, message); checks += 1 }
@MainActor func run() throws {
    var access = false, checksRead = 0, opened = 0, requests = 0
    let permission = ScreenRecordingPermission(check: { checksRead += 1; return access }, request: { requests += 1; return access }, open: { opened += 1; return true })
    check(!permission.allowed && checksRead == 1 && opened == 0, "Initialisation checks without requesting or opening permissions")
    access = true; permission.refresh()
    check(permission.allowed && checksRead == 2, "Refresh recognises access after returning from Settings")
    access = false; permission.refresh()
    check(!permission.allowed, "Revoked access is reflected")
    check(permission.openSettings() && opened == 1 && checksRead == 3, "Only explicit settings action opens Settings")
    permission.request()
    check(requests == 1 && !permission.allowed, "Denied explicit request leaves capture unavailable")
    access = true; permission.request()
    check(requests == 1 && permission.allowed, "Already granted access never triggers another permission request")
    let app = URL(fileURLWithPath: "/Applications/Baker ' $(example).app")
    let arguments = try AppReopen.arguments(application: app, processID: 12345)
    check(arguments.last == app.path && arguments[3] == "12345", "Reopen path and PID stay separate shell arguments")
    check(!arguments[1].contains(app.path), "Paths are never interpolated into shell code")
    let syntax = Process(); syntax.executableURL = URL(fileURLWithPath: "/bin/sh"); syntax.arguments = ["-n", "-c", arguments[1]]
    try syntax.run(); syntax.waitUntilExit()
    check(syntax.terminationStatus == 0, "Reopen script syntax is valid without running it")
    for (url, pid) in [(URL(string: "https://example.invalid/Baker.app")!, Int32(123)), (URL(fileURLWithPath: "/tmp/Tool"), Int32(123)), (app, Int32(1))] {
        do { _ = try AppReopen.arguments(application: url, processID: pid); fatalError("Invalid reopen target accepted") } catch { checks += 1 }
    }
    print("Passed \(checks) permission/reopen checks; no privacy settings or apps were changed")
}
Task { @MainActor in do { try run(); exit(0) } catch { print(error); exit(1) } }
RunLoop.main.run()
