# Lifecycle Playback Policy

## Rule

- If app goes background while playback is `playing`, pause automatically.
- On resume, auto-resume only when the previous pause was lifecycle-triggered.
- Manual pause must not auto-resume on foreground return.

## Current Hooks

- Pause hook: `ChartDocumentController.handleAppPaused()`
- Resume hook: `ChartDocumentController.handleAppResumed()`
- App state bridge: `MobileEditorPage.didChangeAppLifecycleState`

## Regression Checks

- Background while playing -> paused + draft saved
- Foreground after lifecycle pause -> resumed
- Manual pause then background/foreground -> remains paused
