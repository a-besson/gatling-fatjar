package com.gatling.lab.core;

import java.util.Set;

public interface GatlingRunner {

    /**
     * Runs the given simulations, one after the other, in the current JVM.
     *
     * @param simulations fully qualified names of the simulation classes to run
     * @return the number of simulations Gatling reported as failed, 0 when they all succeeded
     */
    int runSimulations(Set<String> simulations);
}
