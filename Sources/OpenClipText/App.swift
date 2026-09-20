import AppKit
import Carbon.HIToolbox

/// AD-1: Swift + AppKit/SwiftUI, no web views. Menu bar app, no dock icon (NFR-2).
@main
struct OpenClipTextApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var service: HistoryService!
    private var monitor: ClipboardMonitor!
    private var menu: QuickMenu!
    private var panel: HistoryPanelController!
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // FR-15 seeds: password managers people commonly want out of history.
        let defaults = UserDefaults.standard
        if defaults.object(forKey: HistoryService.excludedBundleIDsKey) == nil {
            defaults.set(["com.1password.1password", "com.agilebits.onepassword7", "com.apple.keychainaccess"],
                         forKey: HistoryService.excludedBundleIDsKey)
        }

        let store: HistoryStore
        do {
            store = try HistoryStore()
        } catch {
            FileHandle.standardError.write(Data("OpenClipText: falling back to in-memory store (\(error))\n".utf8))
            store = HistoryStore.inMemory()
        }
        service = HistoryService(store: store)

        // AD-6: the panel writes the clipboard too, so it must suppress the monitor's
        // re-record just like the menu path — otherwise every panel copy reorders history.
        panel = HistoryPanelController(service: service) { [weak self] item in
            self?.monitor.ignoreUpcomingChange()
            PasteWriter.copy(item.content)
        }

        menu = QuickMenu(service: service, onOpenPanel: { [weak self] in
            self?.panel.show()
        }, onWillWrite: { [weak self] in
            self?.monitor.ignoreUpcomingChange()
        })

        monitor = ClipboardMonitor(service: service) { _ in
            // Menu rebuilds on open; nothing to push (NFR-3 idle CPU ~0%).
        }
        monitor.start()

        // FR-6: default ⌥⇧V, matching CopyClip.
        hotKey = GlobalHotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(optionKey | shiftKey)) { [weak self] in
            self?.menu.popUp()
        }
        if hotKey == nil {
            // A taken shortcut must not fail silently — the menu bar click still works.
            FileHandle.standardError.write(Data("OpenClipText: ⇧V already registered by another app; hotkey disabled\n".utf8))
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        hotKey?.unregister()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

/// NFR-4/FR-6: system-registered global hotkey via Carbon. No accessibility permission needed.
final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private static var registry: [UInt32: GlobalHotKey] = [:]
    private static var nextID: UInt32 = 1
    private let id: UInt32

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        self.id = Self.nextID
        Self.nextID += 1

        let hotKeyID = EventHotKeyID(signature: OSType(0x4F435458), id: id) // 'OCTX'
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        let callback: EventHandlerUPP = { _, event, _ in
            var pressed = EventHotKeyID()
            guard let event else { return noErr }
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            GlobalHotKey.registry[pressed.id]?.action()
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, nil, &handler)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
        Self.registry[id] = self
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        ref = nil
        handler = nil
        Self.registry[id] = nil
    }

    deinit { unregister() }
}