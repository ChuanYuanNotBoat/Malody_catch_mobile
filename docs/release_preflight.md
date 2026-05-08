# Release Preflight

Run pre-release checks before packaging:

```powershell
./tools/pre_release_check.ps1
```

For cross-repo gate (core + mobile), use:

```powershell
./tools/run_cross_repo_preflight.ps1
```

If native core may be outdated, add:

```powershell
./tools/run_cross_repo_preflight.ps1 -SyncCore
```

This checks:

- `android/key.properties` and required signing fields
- native core `.so` and sync metadata presence
- sync metadata `core_commit` / `ffi_abi_version` consistency with sibling core repo
- `flutter test` pass state

Useful options:

```powershell
# local fast path without signing check
./tools/pre_release_check.ps1 -SkipSigningCheck

# verify built outputs exist
./tools/pre_release_check.ps1 -RequireReleaseArtifacts

# skip core commit/abi consistency check (not recommended for release)
./tools/pre_release_check.ps1 -SkipCoreRepoConsistencyCheck
```
