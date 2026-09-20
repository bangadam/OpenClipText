import XCTest
@testable import OpenClipText

final class HistoryStoreTests: XCTestCase {
    private func makeStore() throws -> HistoryStore {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenClipTextTests-\(UUID().uuidString).sqlite").path
        return try HistoryStore(path: path)
    }

    // MARK: - Dedup & ordering (AD-7)

    func testDuplicateMovesToTopWithUpdatedTimestamp() throws {
        let store = try makeStore()
        _ = try store.record("first", now: 100)
        _ = try store.record("second", now: 200)

        let recopied = try store.record("first", now: 300)

        // Spec, not implementation: same text is one entry, refreshed and back on top.
        XCTAssertEqual(recopied?.content, "first")
        XCTAssertEqual(recopied?.capturedAt, 300)
        XCTAssertEqual(try store.count(), 2, "no new entry for a duplicate")
        XCTAssertEqual(try store.items().map(\.content), ["first", "second"])
    }

    /// The rowid tie-break is why dedup re-inserts: same-second re-copy must still go top.
    func testDuplicateWithinSameSecondStillMovesToTop() throws {
        let store = try makeStore()
        _ = try store.record("first", now: 100)
        _ = try store.record("second", now: 100)

        _ = try store.record("first", now: 100)

        XCTAssertEqual(try store.items().map(\.content), ["first", "second"])
        XCTAssertEqual(try store.count(), 2)
    }

    func testPinnedItemIsNotMovedOnRecopy() throws {
        let store = try makeStore()
        let pinned = try store.record("pinned text", now: 100)
        _ = try store.record("newer", now: 200)
        try store.setPinned(id: pinned!.id!, pinned: true)

        let recopied = try store.record("pinned text", now: 300)

        XCTAssertEqual(recopied?.capturedAt, 100, "pinned timestamp is untouched")
        XCTAssertEqual(try store.items().map(\.content), ["pinned text", "newer"],
                       "pinned stays first, order otherwise unchanged")
    }

    func testPinnedItemsSortFirstThenMostRecent() throws {
        let store = try makeStore()
        let a = try store.record("a", now: 1)
        _ = try store.record("b", now: 2)
        _ = try store.record("c", now: 3)
        try store.setPinned(id: a!.id!, pinned: true)

        XCTAssertEqual(try store.items().map(\.content), ["a", "c", "b"])
    }

    // MARK: - 1MB cap (AD-3)

    func testOversizeTextIsNotRecorded() throws {
        let store = try makeStore()
        let oversized = String(repeating: "x", count: ClipboardItem.maxContentBytes + 1)

        XCTAssertNil(try store.record(oversized))
        XCTAssertEqual(try store.count(), 0)
    }

    func testExactlyOneMegabyteIsRecorded() throws {
        let store = try makeStore()
        let boundary = String(repeating: "x", count: ClipboardItem.maxContentBytes)

        XCTAssertNotNil(try store.record(boundary))
        XCTAssertEqual(try store.count(), 1)
    }

    func testEmptyTextIsNotRecorded() throws {
        let store = try makeStore()
        XCTAssertNil(try store.record(""))
        XCTAssertEqual(try store.count(), 0)
    }

    func testMultibyteSizeIsMeasuredInBytesNotCharacters() {
        // 400k emoji = 1.6MB of UTF-8, well over the cap despite few "characters".
        let emoji = String(repeating: "😀", count: 400_000)
        XCTAssertFalse(ClipboardItem.isRecordable(emoji))
    }

    // MARK: - Search (FR-14)

    func testSearchIsCaseInsensitiveSubstring() throws {
        let store = try makeStore()
        _ = try store.record("Hello World", now: 1)
        _ = try store.record("goodbye", now: 2)

        XCTAssertEqual(try store.items(matching: "hello").map(\.content), ["Hello World"])
        XCTAssertEqual(try store.items(matching: "WORLD").map(\.content), ["Hello World"])
        XCTAssertEqual(try store.items(matching: "o").count, 2)
    }

    func testEmptyQueryReturnsEverything() throws {
        let store = try makeStore()
        _ = try store.record("a", now: 1)
        _ = try store.record("b", now: 2)

        XCTAssertEqual(try store.items(matching: "").count, 2)
        XCTAssertEqual(try store.items(matching: "   ").count, 2)
    }

