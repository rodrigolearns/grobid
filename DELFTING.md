## DeLFT on Windows: development path (Research Signals GROBID fork)

This document is the follow-on plan after Windows `pdfalto 0.4` bootstrap: **optional DeLFT (deep learning) support on native Windows**, aligned with the fork’s “core quickstart stays one-command” philosophy.

DeLFT is **not** part of the core quickstart because it pulls in Python + TensorFlow + native JEP binaries + large model/embedding assets. The goal is a clean, repeatable, maintainer-friendly path that matches upstream’s configuration model.

### What “great UX” means for the optional ML path

- **Explicit opt-in**: core remains `.\gradlew.bat run`; DeLFT is an intentional “ML mode”.
- **Deterministic outputs**: setup produces a known venv location + known DeLFT repo location + a generated config file.
- **Fast confidence checks**: one small smoke test proves DeLFT inference is really used (not silently falling back).
- **Honest resource expectations**: document disk/RAM/network requirements up front (especially embeddings/LMDB behavior).

### Current state (what exists today)

- **Config keys (upstream-compatible)**: `grobid.delft.install`, `grobid.delft.pythonVirtualEnv` (`grobid/grobid-core/.../GrobidConfig.java`, `GrobidProperties.java`)
- **Windows bootstrap script**: `grobid/grobid-home/scripts/setup_delft_windows.ps1` (creates `grobid-home/.venv`, installs TF + JEP, clones DeLFT, generates `grobid-home/config/grobid-delft-windows.yaml`)
- **Windows run task (optional)**: `.\gradlew.bat :grobid-service:runDelftWindows` (runs service using `grobid-home/config/grobid-delft-windows.yaml`)

### Resource and network expectations (Windows)

DeLFT requires **more disk and network** than core CRF mode.

- **Disk (rough budgeting)**
  - **Python venv + wheels** (TensorFlow + deps + JEP): plan for **~3–8 GB**
  - **DeLFT repo clone**: small (**< 1 GB**)
  - **Embeddings / transformers caches**: can be **multiple GB** depending on model choices
  - **LMDB**: the config exposes `lmdbMapSizeGb`; this is a *map-size ceiling* (address space limit), not “preallocated disk”, but the **actual LMDB/embedding data** can still consume **many GB** on disk
  - Practical recommendation: reserve **~15–30 GB free** if you intend to run DeLFT models that rely on embeddings/caches

- **RAM / CPU**
  - CPU-only TensorFlow on Windows is supported; inference throughput depends heavily on model choice.
  - Practical recommendation: **16 GB RAM** minimum for a smooth experience; more helps when models/caches are cold.

- **Network**
  - Setup typically needs to download Python packages (pip) and clone DeLFT (git).
  - In enterprise environments, plan to support:
    - internal PyPI mirrors / allowlists
    - an internal mirror for the DeLFT repo (or vendoring a pinned commit in a maintained mirror)

### Phase A — Make the runtime discovery truly Windows-native (Java side)

**Objective**: Ensure the Java runtime can locate the Windows venv layout without requiring “activate venv” hacks.

- **Work**
  - Ensure venv discovery supports Windows layouts (`<venv>/Lib/site-packages`) in `PythonEnvironmentConfig`.
  - Ensure JEP include paths and native library lookup work when venv paths are provided via YAML config.
  - Ensure error messages are explicit (“missing DeLFT install”, “missing pythonVirtualEnv”, “missing jep*.dll”, “cannot import delft”).

- **Acceptance**
  - With `grobid-home/config/grobid-delft-windows.yaml` populated, `:grobid-service:runDelftWindows` starts successfully.
  - A DeLFT-backed endpoint works (see Phase C).

### Phase B — Hardening the Windows bootstrap (PowerShell script + repo hygiene)

**Objective**: Keep the Windows setup path deterministic, maintainable, and consistent with “meaning per word”.

- **Work**
  - Pin and document the supported Python/TensorFlow matrix (CPU-only on native Windows unless explicitly choosing WSL2/GPU).
  - Keep DeLFT installed as a repo clone + `.pth` registration (avoid `pip install delft` pins that force source builds).
  - Make the output of the setup script a stable “contract”:
    - `grobid-home/.venv/` created
    - `../delft/` clone present (or configured location)
    - `grobid-home/config/grobid-delft-windows.yaml` generated (ignored by Git)
  - Add a **preflight** that checks disk space and prints an estimate/warning before downloading large deps.
  - Add a **non-interactive mode** contract suitable for CI/devboxes (fail fast with clear messages instead of prompts).
  - Add a small, deterministic “sanity probe” command the script can run (import checks + presence of `jep*.dll`).

- **Acceptance**
  - Setup script succeeds on a clean Windows machine with standard prerequisites (JDK + Git).
  - Re-running is idempotent (`-Force` recreates, normal runs reuse).
  - Script prints a clear summary including **where disk-heavy caches/outputs live** (venv path, DeLFT path, config path).

### Phase C — End-to-end validation + minimal smoke tests

**Objective**: Validate DeLFT inference end-to-end without requiring a PDF pipeline.

- **Work**
  - Confirm at least one model is configured to use `engine: delft` in `grobid-delft-windows.yaml` (e.g., `citation`).
  - Add a documented smoke test that hits a DeLFT-dependent endpoint (fastest signal):
    - `POST /api/processCitation` with a short citation string
  - Add an “activation check” that proves the request actually used DeLFT:
    - easiest approach is log-based (look for DeLFT model init / JEP init messages)
    - if feasible, add an explicit diagnostic endpoint or health detail later (optional)
  - Add a tiny automated test (optional) that is skipped unless DeLFT config is present.

- **Acceptance**
  - `.\gradlew.bat :grobid-service:runDelftWindows` + `POST /api/processCitation` returns a valid TEI citation output.
  - The activation check confirms DeLFT was actually invoked.

### Phase D — Maintainability & upstream friendliness

**Objective**: Make it easy for maintainers to keep DeLFT support healthy without turning the repo into “Python distro management”.

- **Work**
  - Add a short doc section summarizing:
    - what is supported (native Windows CPU path),
    - what is explicitly out-of-scope (GPU without WSL2, shipping giant embedding assets in git),
    - how to troubleshoot at the “what failed” level (missing config, missing native lib).
  - Consider CI as *lint/structure checks* only (not full TF installs), e.g.:
    - validate script syntax,
    - validate that config templates parse as YAML,
    - validate Gradle task existence.
  - Add a “pinned inputs” policy for maintainers:
    - which DeLFT commit is expected
    - which TensorFlow/JEP versions are known-good on Windows
    - how to update them safely

- **Acceptance**
  - A maintainer can review changes quickly and see the boundary: core quickstart vs optional ML.


