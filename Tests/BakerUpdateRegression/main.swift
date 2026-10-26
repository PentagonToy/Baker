@MainActor
func runUpdateChecks() async throws {
    var checks = 0
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }; checks += 1
    }
    func fixture(_ tag: String, draft: Bool = false, prerelease: Bool = false, url: String? = nil, asset: Bool = true) -> [String: Any] {
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return ["tag_name": tag, "body": "Release notes", "draft": draft, "prerelease": prerelease,
                "assets": asset ? [["name": "Baker-\(version)-arm64.dmg", "state": "uploaded",
                                    "browser_download_url": url ?? "https://github.com/PentagonToy/Baker/releases/download/\(tag)/Baker-\(version)-arm64.dmg"]] : []]
    }
    func bytes(_ values: [[String: Any]]) throws -> Data { try JSONSerialization.data(withJSONObject: values) }
    let current = AppVersion("0.0.2")!
    expect(AppVersion("v0.0.2") == current, "v-prefix")
    expect(AppVersion("0.0.10")! > AppVersion("0.0.9")!, "numeric comparison")
    expect(AppVersion("1.0.0")! > AppVersion("0.99.99")!, "major comparison")
    for invalid in ["", "0.3", "0.0.3-beta", "pdf-engine-v1.0.0", "01.0.0", "-1.0.0", "１.0.0", "9999999999.0.0"] {
        expect(AppVersion(invalid) == nil, "invalid version: \(invalid)")
    }
    let input = try bytes([fixture("pdf-engine-v1.0.0"), fixture("v0.0.2"), fixture("v0.0.3", prerelease: true),
                           fixture("v0.0.5", draft: true), fixture("v0.0.4", url: "https://example.com/unsafe.dmg"),
                           fixture("v0.0.6", asset: false), fixture("v0.0.10"), fixture("v0.0.9")])
    let candidate = try AppRelease.newest(in: input, after: current)
    expect(candidate?.version.description == "0.0.10", "highest valid stable app release")
    expect(candidate?.notes == "Release notes", "notes retained")
    let equal = try AppRelease.newest(in: bytes([fixture("v0.0.2"), fixture("v0.0.1")]), after: current)
    expect(equal == nil, "equal and older versions ignored")
    do { _ = try AppRelease.newest(in: Data(repeating: 0, count: 524_289), after: current); fatalError("size cap") } catch { checks += 1 }
    do { _ = try AppRelease.newest(in: Data("broken".utf8), after: current); fatalError("malformed JSON") } catch { checks += 1 }
    let suite = "BakerUpdateTests-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var time = Date(timeIntervalSince1970: 1_000_000)
    var calls = 0
    let update = AppUpdates(defaults: defaults, version: "0.0.2", now: { time }, fetch: { calls += 1; return input })
    func settle(_ update: AppUpdates) async throws {
        for _ in 0..<100 { if !update.checking { return }; try await Task.sleep(nanoseconds: 2_000_000) }
        fatalError("check did not settle")
    }
    update.start()
    expect(!update.automatic && calls == 0, "default makes no network request")
    update.checkIfDue(); expect(calls == 0, "disabled due check")
    update.check(); update.check(); try await settle(update)
    expect(calls == 1, "coalesces checks")
    expect(update.available?.version.description == "0.0.10" && update.offerID == 1, "manual offer")
    expect(update.lastChecked == time, "successful timestamp")
    update.setAutomatic(true); expect(calls == 1, "daily holdoff persists")
    time += 86_401; update.checkIfDue(); try await settle(update)
    expect(calls == 2 && update.offerID == 1, "automatic result has no modal offer")
    update.setAutomatic(false); time += 86_401; update.checkIfDue()
    expect(calls == 2 && !defaults.bool(forKey: "automaticUpdates"), "opt out persists")
    update.stop()
    let offline = AppUpdates(defaults: defaults, version: "0.0.2", now: { time }, fetch: { throw URLError(.notConnectedToInternet) })
    offline.check(); try await settle(offline)
    expect(offline.message?.contains("Couldn’t") == true, "manual offline guidance")
    offline.setAutomatic(true); time += 86_401; offline.checkIfDue(); try await settle(offline)
    expect(offline.message == nil && !offline.checking, "automatic failures stay quiet")
    let attempt = defaults.double(forKey: "updateLastAttempt")
    offline.checkIfDue(); expect(defaults.double(forKey: "updateLastAttempt") == attempt, "failure retry throttled")
    offline.stop()
    let slow = AppUpdates(defaults: defaults, version: "0.0.2", fetch: { try? await Task.sleep(nanoseconds: 20_000_000); return input })
    slow.check(); await Task.yield(); slow.stop(); try await Task.sleep(nanoseconds: 30_000_000)
    expect(slow.available == nil && !slow.checking, "late completion after cancellation ignored")
    let development = AppUpdates(defaults: defaults, version: "Development", fetch: { fatalError("invalid version must not fetch") })
    development.check(); expect(development.message != nil && !development.checking, "unversioned app stays offline")
    print("Passed \(checks) update checks; no browser, app or real preferences changed")
}
Task { @MainActor in
    do { try await runUpdateChecks(); exit(0) }
    catch { print(error); exit(1) }
}
RunLoop.main.run()
