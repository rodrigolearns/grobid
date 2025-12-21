# GROBID Native Windows Support

This document tracks work to restore **native Windows support** for GROBID, responding to the README’s call for help:

> "GROBID should run properly 'out of the box' on Linux (64 bits) and macOS (Intel and ARM). **We cannot ensure currently support for Windows as we did before (help welcome!)**"

## Overview

This repository includes a set of changes intended to make GROBID run **natively on Windows**, while preserving Linux/macOS behavior.

- **Out-of-the-box scope (Windows, core)**: a Windows user can clone the repo, run the service, and use core endpoints (health + PDF processing) without hand-editing code or applying local patches.
- **Optional ML scope (DeLFT)**: Deep Learning support is documented separately as an **optional add-on**.

Upstream GROBID documentation recommends Docker for Windows production deployments. This work provides a native Windows option aimed at development/debugging and Windows-based contribution workflows, while keeping Linux/macOS behavior unchanged.

## What was broken on Windows (and what was changed)

Based on an analysis of the baseline repository ([`Research-Signals/grobid`](https://github.com/Research-Signals/grobid.git)), the following Windows-specific breakpoints were identified. For each item, the corresponding change applied in this repository is summarized (with changes kept Windows-guarded to avoid affecting Linux/macOS behavior).

#### 1) Gradle build + runtime `java.library.path` on Windows

- **Broken behavior**: `build.gradle` treated non-Mac/non-Unix as unsupported and assembled runtime library paths using Unix assumptions, which prevents reliable native library loading at startup on Windows.
- **Fix**: add a Windows branch and build library paths using `File.pathSeparator`, pointing at `grobid-home/lib/win-*`. The env-based augmentation (`VIRTUAL_ENV`/`CONDA_PREFIX`) is now Windows-aware (`Lib\\site-packages`) and defensive (won’t throw if the env layout doesn’t match expectations).

#### 2) Native CRF libraries and Windows packaging expectations

- **Broken behavior**: Windows native library layout differs (`win-64`, `win-32`) and DeLFT requires JEP, which is not shipped with GROBID and must match the user’s Python version; without correct loading, CRF/DeLFT execution fails.
- **Fix**: keep Wapiti as a native DLL under `grobid-home/lib/win-64` and load JEP from the Python environment rather than bundling it.

#### 3) DeLFT/JEP integration: Windows virtualenv discovery and JEP loading

- **Broken behavior**: Windows venv layout (`Lib\\site-packages`) differs and JEP discovery/loading was not Windows-aware; as a result, DeLFT fails to initialize because `jep.dll` cannot be located/loaded reliably.
- **Fix**: Windows-aware `PythonEnvironmentConfig` plus Windows-specific JEP loading in `LibraryLoader`.

#### 4) Embedded Python evaluation + Windows path escaping (`\U...`)

- **Broken behavior**: Windows paths passed into `jep.eval("...")` can trigger Python unicode-escape parsing errors (e.g., `\U` sequences), causing DeLFT initialization to fail despite correct installation.
- **Fix**: sanitize Windows paths to forward slashes (`/`) before using them in embedded Python evaluation.

#### 5) Process management assumed Unix

- **Broken behavior**: Unix-specific process cleanup (`pkill`, `UNIXProcess`) is unavailable on Windows, which can leave orphan processes and destabilize long-running services.
- **Fix**: use Java 9+ `ProcessHandle` APIs for cross-platform process control.

#### 6) PDF parsing: pdfalto path/layout on Windows

- **Broken behavior**: pdfalto 0.4 on Windows is under `grobid-home/pdfalto/win-64/pdfalto/` and depends on adjacent DLLs; if the path/layout is not resolved correctly, PDF parsing (and therefore most REST endpoints) fails.
- **Fix**: resolve the correct Windows pdfalto binary path and align the bundled Windows pdfalto binaries (`pdfalto.exe`, `pdfalto_server.exe`, `cygwin1.dll`) with the expected layout.

#### 7) DeLFT embeddings/LMDB cache sizing vs. disk constraints

- **Broken behavior**: DeLFT embedding compilation allocates large LMDB files; on small/tightly-sized disks this fails during the first run, preventing DeLFT from reaching inference even when everything else is correctly installed.
- **Fix**: make LMDB sizing configurable via `grobid.delft.lmdbMapSizeGb` and document storage planning for DeLFT on cloud VMs.

#### 8) Repeatable Windows setup (no patchwork/manual steps)

- **Broken behavior**: a manual dependency/setup process is error-prone on Windows; relying on `pip install delft` alone risks layout/version mismatch, undermining deterministic “out of the box” setup.
- **Fix**: provide `setup_delft_windows.ps1` to create the venv, install dependencies, clone DeLFT, wire it into the venv, and update `grobid.yaml`.

## Quickstart (native Windows, non-ML / core)

### Prerequisites

- Windows x86_64
- JDK 17 (on PATH or `JAVA_HOME` set)
- Git

### Steps

1) Open PowerShell in the `grobid/` directory of this repo.

2) Start the service:

