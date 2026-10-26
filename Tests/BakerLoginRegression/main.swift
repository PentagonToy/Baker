import Foundation

Task { @MainActor in
    let name = "Baker-Login-Test-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    var checks = 0, failures = 0
    func check(_ value: Bool, _ label: String) {
        checks += 1
        if !value { failures += 1; print("FAIL",label) }
    }
    var systemStatus: SMAppService.Status = .notRegistered
    var registrations = 0, removals = 0, questions = 0
    var reject = false
    @MainActor func fresh() -> LaunchAtLogin {
        defaults.removePersistentDomain(forName: name)
        systemStatus = .notRegistered; registrations = 0; removals = 0; questions = 0; reject = false
        return LaunchAtLogin(defaults: defaults, available: true, status: { systemStatus }, register: {
            registrations += 1
            if reject { throw NSError(domain: "Test", code: 1) }
            systemStatus = .enabled
        }, unregister: {
            removals += 1
            if reject { throw NSError(domain: "Test", code: 2) }
            systemStatus = .notRegistered
        })
    }
    var controller = fresh()
    check(!controller.enabled,"Default off")
    check(controller.offerIfNeeded { questions += 1; return false },"Initial question")
    check(questions == 1 && registrations == 0,"Not Now does not register")
    check(!controller.offerIfNeeded { questions += 1; return true },"Offer not repeated")
    check(questions == 1,"No repeated question")
    controller = LaunchAtLogin(defaults: defaults, available: true, status: { systemStatus }, register: { registrations += 1 }, unregister: {})
    check(!controller.offerIfNeeded { true },"Not Now persists across controller recreation")
    controller = fresh()
    controller.offerIfNeeded { true }
    check(controller.enabled && registrations == 1,"Opt-in registers")
    controller.setEnabled(true)
    check(registrations == 1,"Enabled registration not duplicated")
    controller.setEnabled(false)
    check(!controller.enabled && removals == 1,"Disable unregisters")
    controller.setEnabled(false)
    check(removals == 1,"Off registration not removed twice")
    controller = fresh()
    controller = LaunchAtLogin(defaults: defaults, available: true, status: { systemStatus }, register: { systemStatus = .requiresApproval }, unregister: { systemStatus = .notRegistered })
    controller.offerIfNeeded { true }
    check(controller.needsApproval && !controller.enabled, "New registration reports pending approval")
    systemStatus = .enabled; controller.refresh()
    check(controller.enabled && !controller.needsApproval, "System approval refreshes enabled state")
    controller = fresh(); systemStatus = .enabled
    check(!controller.offerIfNeeded { questions += 1; return false },"Already registered skips question")
    check(questions == 0 && registrations == 0,"Existing login item not modified")
    systemStatus = .notRegistered; controller.refresh()
    check(!controller.enabled,"External system change refreshes")
    check(!controller.offerIfNeeded { true },"System removal does not re-offer")
    controller = fresh(); systemStatus = .requiresApproval; controller.refresh()
    check(controller.needsApproval && !controller.enabled,"Approval distinct from enabled")
    check(!controller.offerIfNeeded { true },"Pending approval skips repeat offer")
    controller.setEnabled(true)
    check(registrations == 0,"Pending registration not duplicated")
    controller.setEnabled(false)
    check(systemStatus == .notRegistered && removals == 1,"Pending registration can be removed")
    controller = fresh(); reject = true
    controller.offerIfNeeded { true }
    check(!controller.enabled && controller.errorMessage != nil,"Failed enable retains actual state and reports error")
    check(!controller.offerIfNeeded { true },"Failed opt-in does not nag")
    reject = false; controller.setEnabled(true)
    check(controller.enabled && controller.errorMessage == nil,"Manual retry clears error")
    reject = true; controller.setEnabled(false)
    check(controller.enabled && controller.errorMessage != nil,"Failed removal retains enabled state")
    controller = fresh(); controller.setEnabled(false)
    check(!controller.offerIfNeeded { true },"Manual setting suppresses launch offer")
    controller = fresh(); systemStatus = .notFound; controller.refresh()
    check(!controller.enabled && controller.description.contains("Applications"),"Unavailable status explains recovery")
    controller = LaunchAtLogin(defaults: defaults, available: false, status: { systemStatus }, register: { registrations += 1 }, unregister: {})
    check(!controller.offerIfNeeded { true },"Unbundled execution has no offer")
    controller.setEnabled(true)
    check(registrations == 0,"Unbundled execution does not register")
    print("RESULT", checks, "checks", failures, "failures")
    exit(failures == 0 ? 0 : 1)
}
RunLoop.main.run()
