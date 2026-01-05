## GROBID Native Windows Support (Research Signals fork)

This document tracks work to restore **native Windows support** for GROBID in the Research Signals “GOBRID” fork.

Upstream GROBID explicitly calls out Windows as an area needing help:

> "GROBID should run properly 'out of the box' on Linux (64 bits) and macOS (Intel and ARM). **We cannot ensure currently support for Windows as we did before (help welcome!)**"

### Overview

This fork aims to make GROBID run **natively on Windows**, while preserving Linux/macOS behavior.

- **Out-of-the-box scope (Windows, core)**: a Windows user can clone the repo, run the service, and use core endpoints (health + PDF processing) without hand-editing files or applying local patches.
- **Optional ML scope (DeLFT)**: **available, but not part of the one-command core quickstart**. DeLFT on Windows requires an explicit setup step (Python/JEP/TensorFlow + config), and the repo includes scripts/templates to support that workflow.

Upstream often recommends Docker on Windows for production. This work provides a native Windows option aimed at Research Signals development/debugging and contribution workflows.

### Success criteria (“one-command quickstart”)

- A Windows user can clone this repo and run `.\gradlew.bat run`
- The service starts successfully, and core PDF endpoints produce real TEI output
- No “mystery manual steps” like “install X”, “run this PowerShell script first”, or “download binaries manually”

## What was broken on Windows (and what we changed)

The main Windows breakpoints we’re addressing are:

#### 1) Gradle build + runtime `java.library.path` on Windows

- **Broken behavior**: OS/platform detection and library path building assumed Unix/Mac conventions.
- **Fix**: Windows-aware branches in `grobid/build.gradle`, using `File.pathSeparator` and `grobid-home/lib/win-*`, plus defensive `CONDA_PREFIX` / `VIRTUAL_ENV` handling (`Lib\...`).

#### 2) PDF parsing: the `pdfalto` dependency

GROBID relies on a native PDF → XML converter called **`pdfalto`**. On Windows it’s often missing or outdated (e.g., `0.1`), causing PDF processing failures even though the service starts.

Complication: upstream `kermitt2/pdfalto` does **not reliably publish** a Windows binary asset for the exact version we need (0.4), and many enterprise networks block `api.github.com` or GitHub download redirects. That’s why “just download it at runtime” can be flaky.

#### 3) `pdfalto` flags not supported on Windows

- **Broken behavior**: server-mode added Unix-only flags (`--timeout`, `--ulimit`) that Windows `pdfalto` builds don’t support.
- **Fix**: guard these flags on Windows (`grobid-core`).

#### 5) `pdfalto_server` is not reliable on Windows for `0.4`

- **Problem**: GROBID’s “server-mode” historically calls `pdfalto_server` as a separate executable. In practice, for Windows bundles targeting `pdfalto 0.4`, a working `pdfalto_server.exe` is not reliably available (and older builds can accidentally ship a stale `0.1` binary).
- **Fix**: on Windows we always invoke **`pdfalto.exe`** (0.4) even when GROBID is running in “server mode”. This keeps the fast-path process management (`ProcessPdfToXml`) while ensuring we use the correct version.

#### 4) Process management assumed Unix

- **Broken behavior**: `ProcessRunner.killProcess()` still uses `pkill` and Unix PID reflection.
- **Status**: still a known limitation; should be replaced by a cross-platform `ProcessHandle` approach in a follow-up.

## What we implemented in this fork (current behavior)

### 1) Gradle-native Windows bootstrap for `pdfalto`

We added a Gradle task implemented in `buildSrc`:

- `:grobid-service:ensurePdfaltoWindows` (`org.grobid.gradle.EnsurePdfaltoWindowsTask`)
- `:grobid-service:run` depends on it, so `.\gradlew.bat run` is self-contained on Windows.

**Install source priority order**

1. **Bundled zip in the repo** (offline + deterministic):  
   `grobid-home/pdfalto/win-64/pdfalto-win64-0.4.zip`
