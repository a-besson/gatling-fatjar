package com.gatling.lab;

import io.gatling.recorder.GatlingRecorder;

public class Recorder {

    // Gatling 3.15 removed RecorderPropertiesBuilder and GatlingRecorder.fromMap;
    // the recorder is now driven by its CLI arguments, parsed by RecorderArgsParser.
    public static void main(String[] args) {
        GatlingRecorder.main(new String[] {
                "--simulations-folder", IDEPathHelper.mavenSourcesDirectory.toString(),
                "--resources-folder", IDEPathHelper.mavenResourcesDirectory.toString(),
                "--package", "com.gatling.lab.simulation",
                // Must match maven.compiler.release: left unset, the recorder picks
                // its format from the running JVM and would emit Java 17 sources.
                "--format", "java11"
        });
    }
}
