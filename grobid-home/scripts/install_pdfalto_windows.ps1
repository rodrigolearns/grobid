param(
    [Parameter(Mandatory = $false)]
    [string]$PdfaltoDir = (Join-Path $PSScriptRoot "..\\pdfalto\\win-64\\pdfalto"),

    [Parameter(Mandatory = $false)]
    [string]$PdfaltoVersionTag = "0.4"
)

$ErrorActionPreference = "Stop"

function Write-Info([string]$msg) {
    Write-Host $msg -ForegroundColor Cyan
}

function Write-Warn([string]$msg) {
    Write-Host $msg -ForegroundColor Yellow
}

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path $Path)) {
        # -Force creates intermediate directories when needed (clean clones might not have win-64/ yet)
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Try-VerifyExisting([string]$Dir) {
    $verify = Join-Path $PSScriptRoot "verify_pdfalto_windows.ps1"
    if (-not (Test-Path $verify)) {
        throw "Missing verifier script: $verify"
    }
    try {
        & $verify -PdfaltoDir $Dir | Out-Null
        return $true
    } catch {
        return $false
    }
}

Write-Info "Ensuring Windows pdfalto is installed and verified..."
Write-Info "Target directory: $PdfaltoDir"

if (Try-VerifyExisting -Dir $PdfaltoDir) {
    Write-Info "OK: pdfalto already matches expected SHA256."
    exit 0
}

Write-Warn "pdfalto binaries are missing or do not match expected SHA256. Downloading official pdfalto $PdfaltoVersionTag release..."

# GitHub API (no auth). If rate-limited, user can retry later or set GITHUB_TOKEN and it will be used automatically.
$headers = @{
    "Accept"     = "application/vnd.github+json"
    "User-Agent" = "grobid-windows-bootstrap"
}
if ($env:GITHUB_TOKEN) {
    $headers["Authorization"] = "Bearer $env:GITHUB_TOKEN"
}

$releaseUrl = "https://api.github.com/repos/kermitt2/pdfalto/releases/tags/$PdfaltoVersionTag"
$release = Invoke-RestMethod -Uri $releaseUrl -Headers $headers -Method Get

if (-not $release -or -not $release.assets) {
    throw "Could not fetch release metadata from $releaseUrl"
}

$asset = $release.assets |
    # Prefer the official "Windows_64bit.zip" naming, but keep a fallback to be robust to minor variations.
    Where-Object { $_.name -match '(?i)windows_64bit\\.zip$' } |
    Select-Object -First 1

if (-not $asset) {
    $asset = $release.assets |
        Where-Object { $_.name -match '(?i)win' -and $_.name -match '(?i)64' -and $_.name -match '(?i)\\.zip$' } |
        Select-Object -First 1
}

if (-not $asset) {
    $names = ($release.assets | ForEach-Object { $_.name }) -join ", "
    throw "Could not find a Windows 64-bit .zip asset in pdfalto release $PdfaltoVersionTag. Assets: $names"
}

$downloadUrl = $asset.browser_download_url
Write-Info "Downloading: $($asset.name)"
Write-Info "From: $downloadUrl"

$tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("grobid-pdfalto-" + [System.Guid]::NewGuid().ToString("N"))
$tmpZip = Join-Path $tmpRoot $asset.name
$tmpExtract = Join-Path $tmpRoot "extract"
Ensure-Dir $tmpRoot
Ensure-Dir $tmpExtract

Invoke-WebRequest -Uri $downloadUrl -Headers $headers -OutFile $tmpZip
Expand-Archive -Path $tmpZip -DestinationPath $tmpExtract -Force

function Find-One([string]$Name) {
    $hits = Get-ChildItem -Path $tmpExtract -Recurse -File -Filter $Name -ErrorAction SilentlyContinue
    if (-not $hits -or $hits.Count -lt 1) {
        throw "Could not find $Name inside downloaded archive."
    }
    return $hits | Select-Object -First 1
}

$pdfaltoExe = Find-One -Name "pdfalto.exe"
$pdfaltoFolder = Split-Path -Parent $pdfaltoExe.FullName

# Ensure companion files come from the SAME folder (avoid mixing 32/64-bit files if both are present in the archive)
$pdfaltoServerExe = Join-Path $pdfaltoFolder "pdfalto_server.exe"
if (-not (Test-Path $pdfaltoServerExe)) {
    throw "Could not find pdfalto_server.exe next to pdfalto.exe inside downloaded archive."
}
$cygwinDll = Join-Path $pdfaltoFolder "cygwin1.dll"
if (-not (Test-Path $cygwinDll)) {
    throw "Could not find cygwin1.dll next to pdfalto.exe inside downloaded archive."
}

# Clean target folder if present but invalid (prevents stale/partial installs from surviving)
if (Test-Path $PdfaltoDir) {
    # Keep .gitkeep (tracked) so bootstrapping doesn't dirty the repo
    Get-ChildItem -Path $PdfaltoDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ine ".gitkeep" } |
        Remove-Item -Force -ErrorAction SilentlyContinue
} else {
    Ensure-Dir $PdfaltoDir
}

# Copy the full runtime bundle (DLLs + exes). Grobid launches the EXE directly and does not set PATH/working dir.
Get-ChildItem -Path $pdfaltoFolder -File |
    ForEach-Object {
        Copy-Item -Force -Path $_.FullName -Destination (Join-Path $PdfaltoDir $_.Name)
    }

# Optional: ensure xpdfrc exists at the expected arch root (grobid-home/pdfalto/win-64/xpdfrc)
$archRoot = Split-Path -Parent $PdfaltoDir
$xpdfrcCandidate = Join-Path $pdfaltoFolder "xpdfrc"
if (-not (Test-Path (Join-Path $archRoot "xpdfrc")) -and (Test-Path $xpdfrcCandidate)) {
    Copy-Item -Force -Path $xpdfrcCandidate -Destination (Join-Path $archRoot "xpdfrc")
}

# Verify
$ok = Try-VerifyExisting -Dir $PdfaltoDir
if (-not $ok) {
    throw "pdfalto was downloaded but failed SHA256 verification. See grobid-home/scripts/verify_pdfalto_windows.ps1 for expected values."
}

Write-Info "OK: pdfalto installed and verified."



