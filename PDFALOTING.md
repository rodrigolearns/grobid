# PDFALOTING.md

Development plan for **reliably getting `pdfalto 0.4` working on Windows** in a clean, maintainer-friendly way (for the GOBRID / Windows-ready GROBID fork).

This plan is intentionally written as a **repeatable checklist** with clear acceptance criteria.

---

## Background (why this exists)

- **Goal**: `git clone` → `.\gradlew.bat run` on Windows provisions and uses **`pdfalto 0.4`** automatically, with **SHA256 integrity verification**, and without requiring end-users to install MSYS2/Cygwin manually.
- **Constraint**: upstream `kermitt2/pdfalto` does not provide a consistently available “official” Windows `0.4` binary bundle, so the reliable path is to **build + package** it ourselves and then **bootstrap it via Gradle**.

---

## Phase A — Produce a Windows `pdfalto 0.4` runtime bundle (maintainer workflow)

### Objective
Create a **single committed artifact**:
- `grobid/grobid-home/pdfalto/win-64/pdfalto-win64-0.4.zip`
- plus its manifest `grobid/grobid-home/pdfalto/win-64/pdfalto-win64-0.4.sha256`

### Steps
- **A1: Ensure MSYS2 exists (maintainer machine only)**
  - Script: `grobid/grobid-home/scripts/install_msys2_win64.bat`
  - Expected: MSYS2 root exists (default `%LOCALAPPDATA%\msys64`) and includes `usr\bin\bash.exe`.

- **A2: Build + stage runtime folder**
  - Script: `grobid/grobid-home/scripts/build_pdfalto_win64_msys2.bat`
  - What it does (expected):
    - Builds `pdfalto` tag `0.4` in MSYS2 (mingw64)
    - Copies `pdfalto.exe`, `pdfalto_server.exe`, and required dependent DLLs into:
      - `grobid/grobid-home/pdfalto/win-64/pdfalto/`
    - Uses a temp work dir with sufficient disk space (prefer `D:\_tmp` if available).

- **A3: Package bundle + write SHA256 manifest**
  - Script: `grobid/grobid-home/scripts/package_pdfalto_win64.bat`
  - Output:
    - `grobid/grobid-home/pdfalto/win-64/pdfalto-win64-0.4.zip`
    - `grobid/grobid-home/pdfalto/win-64/pdfalto-win64-0.4.sha256` populated with real hashes.

### Acceptance criteria
- **A-pass-1**: Running the staged binary reports 0.4:
  - `grobid\grobid-home\pdfalto\win-64\pdfalto\pdfalto.exe -v` prints `pdfalto version 0.4` (or equivalent 0.4 identifier).
- **A-pass-2**: The staged folder contains a complete runtime:
  - `pdfalto.exe`, `pdfalto_server.exe`, and all needed `.dll` dependencies (no missing DLL error at runtime).
- **A-pass-3**: Bundle exists + manifest is populated:
  - `pdfalto-win64-0.4.zip` exists
  - `pdfalto-win64-0.4.sha256` contains real (non-placeholder) checksums.

---

## Phase B — Make Gradle provisioning airtight (end-user experience)

### Objective
Ensure that Windows users do not need MSYS2 and still get `pdfalto 0.4` automatically when they run:

- `.\gradlew.bat run`

### Steps
- **B1: Provisioning resolution order (deterministic)**
  - Preferred: local committed artifact
    - `grobid-home/pdfalto/win-64/pdfalto-win64-0.4.zip`
  - Optional override for maintainers:
    - URL override (env var / Gradle property, if implemented)
  - Optional fallback:
    - GitHub Releases mirror (if implemented and reliable)

- **B2: SHA256 verification must be mandatory when manifest exists**
  - Verify extracted files against:
    - `grobid-home/pdfalto/win-64/pdfalto-win64-0.4.sha256`
  - Fail-fast if any mismatch occurs.

- **B3: Version enforcement**
  - Do not silently accept `pdfalto 0.1`.
  - If `pdfalto.exe -v` does not indicate `0.4`, provisioning must fail with a clear message.

- **B4: Location of extracted runtime**
  - Extract to:
    - `grobid-home/pdfalto/win-64/pdfalto/`
  - Ensure `pdfalto.exe` can find its required DLLs (colocated or PATH logic).

### Acceptance criteria
- **B-pass-1**: Fresh clone, no manual setup:
  - `.\gradlew.bat run` provisions `pdfalto 0.4` and starts GROBID successfully.
- **B-pass-2**: Integrity:
  - Tampering with one file in the zip causes provisioning to fail due to SHA mismatch.
