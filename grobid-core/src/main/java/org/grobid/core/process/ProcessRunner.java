package org.grobid.core.process;

import org.apache.commons.io.IOUtils;
import org.apache.commons.lang3.SystemUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.lang.reflect.Field;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.ArrayList;
import java.util.stream.Stream;

public class ProcessRunner extends Thread {
    private static final Logger LOGGER = LoggerFactory.getLogger(ProcessRunner.class);

	private List<String> cmd;
    private Integer exit;
    private Process process;

    public String getErrorStreamContents() {
        return errorStreamContents;
    }

    private String errorStreamContents;

    private boolean useStreamGobbler;
    StreamGobbler sgIn;
    StreamGobbler sgErr;

	public ProcessRunner(List<String> cmd, String name, boolean useStreamGobbler) {
        super(name);
        this.cmd = cmd;
        this.useStreamGobbler = useStreamGobbler;
    }

    // Since we are limiting by ulimit on Unix, pdftoxml is actually a child process, 
    // therefore Process.destroy() won't work. We need to kill all descendants.
    // This method now uses cross-platform ProcessHandle API (Java 9+)
    public void killProcess() {
        if (process != null) {
            try {
                long pid = process.pid();
                LOGGER.info("Killing pdf to xml process with PID " + pid + " and its children");
                
                // Use ProcessHandle API (Java 9+) for cross-platform process tree termination
                ProcessHandle processHandle = process.toHandle();
                
                // First, destroy all descendant processes
                processHandle.descendants().forEach(child -> {
                    LOGGER.debug("Killing child process: " + child.pid());
                    child.destroyForcibly();
                });
                
                // Then destroy the main process
                processHandle.destroyForcibly();
                
                // On Unix, we may also need to use pkill as a fallback for processes 
                // started via bash/ulimit wrapper
                if (SystemUtils.IS_OS_UNIX && !SystemUtils.IS_OS_MAC) {
                    try {
                        Runtime.getRuntime().exec(new String[]{"pkill", "-9", "-P", String.valueOf(pid)}).waitFor();
                    } catch (Exception e) {
                        LOGGER.debug("pkill fallback failed (may be normal): " + e.getMessage());
                    }
                }
            } catch (Exception e) {
                LOGGER.error("Error killing process: " + e.getMessage());
                // Fallback to simple destroy
                if (process != null) {
                    process.destroyForcibly();
                }
            }
        }
    }


    /**
     * Get the PID of a process using the cross-platform ProcessHandle API (Java 9+).
     * This replaces the old Unix-only reflection-based approach.
     * 
     * @param p the Process to get the PID from
     * @return the PID, or null if it cannot be determined
     */
    public static Long getPidOfProcess(Process p) {
        if (p == null) {
            return null;
        }
        
        try {
            // Use Java 9+ Process.pid() method - works on all platforms
            return p.pid();
        } catch (UnsupportedOperationException e) {
            LOGGER.warn("Process.pid() not supported on this platform");
            return null;
        }
    }
    
    /**
     * @deprecated Use {@link #getPidOfProcess(Process)} instead.
     * This method is kept for backwards compatibility but now delegates to the new implementation.
     */
    @Deprecated
    public static Long getPidOfProcessLegacy(Process p) {
        Long pid = null;

        try {
            // Legacy Unix-only approach using reflection
            if (p.getClass().getName().equals("java.lang.UNIXProcess")) {
                Field f = p.getClass().getDeclaredField("pid");
                f.setAccessible(true);
                pid = f.getLong(p);
                f.setAccessible(false);
            }
        } catch (Exception e) {
            pid = null;
        }
        return pid;
    }

    public void run() {
        process = null;
        try {
			ProcessBuilder builder = new ProcessBuilder(cmd);
			process = builder.start();
			
            if (useStreamGobbler) {
                sgIn = new StreamGobbler(process.getInputStream());
                sgErr = new StreamGobbler(process.getErrorStream());
            }

            exit = process.waitFor();
        } 
		catch (InterruptedException ignore) {
            //Process needs to be destroyed -- it's done in the finally block
        } 
		catch (IOException e) {
            LOGGER.error("IOException while launching the command {} : {}", cmd.toString(), e.getMessage());
        } 
		finally {
            if (process != null) {
                IOUtils.closeQuietly(process.getInputStream());
                IOUtils.closeQuietly(process.getOutputStream());
                try {
                    errorStreamContents = IOUtils.toString(process.getErrorStream(), StandardCharsets.UTF_8);
                } catch (IOException e) {
                    LOGGER.error("Error retrieving error stream from process: ", e);
                }
                IOUtils.closeQuietly(process.getErrorStream());

                process.destroy();

            }

            if (useStreamGobbler) {
                try {
                    if (sgIn != null) {
                        sgIn.close();
                    }
                } 
				catch (IOException e) {
                    LOGGER.error("IOException while closing the stream gobbler: {}", e);
                }

                try {
                    if (sgErr != null) {
                        sgErr.close();
                    }
                } 
				catch (IOException e) {
                    LOGGER.error("IOException while closing the stream gobbler: {}", e);
                }
            }
        }

    }

    public Integer getExitStatus() {
        return exit;
    }
}
