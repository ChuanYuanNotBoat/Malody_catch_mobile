# Desktop to Mobile Mapping

Reference baseline: `Malody_catch_editor@f3088da` (`desktop main`, `2026-05-09`)

## Mode and Panel Mapping

- Desktop left tools -> Mobile top toolbar and action row
- Desktop center canvas -> Mobile chart canvas
- Desktop right inspector -> Mobile metadata/BPM tabs and dialogs
- Desktop density bar -> Mobile right-side density bar

## High-Frequency Action Mapping

- Add note/rain -> Tap canvas in selected mode
- Select/multi-select -> Tap note / box select drag
- Move -> Drag selected note(s)
- Delete -> Context menu delete or batch delete action
- Copy/Paste -> Toolbar copy/paste actions
- Undo/Redo -> Toolbar undo/redo actions
- Save/Open/Export -> App bar file actions

## Error Keyword Alignment

- ABI mismatch -> `abi_mismatch`
- Session invalid -> `invalid_session`
- Invalid argument -> `invalid_argument`
- File open/save failure -> `file_open_failed` / `file_save_failed`
- Export/share failure -> `mcz_export_failed` / `mcz_export_share_failed`

## 3-Step Discoverability Rule

- A desktop user should find equivalent mobile action within 3 taps:
  - action category
  - concrete action
  - confirmation (if destructive)

