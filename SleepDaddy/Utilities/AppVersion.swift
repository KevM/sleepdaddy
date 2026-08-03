import Foundation

/// The version Settings shows, read from the bundle instead of hardcoded so it can't drift
/// away from what CI actually shipped.
public struct AppVersion {
    /// "1.0.14", from `MARKETING_VERSION`.
    public static func version(bundle: Bundle = .main) -> String {
        normalizedVersion(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
    }

    /// A build setting that expands to nothing leaves an empty string behind rather than a
    /// missing key, so blank is treated the same as absent.
    static func normalizedVersion(_ raw: String?) -> String {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else {
            return "Unknown"
        }
        return trimmed
    }
}
