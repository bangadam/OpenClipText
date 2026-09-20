import Foundation

/// Domain layer: owns the ordering/dedup/pin rules (AD-7) and is the only seam UI talks to.
final class HistoryService: Sendable {
    private let store: HistoryStore
    // UserDefaults is documented thread-safe; the SDK just hasn't marked it Sendable.
    nonisolated(unsafe) private let defaults: UserDefaults

    static let excludedBundleIDsKey = "excludedBundleIDs"
    static let pageSize = 20

    init(store: HistoryStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
    }

    // MARK: - Recording

    /// AD-3: recording is refused for excluded apps. Bundle IDs come from UserDefaults.
    func isExcluded(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedBundleIDs.contains(bundleID)
    }

    var excludedBundleIDs: [String] {
        get { defaults.stringArray(forKey: Self.excludedBundleIDsKey) ?? [] }
        set { defaults.set(newValue, forKey: Self.excludedBundleIDsKey) }
    }

    /// Called by ClipboardMonitor; oversize/excluded already filtered upstream, re-checked here.
    @discardableResult
    func record(_ text: String) -> ClipboardItem? {
        do {
            return try store.record(text)
        } catch {
            // I/O matrix: DB error → log, skip, keep running.
            FileHandle.standardError.write(Data("OpenClipText: record failed (\(error))\n".utf8))
            return nil
        }
    }

    // MARK: - Reads

    private func read(_ label: String, _ query: String = "") -> [ClipboardItem] {
        do {
            return try store.items(matching: query)
        } catch {
            // A read failure is not an empty history; say so instead of returning [] silently.
            FileHandle.standardError.write(Data("OpenClipText: \(label) failed (\(error))\n".utf8))
            return []
        }
    }

    func items() -> [ClipboardItem] {
        read("read")
    }

    /// Fresh window of the history, page-aligned for the quick menu (AD-4).
    func page(_ index: Int) -> [ClipboardItem] {
        guard index >= 0 else { return [] }
        let all = items()
        let start = index * Self.pageSize
        guard start < all.count else { return [] }
        return Array(all[start..<min(start + Self.pageSize, all.count)])
    }

    func pageCount() -> Int {
        max(1, Int(ceil(Double(items().count) / Double(Self.pageSize))))
    }

    func search(_ query: String) -> [ClipboardItem] {
        // Store-side filtering (escaped LIKE) rather than a full-table in-memory scan.
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items() }
        return read("search", trimmed)
    }

    func preview(for item: ClipboardItem) -> PreviewChunk {
        PreviewChunk.make(from: item.content)
    }

    // MARK: - Mutations

    func setPinned(_ item: ClipboardItem, pinned: Bool) {
        guard let id = item.id else { return }
        perform("pin") { try store.setPinned(id: id, pinned: pinned) }
    }

    func togglePin(_ item: ClipboardItem) {
        setPinned(item, pinned: !item.pinned)
    }

    func delete(_ item: ClipboardItem) {
        guard let id = item.id else { return }
        perform("delete") { try store.delete(id: id) }
    }

    func clearAll(keepingPinned: Bool = false) {
        perform("clear") { try store.clearAll(keepingPinned: keepingPinned) }
    }

    private func perform(_ label: String, _ work: () throws -> Void) {
        do { try work() } catch {
            FileHandle.standardError.write(Data("OpenClipText: \(label) failed (\(error))\n".utf8))
        }
    }
}