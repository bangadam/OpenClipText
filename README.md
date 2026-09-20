# OpenClipText

A native macOS menu bar clipboard history manager. Personal CopyClip replacement, built because hover previews of large text lag in the original.

**The differentiator:** hovering a 1MB text item renders a bounded preview chunk (first 10 lines / 500 chars, whichever hits first) in under 50ms — never the full text.

## Features

- **Automatic recording** — polls the system pasteboard every 250ms; every text copy lands in history. Plain text only (formatting dropped), items over 1MB ignored.
- **Quick menu** — click the menu bar icon (or press `⌥⇧V` globally). Number keys `1–9` select the visible items directly, arrow keys + Enter or click work too. Paginated 20 items per page.
- **History panel** — full history window with live search, hover preview (chunked), expand-to-full, pin, delete, clear all.
- **Pins** — pinned items stay at the top and never get pushed down by new copies.
- **Dedup** — re-copying existing text moves it to the top, never creates a duplicate entry.
- **App exclusions** — copies from excluded apps (password managers etc.) are never recorded. Seeded with 1Password / Keychain Access; edit via:

  ```bash
  defaults write <bundle-id-of-app> excludedBundleIDs -array "com.example.app"
  ```

  (run as the same user; the key lives in the app's `defaults` domain `OpenClipText` — see note below)
- **Persistence** — history lives in SQLite at `~/Library/Application Support/OpenClipText/clipboard.sqlite` and survives restarts.

## Build & install

Requires Xcode 15+ (Swift toolchain 6.1+) on macOS 13+.

```bash
git clone git@github.com:bangadam/OpenClipText.git
cd OpenClipText

# Release build — required for the <50ms preview guarantee
swift build -c release

# Run it
swift run -c release
```

The binary lands at `.build/release/OpenClipText`. Copy it wherever you like:

```bash
mkdir -p ~/bin && cp .build/release/OpenClipText ~/bin/
~/bin/OpenClipText &
```

### Make it a proper menu bar app (optional)

A bare executable has no bundle, so macOS treats it as a plain process (the menu bar icon still works — activation is set at runtime). To get a launchable, double-clickable app:

```bash
mkdir -p OpenClipText.app/Contents/MacOS
cp .build/release/OpenClipText OpenClipText.app/Contents/MacOS/
cat > OpenClipText.app/Contents/Info.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>    <string>OpenClipText</string>
    <key>CFBundleIdentifier</key>    <string>dev.bangadam.OpenClipText</string>
    <key>CFBundleName</key>          <string>OpenClipText</string>
    <key>LSUIElement</key>           <true/>
</dict>
</plist>
EOF
open OpenClipText.app
```

`LSUIElement` keeps it out of the Dock. Move `OpenClipText.app` to `/Applications` to keep it.

### Run at login

System Settings → General → Login Items → add `OpenClipText.app`. (In-app `SMAppService` toggle is not implemented in v1.)

## Tests

```bash
swift test
```

## Architecture

Single SPM executable target, layered by convention (App shell → Domain/HistoryService → Services → GRDB store). See `docs/architecture/` for the binding architecture decisions (AD-1…AD-7) and `docs/prds/` for the product spec.

| Choice | Why |
| --- | --- |
| Swift + AppKit/SwiftUI, SPM only | Native, no Xcode project file, no web views |
| SQLite via GRDB 7 | Sole store of history; indexed search and dedup at scale |
| NSPasteboard changeCount polling (250ms) | The only reliable clipboard-change mechanism on macOS |
| Selection writes the system clipboard | No synthetic keystrokes — you paste with `⌘V` yourself |
| Chunked preview computed at read time | Hover never receives full text; render time bounded by construction |

## Status

v1 — personal use. No cloud sync, no accounts, no App Store packaging. Text-only history (images/files are out of scope for v1).
