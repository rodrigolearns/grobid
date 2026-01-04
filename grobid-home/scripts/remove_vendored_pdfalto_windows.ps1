param(
    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

$ErrorActionPreference = "Continue"

function Write-Info([string]$msg) {
    Write-Host $msg -ForegroundColor Cyan
}

function Write-Warn([string]$msg) {
    Write-Host $msg -ForegroundColor Yellow
}

function Write-Err([string]$msg) {
    Write-Host $msg -ForegroundColor Red
}

function Should-KeepFile([System.IO.FileInfo]$File) {
    if ($File.Name -ieq "xpdfrc") { return $true }
    if ($File.Name -ieq ".gitkeep") { return $true }
    return $false
}

$pdfaltoRoot = Join-Path $PSScriptRoot "..\pdfalto"
$windowsArches = @("win-64", "win-32")

Write-Info "Removing vendored Windows pdfalto binaries/DLLs (keeping xpdfrc + .gitkeep)..."
Write-Info "Pdfalto root: $pdfaltoRoot"
if ($DryRun) {
    Write-Warn "DRY RUN mode: no files will be deleted."
}

$failed = New-Object System.Collections.Generic.List[string]
$deleted = New-Object System.Collections.Generic.List[string]

foreach ($arch in $windowsArches) {
    $archDir = Join-Path $pdfaltoRoot $arch
    if (-not (Test-Path -LiteralPath $archDir)) {
        Write-Warn "Skipping missing directory: $archDir"
        continue
    }

    $files = Get-ChildItem -LiteralPath $archDir -Recurse -File -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        if (Should-KeepFile -File $f) {
            continue
        }

        if ($DryRun) {
            Write-Host ("WOULD DELETE: {0}" -f $f.FullName)
            continue
        }

        try {
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
            $deleted.Add($f.FullName)
        } catch {
            $failed.Add($f.FullName)
            Write-Warning ("FAILED: {0} :: {1}" -f $f.FullName, $_.Exception.Message)
        }
    }
}

Write-Host ""
Write-Info ("Deleted files: {0}" -f $deleted.Count)
if ($failed.Count -gt 0) {
    Write-Err ("Failed deletions: {0}" -f $failed.Count)
}

Write-Host ""
Write-Info "--- Remaining unexpected files under win-64/win-32 (after delete attempt) ---"
$remaining = @()
foreach ($arch in $windowsArches) {
    $archDir = Join-Path $pdfaltoRoot $arch
    if (-not (Test-Path -LiteralPath $archDir)) { continue }
    $remaining += Get-ChildItem -LiteralPath $archDir -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { -not (Should-KeepFile -File $_) } |
        Select-Object -ExpandProperty FullName
}

if ($remaining.Count -gt 0) {
    $remaining | Sort-Object
} else {
    Write-Host "(none)"
}

Write-Host ""
Write-Info "--- Failed deletions (exceptions thrown) ---"
if ($failed.Count -gt 0) {
    $failed | Sort-Object
} else {
    Write-Host "(none)"
}

if (($failed.Count -gt 0) -or ($remaining.Count -gt 0)) {
    exit 1
}

exit 0


