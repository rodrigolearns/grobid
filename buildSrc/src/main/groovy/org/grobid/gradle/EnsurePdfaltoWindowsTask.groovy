package org.grobid.gradle

import org.gradle.api.DefaultTask
import org.gradle.api.GradleException
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.Optional
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.TaskAction

import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import groovy.json.JsonSlurper

/**
 * Gradle-native bootstrap for Windows pdfalto (no PowerShell, no HTML scraping).
 *
 * - Downloads an official pdfalto Windows bundle zip
 * - Installs into grobid-home/pdfalto/win-64/pdfalto
 * - Verifies required files + SHA256 of key binaries
 *
 * Override the download URL if needed (enterprise networks):
 *   -Dgrobid.pdfalto.windows.url=<mirrorZipUrl>
 * or env var:
 *   GROBID_PDFALTO_URL=<mirrorZipUrl>
 */
class EnsurePdfaltoWindowsTask extends DefaultTask {

    @Input
    String pdfaltoVersionTag = "0.4"

    @Input
    @Optional
    String overrideUrl

    @OutputDirectory
    // IMPORTANT: this task is typically attached to a subproject (e.g. :grobid-service).
    // Use rootProject paths so we always refer to the repo-level grobid-home folder.
    File targetDir = project.rootProject.file("grobid-home/pdfalto/win-64/pdfalto")

    /**
     * Bundled binary ZIP committed to this repository (temporary workaround to guarantee one-command Windows quickstart).
     *
     * When present, we prefer this local ZIP to avoid any network dependencies during `gradlew run`.
     */
    private File bundledZipFile() {
        return project.rootProject.file("grobid-home/pdfalto/win-64/pdfalto-win64-${pdfaltoVersionTag}.zip")
    }

    /**
     * Fallback mirror locations (used when upstream pdfalto releases do not publish Windows binary assets).
     * Repo maintainers can publish a single zip (containing pdfalto.exe + required DLLs) as a GitHub Release asset
     * and "one-command" Windows installs will work out-of-the-box.
     *
     * Override with -Dgrobid.pdfalto.windows.url or env GROBID_PDFALTO_URL to point to a different mirror.
     */
    private List<String> defaultMirrorUrls() {
        def tag = pdfaltoVersionTag
        def fileName = "pdfalto-win64-${tag}.zip"
        return [
            // Prefer the fork used by testers (this repo) if the asset is published there.
            "https://github.com/rodrigolearns/grobid/releases/download/pdfalto-win64-${tag}/${fileName}",
            // Expected location if upstream maintainers publish the asset in their repo.
            "https://github.com/Research-Signals/grobid/releases/download/pdfalto-win64-${tag}/${fileName}"
        ]
    }

    /**
     * Required files for a valid install.
     *
     * - If a manifest exists (preferred), required files are the manifest entries.
     * - Otherwise, we fall back to a minimal set of executables (historical default).
     *
     * We intentionally avoid hard-coding a specific runtime DLL set (cyg* vs msys*),
     * because the maintainer-built bundle may vary by toolchain.
     */
    private List<String> requiredFiles() {
        def expected = expectedSha256()
        if (expected != null && !expected.isEmpty()) {
            return expected.keySet().toList()
        }
        // Minimal baseline (manifest-less). We only require pdfalto.exe; server-mode wrappers are optional
        // and may not exist for all Windows bundles.
        return ["pdfalto.exe"]
    }

