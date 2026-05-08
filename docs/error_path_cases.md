# Error Path Case Set

## Goal

Expose high-risk crash paths early and keep failures actionable.

## Cases

1. Native library missing / ABI mismatch
- Expect startup self-check failure with readable reason.
- App must not crash.

2. Corrupted `.mc` / invalid JSON
- Expect parse failure message.
- Existing in-memory session remains valid.

3. `.mcz` missing resource entries
- Import should continue when possible.
- Missing resource should surface warning/error event.

4. Save/export target unavailable
- Save/export returns failure with actionable hint.
- App editing session remains responsive.

5. Export share unavailable
- Export succeeds locally.
- Share failure reports `mcz_export_share_failed` and keeps path available.

6. Audio file missing/unreadable
- Prepare/play reports playback error.
- UI remains usable for non-audio editing.

## Verification

- Automated: widget/controller tests for share and lifecycle paths.
- Manual: run smoke checklist error-path section on at least 2 arm64 devices.
