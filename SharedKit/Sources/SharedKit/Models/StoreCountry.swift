import Foundation

/// Helpers for App Store storefront country codes.
public enum StoreCountry {
    /// Normalizes user input into the canonical lowercase two-letter code.
    public static func normalized(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// English display name (used in notifications and diagnostics).
    public static func displayName(for code: String) -> String {
        switch normalized(code) {
        case "us": return "United States"
        case "hk": return "Hong Kong"
        case "jp": return "Japan"
        case "cn": return "China mainland"
        default: return normalized(code).uppercased()
        }
    }

    /// Uppercased code for display.
    public static func displayCode(for code: String) -> String {
        normalized(code).uppercased()
    }
}

