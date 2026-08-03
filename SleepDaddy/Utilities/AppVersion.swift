import Foundation

/// The version and build Settings shows, read from the bundle instead of hardcoded so they
/// can't drift away from what CI actually shipped.
public struct AppVersion {
    /// "1.0.14", from `MARKETING_VERSION`.
    public static func version(bundle: Bundle = .main) -> String {
        normalizedVersion(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
    }

    /// "14", from `CURRENT_PROJECT_VERSION`, or `nil` when the bundle carries no build number.
    ///
    /// Worth showing on its own row: the marketing version only moves on a release, while the
    /// bump-build workflow raises this on every merge, so it is the number that identifies
    /// which TestFlight build a bug report came from.
    public static func build(bundle: Bundle = .main) -> String? {
        normalizedBuild(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
    }

    /// A build setting that expands to nothing leaves an empty string behind, not a missing
    /// key, so blank is treated the same as absent in both of these.
    static func normalizedVersion(_ raw: String?) -> String {
        nonEmpty(raw) ?? "Unknown"
    }

    /// `nil` hides the Build row rather than printing a placeholder next to a label that would
    /// then explain nothing.
    static func normalizedBuild(_ raw: String?) -> String? {
        nonEmpty(raw)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
