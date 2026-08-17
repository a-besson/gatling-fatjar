package com.gatling.lab.core;

import lombok.AllArgsConstructor;
import lombok.extern.slf4j.Slf4j;

import java.io.IOException;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

import static org.apache.commons.lang3.StringUtils.isEmpty;
import static org.apache.commons.lang3.StringUtils.isNotEmpty;

/**
 * Runs each simulation in its own JVM, through Gatling's supported entry point.
 *
 * <p>Gatling used to expose {@code Gatling.fromMap(...)}, which returned a status
 * and let a single JVM run simulations back to back. Since 3.15 the only public
 * entry point left is {@code io.gatling.app.Gatling.main(String[])}, and it ends
 * with {@code sys.exit}. The one in-process alternative, {@code Gatling.fromArgs},
 * is {@code private[gatling]} and, more importantly, stops the Logback context in
 * a {@code finally} block after every run -- so simulations 2..n of a loop would
 * run with logging shut down.
 *
 * <p>Forking gives each simulation a clean JVM (fresh Logback, fresh ActorSystem,
 * fresh configuration), relies only on the entry point Gatling itself documents,
 * and hands back a per-simulation exit code. The cost is JVM startup per
 * simulation, which is small next to the runs themselves.
 */
@Slf4j
@AllArgsConstructor
public class GatlingRunnerImpl implements GatlingRunner {

    private static final String GATLING_MAIN_CLASS = "io.gatling.app.Gatling";

    /**
     * Since JDK 16 enforced strong encapsulation, Gatling needs java.lang opened
     * to reach the String internals its log writer uses; without it the run dies
     * with an IllegalAccessException as soon as the stats engine starts.
     *
     * <p>Injecting the flag here is what keeps `java -jar gatling-fatjar.jar`
     * working as before: the flag belongs to the JVM that runs the simulation,
     * and callers do not have to know about it.
     */
    private static final List<String> REQUIRED_JVM_ARGS =
            List.of("--add-opens=java.base/java.lang=ALL-UNNAMED");

    private GatlingProperties props;

    @Override
    public int runSimulations(Set<String> simulations) {
        int failed = 0;

        for (String simulation : simulations) {
            Instant start = Instant.now();
            log.info("Start com.gatling.lab.simulation: {}", simulation);

            int status;
            try {
                status = fork(simulation);
            } catch (IOException e) {
                log.error("Could not start a JVM for simulation {}", simulation, e);
                status = -1;
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                log.error("Interrupted while running simulation {}", simulation, e);
                status = -1;
            }

            // Gatling exits 0 on success, 1 on invalid arguments and 2 when an
            // assertion failed. A simulation that declares no assertion exits 0
            // even if every one of its requests failed: assertions are what makes
            // a failed run observable, here and in our own exit code.
            if (status != 0) {
                failed++;
                log.error("Simulation {} failed, Gatling exited with {}", simulation, status);
            }

            log.info("End com.gatling.lab.simulation: {}, duration: {}", simulation,
                    Duration.between(start, Instant.now()));
        }

        return failed;
    }

    private int fork(String simulation) throws IOException, InterruptedException {
        List<String> command = new ArrayList<>();
        command.add(javaBinary());
        command.addAll(REQUIRED_JVM_ARGS);
        command.add("-cp");
        command.add(classpath());
        command.add(GATLING_MAIN_CLASS);
        command.add("--simulation");
        command.add(simulation);
        if (isNotEmpty(props.getResultDir())) {
            command.add("--results-folder");
            command.add(props.getResultDir());
        }

        log.debug("Forking: {}", String.join(" ", command));

        // inheritIO keeps Gatling's own console output -- the live counters and
        // the final summary -- attached to our stdout, as it was when the run
        // happened in-process.
        return new ProcessBuilder(command).inheritIO().start().waitFor();
    }

    private static String javaBinary() {
        Path java = Paths.get(System.getProperty("java.home"), "bin", "java");
        return java.toString();
    }

    /**
     * The classpath to hand to the forked JVM. When started with {@code java -jar},
     * this is the fat jar itself, which carries Gatling and the simulations alike.
     */
    private static String classpath() {
        String classpath = System.getProperty("java.class.path");
        return isEmpty(classpath) ? "." : classpath;
    }
}
