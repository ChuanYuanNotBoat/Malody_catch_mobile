# Malody Catch Mobile

Flutter Android client for the Malody Catch editor migration.

The app is intentionally separate from the existing Qt desktop editor. Core
chart-editing behavior is expected to come from the sibling
`Malody_catch_core` repository through `dart:ffi`.

## Desktop Sync Baseline

- Synced desktop editor release target: `desktop main` (`2026-05-09`)
- Source commit from sibling repo `Malody_catch_editor`: `f3088da`
- Mobile startup path currently validates core ABI compatibility before enabling
  editing actions.

## Current State

- Android-focused Flutter editor page with note/BPM/meta editing surface.
- Dart FFI binding (ABI=4 compatible) is implemented in
  `lib/core/native_core.dart`.
- `CoreSession` + `ChartDocumentController` are wired in
  `lib/core/core_session.dart` and `lib/core/chart_document_controller.dart`.
- File entry now uses system picker (`file_picker`) for open/save/export.
- `.mcz` import flow is enabled:
  secure unzip -> chart selection -> referenced asset copy -> workspace rewrite.
- `.mcz` export flow is enabled:
  save latest `.mc` -> package `0/<chart>.mc` + referenced assets only.
- Main-audio playback link is enabled with `just_audio`:
  play/pause/seek/rate + canvas/density playhead sync.
- Save flow supports both direct overwrite (known path) and
  directory-pick + filename input (new file).
- Android `arm64-v8a` native library is bundled at
  `android/app/src/main/jniLibs/arm64-v8a/libmalody_catch_core_ffi.so`.

## Desktop Parity Scope (Feature / GUI / Interaction)

- Reference desktop baseline:
  `Malody_catch_editor@f3088da` (`desktop main`, `2026-05-09`, sync scope: `2f60ae6..f3088da`)
- Feature parity (current): edit loop, `.mc/.mcz` loop, playback loop.
- GUI parity (current): desktop-like wide layout
  (tools/canvas/inspector + density bar) and compact mobile layout.
- Interaction parity (current): tap place/select, drag move, box select,
  pinch zoom, long-press context menu, grid/time-division workflows.
- Out of scope in this repo: desktop plugin system and desktop Qt panel stack.
- Ongoing parity tracking lives in `TODO.md` (`MOB-M1-007/008/009/M3-003`).

## Sync Native Library

Use the local helper to rebuild and copy the sibling core `.so`:

```powershell
./tools/sync_core_android_so.ps1
```

## Build Release (Android)

```powershell
./tools/build_android_release.ps1 -Target both
```

Pre-release checks:

```powershell
./tools/pre_release_check.ps1
```

This includes sync metadata vs sibling core commit/ABI consistency checks.

Cross-repo preflight (core + mobile):

```powershell
./tools/run_cross_repo_preflight.ps1
```

Cross-repo preflight with forced core `.so` sync:

```powershell
./tools/run_cross_repo_preflight.ps1 -SyncCore
```

- Release build guide:
  `docs/release_build.md`
- Preflight guide:
  `docs/release_preflight.md`
- Cross-repo preflight guide:
  `docs/cross_repo_preflight.md`
- Smoke checklist:
  `docs/smoke_checklist.md`
- Permissions/file access strategy:
  `docs/permissions_file_access_strategy.md`
- Desktop-to-mobile mapping:
  `docs/desktop_to_mobile_mapping.md`
- Gesture conflict rules:
  `docs/gesture_conflict_rules.md`
- Desktop operation replay checklist:
  `docs/desktop_operation_replay_checklist.md`
- Error-path case set:
  `docs/error_path_cases.md`
- Lifecycle playback policy:
  `docs/lifecycle_playback_policy.md`

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.