    // Expected checksums for Windows pdfalto binaries.
    // Preferred: read from grobid-home/pdfalto/win-64/pdfalto-win64-<tag>.sha256 (committed alongside the zip).
    // If the manifest exists but is empty, we treat it as "not available yet" (presence-only verification).
    // Fallback: historical hardcoded values when no manifest exists.
    private Map<String, String> expectedSha256() {
        File manifest = project.rootProject.file("grobid-home/pdfalto/win-64/pdfalto-win64-${pdfaltoVersionTag}.sha256")
        Map<String, String> expected = new LinkedHashMap<>()
        if (manifest.exists()) {
            manifest.readLines("UTF-8")
                .findAll { it != null && it.trim().length() > 0 && !it.trim().startsWith("#") }
                .each { line ->
                    def parts = line.trim().split("\\s+", 2)
                    if (parts.length == 2) {
                        expected.put(parts[1].trim(), parts[0].trim())
                    }
                }
        }
        // If a manifest exists but has no entries, do not silently fall back to hardcoded hashes
        // (those may not match a maintainer-built bundle); just skip SHA verification.
        if (manifest.exists() && expected.isEmpty()) {
            return expected
        }
        if (!manifest.exists() && expected.isEmpty()) {
            expected.put("pdfalto.exe", "FB1CAC5607A24C39C514BA18556831BF56097FFC4B03C1075A05560FB3AA9AE5")
            expected.put("pdfalto_server.exe", "500749D394DFD2A598E85521F04ED89EA5916C1DAA66C5769BFC648974BB5CB5")
            expected.put("cygwin1.dll", "AB54AB444115D42275CE00C62240C81D43C3AFB0C2E2DCE6BCC4CB78D07127DB")
        }
        return expected
    }

    @TaskAction
    void ensureInstalled() {
        if (!isWindows()) {
            logger.info("ensurePdfaltoWindows: not on Windows; skipping.")
            return
        }

        File dir = targetDir
        logger.lifecycle("Ensuring Windows pdfalto is installed and verified...")
        logger.lifecycle("Target directory: ${dir.absolutePath}")

        if (isValidInstall(dir.toPath())) {
            logger.lifecycle("OK: pdfalto already matches expected SHA256.")
            return
        }

        Path zipPath = resolveZip()
        Path extractRoot = newTempDir("extract")
        unzip(zipPath, extractRoot)

        Path pdfaltoExe = findFirst(extractRoot, "pdfalto.exe")
        if (pdfaltoExe == null) {
            throw new GradleException("Downloaded archive did not contain pdfalto.exe (cannot install).")
        }
        Path pdfaltoFolder = pdfaltoExe.parent

        installFromFolder(pdfaltoFolder, dir.toPath())

        // ensure xpdfrc at arch root (grobid-home/pdfalto/win-64/xpdfrc) if missing
        Path archRoot = dir.toPath().parent
        Path xpdfrc = archRoot.resolve("xpdfrc")
        Path xpdfrcCandidate = pdfaltoFolder.resolve("xpdfrc")
        if (!Files.exists(xpdfrc) && Files.exists(xpdfrcCandidate)) {
            Files.copy(xpdfrcCandidate, xpdfrc, StandardCopyOption.REPLACE_EXISTING)
        }

        assertValidInstall(dir.toPath())

        logger.lifecycle("OK: pdfalto installed and verified.")
    }

    private static boolean isWindows() {
        return System.getProperty("os.name", "").toLowerCase(Locale.ROOT).contains("windows")
    }

    private boolean isValidInstall(Path dir) {
        try {
            for (String name : requiredFiles()) {
                if (!Files.exists(dir.resolve(name))) {
                    return false
                }
            }
            expectedSha256().each { k, v ->
                String actual = EnsurePdfaltoWindowsTask.sha256Hex(dir.resolve(k))
                if (!actual.equalsIgnoreCase(v)) {
                    return false
                }
            }
            return true
        } catch (Exception ignored) {
            return false
        }
    }

    private void assertValidInstall(Path dir) {
        for (String name : requiredFiles()) {
            if (!Files.exists(dir.resolve(name))) {
                throw new GradleException("pdfalto install is missing required file: ${dir.resolve(name)}")
            }
        }
        expectedSha256().each { k, v ->
            Path p = dir.resolve(k)
            if (!Files.exists(p)) {
                throw new GradleException("pdfalto install is missing file from SHA256 manifest: ${p}")
            }
            String actual = EnsurePdfaltoWindowsTask.sha256Hex(p)
            if (!actual.equalsIgnoreCase(v)) {
                throw new GradleException("pdfalto SHA256 mismatch for ${p.fileName}\nExpected: ${v}\nActual:   ${actual}\n(see grobid/WINDOWSME.md)")
            }
        }
    }

