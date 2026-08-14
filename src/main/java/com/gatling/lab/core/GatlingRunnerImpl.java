package com.gatling.lab.core;

import io.gatling.app.Gatling;
import io.gatling.core.config.GatlingPropertiesBuilder;
import lombok.AllArgsConstructor;
import lombok.extern.slf4j.Slf4j;

import java.time.Duration;
import java.time.Instant;
import java.util.Set;

@Slf4j
@AllArgsConstructor
public class GatlingRunnerImpl implements GatlingRunner {

    private GatlingProperties props;

    @Override
    public int runSimulations(Set<String> simulations) {
        int failed = 0;

        for (String simulation : simulations) {
            Instant start = Instant.now();
            log.info("Start com.gatling.lab.simulation: {}", simulation);

            GatlingPropertiesBuilder builder = new GatlingPropertiesBuilder()
                    .simulationClass(simulation)
                    .resourcesDirectory(props.getRessourceDir())
                    .resultsDirectory(props.getResultDir());

            // Gatling reports 0 when the run completed and all of its assertions
            // held. A simulation that declares no assertion therefore reports 0
            // even if every one of its requests failed: assertions are what makes
            // a failed run observable here, and in turn in the process exit code.
            int status = Gatling.fromMap(builder.build());
            if (status != 0) {
                failed++;
                log.error("Simulation {} failed, Gatling status: {}", simulation, status);
            }

            log.info("End com.gatling.lab.simulation: {}, duration: {}", simulation,
                    Duration.between(start, Instant.now()));
        }

        return failed;
    }
}
