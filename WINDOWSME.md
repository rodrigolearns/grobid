## GROBID Native Windows Support (Research Signals fork)

This document describes the **native Windows support** added in this fork, with a clear separation between:

- **Core (out-of-the-box)**: native Windows service + real PDF processing (requires `pdfalto`)
- **Optional ML (DeLFT)**: deep learning models via Python/JEP/TensorFlow (explicit opt-in)

Upstream GROBID explicitly calls out Windows as an area needing help:

> "GROBID should run properly 'out of the box' on Linux (64 bits) and macOS (Intel and ARM). **We cannot ensure currently support for Windows as we did before (help welcome!)**"

### Relationship to upstream (Research Signals)

- **Baseline**: `Research-Signals/grobid` (forked from `kermitt2/grobid`) does not guarantee native Windows support and often recommends Docker on Windows.
- **Why this fork exists**: enable a native Windows path for Research Signals development/debugging and contribution workflows.
- **Compatibility principle**: preserve Linux/macOS behavior; scope Windows changes to platform-guarded code paths where possible.

### PR summary (what changed / why it’s maintainable)

- **Core experience**: `.\gradlew.bat run` provisions and verifies **`pdfalto 0.4`** automatically on Windows (no manual downloads).
- **Reliability over network variance**: bootstrap prefers a **bundled zip** (deterministic/offline), with optional override URL for enterprise mirrors.
- **Correct binary selection**: on Windows, GROBID invokes **`pdfalto.exe`** (0.4) to avoid stale/unsupported `pdfalto_server.exe` variants.
- **Windows-safe execution**: Unix-only flags (`--timeout`, `--ulimit`) are guarded on Windows.
- **Reviewability**: key behavior is owned by a small set of files (Gradle bootstrap task + one command-selection point in `grobid-core`), plus a clear file map below.

### Scopes (what you get when you clone this repo)

#### Core (out-of-the-box, Windows)

- **Goal**: clone → `.\gradlew.bat run` → health + PDF endpoints work.
- **Key design choice**: Gradle provisions **`pdfalto 0.4`** with integrity verification (no manual downloads).

#### Optional ML (DeLFT)

- **Goal**: keep core quickstart clean, while enabling DeLFT via an explicit opt-in workflow.
- **Why it’s opt-in**: DeLFT introduces Python + TensorFlow + native JEP binaries + large model/embedding assets and is not suitable for a “core quickstart” guarantee.
- **What’s different**: adds Python + TensorFlow + JEP + DeLFT repo + a machine-specific config file (ignored by Git).
- **Entry point**: `:grobid-service:runDelftWindows` using `grobid-home/config/grobid-delft-windows.yaml` (generated from the template).
- **DeLFT roadmap**: see `DELFTING.md` for the phase plan.

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

#### 4) `pdfalto_server` is not reliable on Windows for `0.4`

- **Problem**: GROBID’s “server-mode” historically calls `pdfalto_server` as a separate executable. In practice, for Windows bundles targeting `pdfalto 0.4`, a working `pdfalto_server.exe` is not reliably available (and older builds can accidentally ship a stale `0.1` binary).
- **Fix**: on Windows we always invoke **`pdfalto.exe`** (0.4) even when GROBID is running in “server mode”. This keeps the fast-path process management (`ProcessPdfToXml`) while ensuring we use the correct version.

## What we implemented in this fork (current behavior)

### 1) Gradle-native Windows bootstrap for `pdfalto`

We added a Gradle task implemented in `buildSrc`:

- `:grobid-service:ensurePdfaltoWindows` (`org.grobid.gradle.EnsurePdfaltoWindowsTask`)
- `:grobid-service:run` depends on it, so `.\gradlew.bat run` is self-contained on Windows.
- **Owned by**: `grobid/build.gradle`, `grobid/buildSrc/src/main/groovy/org/grobid/gradle/EnsurePdfaltoWindowsTask.groovy`

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

- Preferred: verify SHA256 via `grobid-home/pdfalto/win-64/pdfalto-win64-0.4.sha256` (manifest-driven; fails on mismatch).
- If the manifest is missing/empty (maintainer builds), bootstrap falls back to a **presence-only** check to keep packaging workflows unblocked.

### 2) Windows-safe `java.library.path`

`grobid/build.gradle` builds `java.library.path` correctly on Windows using `File.pathSeparator`, and uses `grobid-home/lib/win-64` (or `win-32`) for native libs.

It also handles activated `CONDA_PREFIX` / `VIRTUAL_ENV` on Windows using `Lib\...` paths.
- **Owned by**: `grobid/build.gradle`

### 3) Windows-safe `pdfalto` flags

In `grobid-core` we guard `--timeout` / `--ulimit` flags in server execution mode on Windows because Windows builds of `pdfalto` do not support them and can exit non-zero.
- **Owned by**: `grobid/grobid-core/src/main/java/org/grobid/core/document/DocumentSource.java`