    private Path resolveZip() {
        // Cache under Gradle user home so repeated runs are fast and don't re-download.
        File cacheDir = new File(project.gradle.gradleUserHomeDir, "caches/grobid/pdfalto/${pdfaltoVersionTag}")
        cacheDir.mkdirs()
        Path cachedZip = new File(cacheDir, "pdfalto-win64-${pdfaltoVersionTag}.zip").toPath()

        // 0) Preferred (offline, deterministic): use the bundled ZIP if committed in the repo.
        // IMPORTANT: check this BEFORE returning a cached zip, otherwise updating the committed bundle
        // would not take effect on machines with an older cached copy.
        File bundled = bundledZipFile()
        if (bundled.exists()) {
            logger.lifecycle("Using bundled pdfalto ZIP: ${bundled.absolutePath}")
            if (!looksLikeZip(bundled.toPath())) {
                throw new GradleException("Bundled pdfalto ZIP is not a valid ZIP (missing PK header): ${bundled.absolutePath}")
            }
            Files.copy(bundled.toPath(), cachedZip, StandardCopyOption.REPLACE_EXISTING)
            return cachedZip
        }

        if (Files.exists(cachedZip) && looksLikeZip(cachedZip)) {
            return cachedZip
        }

        // 1) Enterprise override (preferred when network blocks GitHub API)
        if (overrideUrl != null && overrideUrl.trim().length() > 0) {
            String url = overrideUrl.trim()
            logger.lifecycle("Downloading pdfalto from override URL: ${url}")
            Path tmp = Files.createTempFile("pdfalto-", ".zip")
            downloadTo(url, tmp)
            if (!looksLikeZip(tmp)) {
                throw new GradleException("Override URL did not return a ZIP (missing PK header): ${url}")
            }
            Files.move(tmp, cachedZip, StandardCopyOption.REPLACE_EXISTING)
            return cachedZip
        }

        // 2) Preferred default: use GitHub Release API to enumerate assets, then pick the first ZIP
        // that actually contains the expected Windows binaries (no filename guessing).
        def assetUrls = []
        try {
            assetUrls = resolveZipAssetUrlsFromGitHubApi(pdfaltoVersionTag)
        } catch (GradleException e) {
            // If the upstream release has no binary assets (common), fall back to maintainer-published mirrors.
            logger.lifecycle("GitHub API resolution failed; trying maintained mirrors. (${e.message})")
            assetUrls = defaultMirrorUrls()
        }
        List<String> errors = []
        for (String assetUrl : assetUrls) {
            try {
                logger.lifecycle("Downloading pdfalto from: ${assetUrl}")
                Path tmp = Files.createTempFile("pdfalto-", ".zip")
                downloadTo(assetUrl, tmp)
                if (!looksLikeZip(tmp)) {
                    throw new IOException("Downloaded file is not a ZIP (missing PK header).")
                }
                if (!zipLooksLikeWindowsPdfalto(tmp)) {
                    throw new IOException("ZIP does not appear to contain Windows pdfalto runtime (missing pdfalto.exe and companion DLLs).")
                }
                Files.move(tmp, cachedZip, StandardCopyOption.REPLACE_EXISTING)
                return cachedZip
            } catch (Exception e) {
                errors.add("${assetUrl} -> ${e.class.simpleName}: ${e.message}")
            }
        }

        throw new GradleException("Could not find a suitable Windows pdfalto ZIP asset in GitHub release ${pdfaltoVersionTag}.\n" +
            "Tried:\n- " + errors.join("\n- "))
    }

