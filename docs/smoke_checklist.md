# Mobile Smoke Checklist (Release)

## Device baseline

- At least 2 Android arm64 devices (different vendors preferred)
- Fresh install of release APK

## Startup and core handshake

- [ ] App launches successfully.
- [ ] Startup self-check passes.
- [ ] No ABI mismatch error.

## File workflow

- [ ] Open `.mc` succeeds.
- [ ] Edit note + save `.mc` + reopen keeps data consistent.
- [ ] Import `.mcz` succeeds (resources resolved).
- [ ] Export `.mcz` succeeds and share sheet can be opened.

## Playback workflow

- [ ] Play / pause / stop work.
- [ ] Seek beat updates playhead correctly.
- [ ] Playback rate switch works.
- [ ] App pause (background) auto-pauses playback.
- [ ] Return to foreground resumes only when pause was lifecycle-triggered.

## Error-path sanity

- [ ] Missing/invalid file shows readable error instead of crash.
- [ ] Missing audio path shows playback error instead of crash.
- [ ] Permission denial path gives recoverable hint.

## Final release gate

- [ ] Build produced signed `app-release.apk`.
- [ ] Build produced signed `app-release.aab`.
- [ ] Test notes include device model + Android version + test date.
