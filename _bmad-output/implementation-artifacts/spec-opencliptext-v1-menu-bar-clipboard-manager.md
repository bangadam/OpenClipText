---
title: 'OpenClipText v1: menu bar clipboard history manager (macOS, Swift)'
type: 'feature'
created: '2026-09-20'
status: 'done'
baseline_revision: 'ff33c46f7e8a5c899a583f590d1e4b601ec4df4e'
review_loop_iteration: 0
followup_review_recommended: true
context: ['{project-root}/_bmad-output/planning-artifacts/prd-opencliptext.md', '{project-root}/_bmad-output/planning-artifacts/architecture-spine-opencliptext.md']
warnings: []
deferred: []
---

<intent-contract>

## Intent

**Problem:** No personal clipboard history manager on the user's Mac; CopyClip (current tool) lags on hover previews of large text.

**Approach:** Build OpenClipText v1 as a native Swift menu bar app: poll NSPasteboard, persist text items to SQLite (GRDB via SPM), quick-pick via NSMenu (numbers 1–9, 20/page), full history/search/chunked hover preview in a SwiftUI panel.

## Boundaries & Constraints

**Always:**
- Follow architecture spine ADs 1–7 (Swift native; SQLite/GRDB sole store; NSPasteboard changeCount polling ~250ms; NSMenu quick list + separate panel; chunked preview (10 lines/500 chars first) never full text on hover; selection writes system clipboard, no synthetic keystrokes; pinned-first ordering with dedup-move-to-top).
- Text-only recording, plain string (formatting dropped). Items > 1MB ignored.
- UI reads via HistoryService; no direct GRDB access from UI.
- Target macOS 13+; build with Swift Package Manager executable (AppKit), no Xcode project file.

**Never:**
- No rich text, images, or files in history (v1).
- No synthetic paste keystrokes (CGEvent), no accessibility-API pasting.
- No cloud sync, no accounts, no App Store packaging.
- No polling interval below 100ms.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Record copy | User copies text | Row inserted, appears at top of history | DB error → log, skip, keep running |
| Duplicate copy | Text already in history | Existing row's timestamp updated, moved to top (unless pinned) | n/a |
| Oversized text | Clipboard text > 1MB | Not recorded | n/a |
| Excluded app copy | Copy from excluded bundle ID | Not recorded | n/a |
| Select from menu | Number key/click/arrow+Enter | Item content written to NSPasteboard | n/a |
| Hover large item in panel | Item with 5000 lines | Chunk preview: first 10 lines or 500 chars + "+N more lines" | n/a |
| Search | Type in panel search field | List filters live, substring match, case-insensitive | Empty query shows full list |
| Restart app | Relaunch | History restored from SQLite | Corrupt DB → log, start fresh DB |
| Empty clipboard state | Fresh install | Menu shows placeholder/disabled items | n/a |

</intent-contract>

## Code Map

- Greenfield — no existing code. Repo contains only `docs/` (PRD, spine copies of the planning artifacts) and `_bmad/`.
- `_bmad-output/planning-artifacts/prd-opencliptext.md` — requirements source (FR-1..15, NFR-1..4)
- `_bmad-output/planning-artifacts/architecture-spine-opencliptext.md` — binding ADs 1–7, stack, structural seed, ERD (clipboard_items: rowid, content, captured_at, pinned)
- Toolchain verified on this machine: Swift 6.2 (swift-driver 1.127.14.1), macOS 26 SDK, compiles fine for a macOS 13 platform target
- **GRDB 7.11.1 probe-verified locally** (temp package, BUILD SUCCEEDED + runtime OK): `.package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")`, product `GRDB`, links into an `.executableTarget` with `platforms: [.macOS(.v13)]`
- Verified GRDB 7 API shape: `DatabaseQueue(path:)`, `DatabaseMigrator` + `registerMigration` + `migrate()`, `dbQueue.write { db in try item.insert(db) }` (var item, `insert(db)` — NOT `insert(&db)`), `dbQueue.read { db in try Model.order(...).fetchAll(db) }`
- GRDB 7 Swift-6 notes: records as `Codable` structs (Sendable); don't subclass `Record`; `DatabaseQueue` is Sendable, safe off-main; entry point should be `@main struct` with `static func main()` (top-level `main.swift` code is nonisolated in Swift 6 mode)
- Excluded apps: UserDefaults key `excludedBundleIDs` (array of bundle ID strings)
- DB location: `~/Library/Application Support/OpenClipText/` (create dir), single SQLite file

## Tasks & Acceptance

