import Foundation
import SwiftData

/// Errors raised while resolving or opening the shared App Group store.
public enum SharedStoreError: Error, LocalizedError, Equatable {
    case groupContainerUnavailable(identifiers: [String])
    case supportDirectoryUnavailable(path: String, underlying: String)
    case containerInitializationFailed(message: String)

    public var errorDescription: String? {
        switch self {
        case .groupContainerUnavailable(let identifiers):
            return "None of the App Group containers [\(identifiers.joined(separator: ", "))] is writable by this process. The build is not authorized for the shared container; refusing to fall back to a private store."
        case .supportDirectoryUnavailable(let path, let underlying):
            return "Could not create the shared support directory at \(path): \(underlying)"
        case .containerInitializationFailed(let message):
            return "Could not open the shared SwiftData container: \(message)"
        }
    }
}

/// The App Group container this process actually resolved.
public struct GroupContainerResolution: Sendable, Equatable {
    public var identifier: String
    public var url: URL

    public init(identifier: String, url: URL) {
        self.identifier = identifier
        self.url = url
    }
}

/// Central place that resolves the App Group store so that the main app and the
/// helper always agree on exactly one database file.
public enum SharedStore {
    public static var schema: Schema {
        Schema([TrackedApp.self, PriceRecord.self, CheckRunLog.self])
    }

    // MARK: - Container resolution

    /// `FileManager` container lookup for one identifier. May return a URL that
    /// the process is not actually allowed to use (TCC can refuse later), which
    /// is why callers should use `resolveWritableGroupContainer`.
    public static func groupContainerURL(for identifier: String, fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// Well-known unsandboxed path for one identifier (used by appdropctl).
    public static func unsandboxedGroupContainerURL(for identifier: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers", isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
    }

    /// Verifies with a real write that this process may use the container.
    /// `containerURL(forSecurityApplicationGroupIdentifier:)` can report a path
    /// for a container that TCC then refuses to let the process touch, so a
    /// probe is the only reliable check.
    public static func isContainerWritable(_ url: URL, fileManager: FileManager = .default) -> Bool {
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        let probe = url.appendingPathComponent(".appdrop-write-probe-\(UUID().uuidString)")
        do {
            try Data("probe".utf8).write(to: probe, options: .atomic)
            try? fileManager.removeItem(at: probe)
            return true
        } catch {
            return false
        }
    }

    /// First candidate container (spec identifier first, then the team-prefixed
    /// variant) that this process can actually write to.
    public static func resolveWritableGroupContainer(fileManager: FileManager = .default) -> GroupContainerResolution? {
        for identifier in SharedConstants.candidateAppGroupIdentifiers {
            guard let url = groupContainerURL(for: identifier, fileManager: fileManager) else { continue }
            if isContainerWritable(url, fileManager: fileManager) {
                return GroupContainerResolution(identifier: identifier, url: url)
            }
        }
        return nil
    }

    /// Resolution cached for the lifetime of the process (diagnostics/UI).
    public static let resolvedGroupContainer: GroupContainerResolution? = resolveWritableGroupContainer()

    // MARK: - Store location

    /// Resolves (and optionally creates) the shared support directory that holds
    /// the store, the refresh lock and the helper log.
    public static func supportDirectoryURL(
        allowUnsandboxedFallback: Bool = false,
        create: Bool = true,
        fileManager: FileManager = .default
    ) throws -> URL {
        let groupURL: URL
        if let resolution = resolveWritableGroupContainer(fileManager: fileManager) {
            groupURL = resolution.url
        } else if allowUnsandboxedFallback {
            guard let fallback = unsandboxedFallbackGroupContainer(fileManager: fileManager) else {
                throw SharedStoreError.groupContainerUnavailable(identifiers: SharedConstants.candidateAppGroupIdentifiers)
            }
            groupURL = fallback
        } else {
            throw SharedStoreError.groupContainerUnavailable(identifiers: SharedConstants.candidateAppGroupIdentifiers)
        }

        let support = groupURL.appendingPathComponent(SharedConstants.containerSupportDirectoryName, isDirectory: true)
        if create {
            do {
                try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
            } catch {
                throw SharedStoreError.supportDirectoryUnavailable(path: support.path, underlying: error.localizedDescription)
            }
        }
        return support
    }

    /// Unsandboxed fallback: prefer an existing writable candidate container,
    /// otherwise an existing one, otherwise the specification's identifier.
    private static func unsandboxedFallbackGroupContainer(fileManager: FileManager) -> URL? {
        var existing: URL?
        for identifier in SharedConstants.candidateAppGroupIdentifiers {
            let url = unsandboxedGroupContainerURL(for: identifier)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            if existing == nil { existing = url }
            if isContainerWritable(url, fileManager: fileManager) {
                return url
            }
        }
        if let existing { return existing }
        // Nothing exists yet: use the specification's identifier.
        let requested = unsandboxedGroupContainerURL(for: SharedConstants.appGroupIdentifier)
        try? fileManager.createDirectory(at: requested, withIntermediateDirectories: true)
        return fileManager.fileExists(atPath: requested.path) ? requested : nil
    }

    /// URL of the shared SwiftData store file.
    public static func storeURL(
        allowUnsandboxedFallback: Bool = false,
        createDirectory: Bool = true,
        fileManager: FileManager = .default
    ) throws -> URL {
        try supportDirectoryURL(allowUnsandboxedFallback: allowUnsandboxedFallback, create: createDirectory, fileManager: fileManager)
            .appendingPathComponent(SharedConstants.storeFileName, isDirectory: false)
    }

    // MARK: - Container

    /// Opens the shared store. Fails loudly when no shared container is
    /// available; never silently creates a second private database.
    public static func makeContainer(allowUnsandboxedFallback: Bool = false) throws -> ModelContainer {
        let url = try storeURL(allowUnsandboxedFallback: allowUnsandboxedFallback)
        do {
            let configuration = ModelConfiguration(
                "AppDrop",
                schema: schema,
                url: url,
                allowsSave: true,
                cloudKitDatabase: .none
            )
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            throw SharedStoreError.containerInitializationFailed(message: error.localizedDescription)
        }
    }

    /// In-memory container used by unit tests and previews.
    public static func makeInMemoryContainer(allowsSave: Bool = true) throws -> ModelContainer {
        do {
            let configuration = ModelConfiguration(
                "AppDropMemory",
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: allowsSave,
                cloudKitDatabase: .none
            )
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            throw SharedStoreError.containerInitializationFailed(message: error.localizedDescription)
        }
    }
}