    func testSearchReturnsNoMatchForAbsentText() throws {
        let store = try makeStore()
        _ = try store.record("a", now: 1)
        XCTAssertTrue(try store.items(matching: "zzz").isEmpty)
    }

    // MARK: - Delete / clear (FR-12, FR-13)

    func testDeleteSingleItem() throws {
        let store = try makeStore()
        let a = try store.record("a", now: 1)
        _ = try store.record("b", now: 2)

        try store.delete(id: a!.id!)

        XCTAssertEqual(try store.items().map(\.content), ["b"])
    }

    func testClearAllRemovesEverything() throws {
        let store = try makeStore()
        _ = try store.record("a", now: 1)
        _ = try store.record("b", now: 2)
        try store.clearAll()
        XCTAssertEqual(try store.count(), 0)
    }

    func testClearAllKeepingPinned() throws {
        let store = try makeStore()
        let a = try store.record("a", now: 1)
        _ = try store.record("b", now: 2)
        try store.setPinned(id: a!.id!, pinned: true)

        try store.clearAll(keepingPinned: true)

        XCTAssertEqual(try store.items().map(\.content), ["a"])
    }

    // MARK: - Persistence (FR-4)

    func testHistorySurvivesReopen() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenClipTextTests-\(UUID().uuidString).sqlite").path

        do {
            let store = try HistoryStore(path: path)
            _ = try store.record("persisted", now: 42)
        }
        let reopened = try HistoryStore(path: path)

        XCTAssertEqual(try reopened.items().map(\.content), ["persisted"])
    }
}

final class PreviewChunkTests: XCTestCase {
    func testEmptyText() {
        let chunk = PreviewChunk.make(from: "")
        XCTAssertEqual(chunk.text, "")
        XCTAssertEqual(chunk.omittedLineCount, 0)
        XCTAssertFalse(chunk.isTruncated)
        XCTAssertNil(chunk.indicator)
    }

    func testShortSingleLineIsNotTruncated() {
        let chunk = PreviewChunk.make(from: "hello")
        XCTAssertEqual(chunk.text, "hello")
        XCTAssertFalse(chunk.isTruncated)
        XCTAssertEqual(chunk.displayText, "hello")
    }

    func testExactlyTenLinesIsNotTruncated() {
        let text = (1...10).map { "line \($0)" }.joined(separator: "\n")
        let chunk = PreviewChunk.make(from: text)
        XCTAssertEqual(chunk.text, text)
        XCTAssertEqual(chunk.omittedLineCount, 0)
        XCTAssertFalse(chunk.isTruncated)
    }

    func testElevenLinesOmitsOne() {
        let text = (1...11).map { "line \($0)" }.joined(separator: "\n")
        let chunk = PreviewChunk.make(from: text)
        XCTAssertEqual(chunk.text, (1...10).map { "line \($0)" }.joined(separator: "\n"))
        XCTAssertEqual(chunk.omittedLineCount, 1)
        XCTAssertEqual(chunk.indicator, "… +1 more line", "singular for a single omitted line")
    }

    func testFiveThousandLinesAreChunkedFastAndBounded() {
        let text = (1...5000).map { "line \($0)" }.joined(separator: "\n")
        let chunk = PreviewChunk.make(from: text)
        XCTAssertEqual(chunk.text.components(separatedBy: "\n").count, 10)
        XCTAssertEqual(chunk.omittedLineCount, 4990)
        XCTAssertLessThan(chunk.displayText.count, 600, "preview must stay small")
    }

    func testFiveHundredCharacterBoundary() {
        // 5 lines of 100 chars = 500 chars exactly, including the 4 newline separators → 504.
        // The 5th line is cut, so only 4 lines fit and the rest are omitted.
        let text = (1...9).map { String(repeating: String($0), count: 100) }.joined(separator: "\n")
        let chunk = PreviewChunk.make(from: text)
        XCTAssertLessThanOrEqual(chunk.text.count, PreviewChunk.maxCharacters)
        XCTAssertTrue(chunk.isTruncated)
    }

