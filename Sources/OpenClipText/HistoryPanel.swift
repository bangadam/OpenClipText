import AppKit
import SwiftUI

/// AD-4: search, full history and chunked hover preview live here — never in the NSMenu.
/// AD-5: only `PreviewChunk` reaches the preview renderer; full text only after explicit expand.
@MainActor
final class HistoryPanelController {
    private let service: HistoryService
    private let onSelect: (ClipboardItem) -> Void
    private var window: NSWindow?
    private var model: PanelModel?

    init(service: HistoryService, onSelect: @escaping (ClipboardItem) -> Void) {
        self.service = service
        self.onSelect = onSelect
    }

    func show() {
        let model = self.model ?? PanelModel(service: service, onSelect: onSelect)
        self.model = model
        model.reload()

        let window = self.window ?? {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 520),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.title = "OpenClipText History"
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: HistoryPanelView(model: model))
            w.center()
            self.window = w
            return w
        }()

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class PanelModel: ObservableObject {
    /// AD-5: the chunk is computed once here, at read time — never per hover render.
    struct Row: Identifiable {
        let item: ClipboardItem
        let chunk: PreviewChunk
        var id: Int64? { item.id }
        /// Hover body: title only until the row is hovered or expanded (FR-9).
        var collapsed: String { item.title(maxLength: 120) }
        /// Line budget for the collapsed body — covers the chunk plus its indicator line.
        var collapsedLineCount: Int { chunk.isTruncated ? chunk.lineCount : 1 }
    }

    @Published var rows: [Row] = []
    @Published var query: String = ""
    @Published var hoveredID: Int64?
    @Published var expanded: Set<Int64> = []

    private let service: HistoryService
    private let onSelect: (ClipboardItem) -> Void

    init(service: HistoryService, onSelect: @escaping (ClipboardItem) -> Void) {
        self.service = service
        self.onSelect = onSelect
    }

    func reload() {
        rows = service.search(query).map { Row(item: $0, chunk: service.preview(for: $0)) }
    }

    func isExpanded(_ row: Row) -> Bool {
        row.id.map(expanded.contains) ?? false
    }

    func toggleExpand(_ row: Row) {
        guard let id = row.id else { return }
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    func select(_ item: ClipboardItem) {
        onSelect(item)
    }

    func togglePin(_ item: ClipboardItem) {
        service.togglePin(item)
        reload()
    }

    func delete(_ item: ClipboardItem) {
        service.delete(item)
        reload()
    }

    func clearAll() {
        service.clearAll()
        reload()
    }
}

struct HistoryPanelView: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search history", text: $model.query)
                    .textFieldStyle(.plain)
                    .onChange(of: model.query) { _ in model.reload() }
                Button("Clear All") { model.clearAll() }
                    .controlSize(.small)
            }
            .padding(10)

            Divider()

            if model.rows.isEmpty {
                Spacer()
                Text("No history yet").foregroundStyle(.secondary)
                Spacer()
            } else {
                List(model.rows) { row in
                    self.row(row)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 420, minHeight: 320)
    }

    private func row(_ row: PanelModel.Row) -> some View {
        let item = row.item
        let chunk = row.chunk
        let isExpanded = model.isExpanded(row)
        // FR-9/FR-10: idle rows show a one-line title; the chunk appears on hover only.
        let isHovered = model.hoveredID == item.id
        let body = isExpanded ? item.content : (isHovered ? chunk.displayText : row.collapsed)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if item.pinned {
                    Image(systemName: "pin.fill").foregroundStyle(.orange)
                }
                Text(item.title())
                    .lineLimit(1)
                    .font(.system(.body, design: .monospaced))
                Spacer()
                Text(Date(timeIntervalSince1970: TimeInterval(item.capturedAt)), style: .relative)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            // AD-5: only the precomputed chunk reaches this renderer. Never `item.content`
            // unless the user expanded the row.
            Text(body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(isExpanded ? nil : (isHovered ? row.collapsedLineCount : 1))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button("Copy") { model.select(item) }.controlSize(.small)
                Button(isExpanded ? "Collapse" : "Expand") { model.toggleExpand(row) }
                    .controlSize(.small)
                    .disabled(!chunk.isTruncated)
                Button(item.pinned ? "Unpin" : "Pin") { model.togglePin(item) }.controlSize(.small)
                Button("Delete") { model.delete(item) }.controlSize(.small)
                Spacer()
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                model.hoveredID = item.id
            } else if model.hoveredID == item.id {
                model.hoveredID = nil
            }
        }
    }
}