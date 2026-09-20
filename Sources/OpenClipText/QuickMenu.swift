import AppKit

/// AD-4: NSMenu quick list — paginated 20 items, numbers 1–9, one-line truncation.
/// Search/preview never live here (panel-only); both surfaces read from HistoryService.
@MainActor
final class QuickMenu: NSObject, NSMenuDelegate {
    private let service: HistoryService
    private let pasteboard: NSPasteboard
    private let onOpenPanel: () -> Void
    private let onWillWrite: () -> Void

    private let statusItem: NSStatusItem
    /// Test seam: internal read-only view of the NSMenu contents.
    var menuItems: [NSMenuItem] { menu.items }
    private let menu = NSMenu()
    private var pageIndex = 0

    init(
        service: HistoryService,
        pasteboard: NSPasteboard = .general,
        onOpenPanel: @escaping () -> Void,
        onWillWrite: @escaping () -> Void
    ) {
        self.service = service
        self.pasteboard = pasteboard
        self.onOpenPanel = onOpenPanel
        self.onWillWrite = onWillWrite
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "OpenClipText"
        )
        menu.delegate = self
        statusItem.menu = menu
    }

    /// FR-6: open the same dropdown without the mouse (global hotkey path).
    func popUp() {
        pageIndex = 0
        rebuild()
        statusItem.button?.performClick(nil)
    }

    // MARK: - Menu construction

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild()
    }

    private func rebuild() {
        menu.removeAllItems()

        let items = service.items()
        guard !items.isEmpty else {
            let placeholder = NSMenuItem(title: "No history yet", action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            menu.addItem(placeholder)
            menu.addItem(.separator())
            addFooter()
            return
        }

        let pageCount = service.pageCount()
        pageIndex = min(pageIndex, pageCount - 1)
        let page = service.page(pageIndex)

        // FR-7: numbers 1–9 select the visible item directly.
        for (offset, item) in page.enumerated() {
            let menuItem = NSMenuItem(
                title: item.title(),
                action: #selector(selectItem(_:)),
                keyEquivalent: offset < 9 ? String(offset + 1) : ""
            )
            // Number keys must not require a modifier (FR-7), unlike NSMenu's ⌘-default.
            menuItem.keyEquivalentModifierMask = []
            menuItem.target = self
            menuItem.representedObject = ItemBox(item)
            menuItem.state = item.pinned ? .on : .off
            menu.addItem(menuItem)

            let submenu = NSMenu()
            submenu.addItem(submenuItem(item.pinned ? "Unpin" : "Pin", #selector(togglePin(_:)), item))
            submenu.addItem(submenuItem("Delete", #selector(deleteItem(_:)), item))
            submenu.addItem(submenuItem("Open in Panel", #selector(openInPanel(_:)), item))
            menuItem.submenu = submenu
        }

        if pageCount > 1 {
            menu.addItem(.separator())
            let next = NSMenuItem(title: "More…", action: #selector(nextPage), keyEquivalent: "")
            next.target = self
            next.isEnabled = pageIndex < pageCount - 1
            menu.addItem(next)

            let previous = NSMenuItem(title: "Previous…", action: #selector(previousPage), keyEquivalent: "")
            previous.target = self
            previous.isEnabled = pageIndex > 0
            menu.addItem(previous)
        }

        menu.addItem(.separator())
        addFooter()
    }

    private func addFooter() {
        let clear = NSMenuItem(title: "Clear All", action: #selector(clearAll), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        let panel = NSMenuItem(title: "Open History Panel…", action: #selector(openPanel), keyEquivalent: "")
        panel.target = self
        menu.addItem(panel)

        let quit = NSMenuItem(title: "Quit OpenClipText", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func submenuItem(_ title: String, _ action: Selector, _ item: ClipboardItem) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        menuItem.representedObject = ItemBox(item)
        return menuItem
    }

    // MARK: - Actions

    @objc private func selectItem(_ sender: NSMenuItem) {
        guard let item = (sender.representedObject as? ItemBox)?.item else { return }
        select(item)
    }

    @objc private func togglePin(_ sender: NSMenuItem) {
        guard let item = (sender.representedObject as? ItemBox)?.item else { return }
        service.togglePin(item)
    }

    @objc private func deleteItem(_ sender: NSMenuItem) {
        guard let item = (sender.representedObject as? ItemBox)?.item else { return }
        service.delete(item)
    }

    @objc private func openInPanel(_ sender: NSMenuItem) {
        guard let item = (sender.representedObject as? ItemBox)?.item else { return }
        select(item)
        onOpenPanel()
    }

    @objc private func nextPage() {
        pageIndex += 1
        rebuild()
    }

    @objc private func previousPage() {
        pageIndex = max(0, pageIndex - 1)
        rebuild()
    }
    @objc private func clearAll() { service.clearAll() }
    @objc private func openPanel() { onOpenPanel() }
    @objc private func quit() { NSApp.terminate(nil) }

    /// AD-6: selection writes the clipboard; the user pastes with ⌘V.
    private func select(_ item: ClipboardItem) {
        onWillWrite()
        PasteWriter.copy(item.content, to: pasteboard)
    }

    /// Referenced NSMenu items carry their model across the ObjC boundary.
    private final class ItemBox: NSObject {
        let item: ClipboardItem
        init(_ item: ClipboardItem) { self.item = item }
    }
}