param(
    [Parameter(Mandatory = $false)]
    [string]$PdfaltoDir,

    [Parameter(Mandatory = $false)]
    [string]$PdfaltoVersionTag = "0.4"
)

$ErrorActionPreference = "Stop"

function Get-ScriptRoot() {
    if ($PSScriptRoot -and $PSScriptRoot.Trim().Length -gt 0) { return $PSScriptRoot }
    $p = $MyInvocation.MyCommand.Path
    if ($p -and $p.Trim().Length -gt 0) { return (Split-Path -Parent $p) }
    return (Get-Location).Path
}

function Write-Info([string]$msg) { Write-Host $msg -ForegroundColor Cyan }
function Write-Warn([string]$msg) { Write-Host $msg -ForegroundColor Yellow }

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Invoke-WebRequestCompat {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $false)][hashtable]$Headers,
        [Parameter(Mandatory = $false)][string]$OutFile
    )
    $params = @{ Uri = $Uri; Headers = $Headers }
    if ($OutFile) { $params["OutFile"] = $OutFile }
    if ((Get-Command Invoke-WebRequest).Parameters.ContainsKey("UseBasicParsing")) {
        $params["UseBasicParsing"] = $true
    }
    Invoke-WebRequest @params
}

function Try-VerifyExisting([string]$Dir) {
    $verify = Join-Path (Get-ScriptRoot) "verify_pdfalto_windows.ps1"
    if (-not (Test-Path -LiteralPath $verify)) {
        throw "Missing verifier script: $verify"
    }
    try {
        & $verify -PdfaltoDir $Dir | Out-Null
        return $true
    } catch {
        return $false
    }
}

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$scriptRoot = Get-ScriptRoot
if (-not $PdfaltoDir -or $PdfaltoDir.Trim().Length -eq 0) {
    $PdfaltoDir = Join-Path $scriptRoot "..\\pdfalto\\win-64\\pdfalto"
}

Write-Info "Ensuring Windows pdfalto is installed and verified..."
Write-Info "Target directory: $PdfaltoDir"

if (Try-VerifyExisting -Dir $PdfaltoDir) {
    Write-Info "OK: pdfalto already matches expected SHA256."
    exit 0
}

Write-Warn "pdfalto binaries are missing or do not match expected SHA256. Downloading official pdfalto $PdfaltoVersionTag release..."

$headers = @{ "User-Agent" = "grobid-windows-bootstrap" }
if ($env:GITHUB_TOKEN) { $headers["Authorization"] = "Bearer $env:GITHUB_TOKEN" }

