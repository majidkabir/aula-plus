import Foundation
import Observation

/// One cached, refreshable piece of data for a screen.
/// `value` is filled from disk immediately, then replaced by fresh data.
@MainActor
@Observable
final class Loadable<T: Codable> {
    private(set) var value: T?
    private(set) var savedAt: Date?
    private(set) var isLoading = false
    private(set) var error: String?

    let key: String
    private let fetch: () async throws -> T
    /// Called after the value changes (used to update the widget).
    @ObservationIgnored var onChange: (() -> Void)?

    init(key: String, fetch: @escaping () async throws -> T) {
        self.key = key
        self.fetch = fetch
        if let hit = DiskCache.load(T.self, key: key) {
            value = hit.value
            savedAt = hit.savedAt
        }
    }

    /// Refresh unless the cached copy is younger than `maxAge` seconds.
    func load(maxAge: TimeInterval = 0) async {
        if let savedAt, value != nil, Date().timeIntervalSince(savedAt) < maxAge { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await fetch()
            value = fresh
            savedAt = Date()
            error = nil
            DiskCache.save(fresh, key: key)
            onChange?()
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch AuthError.notLoggedIn {
            AppModel.shared.sessionExpired()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Replace with data fetched elsewhere (e.g. by the background refresh).
    func replace(_ fresh: T) {
        value = fresh
        savedAt = Date()
        DiskCache.save(fresh, key: key)
        onChange?()
    }

    func forget() {
        value = nil
        savedAt = nil
        error = nil
    }

    /// Local optimistic edit (e.g. mark a thread read) without refetching.
    func mutate(_ change: (inout T) -> Void) {
        guard var v = value else { return }
        change(&v)
        value = v
        DiskCache.save(v, key: key)
        onChange?()
    }
}
