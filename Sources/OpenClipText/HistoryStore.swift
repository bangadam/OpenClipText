import Foundation
import GRDB

/// AD-2: the only store of history. All DB writes go through here; UI never touches GRDB.
final class HistoryStore: Sendable {
    private let dbQueue: DatabaseQueue

    /// Production store: `~/Library/Application Support/OpenClipText/clipboard.sqlite`.
    static func defaultURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("OpenClipText", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("clipboard.sqlite")
    }

    /// Corrupt DB → rename aside, retry, then fall back (I/O matrix: restart app).
    convenience init() throws {
        let url = try Self.defaultURL()
        do {
            try self.init(path: url.path)
        } catch {
            FileHandle.standardError.write(Data("OpenClipText: store open failed (\(error)); salvaging\n".utf8))
            // Keep the unreadable file for inspection instead of orphaning it, then retry
            // the primary path so history lives in the real location again.
            let stamp = Int(Date().timeIntervalSince1970)
            let salvaged = url.appendingPathExtension("corrupt-\(stamp)")
            try? FileManager.default.moveItem(at: url, to: salvaged)
            try self.init(path: url.path)
        }
    }

    /// Last resort that cannot throw: history is lost for the session, the app still runs.
    static func inMemory() -> HistoryStore {
        do {
            return try HistoryStore(path: ":memory:")
        } catch {
            // ponytail: a throwing in-memory open is unreachable in practice; if the
            // process can't open one, there is nothing left to degrade to.
            fatalError("OpenClipText: in-memory store unavailable (\(error))")
        }
    }

    init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try Self.migrator.migrate(dbQueue)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_clipboard_items") { db in
            try db.create(table: "clipboard_items") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("content", .text).notNull()
                t.column("captured_at", .integer).notNull()
                t.column("pinned", .boolean).notNull().defaults(to: false)
            }
            try db.create(index: "idx_clipboard_items_content", on: "clipboard_items", columns: ["content"], unique: true)
            try db.create(index: "idx_clipboard_items_order", on: "clipboard_items", columns: ["pinned", "captured_at"])
        }
        return migrator
    }

    // MARK: - Writes

    /// AD-7: re-copying existing text refreshes its timestamp and moves it to top, unless pinned.
    /// Returns the stored row, or nil when it was rejected/oversized.
    @discardableResult
    func record(_ text: String, now: Int64 = Int64(Date().timeIntervalSince1970)) throws -> ClipboardItem? {
        guard ClipboardItem.isRecordable(text) else { return nil }

        return try dbQueue.write { db in
            if var existing = try ClipboardItem.filter(Column("content") == text).fetchOne(db) {
                // AD-7: pinned items are never moved — leave the row exactly as it is.
                if existing.pinned { return existing }

                // Unpinned duplicate: delete + re-insert so it gets a fresh rowid. Updating
                // captured_at alone ties with any other copy in the same second, and the
                // ordering breaks such ties by rowid — the item would stay put.
                try ClipboardItem.deleteOne(db, key: existing.id)
                existing.id = nil
                existing.capturedAt = now
                try existing.insert(db)
                if existing.id == nil { existing.id = db.lastInsertedRowID }
                return existing
            }
            var item = ClipboardItem(content: text, capturedAt: now)
            try item.insert(db)
            // GRDB only writes the rowid back for MutablePersistableRecord; keep it explicit.
            if item.id == nil { item.id = db.lastInsertedRowID }
            return item
        }
    }

    func setPinned(id: Int64, pinned: Bool) throws {
        try dbQueue.write { db in
            if var item = try ClipboardItem.fetchOne(db, key: id) {
                item.pinned = pinned
                try item.update(db)
            }
        }
    }

    func delete(id: Int64) throws {
        _ = try dbQueue.write { db in try ClipboardItem.deleteOne(db, key: id) }
    }

    func clearAll(keepingPinned: Bool = false) throws {
        _ = try dbQueue.write { db in
            let request = keepingPinned
                ? ClipboardItem.filter(Column("pinned") == false)
                : ClipboardItem.all()
            return try request.deleteAll(db)
        }
    }

    // MARK: - Reads

    private static let ordered = ClipboardItem
        .order(Column("pinned").desc, Column("captured_at").desc, Column("id").desc)

    /// AD-7 ordering, optionally filtered by a case-insensitive substring (FR-14).
    func items(matching query: String = "", limit: Int? = nil) throws -> [ClipboardItem] {
        try dbQueue.read { db in
            var request = Self.ordered
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                // Escape LIKE metacharacters so a query of "%" matches a literal percent,
                // not the whole table (FR-14 is substring search, not pattern search).
                let escaped = trimmed
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_")
                request = request.filter(Column("content").like("%\(escaped)%", escape: "\\"))
            }
            if let limit { request = request.limit(limit) }
            return try request.fetchAll(db)
        }
    }

    func count() throws -> Int {
        try dbQueue.read { db in try ClipboardItem.fetchCount(db) }
    }
}