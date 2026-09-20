import AppKit

/// AD-3: recording = polling `NSPasteboard.general.changeCount` on a ~250ms timer.
/// Text-only, 1MB cap, excluded apps skipped.
final class ClipboardMonitor: @unchecked Sendable {
    static let pollInterval: TimeInterval = 0.25

    private let pasteboard: NSPasteboard
    private let service: HistoryService
    private let onRecord: (ClipboardItem) -> Void
    private let queue = DispatchQueue(label: "com.opencliptext.monitor")

    private var timer: Timer?
    private var lastChangeCount: Int
    /// Set when we write the clipboard ourselves so re-selection isn't re-recorded as new.
    private var ignoreNextChange = false

    /// Bundle IDs that were frontmost at some point since the last poll. The poll runs up to
    /// 250ms after the copy, by which time the user may have switched away — recording is
    /// skipped if *any* of these is excluded (a secret copied in 1Password then switching
    /// to another app must not be recorded). See `startObservingActivation`.
    private var activeBundleIDsSincePoll: Set<String> = []
    private var activationObserver: NSObjectProtocol?

    init(
        service: HistoryService,
        pasteboard: NSPasteboard = .general,
        onRecord: @escaping (ClipboardItem) -> Void
    ) {
        self.service = service
        self.pasteboard = pasteboard
        self.onRecord = onRecord
        // Seed with the current value so a pre-existing clipboard isn't recorded on launch.
        self.lastChangeCount = pasteboard.changeCount
        self.activeBundleIDsSincePoll = Self.currentFrontmostBundleIDs()
    }

    func start() {
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        // NFR-3: let the OS coalesce wakeups; the poll is a changeCount compare, nothing is missed.
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        startObservingActivation()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    /// Tracks every app that has been frontmost since the last poll.
    private func startObservingActivation() {
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }
            self?.activeBundleIDsSincePoll.insert(bundleID)
        }
    }

    private static func currentFrontmostBundleIDs() -> Set<String> {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return [] }
        return [bundleID]
    }

    /// Suppress recording for a change we made ourselves (AD-6 paste-back).
    func ignoreUpcomingChange() {
        ignoreNextChange = true
        lastChangeCount = pasteboard.changeCount
    }

    private func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        // Snapshot and reset: these are the apps that could have owned the copy.
        let active = activeBundleIDsSincePoll
        activeBundleIDsSincePoll = Self.currentFrontmostBundleIDs()

        if ignoreNextChange {
            ignoreNextChange = false
            return
        }

        guard let text = pasteboard.string(forType: .string) else { return }
        guard ClipboardItem.isRecordable(text) else { return }

        // AD-3: skip when any app frontmost since the last poll is excluded.
        guard !active.contains(where: { service.isExcluded(bundleID: $0) }) else { return }

        queue.async { [weak self] in
            guard let self, let item = self.service.record(text) else { return }
            DispatchQueue.main.async { self.onRecord(item) }
        }
    }
}