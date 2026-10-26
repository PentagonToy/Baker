import Foundation

/// Zero means no user-selected limit; archive safety caps are separate.
public struct CaptureRetentionPolicy: Equatable, Sendable {
    public let count: Int
    public let days: Int
    public init(count: Int = 0, days: Int = 0) { self.count = max(0, count); self.days = max(0, days) }
    public func expired(in records: [CaptureRecord], now: Date = Date()) -> [CaptureRecord] {
        let sorted = records.sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString > $1.id.uuidString : $0.createdAt > $1.createdAt }
        let cutoff = now.addingTimeInterval(-Double(days) * 86400)
        return sorted.enumerated().compactMap { index, record in
            (count > 0 && index >= count) || (days > 0 && record.createdAt < cutoff) ? record : nil
        }
    }
}
public struct CaptureRemovalCandidate: Sendable {
    public let record: CaptureRecord
    public let bytes: Int
    public let modified: Date?
    public init(record: CaptureRecord, bytes: Int, modified: Date?) { self.record = record; self.bytes = bytes; self.modified = modified }
}
