import AppKit

/// AD-6: choosing an item writes the system clipboard; the user pastes with ⌘V.
/// No synthetic keystrokes, ever.
enum PasteWriter {
    @discardableResult
    static func copy(_ text: String, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}