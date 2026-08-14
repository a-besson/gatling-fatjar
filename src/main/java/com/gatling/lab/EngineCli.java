package com.gatling.lab;

import com.gatling.lab.core.GatlingProperties;
import com.gatling.lab.core.GatlingRunner;
import com.gatling.lab.core.GatlingRunnerImpl;
import io.gatling.javaapi.core.Simulation;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.EqualsAndHashCode;
import lombok.NoArgsConstructor;
import lombok.ToString;
import lombok.extern.slf4j.Slf4j;
import org.reflections.Reflections;
import picocli.CommandLine.Command;
import picocli.CommandLine.Model.CommandSpec;
import picocli.CommandLine.Option;
import picocli.CommandLine.ParameterException;
import picocli.CommandLine.Spec;

import java.net.URISyntaxException;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Set;
import java.util.concurrent.Callable;
import java.util.stream.Collectors;

import static org.apache.commons.lang3.StringUtils.isEmpty;
import static org.apache.commons.lang3.StringUtils.isNotEmpty;

@Slf4j
@Data
@Builder
@AllArgsConstructor
@NoArgsConstructor
@Command(name = "gatling",
        description = "Gatling cli runner. Can be used to run multiple simulations",
        aliases = "gtl",
        mixinStandardHelpOptions = true)
public class EngineCli implements Callable<Integer> {

    /** All simulations ran and succeeded. */
    public static final int EXIT_OK = 0;
    /** At least one simulation failed. */
    public static final int EXIT_SIMULATION_FAILED = 1;
    /** No simulation matched the requested package and name. */
    public static final int EXIT_NO_SIMULATION = 3;

    @Option(names = { "--path", "-p" },
            description = "Simulations base package")
    private String simulationPath;

    @Option(names = { "--simul", "-s" },
            description = "Simulation name")
    private String simulation;

    @Option(names = { "--all", "-a" },
            description = "Run all simulations in package (default when --simul is not given)")
    private boolean runAllSimulation;

    @Option(names = { "--resultdir", "-rd" })
    private String resultDir;

    @Option(names = {"--ressourcedir", "-r"})
    private String ressourceDir;

    @Spec
    @ToString.Exclude
    @EqualsAndHashCode.Exclude
    private CommandSpec spec;

    @Override
    public Integer call() throws Exception {

        this.checkArgs();

        Reflections reflections = new Reflections(this.simulationPath);
        Set<String> simulations = reflections.getSubTypesOf(Simulation.class)
                .stream()
                .map(Class::getName)
                .collect(Collectors.toSet());

        if (isNotEmpty(this.simulation)) {
            simulations = simulations.stream()
                    .filter(s -> s.contains(this.simulation))
                    .collect(Collectors.toSet());
        }
        log.info("Found simulations: {}", simulations.size());

        if (simulations.isEmpty()) {
            log.warn("No Simulations Found");
            return EXIT_NO_SIMULATION;
        }

        GatlingRunner runner = new GatlingRunnerImpl(GatlingProperties.builder()
                .simulationPath(this.simulationPath)
                .ressourceDir(this.ressourceDir)
                .resultDir(this.resultDir)
                .build());

        int failed = runner.runSimulations(simulations);
        if (failed > 0) {
            log.error("{} of {} simulation(s) failed", failed, simulations.size());
            return EXIT_SIMULATION_FAILED;
        }

        return EXIT_OK;
    }

    /**
     * Check gatling args
     * @throws URISyntaxException
     */
    private void checkArgs() throws URISyntaxException {
        // --all is what happens anyway when no name is given, so asking for both
        // can only mean one of the two was a mistake.
        if (this.runAllSimulation && isNotEmpty(this.simulation)) {
            throw new ParameterException(this.spec.commandLine(),
                    "--all and --simul are mutually exclusive: --all runs every simulation of the package, "
                            + "--simul runs the ones matching a name.");
        }

        Path path = Paths.get(EngineCli.class.getProtectionDomain().getCodeSource().getLocation().toURI());
        if (isEmpty(this.ressourceDir)) {
            this.ressourceDir = path.toString();
        }

        if (isEmpty(this.resultDir)) {
            this.resultDir = path.getParent() + "/results";
        }
    }
}
