param(
    [ValidateSet("apk", "aab", "both")]
    [string]$Target = "both",
    [switch]$Clean,
    [switch]$SkipPubGet
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path "..").Path
$androidDir = Join-Path $repoRoot "android"
$keyProperties = Join-Path $androidDir "key.properties"
$keyPropertiesExample = Join-Path $androidDir "key.properties.example"
$syncMeta = Join-Path $repoRoot "android\app\src\main\jniLibs\arm64-v8a\libmalody_catch_core_ffi.sync.txt"

function Require-Command([string]$Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (!$cmd) {
        throw "Required command not found in PATH: $Name"
    }
}

function Require-KeyProperties([string]$Path) {
    if (!(Test-Path -LiteralPath $Path)) {
        throw "Missing Android release signing file: $Path`nCreate it from: $keyPropertiesExample"
    }
    $content = Get-Content -LiteralPath $Path
    $required = @("storeFile=", "storePassword=", "keyAlias=", "keyPassword=")
    foreach ($entry in $required) {
        if (-not ($content | Where-Object { $_.Trim().StartsWith($entry) })) {
            throw "Missing signing property in key.properties: $entry"
        }
    }
}

Require-Command "flutter"
Require-KeyProperties -Path $keyProperties

if (!(Test-Path -LiteralPath $syncMeta)) {
    Write-Warning "Core sync metadata not found: $syncMeta"
    Write-Warning "If native core was updated, run: ./tools/sync_core_android_so.ps1"
}

Push-Location $repoRoot
try {
    if ($Clean) {
        flutter clean
    }
    if (-not $SkipPubGet) {
        flutter pub get
    }

    switch ($Target) {
        "apk" {
            flutter build apk --release
        }
        "aab" {
            flutter build appbundle --release
        }
        "both" {
            flutter build apk --release
            flutter build appbundle --release
        }
    }

    Write-Host "Release build finished."
    Write-Host "APK: $repoRoot\build\app\outputs\flutter-apk\app-release.apk"
    Write-Host "AAB: $repoRoot\build\app\outputs\bundle\release\app-release.aab"
} finally {
    Pop-Location
}