    func testBudgetStopsBeforeExceedingCharacterCap() {
        let lines = (1...4).map { _ in String(repeating: "y", count: 200) }
        let chunk = PreviewChunk.make(from: lines.joined(separator: "\n"))
        XCTAssertLessThanOrEqual(chunk.text.count, PreviewChunk.maxCharacters)
        // 200 + 1 + 200 + 1 = 402 fits; the 3rd line would exceed 500.
        XCTAssertEqual(chunk.text.components(separatedBy: "\n").count, 2)
        XCTAssertEqual(chunk.omittedLineCount, 2)
    }

    func testSingleLineLongerThanCapIsCharCutNotEmpty() {
        let chunk = PreviewChunk.make(from: String(repeating: "z", count: 5000))
        XCTAssertEqual(chunk.text.count, PreviewChunk.maxCharacters)
        XCTAssertTrue(chunk.isTruncated)
        // One source line was cut mid-way: "+1 more line" would be a lie.
        XCTAssertTrue(chunk.endsMidLine)
        XCTAssertEqual(chunk.indicator, "… (truncated)")
        // A line cut mid-way counts as omitted (documented), so the count is 1 — but the
        // wording comes from `endsMidLine`, not from this number.
        XCTAssertEqual(chunk.omittedLineCount, 1)
    }

    func testCompletePreviewHasNoIndicatorAndOneLine() {
        let chunk = PreviewChunk.make(from: "one line")
        XCTAssertNil(chunk.indicator)
        XCTAssertEqual(chunk.lineCount, 1)
    }

    /// The indicator occupies a row of its own; the hover budget must cover it.
    func testLineCountIncludesIndicatorRow() {
        let text = (1...11).map { "line \($0)" }.joined(separator: "\n")
        let chunk = PreviewChunk.make(from: text)
        XCTAssertEqual(chunk.text.components(separatedBy: "\n").count, 10)
        XCTAssertEqual(chunk.lineCount, 11, "10 chunk lines + the indicator line")
        XCTAssertEqual(chunk.displayText.components(separatedBy: "\n").count, 11,
                       "lineCount must match displayText, not raw chunk text")
    }

    func testIndentedContentIsPreservedVerbatim() {
        let text = "  indented\n\ttabbed\nplain"
        let chunk = PreviewChunk.make(from: text)
        XCTAssertEqual(chunk.text, text)
    }
}

final class TitleAndCapTests: XCTestCase {
    func testTitleCollapsesNewlinesToOneLine() {
        let item = ClipboardItem(content: "first\nsecond\nthird", capturedAt: 0)
        XCTAssertEqual(item.title(), "first second third")
    }

    func testTitleTruncatesLongContent() {
        let item = ClipboardItem(content: String(repeating: "a", count: 200), capturedAt: 0)
        XCTAssertEqual(item.title(maxLength: 10), "aaaaaaaaaa…")
    }

    func testIsRecordableRejectsOnlyEmptyAndOversize() {
        XCTAssertTrue(ClipboardItem.isRecordable("x"))
        XCTAssertTrue(ClipboardItem.isRecordable("  "))
        XCTAssertFalse(ClipboardItem.isRecordable(""))
        XCTAssertFalse(ClipboardItem.isRecordable(String(repeating: "x", count: ClipboardItem.maxContentBytes + 1)))
    }
}

// Ad-hoc assertion harness for the bounded-render acceptance criterion (NFR-1, FR-11).
final class PreviewLatencyTests: XCTestCase {
    func testHoverPreviewOfOneMegabyteRendersWithin50ms() throws {
        let megabyte = String(repeating: "lorem ipsum dolor sit amet\n", count: 40_000)
        XCTAssertGreaterThan(megabyte.utf8.count, 1_000_000)

        // Hover is steady-state; warm the first-touch page faults and the UTF-8 view.
        _ = PreviewChunk.make(from: megabyte)

        let start = Date()
        let chunk = PreviewChunk.make(from: megabyte)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertTrue(chunk.isTruncated)

        // The whole point of AD-5: the preview never carries the full text.
        XCTAssertLessThan(chunk.displayText.count, 600)

        // NFR-1's 50ms budget; unoptimized debug builds pay an interpreter-speed byte
        // scan for the line count, so only release holds the literal bound.
        #if DEBUG
        XCTAssertLessThan(elapsed, 0.2, "hover preview must not scale with item size (NFR-1)")
        #else
        XCTAssertLessThan(elapsed, 0.05, "hover preview must stay within 50ms for 1MB (NFR-1)")
        #endif
    }
}