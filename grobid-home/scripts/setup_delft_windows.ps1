<#
.SYNOPSIS
    One-click setup script for GROBID Deep Learning (DeLFT) on Windows.

.DESCRIPTION
    This script automates the complete setup of DeLFT for GROBID on Windows:
    - Checks for Python 3.8-3.12 (offers to install if missing)
    - Creates a virtual environment at grobid-home\.venv
    - Installs TensorFlow, JEP, and DeLFT
    - Clones the DeLFT repository
    - Configures grobid.yaml with correct paths
    - Validates the installation

.PARAMETER PythonVersion
    Preferred Python version to install if none found (default: 3.10)

.PARAMETER SkipPythonInstall
    Skip automatic Python installation prompt

.PARAMETER Force
    Overwrite existing virtual environment

.EXAMPLE
    .\setup_delft_windows.ps1
    
.EXAMPLE
    .\setup_delft_windows.ps1 -Force
    
.NOTES
    Run from the GROBID root directory.
    Requires Administrator privileges for Python installation via winget/choco.
#>

param(
    [string]$PythonVersion = "3.10",
    [switch]$SkipPythonInstall,
    [switch]$Force,
    [switch]$NonInteractive,
    [switch]$InstallBuildTools,
    [switch]$Help
)

# ============================================================================
# Configuration
# ============================================================================

$ErrorActionPreference = "Stop"
$SCRIPT_VERSION = "1.0.0"
$MIN_PYTHON_VERSION = [version]"3.8"
$MAX_PYTHON_VERSION = [version]"3.12"

# Paths (relative to GROBID root)
$VENV_PATH = "grobid-home\.venv"
$DELFT_PATH = "..\delft"
$CONFIG_PATH = "grobid-home\config\grobid.yaml"

# ============================================================================
# Helper Functions
# ============================================================================

function Write-Header {
    param([string]$Text)
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([string]$Text)
    Write-Host "[*] $Text" -ForegroundColor Yellow
}

function Write-Success {
    param([string]$Text)
    Write-Host "[OK] $Text" -ForegroundColor Green
}

function Write-Error2 {
    param([string]$Text)
    Write-Host "[X] $Text" -ForegroundColor Red
}

function Write-Info {
    param([string]$Text)
    Write-Host "    $Text" -ForegroundColor Gray
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-PythonInfo {
    # Try to find Python in PATH
    $pythonCandidates = @("python", "python3", "py")
    
    foreach ($candidate in $pythonCandidates) {
        try {
            $versionOutput = & $candidate --version 2>&1
            if ($LASTEXITCODE -eq 0 -and $versionOutput -match "Python (\d+\.\d+\.\d+)") {
                $version = [version]$Matches[1]
                $path = (Get-Command $candidate -ErrorAction SilentlyContinue).Source
                return @{
                    Command = $candidate
                    Version = $version
                    Path = $path
                    Valid = ($version -ge $MIN_PYTHON_VERSION -and $version -le $MAX_PYTHON_VERSION)
                }
            }
        } catch {
            continue
        }
    }
    
    return $null
}

function Install-PythonViaWinget {
    param([string]$Version)
    
    Write-Step "Installing Python $Version via winget..."
    
    try {
        # Check if winget is available
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $winget) {
            return $false
        }
        
        # Install Python
        $packageId = "Python.Python.$($Version -replace '\.', '')"
        & winget install --id $packageId --accept-source-agreements --accept-package-agreements
        
        if ($LASTEXITCODE -eq 0) {
            # Refresh PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + 
                        [System.Environment]::GetEnvironmentVariable("Path", "User")
            return $true
        }
    } catch {
        Write-Info "winget installation failed: $_"
    }
    
    return $false
}

function Install-PythonViaChocolatey {
    param([string]$Version)
    
    Write-Step "Installing Python $Version via Chocolatey..."
    
    try {
        # Check if choco is available
        $choco = Get-Command choco -ErrorAction SilentlyContinue
        if (-not $choco) {
            return $false
        }
        
        # Install Python
        $packageName = "python$($Version -replace '\.', '')"
        & choco install $packageName -y
        
        if ($LASTEXITCODE -eq 0) {
            # Refresh PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + 
                        [System.Environment]::GetEnvironmentVariable("Path", "User")
            return $true
        }
    } catch {
        Write-Info "Chocolatey installation failed: $_"
    }
    
    return $false
}

