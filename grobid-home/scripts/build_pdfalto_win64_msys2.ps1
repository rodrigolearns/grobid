param(
    [Parameter(Mandatory = $false)]
    [string]$PdfaltoTag = "0.4",

    [Parameter(Mandatory = $false)]
    [string]$Msys2Root = (Join-Path $env:LOCALAPPDATA "msys64")
)

$ErrorActionPreference = "Stop"

function Get-ScriptRoot() {
    if ($PSScriptRoot -and $PSScriptRoot.Trim().Length -gt 0) { return $PSScriptRoot }
    $p = $MyInvocation.MyCommand.Path
    if ($p -and $p.Trim().Length -gt 0) { return (Split-Path -Parent $p) }
    return (Get-Location).Path
}

$scriptRoot = Get-ScriptRoot
$repoRoot = Resolve-Path (Join-Path $scriptRoot "..\\..") | Select-Object -ExpandProperty Path

# Normalize path (PowerShell strings do NOT treat backslash as an escape).
if ($Msys2Root) { $Msys2Root = $Msys2Root.Trim() }
$Msys2Root = ($Msys2Root -replace "\\\\+", "\")

$bash = Join-Path $Msys2Root "usr\\bin\\bash.exe"
if (-not (Test-Path -LiteralPath $bash)) {
    throw "MSYS2 not found at $Msys2Root. Install MSYS2 first (see https://www.msys2.org/) then re-run this script."
}

function Get-BestWorkRoot() {
    # Prefer a drive with plenty of free space to avoid ENOSPC mid-clone/build.
    # Users can override by setting env var PDFALTO_WORK_ROOT.
    $override = $env:PDFALTO_WORK_ROOT
    if ($override -and $override.Trim().Length -gt 0) {
        return $override.Trim()
    }

    try {
        $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady -and $_.DriveType -eq [System.IO.DriveType]::Fixed }
        $best = $drives | Sort-Object -Property AvailableFreeSpace -Descending | Select-Object -First 1
        if ($best -and $best.RootDirectory) {
            return (Join-Path $best.RootDirectory.FullName "_tmp")
        }
    } catch {
        # Fall back below.
    }

    return (Join-Path $env:USERPROFILE "_tmp")
}

$shortId = [guid]::NewGuid().ToString("N").Substring(0, 8)
$workRoot = Get-BestWorkRoot
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
$work = Join-Path $workRoot ("pdfalto-build-" + $shortId)
New-Item -ItemType Directory -Force -Path $work | Out-Null

$outDir = Join-Path $repoRoot "grobid-home\\pdfalto\\win-64\\pdfalto"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Write-Host "Building pdfalto $PdfaltoTag using MSYS2 at $Msys2Root" -ForegroundColor Cyan
Write-Host "Work dir: $work" -ForegroundColor Cyan
Write-Host "Output dir: $outDir" -ForegroundColor Cyan

# Pass paths/tag to bash via environment variables to avoid PowerShell expanding bash syntax like $(...) in strings.
$env:PDFALTO_WORK = $work
$env:PDFALTO_OUTDIR = $outDir
$env:PDFALTO_TAG = $PdfaltoTag

# We use mingw64 environment for native 64-bit binaries.
# The command below:
# - installs toolchain + cmake + git + key libs
# - clones pdfalto tag
# - initializes submodules
# - builds with cmake+make
# - copies pdfalto.exe/pdfalto_server.exe and their dependent DLLs into $outDir
#
# NOTE: dependency list may need adjustment if upstream changes; this is a maintainer workflow.
$bashCmd = @'
set -euo pipefail
export MSYSTEM=MINGW64
export CHERE_INVOKING=1
export PATH="/mingw64/bin:/usr/bin:$PATH"
export CFLAGS="-I/mingw64/include ${CFLAGS:-}"
export CXXFLAGS="-I/mingw64/include ${CXXFLAGS:-}"

# Ensure git never tries to use SSH URLs for GitHub (submodules in pdfalto use git@github.com:...).
git config --global url."https://github.com/".insteadOf git@github.com:
git config --global url."https://github.com/".insteadOf ssh://git@github.com/
git config --global url."https://github.com/".insteadOf git://github.com/

# NOTE: do NOT install the 'mingw-w64-x86_64-toolchain' group here because pacman prompts
# for interactive group member selection even with --noconfirm.
pacman -Sy --noconfirm --needed \
  git make \
  mingw-w64-x86_64-gcc mingw-w64-x86_64-binutils mingw-w64-x86_64-make \
  mingw-w64-x86_64-cmake mingw-w64-x86_64-pkgconf \
  mingw-w64-x86_64-libxml2 mingw-w64-x86_64-libxslt mingw-w64-x86_64-zlib mingw-w64-x86_64-icu \
  mingw-w64-x86_64-freetype mingw-w64-x86_64-libpng mingw-w64-x86_64-libjpeg-turbo \
  mingw-w64-x86_64-expat mingw-w64-x86_64-libiconv

