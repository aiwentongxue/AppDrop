import Foundation

/// App-side localization helper. UI strings live in `Localizable.xcstrings`;
/// notification strings live in the SharedKit bundle (`SharedText`).
enum AppStrings {
    static func string(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), arguments: arguments)
    }
}

