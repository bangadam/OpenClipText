# PRD Review — OpenClipText (rubric pass, 2026-09-20)

Reviewer: structural rubric walker (parent run, subagent unavailable). Stakes: hobby/personal, single user, macOS-only.

## Verdict: PASS WITH FIXES

## Findings

**HIGH — FR-7 number keys vs "items terlihat": dropdown CopyClip shows paginated screens (e.g. 20 items/screen) but FR-7 only maps keys 1–9.** Ambiguous whether list is capped at 9 items or paginated. Fix: state pagination behavior explicitly.

**HIGH — FR-9 chunk limits are two different units (10 lines / 500 chars) with no precedence rule.** An engineer must pick one. Fix: state "whichever is smaller" or pick a single unit; leave exact number to implementation.

**MEDIUM — FR-2 duplicate behavior vs FR-8 pinned items not reconciled.** If a duplicate is re-copied, does the moved item unpin? Fix: state pinned items are not moved.

**MEDIUM — NFR-1 hover < 50ms for 1MB text but FR-9 caps preview at ~500 chars; the 1MB bound is really about list rendering + first-line extraction.** Fix: clarify the 1MB bound applies to extraction/rendering path, not full preview.

**MEDIUM — UJ-2 mentions search; FR-14 backs it, but no FR says how search is opened (type-to-filter from the open dropdown?).** Fix: one clause.

**LOW — FR-3 says plain & rich text recorded; everything else treats history as plain text.** Fix: state stored as plain string (formatting dropped) or keep rich — decide.

**LOW — Success metric "CopyClip dihapus" unverifiable by the app itself.** Acceptable for personal stakes; no fix needed.

## Completeness vs scope
Right-sized for hobby/personal. No over-build detected. Not pulled in: data governance, compliance, personas — correctly omitted at this stakes level.

## Coherence
Journeys → FRs trace cleanly. Success metrics and counter-metric coherent. No contradictions found beyond the above.
