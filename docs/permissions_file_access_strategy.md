# Android Permissions and File Access Strategy

## Scope

- Platform: Android (arm64 release target)
- File flows: open/save `.mc`, import/export `.mcz`
- Entry points: system picker (`file_picker`) and app workspace directory

## Access Principles

- Prefer SAF/system picker results over hard-coded external paths.
- Do not assume broad storage permission.
- Keep all export/import intermediate files inside app-controlled workspace.
- Treat picker cancellation as user action, not an error.

## Failure Mapping

- User canceled picker:
  - Event: `file_pick_canceled`
  - UX: lightweight info toast/snackbar, no modal error
- Missing file or unreadable URI:
  - Event: `file_open_failed`
  - UX: actionable message ("Select file again")
- Save/export directory unavailable:
  - Event: `file_save_failed` / `mcz_export_failed`
  - UX: actionable message ("Choose another folder")
- Permission denied by ROM/storage provider:
  - Event: `file_access_denied`
  - UX: actionable message ("Grant access in picker / system settings")

## ROM Compatibility Notes

- Validate on at least 2 vendors before release.
- Prioritize regression checks for:
  - open existing `.mc`
  - import `.mcz` with resources
  - export `.mcz` then share

## Release Gate

- Run [`smoke_checklist.md`](./smoke_checklist.md) file-workflow and error-path sections.
