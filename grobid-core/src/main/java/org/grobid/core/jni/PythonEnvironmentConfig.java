package org.grobid.core.jni;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;
import java.util.stream.Collectors;

import org.apache.commons.collections4.CollectionUtils;
import org.apache.commons.io.FilenameUtils;
import org.apache.commons.lang3.StringUtils;
import org.apache.commons.lang3.SystemUtils;
import org.grobid.core.exceptions.GrobidException;
import org.grobid.core.exceptions.GrobidResourceException;
import org.grobid.core.utilities.GrobidProperties;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class PythonEnvironmentConfig {

    private static final Logger LOGGER = LoggerFactory.getLogger(PythonEnvironmentConfig.class);

    private Path virtualEnv;
    private Path sitePackagesPath;
    private Path jepPath;
    private boolean active;
    private String pythonVersion;

    public PythonEnvironmentConfig(
        Path virtualEnv,
        Path sitePackagesPath,
        Path jepPath,
        String pythonVersion,
        boolean active) {
        this.virtualEnv = virtualEnv;
        this.sitePackagesPath = sitePackagesPath;
        this.jepPath = jepPath;
        this.active = active;
        this.pythonVersion = pythonVersion;
    }

    public boolean isEmpty() {
        return this.virtualEnv == null;
    }

    public Path getVirtualEnv() {
        return this.virtualEnv;
    }

    public Path getSitePackagesPath() {
        return this.sitePackagesPath;
    }

    public Path getNativeLibPath() {
        if (this.virtualEnv == null) {
            return null;
        }
        // Windows uses capital Lib, Unix uses lib
        if (SystemUtils.IS_OS_WINDOWS) {
            return Paths.get(this.virtualEnv.toString(), "Lib");
        }
        return Paths.get(this.virtualEnv.toString(), "lib");
    }

    public Path[] getNativeLibPaths() {
        if (this.virtualEnv == null) {
            return new Path[0];
        }
        return new Path[]{
            this.getNativeLibPath(),
            this.getJepPath()
        };
    }

    public Path getJepPath() {
        return this.jepPath;
    }

    public boolean isActive() {
        return this.active;
    }

    public static PythonEnvironmentConfig getInstanceForVirtualEnv(String virtualEnv, String activeVirtualEnv)
        throws GrobidResourceException {

        if (StringUtils.isEmpty(virtualEnv) && StringUtils.isEmpty(activeVirtualEnv)) {
            return new PythonEnvironmentConfig(null, null, null, null, false);
        }
        if (StringUtils.isEmpty(virtualEnv)) {
            virtualEnv = activeVirtualEnv;
        }

        // Windows and Unix have different virtual environment structures
        if (SystemUtils.IS_OS_WINDOWS) {
            return getInstanceForWindowsVirtualEnv(virtualEnv, activeVirtualEnv);
        }

        List<Path> pythons;
        try {
            pythons = Files.find(
                Paths.get(virtualEnv, "lib"),
                1,
                (path, attr) -> (
                    path.toFile().isDirectory()
                        && path.getFileName().toString().contains("python3")
                )
            ).collect(Collectors.toList());
        } catch (IOException e) {
            throw new GrobidResourceException("failed to get python versions from virtual environment", e);
        }

        List<String> pythonVersions = pythons
            .stream()
            .map(path -> FilenameUtils.getName(path.getFileName().toString())
                .replace("libpython", "").replace("python", ""))
            .filter(version -> version.contains("3.7") || version.contains("3.8") || version.contains("3.9") || version.contains("3.10")  || version.contains("3.11")  || version.contains("3.12"))
            .distinct()
            .sorted()
            .collect(Collectors.toList());

        if (CollectionUtils.isEmpty(pythonVersions)) {
            throw new GrobidException(
                "Cannot find a suitable version (3.7 to 3.12) of python in your virtual environment: " +
                    virtualEnv
            );
        }


        Path sitePackagesPath = Paths.get(pythons.get(0).toString(), "site-packages");
        Path jepPath = Paths.get(sitePackagesPath.toString(), "jep");
        return new PythonEnvironmentConfig(
            Paths.get(virtualEnv),
            sitePackagesPath,
            jepPath,
            pythonVersions.get(0),
            StringUtils.equals(virtualEnv, activeVirtualEnv)
        );
    }

    /**
     * Windows-specific virtual environment configuration.
     * Windows venv structure: venv/Lib/site-packages/jep/ (capital L, no python version dir)
     */
    private static PythonEnvironmentConfig getInstanceForWindowsVirtualEnv(String virtualEnv, String activeVirtualEnv)
        throws GrobidResourceException {
        
        LOGGER.info("Configuring Python environment for Windows: " + virtualEnv);
        
        // Windows uses "Lib" (capital L) instead of "lib/pythonX.X"
        Path libPath = Paths.get(virtualEnv, "Lib");
        if (!Files.exists(libPath)) {
            // Try lowercase as fallback (some tools might use lowercase)
            libPath = Paths.get(virtualEnv, "lib");
            if (!Files.exists(libPath)) {
                throw new GrobidResourceException(
                    "Cannot find Lib directory in Windows virtual environment: " + virtualEnv);
            }
        }
        
        Path sitePackagesPath = Paths.get(libPath.toString(), "site-packages");
        if (!Files.exists(sitePackagesPath)) {
            throw new GrobidResourceException(
                "Cannot find site-packages in Windows virtual environment: " + virtualEnv);
        }
        
        Path jepPath = Paths.get(sitePackagesPath.toString(), "jep");
        if (!Files.exists(jepPath)) {
            LOGGER.warn("JEP not found in site-packages. Please install JEP: pip install jep");
        }
        
        // Detect Python version from the Python executable or Scripts directory
        String pythonVersion = detectWindowsPythonVersion(virtualEnv);
        
        LOGGER.info("Windows Python environment configured - Version: " + pythonVersion + 
            ", JEP path: " + jepPath);
        
        return new PythonEnvironmentConfig(
            Paths.get(virtualEnv),
            sitePackagesPath,
            jepPath,
            pythonVersion,
            StringUtils.equals(virtualEnv, activeVirtualEnv)
        );
    }
    
    /**
     * Detect Python version on Windows by checking the python executable or pyvenv.cfg
     */
    private static String detectWindowsPythonVersion(String virtualEnv) {
        // Try to read pyvenv.cfg which contains version info
        Path pyvenvCfg = Paths.get(virtualEnv, "pyvenv.cfg");
        if (Files.exists(pyvenvCfg)) {
            try {
                List<String> lines = Files.readAllLines(pyvenvCfg);
                for (String line : lines) {
                    if (line.startsWith("version")) {
                        String version = line.split("=")[1].trim();
                        // Extract major.minor (e.g., "3.10" from "3.10.4")
                        String[] parts = version.split("\\.");
                        if (parts.length >= 2) {
                            return parts[0] + "." + parts[1];
                        }
                    }
                }
            } catch (IOException e) {
                LOGGER.warn("Could not read pyvenv.cfg: " + e.getMessage());
            }
        }
        
        // Default to 3.10 if we can't detect
        LOGGER.warn("Could not detect Python version, defaulting to 3.10");
        return "3.10";
    }

    public static String getActiveVirtualEnv() {
        String activeVirtualEnv = System.getenv("VIRTUAL_ENV");
        if (StringUtils.isEmpty(activeVirtualEnv)) {
            activeVirtualEnv = System.getenv("CONDA_PREFIX");
        }
        return activeVirtualEnv;
    }

    public static PythonEnvironmentConfig getInstance() throws GrobidResourceException {
        return getInstanceForVirtualEnv(
            GrobidProperties.getPythonVirtualEnv(),
            getActiveVirtualEnv()
        );
    }

    public String getPythonVersion() {
        return pythonVersion;
    }
}