function Install-VcBuildToolsViaChocolatey {
    Write-Step "Installing Visual C++ Build Tools (required for JEP) via Chocolatey..."

    $choco = Get-Command choco -ErrorAction SilentlyContinue
    if (-not $choco) {
        Write-Error2 "Chocolatey not found. Install Chocolatey or install Visual C++ Build Tools manually."
        return $false
    }

    if (-not (Test-Administrator)) {
        Write-Error2 "Administrator privileges are required to install Visual C++ Build Tools via Chocolatey."
        return $false
    }

    # This is large and can take several minutes.
    & choco install visualstudio2022buildtools visualstudio2022-workload-vctools -y --no-progress
    if ($LASTEXITCODE -ne 0) {
        Write-Error2 "Chocolatey failed to install Visual C++ Build Tools."
        return $false
    }

    Write-Success "Visual C++ Build Tools installed (or already present)"
    return $true
}

function New-VirtualEnvironment {
    param(
        [string]$PythonCommand,
        [string]$VenvPath
    )
    
    Write-Step "Creating virtual environment at $VenvPath..."
    
    if (Test-Path $VenvPath) {
        if ($Force) {
            Write-Info "Removing existing virtual environment..."
            Remove-Item -Path $VenvPath -Recurse -Force
        } else {
            Write-Info "Virtual environment already exists. Use -Force to recreate."
            return $true
        }
    }
    
    & $PythonCommand -m venv $VenvPath
    
    if ($LASTEXITCODE -eq 0 -and (Test-Path "$VenvPath\Scripts\python.exe")) {
        Write-Success "Virtual environment created successfully"
        return $true
    }
    
    Write-Error2 "Failed to create virtual environment"
    return $false
}

function Install-Packages {
    param([string]$VenvPath)
    
    $pip = "$VenvPath\Scripts\pip.exe"
    $python = "$VenvPath\Scripts\python.exe"
    
    Write-Step "Upgrading pip..."
    & $python -m pip install --upgrade pip --quiet
    
    # Pick a conservative TensorFlow version based on the Python version.
    # - Python >= 3.12 requires TF >= 2.16
    # - Python <= 3.11 works with TF 2.15.x on Windows (CPU)
    $pyVer = & $python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null
    $tfSpec = "tensorflow==2.15.*"
    if ($pyVer -match '^3\.12$') {
        $tfSpec = "tensorflow==2.16.*"
    }

    Write-Step "Installing TensorFlow ($tfSpec) (this may take a few minutes)..."
    & $pip install $tfSpec --quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Error2 "Failed to install TensorFlow"
        return $false
    }
    Write-Success "TensorFlow installed"
    
    Write-Step "Installing JEP..."

    if ($InstallBuildTools) {
        $ok = Install-VcBuildToolsViaChocolatey
        if (-not $ok) {
            Write-Error2 "Cannot proceed with JEP install without Visual C++ Build Tools."
            return $false
        }
    }

    # JEP requires a JDK and JAVA_HOME. If JAVA_HOME is missing, try to derive it from javac.
    if (-not $env:JAVA_HOME) {
        try {
            $javacCmd = Get-Command javac -ErrorAction SilentlyContinue
            if ($javacCmd -and (Test-Path $javacCmd.Source)) {
                $binDir = Split-Path -Parent $javacCmd.Source
                $javaHome = Split-Path -Parent $binDir
                if (Test-Path (Join-Path $javaHome "bin\\javac.exe")) {
                    $env:JAVA_HOME = $javaHome
                    Write-Info "JAVA_HOME was not set; derived JAVA_HOME=$javaHome"
                }
            }
        } catch {
            # fall through to the normal error message from pip/jep
        }
    }
    if (-not $env:JAVA_HOME) {
        Write-Info "JAVA_HOME is not set. If JEP fails to build, set JAVA_HOME to your JDK path and retry."
    }

    & $pip install jep==4.2.0 --quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Info "JEP 4.2.0 failed, trying latest version..."
        & $pip install jep --quiet
        if ($LASTEXITCODE -ne 0) {
            Write-Error2 "Failed to install JEP. You may need Visual C++ Build Tools."
            Write-Info "Download from: https://visualstudio.microsoft.com/visual-cpp-build-tools/"
            return $false
        }
    }
    Write-Success "JEP installed"

    Write-Step "Installing additional dependencies..."
    & $pip install numpy scikit-learn lxml --quiet
    Write-Success "Additional dependencies installed"
    
    return $true
}

