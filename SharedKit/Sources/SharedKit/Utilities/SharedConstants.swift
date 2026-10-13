import Foundation

/// Constants shared by the main app and the background helper.
public enum SharedConstants {
    /// App Group identifier used by both processes for the shared SwiftData store.
    ///
    /// Platform note: on recent macOS the Group Containers directory is
    /// TCC-protected, and containermanagerd checks whether the requesting
    /// process may use the container ("Requestor's signature does not allow it
    /// to access a TCC-protected group container"). With a personal-team
    /// signature this requires the user to grant the app full disk access on
    /// that machine; with a paid developer account and a provisioning profile
    /// that carries the App Groups capability no extra grant is needed.
    /// `SharedStore` still verifies the container with a real write probe.
    public static let appGroupIdentifier = "group.com.appdrop.shared"

    /// Candidate App Group identifiers in resolution order. Kept as a list so
    /// that additional identifiers can be added for experiments/migrations.
    public static var candidateAppGroupIdentifiers: [String] {
        [appGroupIdentifier]
    }
    /// Directory (inside the App Group container) that holds the store and support files.
    public static let containerSupportDirectoryName = "AppDrop"
    /// SwiftData store file name inside the support directory.
    public static let storeFileName = "AppDrop.store"
    /// Cross-process refresh lock file name inside the support directory.
    public static let refreshLockFileName = "refresh.lock"
    /// Helper diagnostic log file name inside the support directory.
    public static let helperLogFileName = "helper.log"

    /// Bundle identifier of the embedded helper app.
    public static let helperBundleIdentifier = "com.appdrop.helper"
    /// Name of the embedded launch agent property list.
    public static let helperAgentPlistName = "com.appdrop.helper.plist"
    /// Path (inside the main app bundle) of the helper app.
    public static let helperRelativePath = "Contents/Library/LoginItems/AppDropHelper.app"
    /// Path (inside the main app bundle) of the helper executable.
    public static let helperExecutableRelativePath = helperRelativePath + "/Contents/MacOS/AppDropHelper"

    /// Wishdrop document format identifier.
    public static let wishdropFormatIdentifier = "com.appdrop.wishdrop"
    /// Current supported Wishdrop document version.
    public static let wishdropFormatVersion = 1
    /// Uniform type identifier for `.wishdrop` documents.
    public static let wishdropTypeIdentifier = "com.appdrop.wishdrop"
    /// File extension for `.wishdrop` documents.
    public static let wishdropFileExtension = "wishdrop"

    /// Supported App Store storefront country codes (lowercase, ISO 3166-1 alpha-2).
    public static let supportedCountryCodes: [String] = ["us", "hk", "jp", "cn"]
    /// Default storefront for new tracked apps.
    public static let defaultCountryCode = "us"

    /// Maximum number of App Store identifiers per lookup request.
    public static let lookupBatchSize = 50
    /// Maximum number of concurrent App Store requests.
    public static let maximumConcurrentRequests = 3
    /// Number of retries after the initial attempt for transient failures.
    public static let transientRetryCount = 2

    /// Minimum interval (seconds) between two background check attempts.
    public static let backgroundMinimumInterval: TimeInterval = 20 * 60 * 60
    /// Target interval used in the launch agent property list (24 hours).
    public static let backgroundTargetInterval: TimeInterval = 24 * 60 * 60
    /// Maximum number of check-run log entries kept in the store.
    public static let checkRunLogLimit = 200

    /// Returns true when the given storefront code is supported.
    public static func isSupportedCountry(_ code: String) -> Bool {
        supportedCountryCodes.contains(code.lowercased())
    }
}

