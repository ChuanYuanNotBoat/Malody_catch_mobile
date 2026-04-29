# Malody Catch Mobile

Flutter Android client for the Malody Catch editor migration.

The app is intentionally separate from the existing Qt desktop editor. Core
chart-editing behavior is expected to come from the sibling
`Malody_catch_core` repository through `dart:ffi`.

## Current State

- Android-only Flutter project scaffold.
- Initial Dart FFI binding in `lib/core/native_core.dart`.
- `CoreSession` wrapper and startup smoke page are available in
  `lib/core/core_session.dart` and `lib/main.dart`.
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
