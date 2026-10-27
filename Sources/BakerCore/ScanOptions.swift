import Foundation

/// Options that may change without selecting a new reader or sending input.
public struct ScanOptions: Codable, Equatable, Sendable {
    public var delay: Double?
    public var searchable: Bool?
    public init(delay: Double? = nil, searchable: Bool? = nil) { self.delay = delay; self.searchable = searchable }
    public func validate() throws {
        guard delay != nil || searchable != nil else { throw BakerError(message: "Set delay or searchable for the scan.", code: .invalidInput) }
        if let delay, !delay.isFinite || !(0.1...60).contains(delay) {
            throw BakerError(message: "Use a scan delay from 0.1 to 60 seconds.", code: .invalidInput)
        }
    }
    public static func decode(_ text: String) throws -> ScanOptions {
        let data = Data(text.utf8)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: ["delay", "searchable"]) else {
            throw BakerError(message: "Scan options accept delay and searchable only.", code: .invalidInput)
        }
        let value = try JSONDecoder().decode(Self.self, from: data); try value.validate(); return value
    }
}