function Install-DeLFTFromRepo {
    param(
        [string]$VenvPath,
        [string]$DelftRepoPath
    )

    $pip = "$VenvPath\Scripts\pip.exe"

    if (-not (Test-Path "$DelftRepoPath\setup.py") -and -not (Test-Path "$DelftRepoPath\pyproject.toml")) {
        Write-Error2 "DeLFT repository does not look installable (missing setup.py/pyproject.toml): $DelftRepoPath"
        return $false
    }

    Write-Step "Installing DeLFT from cloned repository (editable install)..."
    # Prefer legacy editable install to avoid PEP517 build isolation issues on Windows
    # (some build dependencies like scikit-learn can fail metadata generation in isolated builds).
    & $pip install -e "$DelftRepoPath" --no-build-isolation --no-use-pep517 --quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Legacy editable install failed; trying PEP517 editable install..."
        & $pip install -e "$DelftRepoPath" --quiet
        if ($LASTEXITCODE -ne 0) {
            Write-Error2 "Failed to install DeLFT from repo"
            return $false
        }
    }

    Write-Success "DeLFT installed from repo"
    return $true
}

function Get-OrCloneDeLFT {
    param([string]$DelftPath)
    
    $absolutePath = [System.IO.Path]::GetFullPath($DelftPath)
    
    if (Test-Path "$absolutePath\delft\sequenceLabelling\__init__.py") {
        Write-Info "DeLFT repository already exists at $absolutePath"
        return $absolutePath
    }
    
    Write-Step "Cloning DeLFT repository..."
    
    # Check if git is available
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) {
        Write-Error2 "Git not found. Please install Git and try again."
        return $null
    }
    
    if (Test-Path $absolutePath) {
        Remove-Item -Path $absolutePath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    & git clone --depth 1 https://github.com/kermitt2/delft.git $absolutePath
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "DeLFT cloned to $absolutePath"
        return $absolutePath
    }
    
    Write-Error2 "Failed to clone DeLFT repository"
    return $null
}