- **B-pass-3**: Correctness:
  - If `pdfalto 0.1` is present, provisioning refuses it and instructs how to get 0.4.

---

## Phase C — Repo hygiene + documentation polish (professional finish)

### Objective
Make the Windows story clean and maintainable for reviewers and future maintainers.

### Steps
- **C1: Remove/avoid accidental use of `pdfalto 0.1`**
  - Ensure the repo does not ship a stray `pdfalto 0.1` runtime folder as the “default”.
  - If a placeholder is needed, keep only a `.gitkeep` and rely on provisioning.

- **C2: Keep a single source of truth for Windows support**
  - Update `grobid/WINDOWSME.md` to reflect:
    - what is bundled
    - how it is verified
    - where it is extracted
    - known limitations

- **C3: Inventory**
  - Maintain an explicit “do not delete” inventory of Windows support files and their purpose (already present in `WINDOWSME.md`).

### Acceptance criteria
- **C-pass-1**: A new maintainer can read `WINDOWSME.md` and rebuild/update the bundle.
- **C-pass-2**: The repo does not contain ambiguous multiple “pdfalto” versions that could be used accidentally.

---

## Phase D — Automation (impress maintainers + reduce bus factor)

### Objective
Make rebuilding the Windows bundle repeatable and auditable with minimal tribal knowledge.

### Steps (recommended)
- **D1: CI build job**
  - Add a GitHub Actions workflow that builds `pdfalto 0.4` on Windows using MSYS2.
  - Outputs:
    - `pdfalto-win64-0.4.zip`
    - `pdfalto-win64-0.4.sha256`
  - Optionally publish them as Release assets.

- **D2: Provenance**
  - In workflow logs, record:
    - pdfalto git commit hash for tag 0.4
    - MSYS2 package versions
    - SHA256 manifest produced

### Acceptance criteria
- **D-pass-1**: Any maintainer can trigger the workflow and get a reproducible zip+sha artifact.
- **D-pass-2**: Artifacts can be compared between builds (hashes stable unless inputs change).

---

## Operational notes / best practices

- **Disk space**: building `pdfalto` from source can be large; prefer a work drive with tens of GB free.
- **No mystery binaries**: shipped binaries must be reproducible from source and verified by SHA256.
- **Keep end-user experience simple**: end-users should only run `.\gradlew.bat run` and not think about MSYS2.


Development plan for **reliably getting `pdfalto 0.4` working on Windows** in a clean, maintainer-friendly way (for the GOBRID / Windows-ready GROBID fork).

This plan is intentionally written as a **repeatable checklist** with clear acceptance criteria.

---

## Background (why this exists)

- **Goal**: `git clone` → `.\gradlew.bat run` on Windows provisions and uses **`pdfalto 0.4`** automatically, with **SHA256 integrity verification**, and without requiring end-users to install MSYS2/Cygwin manually.
- **Constraint**: upstream `kermitt2/pdfalto` does not provide a consistently available “official” Windows `0.4` binary bundle, so the reliable path is to **build + package** it ourselves and then **bootstrap it via Gradle**.

---

## Phase A — Produce a Windows `pdfalto 0.4` runtime bundle (maintainer workflow)

### Objective
Create a **single committed artifact**:
- `grobid/grobid-home/pdfalto/win-64/pdfalto-win64-0.4.zip`
- plus its manifest `grobid/grobid-home/pdfalto/win-64/pdfalto-win64-0.4.sha256`

### Steps
- **A1: Ensure MSYS2 exists (maintainer machine only)**
  - Script: `grobid/grobid-home/scripts/install_msys2_win64.bat`
  - Expected: MSYS2 root exists (default `%LOCALAPPDATA%\msys64`) and includes `usr\bin\bash.exe`.

- **A2: Build + stage runtime folder**
  - Script: `grobid/grobid-home/scripts/build_pdfalto_win64_msys2.bat`
  - What it does (expected):
    - Builds `pdfalto` tag `0.4` in MSYS2 (mingw64)
    - Copies `pdfalto.exe`, `pdfalto_server.exe`, and required dependent DLLs into:
      - `grobid/grobid-home/pdfalto/win-64/pdfalto/`
    - Uses a temp work dir with sufficient disk space (prefer `D:\_tmp` if available).

- **A3: Package bundle + write SHA256 manifest**
  - Script: `grobid/grobid-home/scripts/package_pdfalto_win64.bat`
  - Output:
    - `grobid/grobid-home/pdfalto/win-64/pdfalto-win64-0.4.zip`
    - `grobid/grobid-home/pdfalto/win-64/pdfalto-win64-0.4.sha256` populated with real hashes.

