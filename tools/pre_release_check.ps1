param(
    [string]$CoreRepo = "..\\Malody_catch_core",
    [switch]$SkipSigningCheck,
    [switch]$SkipNativeSyncCheck,
    [switch]$SkipCoreRepoConsistencyCheck,
    [switch]$SkipPubGet,
    [switch]$SkipTests,
    [switch]$RequireReleaseArtifacts
)

$ErrorActionPreference = "Stop"

function Require-Command([string]$Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (!$cmd) {
        throw "Required command not found in PATH: $Name"
    }
}

function Require-File([string]$Path, [string]$Message) {
    if (!(Test-Path -LiteralPath $Path)) {
        throw $Message
    }
}

function Read-KeyValueFile([string]$Path) {
    $map = @{}
    $lines = Get-Content -LiteralPath $Path
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -eq "" -or $trimmed.StartsWith("#")) {
            continue
        }
        $parts = $trimmed.Split("=", 2)
        if ($parts.Length -eq 2) {
            $map[$parts[0].Trim()] = $parts[1].Trim()
        }
    }
    return $map
}

function Try-ResolvePath([string]$Path) {
    try {
        return (Resolve-Path $Path).Path
    } catch {
        return $null
    }
}

function Read-CoreAbiVersion([string]$CoreRoot) {
    try {
        $ffiCpp = Join-Path $CoreRoot "src\\core\\ffi.cpp"
        if (!(Test-Path -LiteralPath $ffiCpp)) {
            return $null
        }
        $content = Get-Content -Raw -LiteralPath $ffiCpp
        if ($content -match "int32_t\s+mce_ffi_abi_version\s*\(\s*\)\s*\{[^}]*return\s+([0-9]+)\s*;") {
            return $Matches[1]
        }
        return $null
    } catch {
        return $null
    }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$androidDir = Join-Path $repoRoot "android"
$keyPropertiesPath = Join-Path $androidDir "key.properties"
$syncMetaPath = Join-Path $repoRoot "android\app\src\main\jniLibs\arm64-v8a\libmalody_catch_core_ffi.sync.txt"
$soPath = Join-Path $repoRoot "android\app\src\main\jniLibs\arm64-v8a\libmalody_catch_core_ffi.so"
$apkPath = Join-Path $repoRoot "build\app\outputs\flutter-apk\app-release.apk"
$aabPath = Join-Path $repoRoot "build\app\outputs\bundle\release\app-release.aab"
$coreRoot = Try-ResolvePath (Join-Path $repoRoot $CoreRepo)

Require-Command "flutter"

if (-not $SkipSigningCheck) {
    Require-File $keyPropertiesPath "Missing signing file: $keyPropertiesPath"
    $props = Read-KeyValueFile $keyPropertiesPath
    foreach ($key in @("storeFile", "storePassword", "keyAlias", "keyPassword")) {
        if (-not $props.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($props[$key])) {
            throw "Invalid key.properties: missing $key"
        }
    }
    Write-Host "Signing config check passed."
}

if (-not $SkipNativeSyncCheck) {
    Require-File $soPath "Missing native core library: $soPath"
    Require-File $syncMetaPath "Missing native sync metadata: $syncMetaPath"
    $syncMeta = Read-KeyValueFile $syncMetaPath
    foreach ($key in @("core_commit", "ffi_abi_version", "synced_at_utc")) {
        if (-not $syncMeta.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($syncMeta[$key])) {
            throw "Invalid sync metadata: missing $key in $syncMetaPath"
        }
    }
    Write-Host "Native sync check passed."
    Write-Host "  core_commit=$($syncMeta["core_commit"])"
    Write-Host "  ffi_abi_version=$($syncMeta["ffi_abi_version"])"

    if (-not $SkipCoreRepoConsistencyCheck) {
        if ([string]::IsNullOrWhiteSpace($coreRoot)) {
            Write-Warning "Core repo not found for consistency check: $CoreRepo"
        } else {
            $gitCmd = Get-Command git -ErrorAction SilentlyContinue
            if ($gitCmd) {
                $coreHead = (git -C $coreRoot rev-parse HEAD).Trim()
                if ($coreHead -ne $syncMeta["core_commit"]) {
                    throw "Core sync mismatch: sync metadata commit=$($syncMeta["core_commit"]) but core HEAD=$coreHead"
                }
            } else {
                Write-Warning "git not found; skipping core commit consistency check."
            }

            $coreAbi = Read-CoreAbiVersion $coreRoot
            if (-not [string]::IsNullOrWhiteSpace($coreAbi) -and $syncMeta["ffi_abi_version"] -ne $coreAbi) {
                throw "Core ABI mismatch: sync metadata abi=$($syncMeta["ffi_abi_version"]) but core abi=$coreAbi"
            }
            Write-Host "Core repo consistency check passed."
        }
    }
}

Push-Location $repoRoot
try {
    if (-not $SkipPubGet) {
        flutter pub get
    }
    if (-not $SkipTests) {
        flutter test
    }
} finally {
    Pop-Location
}

if ($RequireReleaseArtifacts) {
    Require-File $apkPath "Missing release APK: $apkPath"
    Require-File $aabPath "Missing release AAB: $aabPath"
    Write-Host "Release artifact check passed."
}

Write-Host "Pre-release checks passed."