2. **Enterprise override URL** (for internal mirrors):  
   - Env: `GROBID_PDFALTO_URL`  
   - JVM prop: `-Dgrobid.pdfalto.windows.url=...`
3. **Fallback mirrors / GitHub API** (best-effort; may be blocked)

**Install destination**

- Extracts/copies into: `grobid-home/pdfalto/win-64/pdfalto/`
- That folder is intended to be **ignored by Git** (local machine install), while the single zip artifact is what we would commit.

**Verification model**

- Preferred: verify SHA256 via `grobid-home/pdfalto/win-64/pdfalto-win64-0.4.sha256` (manifest-driven).
- If the manifest is missing/empty, bootstrap falls back to a **presence-only** check (this keeps maintainer workflows usable until the manifest is populated).

### 2) Windows-safe `java.library.path`

`grobid/build.gradle` builds `java.library.path` correctly on Windows using `File.pathSeparator`, and uses `grobid-home/lib/win-64` (or `win-32`) for native libs.

It also handles activated `CONDA_PREFIX` / `VIRTUAL_ENV` on Windows using `Lib\...` paths.

### 3) Windows-safe `pdfalto` flags

In `grobid-core` we guard `--timeout` / `--ulimit` flags in server execution mode on Windows because Windows builds of `pdfalto` do not support them and can exit non-zero.

### 4) Known limitation: Unix-only `pkill` in process cleanup

`ProcessRunner.killProcess()` still uses `pkill` (Unix-only). On Windows this generally becomes a no-op because PID detection is Unix-specific, but it’s still not ideal and should be replaced with a Windows-safe approach (`ProcessHandle`) in a follow-up.

## Quickstart (native Windows, core)

### Prerequisites

- Windows x86_64
- JDK 17

### Run

From the `grobid/` directory:

```powershell
.\gradlew.bat run
```

### Verify health

```powershell
curl.exe -sS http://localhost:8070/api/isalive
```

### Smoke test (fulltext)

```powershell
curl.exe -sS -o resp-fulltext.xml -F "input=@grobid-service\src\test\resources\sample1\sample.pdf;type=application/pdf" http://localhost:8070/api/processFulltextDocument
```

### Strong check: XML parse validity

```powershell
[xml]$x = Get-Content .\resp-fulltext.xml
$x.DocumentElement.Name
```

## Current status (important)

- The **bootstrap wiring is present** (Gradle task + run dependency).
- The **bundled zip is present**: `grobid-home/pdfalto/win-64/pdfalto-win64-0.4.zip`
- The **`.sha256` manifest is populated**: `grobid-home/pdfalto/win-64/pdfalto-win64-0.4.sha256`

That means: **today**, Windows users can run `.\gradlew.bat run` offline using the committed bundle, and the Gradle bootstrap can verify integrity via the manifest.

## Maintainer workflow: build + package the Windows bundle

We maintain scripts under `grobid-home/scripts/` to produce a repo-committable bundle:

- `build_pdfalto_win64_msys2.bat`: build pdfalto 0.4 on Windows using MSYS2
- `package_pdfalto_win64.ps1`: zip `grobid-home/pdfalto/win-64/pdfalto/` → write the `.zip` and `.sha256` manifest

Once successfully built, commit **only**:

- `grobid-home/pdfalto/win-64/pdfalto-win64-0.4.zip`
- `grobid-home/pdfalto/win-64/pdfalto-win64-0.4.sha256`

…and keep the extracted folder ignored:

- `grobid-home/pdfalto/win-64/pdfalto/`

## Design choices (why we did it this way)

- **Gradle-native bootstrap**: no reliance on PowerShell availability for end users; easier to keep cross-platform and testable.
- **Bundled zip option**: makes the “one-command quickstart” robust against blocked networks and upstream asset churn.
- **Manifest-driven SHA verification**: avoids hardcoding file lists and lets the exact runtime DLL set vary (toolchain differences), while still verifying integrity.

## Windows support file inventory (do not delete without updating this doc)

