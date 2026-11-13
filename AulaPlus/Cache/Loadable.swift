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
    /// While a streaming load runs: how many items are expected in total (if the server said).
    private(set) var expected: Int?
    /// True while `value` holds only the first part of a streaming load.
    private(set) var isPartial = false

    let key: String
    private let fetch: (_ emit: @escaping @MainActor (T, Int?) -> Void) async throws -> T
    /// Called after the value changes (used to update the widget).
    @ObservationIgnored var onChange: (() -> Void)?

    convenience init(key: String, fetch: @escaping () async throws -> T) {
        self.init(key: key, streaming: { _ in try await fetch() })
    }

    /// `streaming` may call `emit` with partial results (and an expected total) before it returns.
    /// Partial results are shown only when nothing better is on screen, and never saved to disk.
    init(key: String, streaming: @escaping (_ emit: @escaping @MainActor (T, Int?) -> Void) async throws -> T) {
        self.key = key
        self.fetch = streaming
        if Demo.isOn {
            value = Demo.value(for: key) as? T
            savedAt = Date()
            return
        }
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
        guard !isLoading, !Demo.isOn else { return }
        isLoading = true
        let hadValue = value != nil
        defer { isLoading = false; isPartial = false; expected = nil }
        do {
            let fresh = try await fetch { [weak self] partial, total in
                guard let self, self.isLoading else { return }
                self.expected = total
                if !hadValue || self.isPartial {
                    self.value = partial
                    self.isPartial = true
                }
            }
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
