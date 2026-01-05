param(
    [Parameter(Mandatory = $false)]
    [string]$PdfaltoDir,

    [Parameter(Mandatory = $false)]
    [string]$VersionTag = "0.4"
)

$ErrorActionPreference = "Stop"

function Get-ScriptRoot() {
    if ($PSScriptRoot -and $PSScriptRoot.Trim().Length -gt 0) { return $PSScriptRoot }
    $p = $MyInvocation.MyCommand.Path
    if ($p -and $p.Trim().Length -gt 0) { return (Split-Path -Parent $p) }
    return (Get-Location).Path
}

$scriptRoot = Get-ScriptRoot
$repoRoot = Resolve-Path (Join-Path $scriptRoot "..\..") | Select-Object -ExpandProperty Path

if (-not $PdfaltoDir -or $PdfaltoDir.Trim().Length -eq 0) {
    $PdfaltoDir = Join-Path $repoRoot "grobid-home\pdfalto\win-64\pdfalto"
}

if (-not (Test-Path -LiteralPath $PdfaltoDir)) {
    throw "Missing pdfalto directory: $PdfaltoDir"
}

Write-Host "Verifying local pdfalto folder..." -ForegroundColor Cyan
# Minimal verification for maintainer packaging:
# - This script's job is to *create* the manifest, so it must not depend on an existing manifest being correct.
# - We only assert that the staged runtime contains the core executable(s).
$pdfaltoExe = Join-Path $PdfaltoDir "pdfalto.exe"
if (-not (Test-Path -LiteralPath $pdfaltoExe)) {
    throw "Missing required file: $pdfaltoExe"
}

$outZip = Join-Path $repoRoot ("grobid-home\pdfalto\win-64\pdfalto-win64-{0}.zip" -f $VersionTag)
if (Test-Path -LiteralPath $outZip) {
    Remove-Item -LiteralPath $outZip -Force
}

Write-Host "Creating zip: $outZip" -ForegroundColor Cyan
Compress-Archive -Path (Join-Path $PdfaltoDir "*") -DestinationPath $outZip -Force

Write-Host "Writing SHA256 manifest..." -ForegroundColor Cyan
$manifest = Join-Path $repoRoot ("grobid-home\pdfalto\win-64\pdfalto-win64-{0}.sha256" -f $VersionTag)
$lines = New-Object System.Collections.Generic.List[string]
Get-ChildItem -LiteralPath $PdfaltoDir -File | Sort-Object Name | ForEach-Object {
    # Get-FileHash is not available in some PowerShell environments; use .NET directly for portability.
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($_.FullName)
        try {
            $bytes = $sha.ComputeHash($stream)
        } finally {
            $stream.Dispose()
        }
    } finally {
        $sha.Dispose()
    }
    $h = ([System.BitConverter]::ToString($bytes) -replace "-", "").ToUpperInvariant()
    $lines.Add("$h  $($_.Name)")
}
Set-Content -LiteralPath $manifest -Value $lines -Encoding ASCII

Write-Host "OK: Created $outZip" -ForegroundColor Green