function Resolve-DownloadUrl([string]$Tag) {
    # Some environments block api.github.com and/or strip GitHub HTML in a way that hides asset links.
    # So we build a candidate list (API -> HTML -> direct URLs) and try them at download time.

    $candidates = New-Object System.Collections.Generic.List[hashtable]

    # 1) Try GitHub API (preferred)
    try {
        $apiHeaders = @{
            "Accept"     = "application/vnd.github+json"
            "User-Agent" = "grobid-windows-bootstrap"
        }
        if ($env:GITHUB_TOKEN) { $apiHeaders["Authorization"] = "Bearer $env:GITHUB_TOKEN" }

        $releaseUrl = "https://api.github.com/repos/kermitt2/pdfalto/releases/tags/$Tag"
        $release = Invoke-RestMethod -Uri $releaseUrl -Headers $apiHeaders -Method Get
        if ($release -and $release.assets) {
            $asset = $release.assets |
                Where-Object { $_.name -match '(?i)(win|windows).*64.*\.zip$' } |
                Select-Object -First 1
            if ($asset) {
                $candidates.Add(@{ Url = $asset.browser_download_url; Name = $asset.name })
            }
        }
    } catch {
        Write-Warn ("GitHub API release lookup failed; continuing with fallbacks. Reason: {0}" -f $_.Exception.Message)
    }

    # 2) Fallback: parse github.com release HTML for direct /releases/download/<tag>/<asset> links (best-effort)
    try {
        $tagPage = "https://github.com/kermitt2/pdfalto/releases/tag/$Tag"
        $html = (Invoke-WebRequestCompat -Uri $tagPage -Headers $headers).Content
        $pat = '/kermitt2/pdfalto/releases/download/' + [regex]::Escape($Tag) + '/([^"\\s]+\\.zip)'
        $rx = New-Object System.Text.RegularExpressions.Regex($pat, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $matches = $rx.Matches($html)
        foreach ($m in $matches) {
            $name = $m.Groups[1].Value
            if ($name -match '(?i)(win|windows)' -and $name -match '(?i)64') {
                $candidates.Add(@{ Url = "https://github.com/kermitt2/pdfalto/releases/download/$Tag/$name"; Name = $name })
            }
        }
    } catch {
        # ignore and continue
    }

    # 3) Last-resort: try common canonical asset filenames directly (no API, no HTML dependency)
    $commonNames = @(
        "pdfalto_Windows_64bit.zip",
        "pdfalto_windows_64bit.zip",
        "pdfalto-windows-64bit.zip",
        ("pdfalto-{0}-Windows_64bit.zip" -f $Tag),
        ("pdfalto-{0}-windows_64bit.zip" -f $Tag)
    ) | Select-Object -Unique

    foreach ($n in $commonNames) {
        $candidates.Add(@{ Url = "https://github.com/kermitt2/pdfalto/releases/download/$Tag/$n"; Name = $n })
    }

    if ($candidates.Count -lt 1) {
        throw "Could not determine any candidate download URLs for pdfalto $Tag"
    }

    return $candidates
}

$downloadCandidates = Resolve-DownloadUrl -Tag $PdfaltoVersionTag

$tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("grobid-pdfalto-" + [System.Guid]::NewGuid().ToString("N"))
$tmpExtract = Join-Path $tmpRoot "extract"
Ensure-Dir $tmpRoot
Ensure-Dir $tmpExtract

function Test-ZipMagic([string]$Path) {
    try {
        $b = Get-Content -LiteralPath $Path -Encoding Byte -TotalCount 2
        return ($b.Count -eq 2 -and $b[0] -eq 0x50 -and $b[1] -eq 0x4B)
    } catch {
        return $false
    }
}

$tmpZip = $null
$lastError = $null
foreach ($c in $downloadCandidates) {
    $downloadUrl = $c.Url
    $assetName = $c.Name
    if (-not $assetName -or $assetName.Trim().Length -eq 0) { $assetName = "pdfalto.zip" }

    $candidateZip = Join-Path $tmpRoot ($assetName -replace '[\\/:*?\"<>|]', '_')
    Write-Info ("Downloading: {0}" -f $assetName)
    Write-Info ("From: {0}" -f $downloadUrl)
    try {
        Invoke-WebRequestCompat -Uri $downloadUrl -Headers $headers -OutFile $candidateZip
        if (-not (Test-ZipMagic -Path $candidateZip)) {
            throw "Downloaded file is not a ZIP (missing PK header)."
        }
        $tmpZip = $candidateZip
        break
    } catch {
        $lastError = $_.Exception.Message
        Write-Warn ("Download attempt failed: {0}" -f $lastError)
        try { Remove-Item -LiteralPath $candidateZip -Force -ErrorAction SilentlyContinue } catch {}
    }
}

if (-not $tmpZip) {
    throw "Could not download pdfalto $PdfaltoVersionTag Windows 64-bit from any candidate URL. Last error: $lastError"
}

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

$pdfaltoServerExe = Join-Path $pdfaltoFolder "pdfalto_server.exe"
if (-not (Test-Path -LiteralPath $pdfaltoServerExe)) {
    throw "Could not find pdfalto_server.exe next to pdfalto.exe inside downloaded archive."
}
$cygwinDll = Join-Path $pdfaltoFolder "cygwin1.dll"
if (-not (Test-Path -LiteralPath $cygwinDll)) {
    throw "Could not find cygwin1.dll next to pdfalto.exe inside downloaded archive."
}

# Clean target folder if present but invalid (prevents stale/partial installs from surviving)
if (Test-Path -LiteralPath $PdfaltoDir) {
    Get-ChildItem -Path $PdfaltoDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ine ".gitkeep" } |
        Remove-Item -Force -ErrorAction SilentlyContinue
} else {
    Ensure-Dir $PdfaltoDir
}

# Copy the full runtime bundle (DLLs + exes)
Get-ChildItem -Path $pdfaltoFolder -File | ForEach-Object {
    Copy-Item -Force -Path $_.FullName -Destination (Join-Path $PdfaltoDir $_.Name)
}

# Optional: ensure xpdfrc exists at the expected arch root (grobid-home/pdfalto/win-64/xpdfrc)
$archRoot = Split-Path -Parent $PdfaltoDir
$xpdfrcCandidate = Join-Path $pdfaltoFolder "xpdfrc"
if (-not (Test-Path -LiteralPath (Join-Path $archRoot "xpdfrc")) -and (Test-Path -LiteralPath $xpdfrcCandidate)) {
    Copy-Item -Force -Path $xpdfrcCandidate -Destination (Join-Path $archRoot "xpdfrc")
}

# Verify
if (-not (Try-VerifyExisting -Dir $PdfaltoDir)) {
    throw "pdfalto was downloaded but failed SHA256 verification. See grobid-home/scripts/verify_pdfalto_windows.ps1 for expected values."
}

Write-Info "OK: pdfalto installed and verified."


