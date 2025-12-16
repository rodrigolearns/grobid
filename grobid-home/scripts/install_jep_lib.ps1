# install_jep_lib.ps1
# This script installs the JEP library for Windows to enable Deep Learning models in GROBID.
#
# Prerequisites:
# - Python 3.7-3.12 must be installed and on PATH
# - A virtual environment should be activated (recommended)
# - Visual C++ Build Tools may be required for building JEP
#
# Usage:
# Run from grobid root directory:
#   .\grobid-home\scripts\install_jep_lib.ps1

param(
    [string]$PythonPath = "python",
    [switch]$Help
)

if ($Help) {
    Write-Host @"
GROBID JEP Installation Script for Windows

Usage: .\install_jep_lib.ps1 [-PythonPath <path>] [-Help]

Options:
  -PythonPath    Path to Python executable (default: "python")
  -Help          Show this help message

Prerequisites:
  1. Python 3.7-3.12 installed and on PATH
  2. Visual C++ Build Tools (for compiling JEP)
  3. A virtual environment (recommended)

Example:
  # With default Python
  .\grobid-home\scripts\install_jep_lib.ps1
  
  # With specific Python
  .\grobid-home\scripts\install_jep_lib.ps1 -PythonPath "C:\Python310\python.exe"
"@
    exit 0
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "GROBID JEP Installation Script (Windows)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Check Python installation
Write-Host "`nChecking Python installation..." -ForegroundColor Yellow
try {
    $pythonVersion = & $PythonPath --version 2>&1
    Write-Host "Found: $pythonVersion" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Python not found. Please install Python 3.7-3.12 and ensure it's on PATH." -ForegroundColor Red
    exit 1
}

# Check if in virtual environment
$venvPath = $env:VIRTUAL_ENV
$condaPath = $env:CONDA_PREFIX

if ($venvPath) {
    Write-Host "Virtual environment detected: $venvPath" -ForegroundColor Green
} elseif ($condaPath) {
    Write-Host "Conda environment detected: $condaPath" -ForegroundColor Green
} else {
    Write-Host "WARNING: No virtual environment detected. It's recommended to use a virtual environment." -ForegroundColor Yellow
    $continue = Read-Host "Continue anyway? (y/N)"
    if ($continue -ne "y" -and $continue -ne "Y") {
        Write-Host "Aborted. Please activate a virtual environment first." -ForegroundColor Red
        exit 1
    }
}

# Install/upgrade pip
Write-Host "`nUpgrading pip..." -ForegroundColor Yellow
& $PythonPath -m pip install --upgrade pip

# Install JEP
Write-Host "`nInstalling JEP..." -ForegroundColor Yellow
Write-Host "This may take a few minutes as JEP needs to compile native code." -ForegroundColor Gray

try {
    & $PythonPath -m pip install jep==4.0.2
    if ($LASTEXITCODE -ne 0) {
        throw "pip install failed"
    }
} catch {
    Write-Host @"

ERROR: Failed to install JEP.

Common solutions:
1. Install Visual C++ Build Tools:
   - Download from: https://visualstudio.microsoft.com/visual-cpp-build-tools/
   - Select "Desktop development with C++" workload

2. Ensure JAVA_HOME is set:
   - Set JAVA_HOME to your JDK installation directory
   - Add %JAVA_HOME%\bin to PATH

3. Try installing with pre-built wheels (if available):
   pip install --only-binary :all: jep

"@ -ForegroundColor Red
    exit 1
}

# Verify installation
Write-Host "`nVerifying JEP installation..." -ForegroundColor Yellow
$jepLocation = & $PythonPath -c "import jep; print(jep.__file__)" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "JEP installed successfully!" -ForegroundColor Green
    Write-Host "Location: $jepLocation" -ForegroundColor Gray
    
    # Find jep.dll
    $jepDir = Split-Path -Parent $jepLocation
    $jepDll = Get-ChildItem -Path $jepDir -Filter "jep*.dll" -ErrorAction SilentlyContinue | Select-Object -First 1
    
    if ($jepDll) {
        Write-Host "JEP DLL found: $($jepDll.FullName)" -ForegroundColor Green
    } else {
        Write-Host "WARNING: jep.dll not found in $jepDir" -ForegroundColor Yellow
    }
} else {
    Write-Host "WARNING: JEP installed but import test failed. Error: $jepLocation" -ForegroundColor Yellow
}

# Install DeLFT dependencies
Write-Host "`nInstalling DeLFT and TensorFlow dependencies..." -ForegroundColor Yellow
& $PythonPath -m pip install tensorflow
& $PythonPath -m pip install delft

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Installation complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host @"

Next steps:
1. Ensure your GROBID configuration uses DeLFT models
2. Set the VIRTUAL_ENV or CONDA_PREFIX environment variable if not using activation
3. Run GROBID: .\gradlew run

For troubleshooting, see:
https://grobid.readthedocs.io/en/latest/Deep-Learning-models/
"@


