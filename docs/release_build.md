# Android Release Build

## 1) Prepare signing config

1. Copy `android/key.properties.example` to `android/key.properties`.
2. Fill real values:
   - `storeFile`
   - `storePassword`
   - `keyAlias`
   - `keyPassword`

## 2) Sync core native library

```powershell
./tools/sync_core_android_so.ps1
```

Verify metadata file exists after sync:

- `android/app/src/main/jniLibs/arm64-v8a/libmalody_catch_core_ffi.sync.txt`

## 3) Build release artifacts

Build both APK and AAB:

```powershell
./tools/build_android_release.ps1 -Target both
```

Common variants:

```powershell
./tools/build_android_release.ps1 -Target apk
./tools/build_android_release.ps1 -Target aab
./tools/build_android_release.ps1 -Target both -Clean
```

## 4) Expected outputs

- APK: `build/app/outputs/flutter-apk/app-release.apk`
- AAB: `build/app/outputs/bundle/release/app-release.aab`
