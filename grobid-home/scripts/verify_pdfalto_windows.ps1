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

$pdfaltoExe = Join-Path $PdfaltoDir "pdfalto.exe"
$pdfaltoServerExe = Join-Path $PdfaltoDir "pdfalto_server.exe"
$cygwinDll = Join-Path $PdfaltoDir "cygwin1.dll"

# Baseline checksums (upstream Research-Signals/grobid at time of validation).
Assert-FileHash -Path $pdfaltoExe -ExpectedSha256 "FB1CAC5607A24C39C514BA18556831BF56097FFC4B03C1075A05560FB3AA9AE5"
Assert-FileHash -Path $pdfaltoServerExe -ExpectedSha256 "500749D394DFD2A598E85521F04ED89EA5916C1DAA66C5769BFC648974BB5CB5"
Assert-FileHash -Path $cygwinDll -ExpectedSha256 "AB54AB444115D42275CE00C62240C81D43C3AFB0C2E2DCE6BCC4CB78D07127DB"

Write-Host "OK: Windows pdfalto binaries match expected SHA256." -ForegroundColor Green


