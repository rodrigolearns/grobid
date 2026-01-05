param(
    [Parameter(Mandatory = $false)]
    [string]$Msys2Root = (Join-Path $env:LOCALAPPDATA "msys64"),

    [Parameter(Mandatory = $false)]
    [switch]$VerboseLogging,

    [Parameter(Mandatory = $false)]
    [switch]$TarballOnly
)

$ErrorActionPreference = "Stop"

# Normalize path (PowerShell strings do NOT treat backslash as an escape, so callers sometimes pass "C:\\msys64").
if ($Msys2Root) { $Msys2Root = $Msys2Root.Trim() }
$Msys2Root = ($Msys2Root -replace "\\\\+", "\")

$bash = Join-Path $Msys2Root "usr\\bin\\bash.exe"
if ($VerboseLogging) {
    $VerbosePreference = "Continue"
    Write-Host ("[msys2] VerboseLogging enabled. Target root: {0}" -f $Msys2Root) -ForegroundColor Cyan
}

if (Test-Path -LiteralPath $bash) {
    Write-Host "MSYS2 already installed at $Msys2Root" -ForegroundColor Green
    exit 0
}

Write-Host "MSYS2 not found at $Msys2Root. Installing..." -ForegroundColor Cyan

function Install-Msys2FromTarball {
    param(
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)][string]$TempDir
    )

    function Extract-TarXz {
        param(
            [Parameter(Mandatory = $true)][string]$ArchivePath,
            [Parameter(Mandatory = $true)][string]$OutDir
        )

        # Strategy A: use tar.exe if it can handle .xz (requires xz in PATH on some Windows builds)
        $tarCmd = Get-Command tar -ErrorAction SilentlyContinue
        if ($tarCmd) {
            try {
                if ($VerboseLogging) { Write-Host "[msys2] Trying extraction via tar.exe..." -ForegroundColor DarkCyan }
                & tar -xf $ArchivePath -C $OutDir
                if ($LASTEXITCODE -eq 0) { return }
            } catch {
                # fall through
            }
        }

        # Strategy B: use Python's built-in lzma + tarfile (no external xz required)
        $python = Get-Command python -ErrorAction SilentlyContinue
        $py = Get-Command py -ErrorAction SilentlyContinue
        if (-not $python -and -not $py) {
            throw "Cannot extract .tar.xz: tar.exe failed and Python not found. Install Python 3 (or ensure 'py' launcher exists), or install xz/7zip, then re-run."
        }

        $scriptPath = Join-Path $TempDir ("extract-tarxz-" + [guid]::NewGuid().ToString("N") + ".py")
        @'
import lzma, tarfile, sys, os, shutil

archive = sys.argv[1]
outdir = sys.argv[2]

os.makedirs(outdir, exist_ok=True)

tar_path = archive[:-3] if archive.lower().endswith(".xz") else (archive + ".tar")

with lzma.open(archive) as fin, open(tar_path, "wb") as fout:
    shutil.copyfileobj(fin, fout)

with tarfile.open(tar_path, "r:*") as tf:
    tf.extractall(outdir)
'@ | Set-Content -LiteralPath $scriptPath -Encoding UTF8

        if ($VerboseLogging) { Write-Host "[msys2] Trying extraction via Python (lzma)..." -ForegroundColor DarkCyan }
        if ($python) {
            & $python.Source $scriptPath $ArchivePath $OutDir
        } else {
            & $py.Source -3 $scriptPath $ArchivePath $OutDir
        }
        if ($LASTEXITCODE -ne 0) {
            throw "Python-based extraction failed (exit code $LASTEXITCODE)."
        }
    }

    function Resolve-LatestTarballUrlFromIndex {
        param(
            [Parameter(Mandatory = $true)][string]$IndexUrl,
            [Parameter(Mandatory = $true)][string]$FileNameRegex
        )
        try {
            $resp = Invoke-WebRequest -Uri $IndexUrl -UseBasicParsing
            $names = @()
            foreach ($l in $resp.Links) {
                if (-not $l) { continue }
                $href = $l.href
                if (-not $href) { continue }
                $m = [regex]::Match($href, $FileNameRegex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                if ($m.Success) {
                    # keep only the file name portion
                    $names += $m.Groups[0].Value
                }
            }
            if ($names.Count -gt 0) {
                $latest = ($names | Sort-Object -Unique | Sort-Object)[-1]
                return ($IndexUrl.TrimEnd("/") + "/" + $latest)
            }
        } catch {
            # ignore, we'll fall back to hardcoded candidates below
        }
        return $null
    }

    $indexX64 = "https://repo.msys2.org/distrib/x86_64/"
    $latestBase = Resolve-LatestTarballUrlFromIndex -IndexUrl $indexX64 -FileNameRegex "msys2-base-x86_64-\d{8}\.tar\.xz"
    $latestFull = Resolve-LatestTarballUrlFromIndex -IndexUrl $indexX64 -FileNameRegex "msys2-x86_64-\d{8}\.tar\.xz"

    # Fallback list in case directory listing parsing is blocked in some environments.
    # Note: repo.msys2.org historically removed the '*-latest.tar.xz' symlinks, so we do not rely on them.
    $candidateUrls = @()
    if ($latestBase) { $candidateUrls += $latestBase }
    if ($latestFull) { $candidateUrls += $latestFull }
    $candidateUrls += @(
        # Known recent snapshots (keep a couple as a safety net).
        "https://repo.msys2.org/distrib/x86_64/msys2-base-x86_64-20251213.tar.xz",
        "https://repo.msys2.org/distrib/x86_64/msys2-x86_64-20251213.tar.xz",
        "https://repo.msys2.org/distrib/x86_64/msys2-base-x86_64-20250830.tar.xz",
        "https://repo.msys2.org/distrib/x86_64/msys2-x86_64-20250830.tar.xz"
    )

    $archive = Join-Path $TempDir ("msys2-x86_64-latest-{0}.tar.xz" -f ([guid]::NewGuid().ToString("N")))
    $downloaded = $false
    foreach ($u in $candidateUrls) {
        try {
            Write-Host ("[msys2] Trying tarball: {0}" -f $u) -ForegroundColor DarkCyan
            Invoke-WebRequest -Uri $u -OutFile $archive -UseBasicParsing
            $downloaded = $true
            break
        } catch {
            Write-Host ("[msys2] Tarball download failed: {0}" -f $_.Exception.Message) -ForegroundColor DarkCyan
        }
    }
    if (-not $downloaded) {
        throw "Could not download MSYS2 tarball from repo.msys2.org/distrib. Please install MSYS2 manually from https://www.msys2.org/."
    }

    $extractRoot = Join-Path $TempDir ("msys2-extract-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
    Write-Host ("[msys2] Extracting tarball to: {0}" -f $extractRoot) -ForegroundColor DarkCyan
    Extract-TarXz -ArchivePath $archive -OutDir $extractRoot

    $candidate1 = Join-Path $extractRoot "msys64\\usr\\bin\\bash.exe"
    $candidate2 = Join-Path $extractRoot "usr\\bin\\bash.exe"

    if (Test-Path -LiteralPath $candidate1) {
        $srcRoot = Join-Path $extractRoot "msys64"
    } elseif (Test-Path -LiteralPath $candidate2) {
        $srcRoot = $extractRoot
    } else {
        throw "Extracted tarball did not contain expected MSYS2 layout (bash.exe not found)."
    }

    if (Test-Path -LiteralPath $TargetRoot) {
        try { Remove-Item -LiteralPath $TargetRoot -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
    New-Item -ItemType Directory -Force -Path $TargetRoot | Out-Null

    Write-Host ("[msys2] Installing files into: {0}" -f $TargetRoot) -ForegroundColor DarkCyan
    # NOTE: We must use -Path (not -LiteralPath) because we intentionally use a wildcard to copy all children.
    Copy-Item -Path (Join-Path $srcRoot "*") -Destination $TargetRoot -Recurse -Force
}

$tempDir = [Environment]::GetEnvironmentVariable("TEMP")
if ($tempDir) { $tempDir = $tempDir.Trim() }
if (-not $tempDir) { $tempDir = (Get-Location).Path }

if ($TarballOnly) {
    Write-Host "[msys2] TarballOnly requested; skipping .exe installer and extracting base tarball..." -ForegroundColor Yellow
    Install-Msys2FromTarball -TargetRoot $Msys2Root -TempDir $tempDir
    if (-not (Test-Path -LiteralPath $bash)) {
        throw "Tarball install finished but bash.exe not found at $bash"
    }
    Write-Host "OK: MSYS2 installed at $Msys2Root" -ForegroundColor Green
    exit 0
}

$winget = Get-Command winget -ErrorAction SilentlyContinue
if ($winget) {
    Write-Host "Using winget..." -ForegroundColor Cyan
    & winget install --id MSYS2.MSYS2 --exact --silent --accept-package-agreements --accept-source-agreements | Out-Host
} else {
    Write-Host "winget not available; downloading installer..." -ForegroundColor Cyan
    $url = "https://github.com/msys2/msys2-installer/releases/latest/download/msys2-x86_64-latest.exe"
    # Use a unique filename to avoid collisions/locks from previous attempts.
    $installer = Join-Path $tempDir ("msys2-x86_64-latest-{0}.exe" -f ([guid]::NewGuid().ToString("N")))
    if ($VerboseLogging) {
        Write-Host ("[msys2] Download URL: {0}" -f $url) -ForegroundColor DarkCyan
        Write-Host ("[msys2] Download path: {0}" -f $installer) -ForegroundColor DarkCyan
        Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing -Verbose
    } else {
        Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing
    }
    if ($VerboseLogging) {
        try {
            $fi = Get-Item -LiteralPath $installer
            Write-Host ("[msys2] Downloaded {0:N1} MB" -f ($fi.Length / 1MB)) -ForegroundColor DarkCyan
        } catch {}
    }
    Write-Host "Running installer (silent)..." -ForegroundColor Cyan
    # Some installer builds do not exit reliably in silent mode in certain environments.
    # Start it and poll for bash.exe instead of waiting indefinitely.
    # MSYS2 installer is Inno Setup based; use Inno silent flags + logging.
    # Some installer builds ignore "/LOG=path" form, so we use '/LOG' + a separate quoted path.
    $logPath = Join-Path $tempDir ("msys2-install-{0}.log" -f ([guid]::NewGuid().ToString("N")))
    $args = @(
        "/VERYSILENT",
        "/SUPPRESSMSGBOXES",
        "/NORESTART",
        "/SP-",
        "/DIR=$Msys2Root",
        "/LOG", "`"$logPath`""
    )
    if ($VerboseLogging) {
        Write-Host ("[msys2] Start-Process: {0} {1}" -f $installer, ($args -join " ")) -ForegroundColor DarkCyan
        Write-Host ("[msys2] Installer log: {0}" -f $logPath) -ForegroundColor DarkCyan
    }
    $p = Start-Process -FilePath $installer -ArgumentList $args -PassThru
    $deadline = (Get-Date).AddMinutes(30)
    $nextLog = Get-Date
    $nextLogTail = Get-Date
    $fallbackChecked = $false
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $bash) { break }
        if ($VerboseLogging -and (Get-Date) -ge $nextLog) {
            $elapsed = [int]((New-TimeSpan -Start $p.StartTime -End (Get-Date)).TotalSeconds)
            $proc = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
            if ($proc) {
                Write-Host ("[msys2] waiting... {0}s pid={1} cpu={2}s ws={3:N0}KB" -f $elapsed, $p.Id, [math]::Round($proc.CPU,1), [math]::Round($proc.WorkingSet64/1KB)) -ForegroundColor DarkCyan
            } else {
                Write-Host ("[msys2] waiting... installer process exited? pid={0}" -f $p.Id) -ForegroundColor DarkCyan
            }
            if (Test-Path -LiteralPath $Msys2Root) {
                Write-Host ("[msys2] install dir exists: {0}" -f $Msys2Root) -ForegroundColor DarkCyan
            }
            $nextLog = (Get-Date).AddSeconds(15)
        }
        if ($VerboseLogging -and (Get-Date) -ge $nextLogTail) {
            $logToTail = $null
            if (Test-Path -LiteralPath $logPath) {
                $logToTail = $logPath
            } else {
                # Fallback: Inno Setup often writes "Setup Log *.txt" into %TEMP% if /LOG path is ignored.
                try {
                    $cand = Get-ChildItem -LiteralPath $tempDir -File -Filter "Setup Log*.txt" -ErrorAction SilentlyContinue |
                        Sort-Object LastWriteTime -Descending |
                        Select-Object -First 1
                    if ($cand) { $logToTail = $cand.FullName }
                } catch {}
            }
            if ($logToTail -and (Test-Path -LiteralPath $logToTail)) {
                Write-Host ("[msys2] installer log tail ({0}):" -f $logToTail) -ForegroundColor DarkCyan
                Get-Content -LiteralPath $logToTail -Tail 8 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host ("[msys2]  " + $_) -ForegroundColor DarkCyan }
            } else {
                Write-Host "[msys2] (no installer log found yet)" -ForegroundColor DarkCyan
            }
            $nextLogTail = (Get-Date).AddSeconds(30)
        }
        if (-not $fallbackChecked) {
            $elapsed = [int]((New-TimeSpan -Start $p.StartTime -End (Get-Date)).TotalSeconds)
            if ($elapsed -ge 120 -and -not (Test-Path -LiteralPath $Msys2Root) -and -not (Test-Path -LiteralPath $logPath)) {
                $fallbackChecked = $true
                Write-Host "[msys2] Installer appears stuck (no dir/log after 120s). Falling back to tarball install..." -ForegroundColor Yellow
                try { if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } } catch {}
                Install-Msys2FromTarball -TargetRoot $Msys2Root -TempDir $tempDir
                break
            }
        }
        Start-Sleep -Seconds 3
    }
    if (Test-Path -LiteralPath $bash) {
        try { if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } } catch {}
    } else {
        try { if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } } catch {}
        if ($VerboseLogging) {
            Write-Host "[msys2] Timeout diagnostics:" -ForegroundColor Yellow
            Write-Host ("[msys2] bash expected at: {0}" -f $bash) -ForegroundColor Yellow
            if (Test-Path -LiteralPath $Msys2Root) {
                Get-ChildItem -LiteralPath $Msys2Root -ErrorAction SilentlyContinue | Select-Object -First 50 | Format-Table -AutoSize | Out-String | Write-Host
            }
        }
        throw "Timed out waiting for MSYS2 installation to complete (bash.exe not found after 30 minutes)."
    }
}

if (-not (Test-Path -LiteralPath $bash)) {
    throw "MSYS2 install completed but bash.exe not found at $bash"
}

Write-Host "OK: MSYS2 installed at $Msys2Root" -ForegroundColor Green


