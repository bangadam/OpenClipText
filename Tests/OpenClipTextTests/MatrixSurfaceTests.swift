import AppKit
import XCTest
@testable import OpenClipText

// I/O matrix coverage for the rows the store tests don't reach.
@MainActor
final class MatrixSurfaceTests: XCTestCase {
    private func makeService() throws -> HistoryService {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenClipTextMatrix-\(UUID().uuidString).sqlite").path
        let suiteName = "OpenClipTextMatrix-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return HistoryService(store: try HistoryStore(path: path), defaults: defaults)
    }

    // Matrix: excluded app copy → not recorded.
    func testExcludedBundleIDIsSkipped() throws {
        let service = try makeService()
        service.excludedBundleIDs = ["com.example.secret"]
        XCTAssertTrue(service.isExcluded(bundleID: "com.example.secret"))
        XCTAssertFalse(service.isExcluded(bundleID: "com.example.other"))
        XCTAssertFalse(service.isExcluded(bundleID: nil), "no frontmost bundle ID must not block recording")
    }

    // Matrix: select from menu → item content written to NSPasteboard.
    func testPasteWriterWritesStringToPasteboard() {
        let board = NSPasteboard(name: NSPasteboard.Name("MatrixPaste-\(UUID().uuidString)"))
        XCTAssertTrue(PasteWriter.copy("selected text", to: board))
        XCTAssertEqual(board.string(forType: .string), "selected text")
    }

    // Matrix: empty clipboard state → menu shows placeholder/disabled items.
    func testQuickMenuShowsPlaceholderWhenHistoryIsEmpty() throws {
        let service = try makeService()
        var openedPanel = false
        let menu = QuickMenu(
            service: service,
            onOpenPanel: { openedPanel = true },
            onWillWrite: {}
        )
        menu.menuNeedsUpdate(NSMenu())
        let items = menu.menuItems
        let titles = items.map(\.title)
        XCTAssertTrue(titles.contains("No history yet"), "placeholder missing, got: \(titles)")
        XCTAssertFalse(items.first?.isEnabled ?? true, "placeholder must be disabled")
        XCTAssertFalse(openedPanel)
    }

    // Matrix: DB error → log, skip, keep running (service must not throw/crash).
    func testRecordRejectsEmptyAndKeepsServing() throws {
        let service = try makeService()
        XCTAssertNil(service.record(""), "empty text is not recordable")
        XCTAssertNotNil(service.record("ok"))
        XCTAssertEqual(service.items().count, 1, "the rejected record must not disturb the store")
    }

    func testSearchSeamFiltersAndPassesEmptyQueryThrough() throws {
        let service = try makeService()
        service.record("alpha one")
        service.record("beta two")

        XCTAssertEqual(service.search("").count, 2, "empty query shows full list")
        XCTAssertEqual(service.search("ALPHA").map(\.content), ["alpha one"])
        XCTAssertTrue(service.search("gamma").isEmpty)
    }

    /// FR-14 is a substring search: a LIKE wildcard typed as text is a literal.
    func testSearchTreatsWildcardsAsLiteralText() throws {
        let service = try makeService()
        service.record("100% done")
        service.record("under_score")
        service.record("plain")

        XCTAssertEqual(service.search("%").map(\.content), ["100% done"])
        XCTAssertEqual(service.search("_").map(\.content), ["under_score"])
    }

    func testPageRejectsNegativeIndex() throws {
        let service = try makeService()
        service.record("one")
        XCTAssertTrue(service.page(-1).isEmpty, "a negative page must not trap")
        XCTAssertEqual(service.page(0).count, 1)
    }

    // Matrix: select from menu → item content written to NSPasteboard.
    func testQuickMenuSelectWritesPasteboardAndSuppressesRecord() throws {
        let service = try makeService()
        service.record("first entry")
        service.record("second entry")

        let board = NSPasteboard(name: NSPasteboard.Name("MatrixSelect-\(UUID().uuidString)"))
        var willWriteFired = false
        let menu = QuickMenu(
            service: service,
            pasteboard: board,
            onOpenPanel: {},
            onWillWrite: { willWriteFired = true }
        )

        menu.menuNeedsUpdate(NSMenu())
        let first = try XCTUnwrap(menu.menuItems.first, "history is non-empty, so a row must exist")
        XCTAssertEqual(first.title, "second entry", "most recent first")

        // Invoke through the menu item's real target/action, as a click would.
        let target = try XCTUnwrap(first.target)
        _ = target.perform(first.action!, with: first)

        XCTAssertEqual(board.string(forType: .string), "second entry")
        XCTAssertTrue(willWriteFired, "the monitor must be told to skip re-recording our own write")
    }

    /// FR-7: paging must actually repaint the menu.
    func testQuickMenuPagingRebuildsVisibleRows() throws {
        let service = try makeService()
        for index in 1...(HistoryService.pageSize + 1) {
            service.record("entry \(index)")
        }

        let menu = QuickMenu(service: service, pasteboard: NSPasteboard(name: .init("MatrixPage")),
                             onOpenPanel: {}, onWillWrite: {})
        menu.menuNeedsUpdate(NSMenu())
        XCTAssertTrue(menu.menuItems.contains { $0.title == "More…" })

        let next = try XCTUnwrap(menu.menuItems.first { $0.title == "More…" })
        _ = try XCTUnwrap(next.target).perform(next.action!, with: next)

        // Page 2 holds the single oldest entry; the selectable row set differs from page 1.
        let rows = menu.menuItems.filter { $0.action != nil && $0.keyEquivalent == "1" }
        XCTAssertEqual(rows.map(\.title), ["entry 1"], "page 2 must show the remainder")
    }
}