function Update-GrobidConfig {
    param(
        [string]$ConfigPath,
        [string]$VenvPath,
        [string]$DelftPath
    )
    
    Write-Step "Updating GROBID configuration..."
    
    if (-not (Test-Path $ConfigPath)) {
        Write-Error2 "Configuration file not found: $ConfigPath"
        return $false
    }
    
    # Get absolute paths
    $venvAbsolute = [System.IO.Path]::GetFullPath($VenvPath)
    $delftAbsolute = [System.IO.Path]::GetFullPath($DelftPath)
    
    # Update only within the "grobid -> delft" block to avoid accidental replacements elsewhere.
    $lines = Get-Content $ConfigPath
    $delftLineIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*delft:\s*$') {
            $delftLineIdx = $i
            break
        }
    }

    if ($delftLineIdx -lt 0) {
        Write-Error2 "Could not find 'delft:' section in $ConfigPath"
        return $false
    }

    $delftIndent = ($lines[$delftLineIdx] -replace '(\S.*)$','').Length
    $endIdx = $lines.Count
    for ($j = $delftLineIdx + 1; $j -lt $lines.Count; $j++) {
        $indent = ($lines[$j] -replace '(\S.*)$','').Length
        if ($lines[$j].Trim() -ne "" -and $indent -le $delftIndent) {
            $endIdx = $j
            break
        }
    }

    $installUpdated = $false
    $venvUpdated = $false
    for ($k = $delftLineIdx + 1; $k -lt $endIdx; $k++) {
        if ($lines[$k] -match '^\s*install:\s*') {
            $prefix = ($lines[$k] -replace '^(\\s*install:\\s*).*$','$1')
            $lines[$k] = "$prefix`"$delftAbsolute`""
            $installUpdated = $true
        }
        if ($lines[$k] -match '^\s*pythonVirtualEnv:\s*') {
            $prefix = ($lines[$k] -replace '^(\\s*pythonVirtualEnv:\\s*).*$','$1')
            $lines[$k] = "$prefix`"$venvAbsolute`""
            $venvUpdated = $true
        }
    }

    if (-not $installUpdated) {
        # Insert install line right after delft:
        $insertAt = $delftLineIdx + 1
        $lines = $lines[0..($insertAt-1)] + (" " * ($delftIndent + 2) + "install: `"$delftAbsolute`"") + $lines[$insertAt..($lines.Count-1)]
    }

    if (-not $venvUpdated) {
        # Insert pythonVirtualEnv line right after install (or after delft: if install was missing)
        $newLines = New-Object System.Collections.Generic.List[string]
        $inserted = $false
        for ($m = 0; $m -lt $lines.Count; $m++) {
            $newLines.Add($lines[$m])
            if (-not $inserted -and $m -ge $delftLineIdx -and $lines[$m] -match '^\s*install:\s*') {
                $newLines.Add((" " * ($delftIndent + 2) + "pythonVirtualEnv: `"$venvAbsolute`""))
                $inserted = $true
            }
        }
        if (-not $inserted) {
            $newLines.Insert($delftLineIdx + 1, (" " * ($delftIndent + 2) + "pythonVirtualEnv: `"$venvAbsolute`""))
        }
        $lines = $newLines.ToArray()
    }

    $lines | Set-Content $ConfigPath
    
    Write-Success "Configuration updated"
    Write-Info "DeLFT path: $delftAbsolute"
    Write-Info "Virtual env: $venvAbsolute"
    
    return $true
}

function Test-Installation {
    param([string]$VenvPath)
    
    Write-Step "Validating installation..."
    
    $python = "$VenvPath\Scripts\python.exe"
    
    # Test TensorFlow
    Write-Info "Testing TensorFlow..."
    $tfTest = & $python -c "import tensorflow as tf; print(f'TensorFlow {tf.__version__}')" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success $tfTest
    } else {
        Write-Error2 "TensorFlow import failed: $tfTest"
        return $false
    }
    
    # Test JEP
    Write-Info "Testing JEP..."
    $jepTest = & $python -c "import jep; print(f'JEP {jep.__version__}')" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success $jepTest
    } else {
        Write-Error2 "JEP import failed: $jepTest"
        return $false
    }
    
    # Test DeLFT
    Write-Info "Testing DeLFT..."
    $delftTest = & $python -c "from delft.sequenceLabelling import Sequence; print('DeLFT OK')" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success $delftTest
    } else {
        Write-Error2 "DeLFT import failed: $delftTest"
        return $false
    }
    
    # Check for jep.dll
    Write-Info "Checking for jep.dll..."
    $jepDll = Get-ChildItem -Path "$VenvPath\Lib\site-packages\jep" -Filter "jep*.dll" -ErrorAction SilentlyContinue
    if ($jepDll) {
        Write-Success "Found: $($jepDll.Name)"
    } else {
        Write-Error2 "jep.dll not found - JEP native library missing"
        return $false
    }
    
    return $true
}

function Show-Help {
    Write-Host @"
GROBID DeLFT Setup Script for Windows
Version: $SCRIPT_VERSION

Usage: .\setup_delft_windows.ps1 [options]

Options:
  -PythonVersion <ver>   Preferred Python version to install (default: 3.10)
  -SkipPythonInstall     Don't prompt for Python installation
  -Force                 Overwrite existing virtual environment
  -Help                  Show this help message

Example:
  # Basic setup
  .\grobid-home\scripts\setup_delft_windows.ps1
  
  # Force recreation of virtual environment
  .\grobid-home\scripts\setup_delft_windows.ps1 -Force

Prerequisites:
  - Run from GROBID root directory
  - Git must be installed
  - For Python auto-install: winget or Chocolatey

After setup, enable DeLFT models in grobid-home\config\grobid.yaml:
  Change 'engine: "wapiti"' to 'engine: "delft"' for desired models.
"@
}

# ============================================================================
# Main Script
# ============================================================================

if ($Help) {
    Show-Help
    exit 0
}

Write-Header "GROBID DeLFT Setup for Windows v$SCRIPT_VERSION"

# Check we're in GROBID root directory
if (-not (Test-Path "grobid-home\config\grobid.yaml")) {
    Write-Error2 "Please run this script from the GROBID root directory."
    Write-Info "Expected to find: grobid-home\config\grobid.yaml"
    exit 1
}

Write-Success "Running from GROBID root directory"

# ============================================================================
# Step 1: Check/Install Python
# ============================================================================

Write-Header "Step 1: Python Environment"

$pythonInfo = Get-PythonInfo

if ($pythonInfo -and $pythonInfo.Valid) {
    Write-Success "Found Python $($pythonInfo.Version) at $($pythonInfo.Path)"
    $pythonCommand = $pythonInfo.Command
} elseif ($pythonInfo) {
    Write-Error2 "Found Python $($pythonInfo.Version) but need version $MIN_PYTHON_VERSION - $MAX_PYTHON_VERSION"
    $pythonCommand = $null
} else {
    Write-Error2 "Python not found in PATH"
    $pythonCommand = $null
}

if (-not $pythonCommand -and -not $SkipPythonInstall) {
    Write-Host ""
    Write-Host "Python $MIN_PYTHON_VERSION-$MAX_PYTHON_VERSION is required but not found." -ForegroundColor Yellow
    Write-Host ""
    
    if ($NonInteractive) {
        Write-Error2 "Python not found and NonInteractive was set. Install Python $MIN_PYTHON_VERSION-$MAX_PYTHON_VERSION and re-run."
        exit 1
    }

    $response = Read-Host "Would you like to install Python $PythonVersion? (Y/n)"
    
    if ($response -eq "" -or $response -eq "Y" -or $response -eq "y") {
        if (-not (Test-Administrator)) {
            Write-Info "Note: Python installation may require Administrator privileges."
        }
        
        $installed = Install-PythonViaWinget -Version $PythonVersion
        if (-not $installed) {
            $installed = Install-PythonViaChocolatey -Version $PythonVersion
        }
        
        if ($installed) {
            Write-Success "Python installed successfully"
            # Re-check Python
            $pythonInfo = Get-PythonInfo
            if ($pythonInfo -and $pythonInfo.Valid) {
                $pythonCommand = $pythonInfo.Command
            }
        } else {
            Write-Error2 "Automatic Python installation failed."
            Write-Host ""
            Write-Host "Please install Python manually:" -ForegroundColor Yellow
            Write-Host "  1. Download from https://www.python.org/downloads/" -ForegroundColor Gray
            Write-Host "  2. Run installer and CHECK 'Add Python to PATH'" -ForegroundColor Gray
            Write-Host "  3. Re-run this script" -ForegroundColor Gray
            exit 1
        }
    } else {
        Write-Error2 "Python is required. Please install Python $MIN_PYTHON_VERSION-$MAX_PYTHON_VERSION and try again."
        exit 1
    }
}

if (-not $pythonCommand) {
    Write-Error2 "No valid Python installation found. Aborting."
    exit 1
}

# ============================================================================
# Step 2: Create Virtual Environment
# ============================================================================

Write-Header "Step 2: Virtual Environment"

$venvCreated = New-VirtualEnvironment -PythonCommand $pythonCommand -VenvPath $VENV_PATH

if (-not $venvCreated) {
    Write-Error2 "Failed to create virtual environment. Aborting."
    exit 1
}

# ============================================================================
# Step 3: Install Packages
# ============================================================================

Write-Header "Step 3: Package Installation"

$packagesInstalled = Install-Packages -VenvPath $VENV_PATH

if (-not $packagesInstalled) {
    Write-Error2 "Package installation failed. See errors above."
    exit 1
}

# ============================================================================
# Step 4: Clone DeLFT Repository + install it into the venv
# ============================================================================

Write-Header "Step 4: DeLFT Repository"

$delftPath = Get-OrCloneDeLFT -DelftPath $DELFT_PATH

if (-not $delftPath) {
    Write-Error2 "Failed to set up DeLFT repository. Aborting."
    exit 1
}

$delftInstalled = Install-DeLFTFromRepo -VenvPath $VENV_PATH -DelftRepoPath $delftPath
if (-not $delftInstalled) {
    Write-Error2 "Failed to install DeLFT from the cloned repository. Aborting."
    exit 1
}

# ============================================================================
# Step 5: Configure GROBID
# ============================================================================

Write-Header "Step 5: GROBID Configuration"

$configUpdated = Update-GrobidConfig -ConfigPath $CONFIG_PATH -VenvPath $VENV_PATH -DelftPath $delftPath

if (-not $configUpdated) {
    Write-Info "Please manually update grobid-home\config\grobid.yaml"
}

# ============================================================================
# Step 6: Validate Installation
# ============================================================================

Write-Header "Step 6: Validation"

$valid = Test-Installation -VenvPath $VENV_PATH

# ============================================================================
# Summary
# ============================================================================

Write-Header "Setup Complete!"

if ($valid) {
    Write-Host @"
    
DeLFT has been successfully installed and configured!

Virtual Environment: $(Resolve-Path $VENV_PATH)
DeLFT Repository:    $delftPath

NEXT STEPS:

1. Enable DeLFT models in grobid-home\config\grobid.yaml:
   Change 'engine: "wapiti"' to 'engine: "delft"' for desired models.
   
   Recommended models to enable:
   - citation (significantly better accuracy)
   - header
   - reference-segmenter

2. Start GROBID:
   .\gradlew.bat run

3. Test with a PDF:
   curl -v --form input=@./paper.pdf localhost:8070/api/processFulltextDocument

For more information, see:
https://grobid.readthedocs.io/en/latest/Deep-Learning-models/

"@ -ForegroundColor Green
} else {
    Write-Host @"

Setup completed with warnings. Some components may not work correctly.
Please review the errors above and try the following:

1. Ensure Visual C++ Build Tools are installed
2. Check that JAVA_HOME is set correctly
3. Try reinstalling packages manually:
   
   $VENV_PATH\Scripts\activate.ps1
   pip install tensorflow jep delft

"@ -ForegroundColor Yellow
}