cd "$PDFALTO_WORK"
rm -rf pdfalto
git clone --depth 1 --branch "$PDFALTO_TAG" https://github.com/kermitt2/pdfalto.git pdfalto
cd pdfalto

# Submodules in pdfalto use git@github.com:... (SSH). Force HTTPS at the repo level before init.
git config url."https://github.com/".insteadOf git@github.com:
git config url."https://github.com/".insteadOf ssh://git@github.com/
git config url."https://github.com/".insteadOf git://github.com/
# Also patch .gitmodules defensively, then sync.
git config -f .gitmodules submodule.xpdf-4.03.url https://github.com/kermitt2/xpdf-4.03.git || true
git submodule sync --recursive
git submodule update --init --recursive

# pdfalto's sources use `using namespace std;` (file-scope). Under C++17, this exposes `std::byte` and
# causes ambiguous `byte` references inside Windows headers pulled in via xpdf/goo (windows.h/rpcndr.h).
# Fix by narrowing `std` imports on Windows only (keep legacy behavior elsewhere).
if [ -f src/XmlAltoOutputDev.cc ]; then
  awk '
    $0=="using namespace std;" {
      print "#ifdef _WIN32"
      print "using std::string;"
      print "using std::vector;"
      print "using std::list;"
      print "using std::stack;"
      print "using std::pair;"
      print "using std::cout;"
      print "using std::endl;"
      print "using std::min;"
      print "using std::max;"
      print "using std::min_element;"
      print "using std::max_element;"
      print "#else"
      print "using namespace std;"
      print "#endif"
      next
    }
    { print }
  ' src/XmlAltoOutputDev.cc > src/XmlAltoOutputDev.cc.tmp && mv src/XmlAltoOutputDev.cc.tmp src/XmlAltoOutputDev.cc
fi

# xpdf's build files include MSVC-only flags (/D..., /wdNNNN, /EHsc) which break MinGW GCC.
# We strip them in the temp checkout so the build works with modern MSYS2 + GCC.
if [ -f xpdf-4.03/CMakeLists.txt ]; then
  sed -Ei 's@/D[A-Za-z0-9_]+@@g; s@/wd[0-9]+@@g; s@/EHsc@@g' xpdf-4.03/CMakeLists.txt || true
fi
if [ -f xpdf-4.03/cmake-config.txt ]; then
  sed -Ei 's@/D[A-Za-z0-9_]+@@g; s@/wd[0-9]+@@g; s@/EHsc@@g' xpdf-4.03/cmake-config.txt || true
fi