    private List<String> resolveZipAssetUrlsFromGitHubApi(String tag) {
        String apiUrl = "https://api.github.com/repos/kermitt2/pdfalto/releases/tags/${tag}"
        try {
            Map<String, String> headers = [
                "Accept"     : "application/vnd.github+json",
                "User-Agent" : "grobid-windows-bootstrap"
            ]
            String token = System.getenv("GITHUB_TOKEN")
            if (token != null && token.trim().length() > 0) {
                headers["Authorization"] = "Bearer " + token.trim()
            }

            HttpURLConnection conn = openHttpFollowingRedirects(new URL(apiUrl), headers, 10)
            def jsonText = conn.getInputStream().getText("UTF-8")
            def obj = new JsonSlurper().parseText(jsonText)
            def assets = obj?.assets
            if (assets == null) {
                throw new IOException("No assets field in GitHub release JSON")
            }

            def zipAssets = assets.findAll { a ->
                def name = (a?.name ?: "").toString().toLowerCase(Locale.ROOT)
                return name.endsWith(".zip")
            }
            if (zipAssets == null || zipAssets.isEmpty()) {
                // Upstream often publishes only "Source code" downloads (not listed under assets),
                // so this is expected in practice.
                throw new IOException("No uploaded .zip assets in GitHub release JSON (assets count=${assets.size()})")
            }

            def urls = zipAssets.collect { a -> a?.browser_download_url?.toString() }
                .findAll { u -> u != null && !u.trim().isEmpty() }
                .unique()

            if (urls.isEmpty()) {
                throw new IOException("ZIP assets missing browser_download_url")
            }

            // Prefer urls that look like windows builds first (but don't require it).
            def preferred = urls.findAll { it.toLowerCase(Locale.ROOT).contains("win") || it.toLowerCase(Locale.ROOT).contains("windows") }
            def rest = urls - preferred
            return preferred + rest
        } catch (Exception e) {
            String hint = "If your network blocks api.github.com, set -Dgrobid.pdfalto.windows.url=<mirrorZipUrl> (or env GROBID_PDFALTO_URL) and re-run."
            throw new GradleException("Failed to resolve pdfalto Windows asset URL from GitHub API (${apiUrl}). " +
                "Reason: ${e.class.simpleName}: ${e.message}\n" + hint, e)
        }
    }

    private static boolean zipLooksLikeWindowsPdfalto(Path zipPath) {
        ZipFile zf = new ZipFile(zipPath.toFile())
        try {
            Set<String> names = new HashSet<>()
            Enumeration<? extends ZipEntry> entries = zf.entries()
            while (entries.hasMoreElements()) {
                ZipEntry e = entries.nextElement()
                if (!e.isDirectory()) {
                    names.add(new File(e.name).name.toLowerCase(Locale.ROOT))
                }
            }
            // Minimal signal that this is the Windows bundle we expect
            if (!names.contains("pdfalto.exe")) return false
            return true
        } finally {
            zf.close()
        }
    }

    private static void downloadTo(String url, Path dest) {
        Map<String, String> headers = [
            "User-Agent": "grobid-windows-bootstrap"
        ]
        HttpURLConnection conn = openHttpFollowingRedirects(new URL(url), headers, 10)
        conn.getInputStream().withCloseable { input ->
            Files.copy(input, dest, StandardCopyOption.REPLACE_EXISTING)
        }
    }

    /**
     * Open an HTTP connection and follow redirects manually.
     * Important: apply headers/timeouts BEFORE triggering the connection (responseCode/connect/getInputStream),
     * otherwise Java can throw IllegalStateException("Already connected") when setting request properties.
     */
    private static HttpURLConnection openHttpFollowingRedirects(URL url, Map<String, String> headers, int maxRedirects) {
        URL current = url
        for (int i = 0; i < maxRedirects; i++) {
            URLConnection raw = current.openConnection()
            if (!(raw instanceof HttpURLConnection)) {
                throw new IOException("Unsupported protocol for URL: ${current}")
            }
            HttpURLConnection h = (HttpURLConnection) raw
            h.instanceFollowRedirects = false
            h.connectTimeout = 30000
            h.readTimeout = 30000
            headers?.each { k, v ->
                if (k != null && v != null) {
                    h.setRequestProperty(k, v)
                }
            }

            int code = h.responseCode
            if (code >= 300 && code < 400) {
                String loc = h.getHeaderField("Location")
                if (loc == null || loc.trim().isEmpty()) {
                    throw new IOException("HTTP ${code} without Location header")
                }
                current = new URL(current, loc)
                continue
            }
            if (code >= 400) {
                throw new IOException("HTTP ${code}")
            }
            return h
        }
        throw new IOException("Too many redirects for URL: ${url}")
    }

