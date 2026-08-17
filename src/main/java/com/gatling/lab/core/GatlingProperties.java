package com.gatling.lab.core;

import lombok.Builder;
import lombok.Data;

@Data
@Builder
public class GatlingProperties {

    /**
     * Where Gatling writes the run results and the generated report.
     *
     * <p>Gatling 3.15 dropped the resources directory from what a caller can pass
     * per run ({@code GatlingArgs} has no counterpart to the old
     * {@code GatlingPropertiesBuilder.resourcesDirectory}), so the results folder
     * is the only knob left here. Resources are resolved from the classpath and
     * {@code gatling.conf}.
     */
    private String resultDir;

}
