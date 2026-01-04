param(
    [Parameter(Mandatory = $false)]
    [string]$PdfaltoDir = (Join-Path $PSScriptRoot "..\\pdfalto\\win-64\\pdfalto")
)

$ErrorActionPreference = "Stop"

function Assert-FileHash {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256
    )

    if (-not (Test-Path $Path)) {
        throw "Missing file: $Path"
    }

    $actual = (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToUpperInvariant()
    if ($actual -ne $ExpectedSha256.ToUpperInvariant()) {
        throw "SHA256 mismatch for $Path`nExpected: $ExpectedSha256`nActual:   $actual"
    }
}

function Assert-FilePresent {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )
    if (-not (Test-Path $Path)) {
        throw "Missing file: $Path"
    }
}

$pdfaltoExe = Join-Path $PdfaltoDir "pdfalto.exe"
$pdfaltoServerExe = Join-Path $PdfaltoDir "pdfalto_server.exe"
$cygwinDll = Join-Path $PdfaltoDir "cygwin1.dll"

# Ensure the full runtime bundle is present (missing DLLs will cause runtime failures).
$requiredCompanionFiles = @(
    "cyggcc_s-1.dll",
    "cygiconv-2.dll",
    "cyglzma-5.dll",
    "cygstdc++-6.dll",
    "cygwin1.dll",
    "cygxml2-2.dll",
    "cygz.dll",
    "pdfalto.exe",
    "pdfalto_server.exe"
)
foreach ($name in $requiredCompanionFiles) {
    Assert-FilePresent -Path (Join-Path $PdfaltoDir $name)
}

# Expected checksums for the official Windows pdfalto binaries used by this repo (pdfalto 0.4).
Assert-FileHash -Path $pdfaltoExe -ExpectedSha256 "FB1CAC5607A24C39C514BA18556831BF56097FFC4B03C1075A05560FB3AA9AE5"
Assert-FileHash -Path $pdfaltoServerExe -ExpectedSha256 "500749D394DFD2A598E85521F04ED89EA5916C1DAA66C5769BFC648974BB5CB5"
Assert-FileHash -Path $cygwinDll -ExpectedSha256 "AB54AB444115D42275CE00C62240C81D43C3AFB0C2E2DCE6BCC4CB78D07127DB"

Write-Host "OK: Windows pdfalto binaries match expected SHA256." -ForegroundColor Green