    /**
     * Helper used by ProbeUrlsTask to precisely report where GitHub access fails.
     */
    static Map<String, Object> probeUrl(String url, int maxRedirects) {
        Map<String, String> headers = [
            "User-Agent": "grobid-windows-bootstrap"
        ]
        URL current = new URL(url)
        String lastLocation = null
        for (int i = 0; i < maxRedirects; i++) {
            URLConnection raw = current.openConnection()
            if (!(raw instanceof HttpURLConnection)) {
                return [status: -1, finalUrl: current.toString(), locationHeader: null]
            }
            HttpURLConnection h = (HttpURLConnection) raw
            h.instanceFollowRedirects = false
            h.connectTimeout = 15000
            h.readTimeout = 15000
            headers.each { k, v -> h.setRequestProperty(k, v) }

            int code = h.responseCode
            lastLocation = h.getHeaderField("Location")
            if (code >= 300 && code < 400 && lastLocation != null && !lastLocation.trim().isEmpty()) {
                current = new URL(current, lastLocation)
                continue
            }
            return [status: code, finalUrl: current.toString(), locationHeader: lastLocation]
        }
        return [status: -2, finalUrl: current.toString(), locationHeader: lastLocation]
    }

    private static boolean looksLikeZip(Path p) {
        byte[] b = Files.readAllBytes(p)
        return b.length >= 2 && b[0] == (byte) 0x50 && b[1] == (byte) 0x4B
    }

    private Path newTempDir(String prefix) {
        File base = new File(project.gradle.gradleUserHomeDir, "caches/grobid/tmp")
        base.mkdirs()
        return Files.createTempDirectory(base.toPath(), "pdfalto-${prefix}-")
    }

    private static void unzip(Path zip, Path destDir) {
        Files.createDirectories(destDir)
        ZipFile zf = new ZipFile(zip.toFile())
        try {
            Enumeration<? extends ZipEntry> entries = zf.entries()
            while (entries.hasMoreElements()) {
                ZipEntry e = entries.nextElement()
                Path out = destDir.resolve(e.name).normalize()
                if (!out.startsWith(destDir)) {
                    throw new IOException("Zip entry escapes target dir: ${e.name}")
                }
                if (e.isDirectory()) {
                    Files.createDirectories(out)
                } else {
                    Files.createDirectories(out.parent)
                    zf.getInputStream(e).withCloseable { input ->
                        Files.copy(input, out, StandardCopyOption.REPLACE_EXISTING)
                    }
                }
            }
        } finally {
            zf.close()
        }
    }

    private static Path findFirst(Path root, String filename) {
        def stream = Files.walk(root)
        try {
            return stream
                .filter { p -> Files.isRegularFile(p) && p.fileName.toString().equalsIgnoreCase(filename) }
                .findFirst()
                .orElse(null)
        } finally {
            stream.close()
        }
    }

    private static void installFromFolder(Path sourceFolder, Path targetFolder) {
        Files.createDirectories(targetFolder)

        // Clean target (but keep .gitkeep)
        def existing = Files.list(targetFolder)
        try {
            existing.forEach { p ->
                if (Files.isRegularFile(p) && !p.fileName.toString().equalsIgnoreCase(".gitkeep")) {
                    Files.deleteIfExists(p)
                }
            }
        } finally {
            existing.close()
        }

        def srcFiles = Files.list(sourceFolder)
        try {
            srcFiles.forEach { p ->
                if (Files.isRegularFile(p)) {
                    Files.copy(p, targetFolder.resolve(p.fileName.toString()), StandardCopyOption.REPLACE_EXISTING)
                }
            }
        } finally {
            srcFiles.close()
        }
    }

    private static String sha256Hex(Path p) {
        MessageDigest md = MessageDigest.getInstance("SHA-256")
        p.toFile().newInputStream().withCloseable { is ->
            byte[] buf = new byte[8192]
            int r
            while ((r = is.read(buf)) >= 0) {
                if (r > 0) md.update(buf, 0, r)
            }
        }
        byte[] digest = md.digest()
        StringBuilder sb = new StringBuilder(digest.length * 2)
        for (byte b : digest) sb.append(String.format("%02X", b))
        return sb.toString()
    }
}


