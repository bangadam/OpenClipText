import Foundation
import GRDB

/// A recorded clipboard item. `id` is the SQLite rowid (spine: item id = rowid).
struct ClipboardItem: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    static let databaseTableName = "clipboard_items"

    var id: Int64?
    var content: String
    /// Unix epoch seconds (spine convention).
    var capturedAt: Int64
    var pinned: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case content
        case capturedAt = "captured_at"
        case pinned
    }

    init(id: Int64? = nil, content: String, capturedAt: Int64, pinned: Bool = false) {
        self.id = id
        self.content = content
        self.capturedAt = capturedAt
        self.pinned = pinned
    }

    /// AD-3: items larger than 1MB are not recorded.
    static let maxContentBytes = 1_048_576

    static func isRecordable(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.count <= maxContentBytes
    }

    /// Single-line, truncated title for the quick menu (AD-4).
    /// Bounded: only ever scans a prefix, so a 1MB item costs the same as a short one.
    func title(maxLength: Int = 80) -> String {
        let scanLimit = maxLength * 4

        // Fast path: a short body can't need more than one line of it.
        if content.count <= maxLength, !content.contains(where: \.isNewline) {
            return content
        }

        var pieces: [Substring] = []
        var scanned = 0
        for line in content.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            pieces.append(line)
            scanned += line.count
            if scanned >= scanLimit { break }
        }

        let oneLine = pieces.joined(separator: " ")
        guard oneLine.count > maxLength else { return oneLine }
        return String(oneLine.prefix(maxLength)) + "…"
    }
}

/// AD-5: the only thing a hover preview is allowed to render. Never the full text.
struct PreviewChunk: Equatable, Sendable {
    static let maxLines = 10
    static let maxCharacters = 500

    let text: String
    /// Source lines not fully rendered in `text`. A line cut mid-way counts as omitted.
    let omittedLineCount: Int
    /// True when `text` ends inside a line rather than on a line boundary, so the
    /// omitted-line count understates what is hidden and must not drive the wording.
    let endsMidLine: Bool

    init(text: String, omittedLineCount: Int, endsMidLine: Bool = false) {
        self.text = text
        self.omittedLineCount = omittedLineCount
        self.endsMidLine = endsMidLine
    }

    var isTruncated: Bool { omittedLineCount > 0 || endsMidLine }

    /// Hover indicator; nil when the whole text is shown.
    var indicator: String? {
        guard isTruncated else { return nil }
        if endsMidLine { return "… (truncated)" }
        return omittedLineCount == 1 ? "… +1 more line" : "… +\(omittedLineCount) more lines"
    }

    var displayText: String { indicator.map { text + "\n" + $0 } ?? text }

    /// Rows `displayText` occupies, indicator line included — the panel's hover line budget.
    var lineCount: Int {
        var lines = 1
        for byte in text.utf8 where byte == 0x0A { lines += 1 }
        return indicator == nil ? lines : lines + 1
    }

    // Bounded by construction: never splits the whole text, never builds a String of
    // more than `maxCharacters` (NFR-1, FR-11).
    // ponytail: cut on line boundaries, so a chunk can be shorter than 500 chars.
    // Upgrade to a mid-line cut only if a single long line reads badly.
    static func make(from text: String) -> PreviewChunk {
        guard !text.isEmpty else { return PreviewChunk(text: "", omittedLineCount: 0) }

        // Stops scanning after maxLines separators — the rest of a 1MB body is never materialised.
        let head = text.split(separator: "\n", maxSplits: maxLines, omittingEmptySubsequences: false)
        var shown = ""
        var fullyShown = 0
        var midLine = false

        for (index, line) in head.prefix(maxLines).enumerated() {
            let piece = index == 0 ? String(line) : "\n" + line
            let room = maxCharacters - shown.count
            if piece.count <= room {
                shown += piece
                fullyShown = index + 1
            } else {
                // A single line bigger than the whole budget still gets a char-level cut,
                // otherwise the preview would be empty.
                if index == 0 {
                    shown += line.prefix(maxCharacters)
                    midLine = true
                }
                break
            }
        }

        return PreviewChunk(
            text: shown,
            omittedLineCount: totalLineCount(of: text) - fullyShown,
            endsMidLine: midLine
        )
    }

    /// Byte-level newline scan: no allocation, ~1ms even for 1MB.
    private static func totalLineCount(of text: String) -> Int {
        var lines = 1
        for byte in text.utf8 where byte == 0x0A { lines += 1 }
        return lines
    }
}