This section is the “source of truth” checklist for Windows enablement in this fork. If you remove/rename any of these, update this list in the same PR.

### Core: `pdfalto` (required for real PDF processing)

- **Gradle bootstrap task**: `grobid/buildSrc/src/main/groovy/org/grobid/gradle/EnsurePdfaltoWindowsTask.groovy`  
  - **Purpose**: provision `pdfalto 0.4` on Windows during `.\gradlew.bat run` (prefers bundled zip, supports override URL, verifies via `.sha256` manifest).
- **Bundled artifact (temporary workaround)**: `grobid-home/pdfalto/win-64/pdfalto-win64-0.4.zip`  
  - **Purpose**: the offline/deterministic “one-command quickstart” input; extracted to `grobid-home/pdfalto/win-64/pdfalto/`.
- **SHA256 manifest**: `grobid-home/pdfalto/win-64/pdfalto-win64-0.4.sha256`  
  - **Purpose**: integrity verification for the bundle; format is `SHA256  relative/path`.
- **Maintainer build script**: `grobid-home/scripts/build_pdfalto_win64_msys2.ps1` / `.bat`  
  - **Purpose**: build `pdfalto 0.4` on Windows via MSYS2, producing an install-ready runtime folder.
- **Maintainer packaging script**: `grobid-home/scripts/package_pdfalto_win64.ps1` / `.bat`  
  - **Purpose**: zip the runtime folder and generate the `.sha256` manifest.
- **MSYS2 installer helper (maintainers)**: `grobid-home/scripts/install_msys2_win64.ps1` / `.bat`  
  - **Purpose**: best-effort unattended MSYS2 provisioning (with tarball fallback) for maintainers building `pdfalto`.
- **Optional local helpers**: `grobid-home/scripts/install_pdfalto_windows.ps1` / `.bat`, `verify_pdfalto_windows.ps1` / `.bat`  
  - **Purpose**: local/maintainer-friendly install & verification outside Gradle (should not be required for end users if the Gradle bootstrap works).

### Optional ML: DeLFT / JEP (Windows setup path, not part of core quickstart)

- **DeLFT setup (PowerShell)**: `grobid-home/scripts/setup_delft_windows.ps1`  
  - **Purpose**: create `grobid-home/.venv`, install TensorFlow + JEP, clone/register DeLFT, update `grobid.yaml`, and generate a machine-specific config.
- **DeLFT setup wrapper (BAT)**: `grobid-home/scripts/setup_delft_windows.bat`  
  - **Purpose**: convenience wrapper to run the PS1 from `cmd.exe`.
- **DeLFT config template (example)**: `grobid-home/config/grobid-delft-windows.example.yaml`  
  - **Purpose**: checked-in template (no machine-specific paths); copied/generated into `grobid-home/config/grobid-delft-windows.yaml`.
- **DeLFT config (generated, ignored)**: `grobid-home/config/grobid-delft-windows.yaml`  
  - **Purpose**: local file with absolute paths; intentionally ignored by Git (see `.gitignore`).
- **JEP helper (PowerShell)**: `grobid-home/scripts/install_jep_lib.ps1`  
  - **Purpose**: legacy/standalone helper to install JEP + DeLFT deps into an existing Python environment.
- **JEP helper wrapper (BAT)**: `grobid-home/scripts/install_jep_lib.bat`  
  - **Purpose**: convenience wrapper to run the PS1 from `cmd.exe`.

### Repo hygiene (prevents committing machine-specific artifacts)

- **Ignore rules**: `grobid/.gitignore`  
  - **Purpose**: ignore extracted `pdfalto` runtime folder, `.venv`, generated DeLFT config, and JEP DLLs; explicitly allow committing the single `pdfalto-win64-*.zip` bundle.

## Licensing note (important)

`pdfalto` is licensed under **GPL-2.0**. Bundling binaries inside an Apache-2.0 project has implications.
We keep the Windows bundle as a single, clearly documented artifact and treat it as a pragmatic Windows enablement workaround.