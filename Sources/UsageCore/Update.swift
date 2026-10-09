import Foundation

public struct UpdateCheckError: Error, Equatable, Sendable {
    public let message: String
    public init(message: String) { self.message = message }
}

/// The version in GitHub's `releases/latest` JSON (tag `v1.0.2` → `1.0.2`) when it is newer than `current`, nil when
/// `current` is the latest; a body without a tag (rate limit, no release) fails with GitHub's message when it has one.
public func newerRelease(_ json: Data, than current: String) -> Result<String?, UpdateCheckError> {
    struct Release: Decodable { let tag_name: String?; let message: String? }
    let release = try? JSONDecoder().decode(Release.self, from: json)
    guard let tag = release?.tag_name else { return .failure(UpdateCheckError(message: release?.message ?? "No release found")) }
    let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    return .success(version.compare(current, options: .numeric) == .orderedDescending ? version : nil)
}
