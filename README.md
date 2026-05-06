# Malody Catch Mobile

Flutter Android client for the Malody Catch editor migration.

The app is intentionally separate from the existing Qt desktop editor. Core
chart-editing behavior is expected to come from the sibling
`Malody_catch_core` repository through `dart:ffi`.

## Desktop Sync Baseline

- Synced desktop editor release target: `desktop main` (`2026-05-05`)
- Source commit from sibling repo `Malody_catch_editor`: `2f60ae6`
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

## Sync Native Library

Use the local helper to rebuild and copy the sibling core `.so`:

```powershell
./tools/sync_core_android_so.ps1
```

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
