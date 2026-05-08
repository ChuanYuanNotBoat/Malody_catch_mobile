param(
    [string]$CoreRepo = "..\\Malody_catch_core",
    [string]$CoreBuildDir = "build_codex",
    [string]$CoreConfig = "Debug",
    [switch]$SyncCore,
    [switch]$SkipCoreGuard,
    [switch]$SkipCoreBuild,
    [switch]$SkipSigningCheck,
    [switch]$SkipNativeSyncCheck,
    [switch]$SkipCoreRepoConsistencyCheck,
    [switch]$SkipPubGet,
    [switch]$SkipTests,
    [switch]$RequireReleaseArtifacts
)

$ErrorActionPreference = "Stop"

function Require-File([string]$Path, [string]$Message) {
    if (!(Test-Path -LiteralPath $Path)) {
        throw $Message
    }
}

$mobileRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$coreRoot = (Resolve-Path (Join-Path $mobileRoot $CoreRepo)).Path

$coreGuardScript = Join-Path $coreRoot "tools\\run_ffi_symbol_guard.ps1"
$coreSyncScript = Join-Path $mobileRoot "tools\\sync_core_android_so.ps1"
$mobilePreflightScript = Join-Path $mobileRoot "tools\\pre_release_check.ps1"
$artifactRoot = Join-Path $mobileRoot "build\\preflight_artifacts"
$coreArtifactDir = Join-Path $artifactRoot "core"
$summaryPath = Join-Path $artifactRoot "cross_repo_preflight_summary.txt"

Require-File $mobilePreflightScript "Missing mobile preflight script: $mobilePreflightScript"
if (-not $SkipCoreGuard) {
    Require-File $coreGuardScript "Missing core guard script: $coreGuardScript"
}
if ($SyncCore) {
    Require-File $coreSyncScript "Missing core sync script: $coreSyncScript"
}

New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null

if ($SyncCore) {
    Write-Host "[0/2] Syncing core native library..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File $coreSyncScript -CoreRepo $coreRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Core native sync failed."
    }
}

if (-not $SkipCoreGuard) {
    Write-Host "[1/2] Running core FFI symbol guard..."
    $coreArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $coreGuardScript,
        "-BuildDir", $CoreBuildDir,
        "-Config", $CoreConfig,
        "-ArtifactDir", $coreArtifactDir
    )
    if ($SkipCoreBuild) {
        $coreArgs += "-SkipBuild"
    }
    & powershell @coreArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Core FFI symbol guard failed."
    }
}

Write-Host "[2/2] Running mobile pre-release checks..."
$mobileArgs = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $mobilePreflightScript
)
if ($SkipSigningCheck) { $mobileArgs += "-SkipSigningCheck" }
if ($SkipNativeSyncCheck) { $mobileArgs += "-SkipNativeSyncCheck" }
if ($SkipCoreRepoConsistencyCheck) { $mobileArgs += "-SkipCoreRepoConsistencyCheck" }
if ($SkipPubGet) { $mobileArgs += "-SkipPubGet" }
if ($SkipTests) { $mobileArgs += "-SkipTests" }
if ($RequireReleaseArtifacts) { $mobileArgs += "-RequireReleaseArtifacts" }
$mobileArgs += @("-CoreRepo", $coreRoot)

& powershell @mobileArgs
if ($LASTEXITCODE -ne 0) {
    throw "Mobile pre-release check failed."
}

$summaryLines = @(
    "status=PASS",
    "checked_at_utc=$([DateTime]::UtcNow.ToString('o'))",
    "mobile_repo=$mobileRoot",
    "core_repo=$coreRoot",
    "sync_core=$SyncCore",
    "skip_core_guard=$SkipCoreGuard",
    "skip_core_build=$SkipCoreBuild",
    "skip_signing_check=$SkipSigningCheck",
    "skip_native_sync_check=$SkipNativeSyncCheck",
    "skip_core_repo_consistency_check=$SkipCoreRepoConsistencyCheck",
    "skip_pub_get=$SkipPubGet",
    "skip_tests=$SkipTests",
    "require_release_artifacts=$RequireReleaseArtifacts",
    "core_symbol_report=$coreArtifactDir\\ffi_symbol_report.txt"
)
Set-Content -Path $summaryPath -Value $summaryLines -Encoding UTF8

Write-Host "Cross-repo preflight passed."
Write-Host "Core repo:   $coreRoot"
Write-Host "Mobile repo: $mobileRoot"
if (-not $SkipCoreGuard) {
    Write-Host "Core artifact: $coreArtifactDir\\ffi_symbol_report.txt"
}
Write-Host "Summary: $summaryPath"