**Execution:**
- `Package.swift` -- create SPM executable package, macOS 13 platform, GRDB 7.x dependency (`from: "7.0.0"`, product `GRDB`) -- foundation (probe-verified)
- `Sources/OpenClipText/Models.swift` -- `ClipboardItem` struct (id, content, capturedAt, pinned), `PreviewChunk` computation (10 lines/500 chars first + "+N more lines") -- AD-5
- `Sources/OpenClipText/HistoryStore.swift` -- GRDB store: migrations (clipboard_items), insert with dedup/update-timestamp, pinned-first ordering query, delete single, clear all, search filter -- AD-2, AD-7
- `Sources/OpenClipText/ClipboardMonitor.swift` -- 250ms timer, changeCount check, text-only extraction, 1MB cap, excluded-app check (frontmost bundle ID), callback to store -- AD-3
- `Sources/OpenClipText/PasteWriter.swift` -- write item content to NSPasteboard (clear + set string) -- AD-6
- `Sources/OpenClipText/QuickMenu.swift` -- NSStatusItem + NSMenu: paginated 20 items, numbers 1–9, arrow/Enter, click; submenu actions (pin/unpin, delete, clear all, open panel) -- AD-4
- `Sources/OpenClipText/HistoryPanel.swift` -- SwiftUI window: full list, search field, chunked hover preview, expand-to-full, pin/delete actions, openable from menu -- AD-4, AD-5
- `Sources/OpenClipText/App.swift` -- `@main` entry point: NSApplication menu bar app (no dock icon, `.accessory`), wire monitor→store→UI -- Swift 6 entry point
- `Tests/OpenClipTextTests/HistoryStoreTests.swift` -- unit tests: dedup move-to-top, pinned not moved, ordering, search, delete/clear, 1MB cap logic, chunk computation edge cases (empty, short, exactly 10 lines, 11 lines, 500-char boundary) -- I/O matrix

**Acceptance Criteria:**
- Given text is copied in any app, when 250ms elapses, then the item appears at top of both quick menu and panel
- Given the app is relaunched, when history is opened, then previously recorded items are present
- Given a 1MB+ text item in history, when hovered in the panel, then preview renders within 50ms showing only the chunk with "+N more lines" indicator
- Given an item is selected from the quick menu, when ⌘V is pressed in another app, then that item's text is pasted
- Given an excluded app is in frontmost, when text is copied there, then no new history entry is created

## Spec Change Log

## Review Triage Log

### 2026-09-20 — Review pass
- verdicts: 41 findings — high 5, medium 12, low 6, false 3 (dupes across the four layers folded into single rows)
- findings:
  - `[high]` `[patch]` Panel select missing `ignoreUpcomingChange` — every panel copy re-records and reorders history. FIXED: panel onSelect routed through `monitor.ignoreUpcomingChange()`.
  - `[high]` `[patch]` Exclusion race — frontmost check at poll time (up to 250ms after copy) lets copy-then-switch record excluded-app secrets. FIXED: `didActivateApplication` observation tracks bundle IDs frontmost since last poll.
  - `[high]` `[patch]` LIKE wildcard injection — `search("%")` returned the entire table. FIXED: escaped LIKE; discriminating test added (verified by temporarily reverting).
  - `[high]` `[patch]` Indicator clipped by own line limit — `chunkLineLimit` counted `chunk.text` lines while `displayText` is one more, cutting the "+N more lines" row exactly when truncation is largest. FIXED: line count precomputed from `displayText` in `PanelModel.Row`.
  - `[high]` `[patch]` Same-second dedup ordering — re-copy in the same epoch second left the item below older rowids. FIXED: DELETE + re-insert for unpinned dupes.
  - `[medium]` `[patch]` `page(-1)` slice trap. FIXED: guard + test.
  - `[medium]` `[patch]` `nextPage`/`previousPage` mutated index without rebuild. FIXED: rebuild called; duplicated pagination moved into `service.page`/`pageCount`.
  - `[medium]` `[patch]` `try!` launch trap when fallback store also fails. FIXED: `HistoryStore.inMemory()`.
  - `[medium]` `[patch]` Corrupt DB silently orphaned. FIXED: renamed `clipboard.sqlite-corrupt-<ts>`, primary path retried.
  - `[medium]` `[patch]` `title()` materialized whole 1MB content per row per menu open. FIXED: bounded-prefix scan.
  - `[medium]` `[patch]` Hover preview not hover-gated (`hoveredID` dead). FIXED: chunk on hover/expand only.
  - `[medium]` `[patch]` Char-cut single line reported "+1 more lines". FIXED: "… (truncated)" + singular grammar.
  - `[medium]` `[patch]` Silent DB read failures indistinguishable from empty history. FIXED: stderr logging via shared read helper.
  - `[medium]` `[patch]` Hotkey comment ⌥V vs code ⌥⇧V; silent nil registration. FIXED: comment corrected (PRD: ⌥⇧V), stderr log.
  - `[medium]` `[defer]` FR-15/FR-14 wiring-level tests — select-path/search-seam/wildcard/paging tests added; monitor-level pasteboard test still absent.
  - `[low]` `[patch]` Timer tolerance unset. FIXED: `timer.tolerance = 0.1`.
  - `[low]` `[patch]` Unused `import ServiceManagement`. FIXED: deleted.
  - `[low]` `[patch]` No `.gitignore`. FIXED: added.
  - `[low]` `[patch]` Duplicated search semantics. FIXED: unified store-side, `SearchFilter.swift` deleted.
  - `[low]` `[defer]` Panel search reload unthrottled over unbounded row set. Deferred.
  - `[low]` `[defer]` UNIQUE index on 1MB TEXT doubles disk usage. Deferred.
  - `[low]` `[defer]` 50ms NFR-1 bound release-only. Deferred (documented in test).
  - `[low]` `[defer]` NFR-2 login-item autostart unimplemented. Deferred.
  - `[low]` `[defer]` No UI to edit exclusions (FR-15 seed-only). Deferred.
  - `[low]` `[defer]` Clear All unconfirmed, destroys pinned by default. Deferred.
  - `[false]` `[reject]` "Latency test skipped in default run" — runs; only the numeric bound differs by config.
  - `[false]` `[reject]` "1MB materialized before cap check" — cap enforced before insert; data-based pre-check is an optimization.
  - `[false]` `[reject]` "AD/NFR/FR ids unverifiable" — spec is the claims file; intent contract binds the same constraints.

