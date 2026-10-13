import Foundation
import SwiftData

/// Result of one refresh cycle. Codable so the helper can print it for scripts.
public struct RefreshSummary: Sendable, Equatable, Codable {
    public var source: CheckSource
    public var outcome: CheckRunOutcome
    public var startedAt: Date
    public var finishedAt: Date
    public var checkedCount: Int
    public var changedCount: Int
    public var failedCount: Int
    public var notifiedCount: Int
    public var message: String?

    public init(
        source: CheckSource,
        outcome: CheckRunOutcome,
        startedAt: Date,
        finishedAt: Date,
        checkedCount: Int,
        changedCount: Int,
        failedCount: Int,
        notifiedCount: Int,
        message: String? = nil
    ) {
        self.source = source
        self.outcome = outcome
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.checkedCount = checkedCount
        self.changedCount = changedCount
        self.failedCount = failedCount
        self.notifiedCount = notifiedCount
        self.message = message
    }
}

/// Result of replacing the storefront of a tracked app.
public enum RegionReplaceResult: Sendable, Equatable {
    case replaced(TrackedAppSnapshot)
    case unchanged
    case duplicate
    case failed(message: String)
}

/// The shared price-check pipeline used by the main app (manual refresh) and by
/// the background helper (scheduled runs). Serialized across processes with an
/// advisory file lock and idempotent notifications.
public final class RefreshEngine: @unchecked Sendable {
    private let store: AppDataStore
    private let fetcher: any AppStoreFetching
    private let notifier: any UserNotifying
    private let lock: FileLock?
    private let logURL: URL?
    private let now: @Sendable () -> Date

    public init(
        container: ModelContainer,
        fetcher: any AppStoreFetching,
        notifier: any UserNotifying,
        lockURL: URL? = nil,
        logURL: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = AppDataStore(modelContainer: container)
        self.fetcher = fetcher
        self.notifier = notifier
        self.lock = lockURL.map { FileLock(url: $0) }
        self.logURL = logURL
        self.now = now
    }

    /// Convenience factory that wires up the App Group lock file.
    public static func defaultLockURL() -> URL? {
        guard let support = try? SharedStore.supportDirectoryURL() else { return nil }
        return support.appendingPathComponent(SharedConstants.refreshLockFileName)
    }

    /// Convenience factory that wires up the helper log file.
    public static func defaultLogURL() -> URL? {
        guard let support = try? SharedStore.supportDirectoryURL() else { return nil }
        return support.appendingPathComponent(SharedConstants.helperLogFileName)
    }

    /// Should a scheduled background run happen?
    public static func isOverdue(
        lastAttempt: Date?,
        now: Date,
        minimumInterval: TimeInterval = SharedConstants.backgroundMinimumInterval
    ) -> Bool {
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= minimumInterval
    }

    // MARK: - Public entry points

    /// Refreshes all tracked apps.
    /// - Parameters:
    ///   - source: who triggered the cycle (recorded in the run log).
    ///   - mode: lock behaviour; the helper skips, the app may wait briefly.
    ///   - force: when false and the source is `.background`, the cycle is
    ///     skipped if the previous attempt is less than 20 hours old.
    public func run(
        source: CheckSource,
        mode: FileLockMode,
        force: Bool = true
    ) async -> RefreshSummary {
        let startedAt = now()
        var handle: FileLock.Handle?
        if let lock {
            do {
                handle = try lock.acquire(mode)
            } catch {
                let summary = RefreshSummary(
                    source: source,
                    outcome: .skipped,
                    startedAt: startedAt,
                    finishedAt: now(),
                    checkedCount: 0,
                    changedCount: 0,
                    failedCount: 0,
                    notifiedCount: 0,
                    message: "Skipped: another refresh is already running."
                )
                log("run skipped because the refresh lock is busy")
                return summary
            }
        }
        defer { handle?.release() }

        do {
            if source == .background, !force {
                let lastAttempt = try await store.latestAttemptDate()
                guard Self.isOverdue(lastAttempt: lastAttempt, now: startedAt) else {
                    let summary = RefreshSummary(
                        source: source,
                        outcome: .skipped,
                        startedAt: startedAt,
                        finishedAt: now(),
                        checkedCount: 0,
                        changedCount: 0,
                        failedCount: 0,
                        notifiedCount: 0,
                        message: "Skipped: the previous check is less than 20 hours old."
                    )
                    log("run skipped because of the minimum interval")
                    return summary
                }
            }

            let snapshots = try await store.allSnapshots()
            return await performCycle(snapshots: snapshots, source: source, startedAt: startedAt)
        } catch {
            let summary = RefreshSummary(
                source: source,
                outcome: .failed,
                startedAt: startedAt,
                finishedAt: now(),
                checkedCount: 0,
                changedCount: 0,
                failedCount: 0,
                notifiedCount: 0,
                message: error.localizedDescription
            )
            log("run failed: \(error.localizedDescription)")
            try? await store.recordRun(summary)
            return summary
        }
    }

