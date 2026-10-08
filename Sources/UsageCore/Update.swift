import Foundation

/// The version in GitHub's `releases/latest` JSON (tag `v1.0.2` → `1.0.2`) when it is newer than `current`; else nil.
public func newerRelease(_ json: Data, than current: String) -> String? {
    struct Release: Decodable { let tag_name: String }
    guard let tag = try? JSONDecoder().decode(Release.self, from: json).tag_name else { return nil }
    let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    return version.compare(current, options: .numeric) == .orderedDescending ? version : nil
}