### 4) Windows-safe `pdfalto` executable selection

On Windows, we select `pdfalto.exe` to avoid unreliable/legacy `pdfalto_server.exe` variants.
- **Owned by**: `grobid/grobid-core/src/main/java/org/grobid/core/document/DocumentSource.java`

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
curl.exe --% -sS -o resp-fulltext.xml -F input=@grobid-service\src\test\resources\sample1\sample.pdf;type=application/pdf http://localhost:8070/api/processFulltextDocument
```

### Strong check: XML parse validity

```powershell
$x = [xml](Get-Content .\resp-fulltext.xml)
$x.DocumentElement.LocalName
```

## Current status (important)

## Status / assumptions

- **pdfalto provisioning**: uses the committed bundle (`pdfalto-win64-0.4.zip`) + verifies via the populated SHA256 manifest (no GitHub/API dependency for `pdfalto` when the bundle is present).
- **Build-time dependencies**: `.\gradlew.bat run` may still download the Gradle distribution (`gradle-wrapper.properties`) and Maven dependencies on first run unless already cached / mirrored internally.

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
- **Bundled zip option**: makes Windows `pdfalto` provisioning robust against blocked `api.github.com` / GitHub release downloads and upstream asset churn. (It does not make Gradle/Maven dependency resolution fully offline.)
- **Manifest-driven SHA verification**: avoids hardcoding file lists and lets the exact runtime DLL set vary (toolchain differences), while still verifying integrity.

## Known gaps / follow-ups (intentionally out of scope for the initial Windows restore)

- **Process cleanup**: `ProcessRunner.killProcess()` uses Unix `pkill`. The intended replacement is a cross-platform approach based on `ProcessHandle`.
  - **Owned by**: `grobid/grobid-core/src/main/java/org/grobid/core/process/ProcessRunner.java`

## Windows support file map (shared vs scope-specific)

This is the scope-oriented “source of truth” for what’s in the repo. If you remove/rename any of these, update this list in the same PR.

### Shared (core + optional ML)

- **Main config (core defaults)**: `grobid-home/config/grobid.yaml`  
  - **Purpose**: baseline service config (CRF by default).
- **Windows libpath handling**: `grobid/build.gradle`  
  - **Purpose**: Windows-aware `java.library.path` wiring + app run tasks.
- **Ignore rules**: `grobid/.gitignore`  
  - **Purpose**: ignore extracted `pdfalto` runtime folder, `.venv`, generated DeLFT config, and JEP DLLs; explicitly allow committing the single `pdfalto-win64-*.zip` bundle.

### Core-only: `pdfalto` bootstrap (required for real PDF processing)

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

### Optional ML-only: DeLFT / JEP (explicit opt-in)

- **DeLFT setup (PowerShell)**: `grobid-home/scripts/setup_delft_windows.ps1`  
  - **Purpose**: create `grobid-home/.venv`, install TensorFlow + JEP, clone/register DeLFT, update `grobid.yaml`, and generate a machine-specific config.
- **DeLFT setup wrapper (BAT)**: `grobid-home/scripts/setup_delft_windows.bat`  
  - **Purpose**: convenience wrapper to run the PS1 from `cmd.exe`.
- **DeLFT config template (example)**: `grobid-home/config/grobid-delft-windows.example.yaml`  
  - **Purpose**: checked-in template (no machine-specific paths); copied/generated into `grobid-home/config/grobid-delft-windows.yaml`.
- **DeLFT config (generated, ignored)**: `grobid-home/config/grobid-delft-windows.yaml`  
  - **Purpose**: local file with absolute paths; intentionally ignored by Git (see `.gitignore`).
- **DeLFT run task**: `:grobid-service:runDelftWindows` (Gradle)  
  - **Purpose**: starts grobid-service with the DeLFT-enabled config (keeps core `run` clean).
- **JEP helper (PowerShell)**: `grobid-home/scripts/install_jep_lib.ps1`  
  - **Purpose**: legacy/standalone helper to install JEP + DeLFT deps into an existing Python environment.
- **JEP helper wrapper (BAT)**: `grobid-home/scripts/install_jep_lib.bat`  
  - **Purpose**: convenience wrapper to run the PS1 from `cmd.exe`.

## Licensing note

`pdfalto` is licensed under **GPL-2.0**. Bundling binaries inside an Apache-2.0 project has implications.
We keep the Windows bundle as a single, clearly documented artifact and treat it as a pragmatic Windows enablement workaround.

## Testing checklist (recommended)

- **Bootstrap**: `.\gradlew.bat :grobid-service:ensurePdfaltoWindows --info` succeeds and verifies SHA256 via `pdfalto-win64-0.4.sha256`.
- **API**: `/api/isalive` and one PDF endpoint (`processFulltextDocument`) succeed.
- **Integrity**: tamper with one file in the bundle zip and confirm bootstrap fails (SHA mismatch).