```powershell
.\gradlew.bat run
```

3) Verify health:

```powershell
curl.exe -sS http://localhost:8070/api/isalive
```

4) Smoke test with a PDF (bundled example):

```powershell
curl.exe -sS -o resp-fulltext.xml -F "input=@grobid-service\src\test\resources\sample1\sample.pdf;type=application/pdf" http://localhost:8070/api/processFulltextDocument
```


## Status

Validated on 2025-12-21:

| Area | Status | Notes |
|------|--------|-------|
| Build | ✅ | Gradle builds successfully |
| Service startup | ✅ | Service starts and responds on `:8070` |
| CRF (Wapiti) | ✅ | Native DLL loads and CRF pipeline runs |
| PDF processing | ✅ | pdfalto-based parsing works (header/fulltext) |
| Deep Learning (DeLFT) | ✅ (optional) | JEP + embeddings + model load validated (see “Optional ML” below) |

Validation evidence (core):
- `GET /api/isalive` returns `200`
- `POST /api/processFulltextDocument` (multipart PDF upload) returns `200` with TEI XML output

## Tested environment (used for validation)

This is the environment used for end-to-end validation of native Windows support (core).

- **Platform**: Google Cloud (Compute Engine)
- **OS**: Windows Server (build `10.0.20348`)
- **Java**: JDK 17 (Adoptium distribution)
- Optional ML (DeLFT) was validated on the same VM using a dedicated `D:` data disk; see the DeLFT section below.

## Deep Learning (DeLFT) setup

DeLFT support is optional. It adds Python/TensorFlow/JEP dependencies and the first run may download and build large embedding caches.

### Setup steps (one-command install)

From the `grobid/` directory:

```powershell
.\grobid-home\scripts\setup_delft_windows.ps1 -DelftInstallPath "D:\delft" -NonInteractive
```

This script:
- creates `grobid-home\.venv`
- installs TensorFlow + JEP + dependencies
- clones DeLFT to the provided `-DelftInstallPath`
- updates `grobid-home/config/grobid.yaml` with absolute, Windows-safe paths for `delft.install` and `delft.pythonVirtualEnv`

### Enabling DeLFT models

By default, core usage does not require DeLFT.

To run GROBID with DeLFT enabled without editing files back and forth, this repository includes a DeLFT-enabled config file and a dedicated Gradle run task.

```powershell
.\gradlew.bat runDelftWindows
```

This uses `grobid-home/config/grobid-delft-windows.yaml`, which enables DeLFT for the `citation` model (and keeps other models on Wapiti), and contains the DeLFT install/venv paths used during validation.

### DeLFT embeddings + LMDB sizing (facts + guidance)

Operational facts observed during validation:
- The DeLFT `citation` model uses **`glove-840B`** embeddings.
- If embeddings are not present locally, DeLFT downloads ~2GB (`glove.840B.300d.zip`).
- DeLFT builds an LMDB cache under `D:\delft\data\db\...` and **pre-allocates** the LMDB file size based on `grobid.delft.lmdbMapSizeGb`.

Clean-slate validation observation (this repo, 2025-12-21):
- With `grobid.delft.lmdbMapSizeGb: 100`, the LMDB file `D:\delft\data\db\glove-840B\data.mdb` was created at **100.00 GiB**.
- On a 200GB `D:` disk, this left approximately **~99 GiB free** immediately after LMDB creation.

Guidance (non-prescriptive):
- Plan storage headroom for the first DeLFT run (download + extraction + LMDB build).
- Consider using a dedicated data disk for DeLFT artifacts on cloud VMs.

## Next steps

- **Upstreamability**: split changes into focused commits/PRs (build/runtime fixes vs. DeLFT/JEP integration vs. docs).
- **Windows coverage**: add a minimal Windows CI job (build + `api/isalive`) to prevent regressions.
- **Optional validation**: if CRF++ is intended to be supported on Windows, add a targeted validation case for `libcrfpp.dll` (current validated CRF path is Wapiti).

