param(
    [string]$CoreRepo = "..\\Malody_catch_core",
    [string]$NdkVersion = "26.3.11579264",
    [string]$Abi = "arm64-v8a",
    [int]$AndroidApi = 24
)

$ErrorActionPreference = "Stop"

$mobileRoot = (Resolve-Path "..").Path
$coreRoot = (Resolve-Path $CoreRepo).Path
$ndkRoot = "C:\\Users\\boatnotcy\\AppData\\Local\\Android\\Sdk\\ndk\\$NdkVersion"
$toolchain = Join-Path $ndkRoot "build\\cmake\\android.toolchain.cmake"
$buildDir = Join-Path $coreRoot "build_android_$Abi"
$targetSo = Join-Path $coreRoot "$([System.IO.Path]::GetFileName($buildDir))\\libmalody_catch_core_ffi.so"
$targetSoFinal = Join-Path $mobileRoot "android\\app\\src\\main\\jniLibs\\$Abi\\libmalody_catch_core_ffi.so"

if (!(Test-Path $toolchain)) {
    throw "Android NDK toolchain not found: $toolchain"
}

cmake -S $coreRoot -B $buildDir -G Ninja `
    -DMCE_BUILD_QT_TRANSITIONAL=OFF `
    -DBUILD_TESTING=OFF `
    -DCMAKE_TOOLCHAIN_FILE=$toolchain `
    -DANDROID_ABI=$Abi `
    -DANDROID_PLATFORM=$AndroidApi `
    -DCMAKE_BUILD_TYPE=Release

cmake --build $buildDir --target malody_catch_core_ffi

if (!(Test-Path $targetSo)) {
    throw "Built .so not found: $targetSo"
}

$jniDir = Join-Path $mobileRoot "android\\app\\src\\main\\jniLibs\\$Abi"
New-Item -ItemType Directory -Force $jniDir | Out-Null
Copy-Item -Force $targetSo $targetSoFinal

$coreCommit = "unknown"
try {
    $coreCommit = (git -C $coreRoot rev-parse HEAD).Trim()
} catch {
    # Best-effort only.
}

$ffiAbiVersion = "unknown"
try {
    $ffiCpp = Join-Path $coreRoot "src\\core\\ffi.cpp"
    $ffiContent = Get-Content -Raw -Path $ffiCpp
    if ($ffiContent -match "int32_t\s+mce_ffi_abi_version\s*\(\s*\)\s*\{[^}]*return\s+([0-9]+)\s*;") {
        $ffiAbiVersion = $Matches[1]
    }
} catch {
    # Best-effort only.
}

$syncMetaPath = Join-Path $jniDir "libmalody_catch_core_ffi.sync.txt"
$syncMeta = @(
    "core_repo=$coreRoot",
    "core_commit=$coreCommit",
    "ffi_abi_version=$ffiAbiVersion",
    "android_abi=$Abi",
    "android_api=$AndroidApi",
    "ndk_version=$NdkVersion",
    "source_so=$targetSo",
    "target_so=$targetSoFinal",
    "synced_at_utc=$([DateTime]::UtcNow.ToString('o'))"
)
Set-Content -Path $syncMetaPath -Value $syncMeta -Encoding UTF8

Write-Host "Synced native core:"
Write-Host "  from: $targetSo"
Write-Host "  to:   $targetSoFinal"
Write-Host "Sync metadata:"
Write-Host "  file: $syncMetaPath"
Write-Host "  commit: $coreCommit"
Write-Host "  abi: $ffiAbiVersion"
