import Foundation

/// Only stable app releases with an exact, first-party DMG are update candidates.
public struct AppVersion: Comparable, Equatable, Sendable {
    public let description: String
    private let components: [Int]
    public init?(_ text: String) {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.count <= 8 && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              parts.allSatisfy({ $0.count == 1 || !$0.hasPrefix("0") }) else { return nil }
        components = parts.compactMap { Int($0) }
        guard components.count == 3 else { return nil }
        description = value
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.components.lexicographicallyPrecedes(rhs.components) }
}

public struct AppRelease: Equatable, Sendable {
    public let version: AppVersion
    public let notes: String
    public let download: URL
    public let page: URL

    public static func newest(in data: Data, after current: AppVersion) throws -> Self? {
        struct Asset: Decodable { let name: String; let browser_download_url: String; let state: String }
        struct Release: Decodable {
            let tag_name: String; let body: String?; let draft: Bool; let prerelease: Bool; let assets: [Asset]
        }
        guard data.count <= 524_288 else { throw URLError(.dataLengthExceedsMaximum) }
        return try JSONDecoder().decode([Release].self, from: data).compactMap { release -> Self? in
            guard !release.draft, !release.prerelease, release.tag_name.hasPrefix("v"),
                  let version = AppVersion(release.tag_name), version > current else { return nil }
            let address = "https://github.com/PentagonToy/Baker/releases/download/v\(version.description)/Baker-\(version.description)-arm64.dmg"
            guard release.assets.contains(where: { $0.state == "uploaded" && $0.name == "Baker-\(version.description)-arm64.dmg" && $0.browser_download_url == address }),
                  let download = URL(string: address), let page = URL(string: "https://github.com/PentagonToy/Baker/releases/tag/v\(version.description)") else { return nil }
            return Self(version: version, notes: String((release.body ?? "").prefix(12_000)), download: download, page: page)
        }.max(by: { $0.version < $1.version })
    }
}