---

## Files changed (summary)

The changes are intentionally scoped to Windows-specific branches/paths to preserve Linux/macOS behavior.

### Core runtime / compatibility

| File | Why it changed (Windows impact) |
|------|----------------------------------|
| `build.gradle` | Adds Windows platform handling and correct `java.library.path` assembly; adds `runDelftWindows` task |
| `grobid-core/src/main/java/org/grobid/core/main/LibraryLoader.java` | Loads Wapiti + JEP correctly on Windows (JEP from venv) |
| `grobid-core/src/main/java/org/grobid/core/jni/PythonEnvironmentConfig.java` | Windows venv discovery (`Lib\\site-packages`, `pyvenv.cfg`) |
| `grobid-core/src/main/java/org/grobid/core/process/ProcessRunner.java` | Replaces Unix-only process handling with `ProcessHandle` |
| `grobid-core/src/main/java/org/grobid/core/document/DocumentSource.java` | Windows pdfalto path handling (pdfalto 0.4 layout) |
| `grobid-home/pdfalto/win-64/pdfalto/pdfalto.exe` | Updated Windows pdfalto binary (required by the Windows layout assumptions) |
| `grobid-home/pdfalto/win-64/pdfalto/pdfalto_server.exe` | Updated Windows pdfalto server binary (required by the Windows layout assumptions) |
| `grobid-home/pdfalto/win-64/pdfalto/cygwin1.dll` | Updated dependency DLL shipped alongside Windows pdfalto |

### DeLFT/JEP robustness on Windows

| File | Why it changed (Windows impact) |
|------|----------------------------------|
| `grobid-core/src/main/java/org/grobid/core/jni/JEPThreadPool.java` | Sanitizes Windows paths before `jep.eval(...)`; passes LMDB sizing config |
| `grobid-core/src/main/java/org/grobid/core/jni/JEPThreadPoolClassifier.java` | Same path sanitization for classifier pool |
| `grobid-core/src/main/java/org/grobid/core/jni/DeLFTModel.java` | Sanitizes Windows paths used in model initialization |
| `grobid-core/src/main/java/org/grobid/core/utilities/GrobidConfig.java` | Adds `grobid.delft.lmdbMapSizeGb` configuration binding |
| `grobid-core/src/main/java/org/grobid/core/utilities/GrobidProperties.java` | Exposes `getDelftLmdbMapSizeGb()` for runtime |
| `grobid-home/config/grobid.yaml` | Sets `delft.install`, `pythonVirtualEnv`, and conservative `lmdbMapSizeGb` |
| `grobid-home/scripts/install_jep_lib.ps1` | Installs JEP into the Python environment on Windows (PowerShell) |
| `grobid-home/scripts/install_jep_lib.bat` | Batch wrapper for `install_jep_lib.ps1` |
| `grobid-home/config/grobid-delft-windows.yaml` | Dedicated Windows DeLFT config (enables DeLFT for `citation` without editing default config) |

### Windows setup scripts

| File | Purpose |
|------|---------|
| `grobid-home/scripts/setup_delft_windows.ps1` | One-step DeLFT setup (venv + deps + clone + config + validation) |
| `grobid-home/scripts/setup_delft_windows.bat` | Batch wrapper for PowerShell setup |

### Repo hygiene / documentation

| File | Purpose |
|------|---------|
| `.gitignore` | Prevents committing local Windows validation artifacts (logs, response XMLs) and avoids vendoring JEP DLLs |
| `WINDOWSME.md` | This document |

## Known limitations / operational notes

- **GPU**: not validated as part of this work; validation was performed on CPU.

---

## References

- [GROBID Docker Documentation](https://grobid.readthedocs.io/en/latest/Grobid-docker/)
- [GROBID Troubleshooting - Windows](https://grobid.readthedocs.io/en/latest/Troubleshooting/)
- [GROBID FAQ - Windows](https://grobid.readthedocs.io/en/latest/Frequently-asked-questions/)
- [pdfalto Repository](https://github.com/kermitt2/pdfalto)
- [GitHub Issues - Windows-specific](https://github.com/kermitt2/grobid/issues?q=is%3Aissue+label%3AWindows-specific)
- [WSL Known Issues](https://github.com/kermitt2/grobid/issues/954)




