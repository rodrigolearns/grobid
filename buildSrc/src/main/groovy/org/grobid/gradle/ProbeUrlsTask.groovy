package org.grobid.gradle

import org.gradle.api.DefaultTask
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.TaskAction

import java.net.HttpURLConnection

/**
 * Small, Gradle-native network diagnostics task.
 * Probes URLs with GET (no auth by default) and prints:
 * - status code
 * - final URL after redirects
 * - Location header (when present)
 *
 * This is intentionally simple and dependency-free so it can run on clean Windows machines.
 */
class ProbeUrlsTask extends DefaultTask {

    @Input
    List<String> urls = []

    @TaskAction
    void probe() {
        if (urls == null || urls.isEmpty()) {
            logger.lifecycle("No URLs configured to probe.")
            return
        }
        logger.lifecycle("Probing ${urls.size()} URLs...")
        urls.each { u ->
            // Make the receiver explicit to avoid Gradle/Groovy DSL method-resolution surprises.
            this.probeOne(u?.toString())
        }
    }

    // Must not be private: Gradle task actions run in a dynamic Groovy context and private methods
    // can be mis-resolved as missing DSL methods.
    void probeOne(String url) {
        try {
            def result = EnsurePdfaltoWindowsTask.probeUrl(url, 10)
            logger.lifecycle(String.format("OK  %s  ->  %s  (final: %s)%s",
                padRight(result.status.toString(), 4),
                url,
                result.finalUrl,
                result.locationHeader ? "  Location: ${result.locationHeader}" : ""
            ))
        } catch (Exception e) {
            logger.lifecycle(String.format("ERR %-4s ->  %s  (%s: %s)",
                "",
                url,
                e.class.simpleName,
                (e.message ?: "").replaceAll("[\\r\\n]+", " ")
            ))
        }
    }

    private static String padRight(String s, int n) {
        if (s == null) s = ""
        if (s.length() >= n) return s
        return s + (" " * (n - s.length()))
    }
}


