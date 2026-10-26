import Foundation

Task { @MainActor in
    let name = "local.baker.test.usage." + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let previous: [String: Any] = ["localImages": 3, "localDocuments": 2, "localPages": 5,
        "onlineImages": 99, "onlineDocuments": 9, "onlinePages": 100, "since": 12345.0]
    defaults.set(try! JSONSerialization.data(withJSONObject: previous), forKey: PreferenceKeys.recognitionUsage.name)
    let usage = LocalUsage(defaults: defaults)
    precondition(usage.counts.localImages == 3 && usage.counts.localDocuments == 2 && usage.counts.localPages == 5)
    precondition(usage.counts.since.timeIntervalSinceReferenceDate == 12345)
    let persisted = try! JSONSerialization.jsonObject(with: defaults.data(forKey: PreferenceKeys.recognitionUsage.name)!) as! [String: Any]
    precondition(persisted["onlineImages"] == nil && persisted["onlineDocuments"] == nil && persisted["onlinePages"] == nil)
    usage.record()
    precondition(usage.counts.localImages == 4)
    usage.record(pages: 3)
    precondition(usage.counts.localDocuments == 3 && usage.counts.localPages == 8)
    let restored = LocalUsage(defaults: defaults)
    precondition(restored.counts.localImages == 4 && restored.counts.localPages == 8)
    usage.reset()
    precondition(usage.counts.localImages == 0 && usage.counts.localDocuments == 0 && usage.counts.localPages == 0)
    precondition(abs(usage.counts.since.timeIntervalSinceNow) < 5)
    print("8 local-usage migration and reset checks passed")
    exit(0)
}
dispatchMain()