### Acceptance criteria
- **A-pass-1**: Running the staged binary reports 0.4:
  - `grobid\grobid-home\pdfalto\win-64\pdfalto\pdfalto.exe -v` prints `pdfalto version 0.4` (or equivalent 0.4 identifier).
- **A-pass-2**: The staged folder contains a complete runtime:
  - `pdfalto.exe`, `pdfalto_server.exe`, and all needed `.dll` dependencies (no missing DLL error at runtime).
- **A-pass-3**: Bundle exists + manifest is populated:
  - `pdfalto-win64-0.4.zip` exists
  - `pdfalto-win64-0.4.sha256` contains real (non-placeholder) checksums.

---

## Phase B — Make Gradle provisioning airtight (end-user experience)

### Objective
Ensure that Windows users do not need MSYS2 and still get `pdfalto 0.4` automatically when they run:

- `.\gradlew.bat run`

### Steps
- **B1: Provisioning resolution order (deterministic)**
  - Preferred: local committed artifact
    - `grobid-home/pdfalto/win-64/pdfalto-win64-0.4.zip`
  - Optional override for maintainers:
    - URL override (env var / Gradle property, if implemented)
  - Optional fallback:
    - GitHub Releases mirror (if implemented and reliable)

- **B2: SHA256 verification must be mandatory when manifest exists**
  - Verify extracted files against:
    - `grobid-home/pdfalto/win-64/pdfalto-win64-0.4.sha256`
  - Fail-fast if any mismatch occurs.

- **B3: Version enforcement**
  - Do not silently accept `pdfalto 0.1`.
  - If `pdfalto.exe -v` does not indicate `0.4`, provisioning must fail with a clear message.

- **B4: Location of extracted runtime**
  - Extract to:
    - `grobid-home/pdfalto/win-64/pdfalto/`
  - Ensure `pdfalto.exe` can find its required DLLs (colocated or PATH logic).

### Acceptance criteria
- **B-pass-1**: Fresh clone, no manual setup:
  - `.\gradlew.bat run` provisions `pdfalto 0.4` and starts GROBID successfully.
- **B-pass-2**: Integrity:
  - Tampering with one file in the zip causes provisioning to fail due to SHA mismatch.
- **B-pass-3**: Correctness:
  - If `pdfalto 0.1` is present, provisioning refuses it and instructs how to get 0.4.

---

## Phase C — Repo hygiene + documentation polish (professional finish)

### Objective
Make the Windows story clean and maintainable for reviewers and future maintainers.

### Steps
- **C1: Remove/avoid accidental use of `pdfalto 0.1`**
  - Ensure the repo does not ship a stray `pdfalto 0.1` runtime folder as the “default”.
  - If a placeholder is needed, keep only a `.gitkeep` and rely on provisioning.

- **C2: Keep a single source of truth for Windows support**
  - Update `grobid/WINDOWSME.md` to reflect:
    - what is bundled
    - how it is verified
    - where it is extracted
    - known limitations

- **C3: Inventory**
  - Maintain an explicit “do not delete” inventory of Windows support files and their purpose (already present in `WINDOWSME.md`).

### Acceptance criteria
- **C-pass-1**: A new maintainer can read `WINDOWSME.md` and rebuild/update the bundle.
- **C-pass-2**: The repo does not contain ambiguous multiple “pdfalto” versions that could be used accidentally.

---

## Phase D — Automation (impress maintainers + reduce bus factor)

### Objective
Make rebuilding the Windows bundle repeatable and auditable with minimal tribal knowledge.

### Steps (recommended)
- **D1: CI build job**
  - Add a GitHub Actions workflow that builds `pdfalto 0.4` on Windows using MSYS2.
  - Outputs:
    - `pdfalto-win64-0.4.zip`
    - `pdfalto-win64-0.4.sha256`
  - Optionally publish them as Release assets.

- **D2: Provenance**
  - In workflow logs, record:
    - pdfalto git commit hash for tag 0.4
    - MSYS2 package versions
    - SHA256 manifest produced

### Acceptance criteria
- **D-pass-1**: Any maintainer can trigger the workflow and get a reproducible zip+sha artifact.
- **D-pass-2**: Artifacts can be compared between builds (hashes stable unless inputs change).

---

## Operational notes / best practices

- **Disk space**: building `pdfalto` from source can be large; prefer a work drive with tens of GB free.
- **No mystery binaries**: shipped binaries must be reproducible from source and verified by SHA256.
- **Keep end-user experience simple**: end-users should only run `.\gradlew.bat run` and not think about MSYS2.