# pdfalto CMakeLists links against 'dl' (libdl) which does not exist on Windows/MinGW.
if [ -f CMakeLists.txt ]; then
  # Remove occurrences of the 'dl' token in target_link_libraries lines.
  sed -Ei 's@[[:space:]]dl@@g' CMakeLists.txt || true

  # pdfalto's Windows build hardcodes prebuilt static libs under libs/**/windows/** which are
  # not compatible with MSYS2/MinGW (missing __getreent, dlopen, sockets, etc). Rewire to MSYS2 libs.
  # NOTE: this script is inside a single-quoted here-string, so backslashes are passed through as-is.
  # Be careful not to over-escape (e.g., `\\(` becomes a literal `\` + an unbalanced `(` in sed -E).
  echo "=== CMakeLists ICU lines (before patch) ==="
  grep -n "ICU" CMakeLists.txt || true
  echo "=== CMakeLists libs/icu references (before patch) ==="
  grep -n "libs/icu" CMakeLists.txt || true
  echo "=== CMakeLists C++ standard / flags (before patch) ==="
  grep -nE "CMAKE_CXX_STANDARD|CMAKE_CXX_FLAGS|-std=gnu\\+\\+|-std=c\\+\\+" CMakeLists.txt || true

  sed -Ei 's@set\(FREETYPE_INCLUDE_DIR_ft2build .*@set(FREETYPE_INCLUDE_DIR_ft2build /mingw64/include/freetype2)@' CMakeLists.txt || true
  sed -Ei 's@set\(FREETYPE_INCLUDE_DIR_freetype_freetype .*@set(FREETYPE_INCLUDE_DIR_freetype_freetype /mingw64/include/freetype2)@' CMakeLists.txt || true
  sed -Ei 's@include_directories\([^)]*ZLIB_SUBDIR[^)]*\)@include_directories("/mingw64/include")@' CMakeLists.txt || true
  # Keep pdfalto's bundled libpng headers (pdfalto uses libpng internals); we'll build a matching libpng static library below.
  sed -Ei 's@set\(PNG_INCLUDE_DIRS .*@set(PNG_INCLUDE_DIRS ${PNG_SUBDIR}/src)@' CMakeLists.txt || true

  # Ensure we compile against MSYS2 ICU headers (namespace/version must match the linked libs).
  sed -Ei 's@libs/icu/common@/mingw64/include@g; s@libs/icu/i18n@/mingw64/include@g' CMakeLists.txt || true
  # Replace literal ${ICU_PATH}/common with /mingw64/include (avoid sed -E brace parsing issues).
  sed -i 's@${ICU_PATH}/common@/mingw64/include@g; s@${ICU_PATH}/i18n@/mingw64/include@g' CMakeLists.txt || true

  # Do NOT force the whole project to C++17:
  # - xpdf/goo triggers `byte` ambiguities with Windows headers under C++17 (std::byte vs rpcndr.h byte).
  # We keep the overall build at C++14, and later force only the `pdfalto` targets to C++17.

  sed -Ei 's@set \( XML_LIBRARY .*@set ( XML_LIBRARY xml2)@' CMakeLists.txt || true
  sed -Ei 's@set \( ZLIB_LIBRARY .*@set ( ZLIB_LIBRARY z)@' CMakeLists.txt || true
  sed -Ei 's@set \( FREETYPE_LIBRARY .*@set ( FREETYPE_LIBRARY freetype)@' CMakeLists.txt || true
  # MSYS2 ICU uses icuuc + icudt (not "icudata").
  sed -Ei 's@set \( ICUUC_LIB .*@set ( ICUUC_LIB icuuc)@' CMakeLists.txt || true
  sed -Ei 's@set \( ICUDATA_LIB .*@set ( ICUDATA_LIB icudt)@' CMakeLists.txt || true

  # xpdf (static) references Windows COM helpers (CoInitialize, IID_*). Ensure final link includes the required system libs.
  # Ensure the file ends with a newline before appending to avoid CMake parse errors.
  printf '\n' >> CMakeLists.txt
  cat >> CMakeLists.txt <<'EOF'
if(WIN32)
  target_link_libraries(pdfalto ole32 uuid shell32)
  # ICU can require additional components depending on build; adding icuin makes linking more robust on MSYS2.
  target_link_libraries(pdfalto icuuc icudt icuin)
endif()
if(TARGET pdfalto)
  set_property(TARGET pdfalto PROPERTY CXX_STANDARD 17)
  set_property(TARGET pdfalto PROPERTY CXX_STANDARD_REQUIRED ON)
endif()
if(TARGET pdfalto_server)
  set_property(TARGET pdfalto_server PROPERTY CXX_STANDARD 17)
  set_property(TARGET pdfalto_server PROPERTY CXX_STANDARD_REQUIRED ON)
endif()
EOF
fi

