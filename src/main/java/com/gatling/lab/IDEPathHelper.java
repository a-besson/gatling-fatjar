package com.gatling.lab;

import java.net.URISyntaxException;
import java.nio.file.Path;
import java.nio.file.Paths;

public class IDEPathHelper {

    public static final Path mavenSourcesDirectory;
    public static final Path mavenResourcesDirectory;
    public static final Path mavenBinariesDirectory;
    public static final Path resultsDirectory;

    static {
        try {
            Path projectRootDir = Paths.get(IDEPathHelper.class.getClassLoader().getResource("gatling.conf").toURI()).getParent().getParent().getParent();
            Path mavenTargetDirectory = projectRootDir.resolve("target");
            Path mavenSrcTestDirectory = projectRootDir.resolve("src").resolve("test");

            mavenSourcesDirectory = mavenSrcTestDirectory.resolve("java");
            mavenResourcesDirectory = mavenSrcTestDirectory.resolve("resources");
            mavenBinariesDirectory = mavenTargetDirectory.resolve("test-classes");
            resultsDirectory = mavenTargetDirectory.resolve("gatling");
            // No recorderConfigFile: since Gatling 3.15 the recorder takes its
            // settings from CLI arguments only, there is no config file to pass.
        } catch (URISyntaxException e) {
            throw new ExceptionInInitializerError(e);
        }
    }
}
