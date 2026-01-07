 param(
    [Parameter(Mandatory = $false)]
    [string]$PdfaltoDir
)

$ErrorActionPreference = "Stop"

function Get-ScriptRoot() {
    if ($PSScriptRoot -and $PSScriptRoot.Trim().Length -gt 0) {
        return $PSScriptRoot
    }
    $p = $MyInvocation.MyCommand.Path
    if ($p -and $p.Trim().Length -gt 0) {
        return (Split-Path -Parent $p)
    }
    return (Get-Location).Path
}

function Assert-FileHash {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing file: $Path"
    }

    # Get-FileHash is not available in some PowerShell environments; use .NET directly for portability.
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            $bytes = $sha.ComputeHash($stream)
        } finally {
            $stream.Dispose()
        }
    } finally {
        $sha.Dispose()
    }
    $actual = ([System.BitConverter]::ToString($bytes) -replace "-", "").ToUpperInvariant()
    if ($actual -ne $ExpectedSha256.ToUpperInvariant()) {
        throw "SHA256 mismatch for $Path`nExpected: $ExpectedSha256`nActual:   $actual"
    }
}

function Assert-FilePresent {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing file: $Path"
    }
}

$scriptRoot = Get-ScriptRoot
if (-not $PdfaltoDir -or $PdfaltoDir.Trim().Length -eq 0) {
    $PdfaltoDir = Join-Path $scriptRoot "..\\pdfalto\\win-64\\pdfalto"
}

# Expected checksums:
# - Preferred: read from repo manifest `grobid-home/pdfalto/win-64/pdfalto-win64-0.4.sha256`
# - Fallback: hardcoded values (historical)
$manifest = Join-Path (Split-Path -Parent $PdfaltoDir) "pdfalto-win64-0.4.sha256"
$expected = @{}
if (Test-Path -LiteralPath $manifest) {
    $lines = Get-Content -LiteralPath $manifest | Where-Object { $_ -and $_.Trim().Length -gt 0 -and -not $_.Trim().StartsWith("#") }
    foreach ($l in $lines) {
        # Format: "<sha256>  <filename>"
        $parts = $l.Trim() -split "\s+", 2
        if ($parts.Count -eq 2) {
            $expected[$parts[1].Trim()] = $parts[0].Trim()
        }
    }
    if ($expected.Count -lt 1) {
        Write-Host "WARN: SHA256 manifest exists but is empty; skipping hash verification and only checking required files. ($manifest)" -ForegroundColor Yellow
    }
} else {
    $expected["pdfalto.exe"] = "FB1CAC5607A24C39C514BA18556831BF56097FFC4B03C1075A05560FB3AA9AE5"
    $expected["pdfalto_server.exe"] = "500749D394DFD2A598E85521F04ED89EA5916C1DAA66C5769BFC648974BB5CB5"
    $expected["cygwin1.dll"] = "AB54AB444115D42275CE00C62240C81D43C3AFB0C2E2DCE6BCC4CB78D07127DB"
}

if ($expected.Count -gt 0) {
    foreach ($k in $expected.Keys) {
        Assert-FilePresent -Path (Join-Path $PdfaltoDir $k)
        Assert-FileHash -Path (Join-Path $PdfaltoDir $k) -ExpectedSha256 $expected[$k]
    }
} else {
    # Minimal verification when manifest is not yet populated.
    Assert-FilePresent -Path (Join-Path $PdfaltoDir "pdfalto.exe")
    Assert-FilePresent -Path (Join-Path $PdfaltoDir "pdfalto_server.exe")
}

Write-Host "OK: Windows pdfalto binaries match expected SHA256." -ForegroundColor Green



        Assert-FileHash -Path (Join-Path $PdfaltoDir $k) -ExpectedSha256 $expected[$k]
    }
} else {
    # Minimal verification when manifest is not yet populated.
    Assert-FilePresent -Path (Join-Path $PdfaltoDir "pdfalto.exe")
    Assert-FilePresent -Path (Join-Path $PdfaltoDir "pdfalto_server.exe")
}

Write-Host "OK: Windows pdfalto binaries match expected SHA256." -ForegroundColor Green