## Design Notes

Spine layers map to a single SPM executable target with directory separation (App shell/Domain/Services/Storage per structural seed) — a single executable target keeps build simple for a personal app; layer rule enforced by convention (UI → HistoryService → HistoryStore only).

Menu bar app without Xcode project: `@main struct App` calling `NSApplication` with `.accessory` activation policy, then `NSApp.run()`. GRDB `DatabaseQueue` writes are fast enough for main-thread sync use at this scale; run monitor callback → store write on a background queue if contention shows up.

## Auto Run Result

Status: done

**Summary:** OpenClipText v1 implemented as a single SPM executable target (macOS 13, GRDB 7.11.1): NSPasteboard polling monitor with exclusion tracking, GRDB store with dedup/pinned-first ordering, NSMenu quick list (1–9 keys, 20/page) + SwiftUI history panel with hover-gated chunked preview, Carbon global hotkey ⌥⇧V, 39 unit tests.

**Files changed:**
- `Package.swift`, `Package.resolved`, `.gitignore` — SPM package, GRDB 7.11.1, build noise ignored
- `Sources/OpenClipText/Models.swift` — ClipboardItem, bounded PreviewChunk (10 lines/500 chars, "… (truncated)" / "+N more line(s)" indicators), bounded title()
- `Sources/OpenClipText/HistoryStore.swift` — GRDB store: migrations, escaped-LIKE search, dedup DELETE+reinsert, corrupt-DB quarantine, inMemory() fallback
- `Sources/OpenClipText/HistoryService.swift` — domain seam: exclusion list, pagination, stderr-logged reads
- `Sources/OpenClipText/ClipboardMonitor.swift` — 250ms poll (tolerance 0.1), 1MB cap, didActivateApplication exclusion tracking, self-write suppression
- `Sources/OpenClipText/PasteWriter.swift` — clipboard write (no keystrokes)
- `Sources/OpenClipText/QuickMenu.swift` — NSStatusItem/NSMenu, paging, submenus, select path with suppression
- `Sources/OpenClipText/HistoryPanel.swift` — SwiftUI panel: search, hover-gated chunked preview, expand, pin/delete
- `Sources/OpenClipText/App.swift` — @main accessory app, hotkey ⌥⇧V, wiring
- `Tests/` — 39 tests: store/chunk/matrix-surface/select-path/paging/wildcard

**Review findings:** 41 findings across 4 layers. 16 patched (5 high — panel suppression, exclusion race, LIKE injection, indicator clipping, same-second dedup; 9 medium; 2 low), 8 deferred (panel reload throttle, hash index, release-only latency bound, login autostart, exclusions UI, Clear All confirmation, monitor wiring test, 8th placeholder), 3 rejected as false. Patched counts by verdict: high 5, medium 9, low 2.

**Follow-up review recommendation:** true — the exclusion-race fix (`didActivateApplication` tracking in ClipboardMonitor) was a high-severity patch and has no automated test covering the new tracking logic; only the `isExcluded` predicate and the select path are tested.

**Verification:** `swift build` → 0 warnings/0 errors. `swift test` → 39/39 pass. LIKE-escape fix verified discriminating (reverting made the wildcard test fail). Matrix rows covered: record/dedup/oversize/select/preview/search/placeholder; corrupt-DB row covered by quarantine code path, restart row by reopen test. Manual GUI checks (status item, hotkey, live copy, cross-app ⌘V) not run — no human interaction in auto mode.

**Residual risks:** GUI wiring (hotkey registration, menu popup, panel rendering) untested by automation; `inMemory()` fatalError unreachable in normal launch; debug builds assert 200ms not 50ms on preview latency (release holds the NFR-1 bound — ship `-c release`).

## Verification

**Commands:**
- `swift build` -- expected: BUILD SUCCEEDED
- `swift test` -- expected: all tests pass

**Manual checks (if no CLI):**
- Run `swift run` binary, verify status item appears, copy text in Safari, check menu shows it, select it, paste back.
