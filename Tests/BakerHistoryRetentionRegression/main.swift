import AppKit
import Foundation

@MainActor func run() async throws {
    var checks = 0
    func check(_ value: Bool, _ label: String) { precondition(value, label); checks += 1 }
    let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("fixtures-\(UUID())")
    let directory = root.appendingPathComponent("captures"), trash = root.appendingPathComponent("trash")
    let files = FileManager.default
    try files.createDirectory(at: trash, withIntermediateDirectories: true)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let records = (0..<5).map { i in CaptureRecord(id: UUID(), createdAt: now.addingTimeInterval(-Double(i)*86400), fileName: "", pixelWidth: 1, pixelHeight: 1) }
    check(CaptureRetentionPolicy().expired(in: records, now: now).isEmpty, "Default has no image limits")
    check(CaptureRetentionPolicy(count: 2).expired(in: records, now: now).count == 3, "Count retention")
    check(CaptureRetentionPolicy(days: 2).expired(in: records, now: now).count == 2, "Age retention preserves cutoff boundary")
    check(CaptureRetentionPolicy(count: 4, days: 2).expired(in: records, now: now).count == 2, "Either limit can expire an image")
    check(CaptureRetentionPolicy(count: -1, days: -1).expired(in: records, now: now).isEmpty, "Invalid negative values do not delete images")
    let library = CaptureLibrary(directory: directory), store = library.store
    let cg = CGContext(data:nil,width:24,height:12,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!.makeImage()!
    var saved: [StoredCapture] = []
    for _ in 0..<5 { saved.append(try await store.add(image: cg)) }
    // Serial removal must not race an earlier save or remove the capture itself.
    let originals = try saved.map { try Data(contentsOf: directory.appendingPathComponent($0.record.fileName)) }
    func metadata(_ index: Int) -> SavedFormula {
        SavedFormula(id: saved[index].record.id, originalLatex: "x", latex: "x+\(index)", unicodeOverride:nil,
            model:"fixture", confidenceMethod:nil, confidence:nil, diagnostics:nil, format:"LaTeX", style:"")
    }
    for index in 0..<3 { _ = library.enqueue(.save(metadata(index), limit: 50, days: 0)) }
    let removed = try await library.enqueue(.remove([saved[0].record.id, saved[1].record.id])).value
    check(removed.count == 1 && removed[saved[2].record.id] != nil, "Batch deletion follows queued saves and preserves unselected formula")
    check(try await store.records().count == 5, "Formula deletion retains all capture records")
    for index in 0..<5 {
        check(try Data(contentsOf: directory.appendingPathComponent(saved[index].record.fileName)) == originals[index], "Formula deletion preserves capture bytes")
    }
    let reopenedFormulas = try FormulaArchive(directory: directory)
    check(reopenedFormulas.formulas == removed, "Formula removal survives reopening")
    let emptyRemoval = try await library.enqueue(.remove([])).value
    check(emptyRemoval == removed, "Empty selection is a no-op")
    let singleRemoval = try await library.enqueue(.remove([saved[2].record.id])).value
    check(singleRemoval.isEmpty, "Individual deletion removes only selected metadata")
    let deleted = saved[0].record
    let formula = SavedFormula(id: deleted.id, originalLatex: "x", latex: "x", unicodeOverride:nil, model:"fixture", confidenceMethod:nil, confidence:nil, diagnostics:nil, format:"LaTeX", style:"")
    try await store.saveFormula(formula)
    _ = try await library.thumbnail(deleted, protecting: [])
    check(library.cachedThumbnail(deleted.id) != nil, "Cached fixture present")
    try files.removeItem(at: directory.appendingPathComponent(deleted.fileName))
    let kept = try await store.reconcileHistory()
    library.clearCache()
    check(kept.count == 4 && !kept.contains(deleted), "Finder deletion removed from history")
    check(try await store.savedFormulas().isEmpty, "Missing image's formula metadata removed")
    check(library.cachedThumbnail(deleted.id) == nil, "Cache clear drops missing image preview")
    check(try CaptureArchive(directory:directory).records.count == 4, "Pruning survives reopening")
    do { _ = try await library.thumbnail(deleted, protecting: []); fatalError("Deleted file decoded") } catch { checks += 1 }
    let candidates = try await store.retentionCandidates(.init(count: 2))
    check(candidates.count == 2 && candidates.allSatisfy { $0.bytes > 0 }, "Review has exact image count and bytes")
    let video = directory.appendingPathComponent("leave-video.mp4")
    try Data("video fixture".utf8).write(to: video)
    let gif = directory.appendingPathComponent("leave-animation.gif")
    try Data("gif fixture".utf8).write(to: gif)
    let untouched = directory.appendingPathComponent("unrelated.png")
    try Data("unindexed".utf8).write(to: untouched)
    try await store.trashCaptures(candidates) { url in try files.moveItem(at: url, to: trash.appendingPathComponent(url.lastPathComponent)) }
    check(try await store.records().count == 2, "Reviewed images removed from index")
    check(try files.contentsOfDirectory(atPath:trash.path).count == 2, "Images moved, never permanently deleted")
    check(files.fileExists(atPath:video.path) && files.fileExists(atPath:gif.path) && files.fileExists(atPath:untouched.path), "Recordings and unrelated files untouched")
    let remaining = try await store.records()
    let review = try await store.retentionCandidates(.init(count: 1))
    let changed = directory.appendingPathComponent(review[0].record.fileName)
    let original = try Data(contentsOf: changed)
    try (original + Data([0])).write(to: changed)
    var moved = false
    do { try await store.trashCaptures(review) { _ in moved = true }; fatalError("Stale review accepted") }
    catch let e as BakerError { check(e.code == .storageConflict && !moved, "Changed file aborts before moving anything") }
    try original.write(to: changed)
    // A partial Trash failure commits only files actually moved; the remaining source survives.
    let all = try remaining.map { record -> CaptureRemovalCandidate in
        let v = try directory.appendingPathComponent(record.fileName).resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey])
        return .init(record:record,bytes:v.fileSize!,modified:v.contentModificationDate)
    }
    var attempted = 0
    do {
        try await store.trashCaptures(all) { url in
            attempted += 1
            if attempted == 2 { throw BakerError(message:"fixture Trash failure",code:.storageFailed) }
            try files.moveItem(at:url,to:trash.appendingPathComponent(url.lastPathComponent))
        }
        fatalError("Partial failure ignored")
    } catch { checks += 1 }
    check(try await store.reconcileHistory().count == 1, "Partial failure leaves accurate history")
    let archive = try CaptureArchive(directory:directory)
    let movedDirectory = root.appendingPathComponent("disconnected")
    try files.moveItem(at:directory,to:movedDirectory)
    do { _ = try archive.reconcile(); fatalError("Unavailable directory treated as deleted content") } catch { checks += 1 }
    check(!files.fileExists(atPath:directory.path), "Refresh does not recreate unavailable folder")
    let ageing = CaptureStore(directory: root.appendingPathComponent("formula-age"))
    var ageIDs: [UUID] = []
    for days in [89, 90, 91] {
        let record = try await ageing.add(image: cg).record
        ageIDs.append(record.id)
        try await ageing.saveFormula(SavedFormula(id: record.id, originalLatex: "x", latex: "x", unicodeOverride: nil,
            model: "fixture", confidenceMethod: nil, confidence: nil, diagnostics: nil, format: "LaTeX", style: "",
            savedAt: now.addingTimeInterval(-Double(days) * 86400)))
    }
    let retained = try await ageing.maintainFormulas(limit: 50, days: 90, now: now)
    check(retained[ageIDs[0]] != nil && retained[ageIDs[1]] != nil, "90-day retention includes the cutoff boundary")
    check(retained[ageIDs[2]] == nil, "90-day retention removes older formula metadata")
    check(try await ageing.records().count == 3, "90-day formula expiry preserves capture images")
    print("History retention:", checks, "checks passed")
}
Task { @MainActor in do { try await run();exit(0) } catch { print(error);exit(1) } }
dispatchMain()