# Build libpng from the bundled source so it matches pdfalto's internal-struct usage.
mkdir -p png-build
/mingw64/bin/cmake -S libs/image/png/src -B png-build -GMSYS\ Makefiles -DCMAKE_BUILD_TYPE=Release -DPNG_SHARED=OFF -DPNG_STATIC=ON
/mingw64/bin/cmake --build png-build -j2
pnglib=$(ls -1 png-build/*.a | head -n 1)
if [ -z "$pnglib" ]; then
  echo "ERROR: could not find built libpng static library under png-build/"
  ls -la png-build || true
  exit 3
fi
if [ -f CMakeLists.txt ]; then
  # Use an absolute path; some CMake/MinGW combinations treat relative *.a paths as -l<name>.
  pnglib_abs="$(cd "$(dirname "$pnglib")" && pwd)/$(basename "$pnglib")"
  if [ ! -f "$pnglib_abs" ]; then
    echo "ERROR: expected libpng at $pnglib_abs but it does not exist"
    exit 4
  fi
  sed -Ei "s@set \\( PNG_LIBRARIES .*@set ( PNG_LIBRARIES ${pnglib_abs})@" CMakeLists.txt || true
fi

/mingw64/bin/cmake -GMSYS\ Makefiles -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_CXX_STANDARD=14 -DCMAKE_CXX_STANDARD_REQUIRED=ON .
make -j2

if [ ! -f ./pdfalto.exe ]; then
  echo "ERROR: build did not produce pdfalto.exe in repo root"
  exit 2
fi

mkdir -p "$PDFALTO_OUTDIR"
cp -f ./pdfalto.exe "$PDFALTO_OUTDIR/pdfalto.exe"
if [ -f ./pdfalto_server.exe ]; then
  cp -f ./pdfalto_server.exe "$PDFALTO_OUTDIR/pdfalto_server.exe"
fi

# Copy dependent DLLs for the binaries from mingw64 runtime
deps=$(ldd ./pdfalto.exe | awk '{print $3}' | grep -E '^/mingw64/bin/.*\.dll$' | sort -u || true)
for d in $deps; do
  bn=$(basename "$d")
  cp -f "$d" "$PDFALTO_OUTDIR/$bn"
done

if [ -f ./pdfalto_server.exe ]; then
  deps2=$(ldd ./pdfalto_server.exe | awk '{print $3}' | grep -E '^/mingw64/bin/.*\.dll$' | sort -u || true)
  for d in $deps2; do
    bn=$(basename "$d")
    cp -f "$d" "$PDFALTO_OUTDIR/$bn"
  done
fi
'@

# IMPORTANT: When passing a multi-line bash script via `bash -lc`, CRLF line endings can
# break bash parsing (especially lines ending with `\` continuations) and result in
# errors like "syntax error: unexpected end of file from `if`".
# Normalize to LF before invoking bash.
$bashCmd = $bashCmd -replace "`r`n", "`n"
$bashCmd = $bashCmd -replace "`r", "`n"

# Run in MSYS2 bash.
# IMPORTANT: passing a large multi-line script via `bash -lc "<script>"` can be brittle on Windows.
# We instead write the script to a file under the temp work dir and execute it from bash via `cygpath`.
$bashScriptWin = Join-Path $work "build_pdfalto_win64_msys2.sh"
# PowerShell 5.1's `Set-Content -Encoding UTF8` writes a BOM which can break bash parsing.
# Use .NET to write UTF-8 without BOM (works on both Windows PowerShell 5.1 and PowerShell 7+).
[System.IO.File]::WriteAllText($bashScriptWin, $bashCmd, (New-Object System.Text.UTF8Encoding($false)))
$env:PDFALTO_BASH_SCRIPT = $bashScriptWin

$bashWrapper = @'
set -euo pipefail
script_unix=$(cygpath -u "$PDFALTO_BASH_SCRIPT")
bash "$script_unix"
'@
$bashWrapper = $bashWrapper -replace "`r`n", "`n"
$bashWrapper = $bashWrapper -replace "`r", "`n"

& $bash -lc $bashWrapper
if ($LASTEXITCODE -ne 0) {
    throw "MSYS2 build failed (exit code $LASTEXITCODE). Not packaging/validating."
}

Write-Host "Build completed. Packaging into repo artifact zip + sha256..." -ForegroundColor Cyan
& (Join-Path $repoRoot "grobid-home\\scripts\\package_pdfalto_win64.ps1") -PdfaltoDir $outDir -VersionTag $PdfaltoTag

Write-Host "OK: Built and packaged pdfalto win64 $PdfaltoTag" -ForegroundColor Green


  sed -Ei 's@set \( FREETYPE_LIBRARY .*@set ( FREETYPE_LIBRARY freetype)@' CMakeLists.txt || true
  # MSYS2 ICU uses icuuc + icudt (not "icudata").
  sed -Ei 's@set \( ICUUC_LIB .*@set ( ICUUC_LIB icuuc)@' CMakeLists.txt || true
  sed -Ei 's@set \( ICUDATA_LIB .*@set ( ICUDATA_LIB icudt)@' CMakeLists.txt || true

  # xpdf (static) references Windows COM helpers (CoInitialize, IID_*). Ensure final link includes the required system libs.
  # Ensure the file ends with a newline before appending to avoid CMake parse errors.
  printf '\n' >> CMakeLists.txt
  cat >> CMakeLists.txt <<'EOF'
if(WIN32)
  target_link_libraries(pdfalto ole32 uuid shell32)
  # ICU can require additional components depending on build; adding icuin makes linking more robust on MSYS2.
  target_link_libraries(pdfalto icuuc icudt icuin)
endif()
if(TARGET pdfalto)
  set_property(TARGET pdfalto PROPERTY CXX_STANDARD 17)
  set_property(TARGET pdfalto PROPERTY CXX_STANDARD_REQUIRED ON)
endif()
if(TARGET pdfalto_server)
  set_property(TARGET pdfalto_server PROPERTY CXX_STANDARD 17)
  set_property(TARGET pdfalto_server PROPERTY CXX_STANDARD_REQUIRED ON)
endif()
EOF
fi

# Build libpng from the bundled source so it matches pdfalto's internal-struct usage.
mkdir -p png-build
/mingw64/bin/cmake -S libs/image/png/src -B png-build -GMSYS\ Makefiles -DCMAKE_BUILD_TYPE=Release -DPNG_SHARED=OFF -DPNG_STATIC=ON
/mingw64/bin/cmake --build png-build -j2
pnglib=$(ls -1 png-build/*.a | head -n 1)
if [ -z "$pnglib" ]; then
  echo "ERROR: could not find built libpng static library under png-build/"
  ls -la png-build || true
  exit 3
fi
if [ -f CMakeLists.txt ]; then
  # Use an absolute path; some CMake/MinGW combinations treat relative *.a paths as -l<name>.
  pnglib_abs="$(cd "$(dirname "$pnglib")" && pwd)/$(basename "$pnglib")"
  if [ ! -f "$pnglib_abs" ]; then
    echo "ERROR: expected libpng at $pnglib_abs but it does not exist"
    exit 4
  fi
  sed -Ei "s@set \\( PNG_LIBRARIES .*@set ( PNG_LIBRARIES ${pnglib_abs})@" CMakeLists.txt || true
fi

/mingw64/bin/cmake -GMSYS\ Makefiles -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_CXX_STANDARD=14 -DCMAKE_CXX_STANDARD_REQUIRED=ON .
make -j2

if [ ! -f ./pdfalto.exe ]; then
  echo "ERROR: build did not produce pdfalto.exe in repo root"
  exit 2
fi

mkdir -p "$PDFALTO_OUTDIR"
cp -f ./pdfalto.exe "$PDFALTO_OUTDIR/pdfalto.exe"
if [ -f ./pdfalto_server.exe ]; then
  cp -f ./pdfalto_server.exe "$PDFALTO_OUTDIR/pdfalto_server.exe"
fi

# Copy dependent DLLs for the binaries from mingw64 runtime
deps=$(ldd ./pdfalto.exe | awk '{print $3}' | grep -E '^/mingw64/bin/.*\.dll$' | sort -u || true)
for d in $deps; do
  bn=$(basename "$d")
  cp -f "$d" "$PDFALTO_OUTDIR/$bn"
done

if [ -f ./pdfalto_server.exe ]; then
  deps2=$(ldd ./pdfalto_server.exe | awk '{print $3}' | grep -E '^/mingw64/bin/.*\.dll$' | sort -u || true)
  for d in $deps2; do
    bn=$(basename "$d")
    cp -f "$d" "$PDFALTO_OUTDIR/$bn"
  done
fi
'@

# IMPORTANT: When passing a multi-line bash script via `bash -lc`, CRLF line endings can
# break bash parsing (especially lines ending with `\` continuations) and result in
# errors like "syntax error: unexpected end of file from `if`".
# Normalize to LF before invoking bash.
$bashCmd = $bashCmd -replace "`r`n", "`n"
$bashCmd = $bashCmd -replace "`r", "`n"

# Run in MSYS2 bash.
# IMPORTANT: passing a large multi-line script via `bash -lc "<script>"` can be brittle on Windows.
# We instead write the script to a file under the temp work dir and execute it from bash via `cygpath`.
$bashScriptWin = Join-Path $work "build_pdfalto_win64_msys2.sh"
# PowerShell 5.1's `Set-Content -Encoding UTF8` writes a BOM which can break bash parsing.
# Use .NET to write UTF-8 without BOM (works on both Windows PowerShell 5.1 and PowerShell 7+).
[System.IO.File]::WriteAllText($bashScriptWin, $bashCmd, (New-Object System.Text.UTF8Encoding($false)))
$env:PDFALTO_BASH_SCRIPT = $bashScriptWin

$bashWrapper = @'
set -euo pipefail
script_unix=$(cygpath -u "$PDFALTO_BASH_SCRIPT")
bash "$script_unix"
'@
$bashWrapper = $bashWrapper -replace "`r`n", "`n"
$bashWrapper = $bashWrapper -replace "`r", "`n"

& $bash -lc $bashWrapper
if ($LASTEXITCODE -ne 0) {
    throw "MSYS2 build failed (exit code $LASTEXITCODE). Not packaging/validating."
}

Write-Host "Build completed. Packaging into repo artifact zip + sha256..." -ForegroundColor Cyan
& (Join-Path $repoRoot "grobid-home\\scripts\\package_pdfalto_win64.ps1") -PdfaltoDir $outDir -VersionTag $PdfaltoTag

Write-Host "OK: Built and packaged pdfalto win64 $PdfaltoTag" -ForegroundColor Green

