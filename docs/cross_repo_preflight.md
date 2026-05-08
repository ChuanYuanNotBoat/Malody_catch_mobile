# Cross-Repo Preflight

Run one command from `Malody_catch_mobile` to validate both repos:

```powershell
./tools/run_cross_repo_preflight.ps1
```

What it runs:

1. `Malody_catch_core/tools/run_ffi_symbol_guard.ps1`
2. `Malody_catch_mobile/tools/pre_release_check.ps1`

And in step 2, by default it validates sync metadata against sibling core HEAD:

- `core_commit` must match core `git rev-parse HEAD`
- `ffi_abi_version` must match core `mce_ffi_abi_version()` source

Useful local fast mode:

```powershell
./tools/run_cross_repo_preflight.ps1 `
  -SkipSigningCheck `
  -SkipNativeSyncCheck `
  -SkipPubGet
```

Force `.so` sync before checks:

```powershell
./tools/run_cross_repo_preflight.ps1 -SyncCore
```

If you only want mobile checks:

```powershell
./tools/run_cross_repo_preflight.ps1 -SkipCoreGuard
```

Skip core consistency check (only for local troubleshooting):

```powershell
./tools/run_cross_repo_preflight.ps1 -SkipCoreRepoConsistencyCheck
```

Output artifacts:

- `build/preflight_artifacts/core/ffi_symbol_report.txt`
- `build/preflight_artifacts/cross_repo_preflight_summary.txt`