    /// Refreshes a single tracked app (detail view "check now").
    public func refreshSingle(appID: UUID, source: CheckSource = .manual) async -> RefreshSummary {
        let startedAt = now()
        var handle: FileLock.Handle?
        if let lock {
            do {
                handle = try lock.acquire(.wait(timeout: 15))
            } catch {
                return RefreshSummary(
                    source: source,
                    outcome: .skipped,
                    startedAt: startedAt,
                    finishedAt: now(),
                    checkedCount: 0,
                    changedCount: 0,
                    failedCount: 0,
                    notifiedCount: 0,
                    message: "Skipped: another refresh is already running."
                )
            }
        }
        defer { handle?.release() }

        do {
            guard let snapshot = try await store.snapshot(appID: appID) else {
                return RefreshSummary(
                    source: source,
                    outcome: .failed,
                    startedAt: startedAt,
                    finishedAt: now(),
                    checkedCount: 0,
                    changedCount: 0,
                    failedCount: 0,
                    notifiedCount: 0,
                    message: "The tracked app no longer exists."
                )
            }
            return await performCycle(snapshots: [snapshot], source: source, startedAt: startedAt)
        } catch {
            return RefreshSummary(
                source: source,
                outcome: .failed,
                startedAt: startedAt,
                finishedAt: now(),
                checkedCount: 0,
                changedCount: 0,
                failedCount: 0,
                notifiedCount: 0,
                message: error.localizedDescription
            )
        }
    }

