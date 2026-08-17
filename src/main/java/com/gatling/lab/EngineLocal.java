package com.gatling.lab;

import lombok.extern.slf4j.Slf4j;
import picocli.CommandLine;

@Slf4j
public class EngineLocal {

    public static void main(String[] args) {
        int exitCode = new CommandLine(new EngineCli.EngineCliBuilder()
                .simulationPath("com.gatling.lab.simulation")
                .resultDir(IDEPathHelper.resultsDirectory.toString())
                .build()).execute(args);
        System.exit(exitCode);
    }
}