    /// Replaces the storefront of a tracked app: fetch first, then delete the
    /// old entry and create a fresh baseline in the new storefront.
    public func replaceRegion(appID: UUID, newCountryCode: String, source: CheckSource = .manual) async -> RegionReplaceResult {
        let country = StoreCountry.normalized(newCountryCode)
        guard SharedConstants.isSupportedCountry(country) else {
            return .failed(message: "Unsupported storefront \"\(newCountryCode)\".")
        }
        do {
            guard let current = try await store.snapshot(appID: appID) else {
                return .failed(message: "The tracked app no longer exists.")
            }
            if current.countryCode == country { return .unchanged }
            if try await store.contains(trackId: current.trackId, countryCode: country) {
                return .duplicate
            }

            let result: AppStoreApp?
            do {
                result = try await fetcher.lookupOne(appId: current.trackId, country: country)
            } catch {
                return .failed(message: error.localizedDescription)
            }
            guard let result, let price = result.price, let currency = result.currency,
                  let formatted = result.formattedPrice else {
                return .failed(message: "The app could not be found in the \(country.uppercased()) storefront.")
            }

            try await store.delete(appID: appID)
            let draft = NewTrackedAppDraft(
                trackId: current.trackId,
                countryCode: country,
                name: result.name,
                developerName: result.developerName,
                artworkURL: result.artworkURL,
                appStoreURL: result.appStoreURL,
                price: price,
                formattedPrice: formatted,
                currency: currency
            )
            let snapshot = try await store.insert(draft, now: now())
            log("storefront replaced for \(current.trackId): \(current.countryCode) -> \(country)")
            return .replaced(snapshot)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    // MARK: - Cycle implementation

    private func performCycle(
        snapshots: [TrackedAppSnapshot],
        source: CheckSource,
        startedAt: Date
    ) async -> RefreshSummary {
        guard !snapshots.isEmpty else {
            let summary = RefreshSummary(
                source: source,
                outcome: .success,
                startedAt: startedAt,
                finishedAt: now(),
                checkedCount: 0,
                changedCount: 0,
                failedCount: 0,
                notifiedCount: 0,
                message: "No tracked apps."
            )
            try? await store.recordRun(summary)
            return summary
        }

        var checkedCount = 0
        var changedCount = 0
        var failedCount = 0
        var failures: [String] = []
        var pendingNotifications: [PriceDropNotification] = []

        let byCountry = Dictionary(grouping: snapshots, by: \.countryCode)
        for (country, apps) in byCountry.sorted(by: { $0.key < $1.key }) {
            let outcome = await fetcher.lookup(appIds: apps.map(\.trackId), country: country)
            let byId = Dictionary(outcome.apps.map { ($0.trackId, $0) }, uniquingKeysWith: { first, _ in first })
            let failedIds = Set(outcome.failedIds)
            let failureMessage = outcome.failures.first?.message

            for app in apps {
                do {
                    if failedIds.contains(app.trackId) {
                        failedCount += 1
                        failures.append("\(app.name): \(failureMessage ?? "lookup failed")")
                        try await store.markAttempt(
                            appID: app.id,
                            status: .error,
                            error: failureMessage ?? "App Store lookup failed",
                            attemptedAt: now()
                        )
                        continue
                    }
                    let result = byId[app.trackId]
                    let evaluation = PriceEngine.evaluate(previous: app.price, result: result)
                    let applied = try await store.apply(evaluation, appID: app.id, metadata: result, now: now())
                    checkedCount += 1
                    switch evaluation {
                    case .decreased(_, let dropPercent, let isNewLow):
                        changedCount += 1
                        if let recordID = applied.appendedRecordID,
                           let formatted = applied.app.price.formattedPrice {
                            pendingNotifications.append(PriceDropNotification(
                                appName: applied.app.name,
                                trackId: applied.app.trackId,
                                countryCode: applied.app.countryCode,
                                formattedPrice: formatted,
                                currency: applied.app.price.currency ?? "",
                                dropPercent: dropPercent,
                                isNewLow: isNewLow,
                                recordID: recordID
                            ))
                        }
                    case .increased, .currencyChanged:
                        changedCount += 1
                    case .baseline, .unchanged, .unavailable:
                        break
                    }
                } catch {
                    failedCount += 1
                    failures.append("\(app.name): \(error.localizedDescription)")
                }
            }
        }

        var notifiedCount = 0
        for notification in pendingNotifications {
            if await notifier.sendPriceDrop(notification) {
                try? await store.markNotified(recordID: notification.recordID, at: now())
                notifiedCount += 1
            }
        }

        let outcome: CheckRunOutcome
        if failedCount == 0 {
            outcome = .success
        } else if checkedCount > 0 {
            outcome = .partial
        } else {
            outcome = .failed
        }
        let message: String? = failures.isEmpty ? nil : failures.prefix(5).joined(separator: "; ")
        let summary = RefreshSummary(
            source: source,
            outcome: outcome,
            startedAt: startedAt,
            finishedAt: now(),
            checkedCount: checkedCount,
            changedCount: changedCount,
            failedCount: failedCount,
            notifiedCount: notifiedCount,
            message: message
        )
        try? await store.recordRun(summary)
        log("run finished: outcome=\(outcome.rawValue) checked=\(checkedCount) changed=\(changedCount) failed=\(failedCount) notified=\(notifiedCount)")
        return summary
    }

    private func log(_ message: String) {
        AppLog.info("[refresh] \(message)", fileURL: logURL)
    }
}

