Gatling Java Fat Jar
============================================

[![CI](https://github.com/a-besson/gatling-fatjar/actions/workflows/ci.yml/badge.svg)](https://github.com/a-besson/gatling-fatjar/actions/workflows/ci.yml)

Gatling Java fatjar executable demo.

Can launch one or multiple simulations.

**Getting started:**
```shell
user@MBP-user gatling-fatjar % java -jar target/gatling-fatjar-1.0.0-SNAPSHOT.jar --help
Usage: gatling [-ahV] [-p=<simulationPath>] [-r=<ressourceDir>]
               [-rd=<resultDir>] [-s=<simulation>]
Gatling cli runner. Can be used to run multiple simulations
  -a, --all                  Run all simulations in package (default when
                               --simul is not given)
  -h, --help                 Show this help message and exit.
  -p, --path=<simulationPath>
                             Simulations base package
  -r, --ressourcedir=<ressourceDir>

      -rd, --resultdir=<resultDir>

  -s, --simul=<simulation>   Simulation name
  -V, --version              Print version information and exit.
```

`--all` and `--simul` are mutually exclusive: `--all` is what already happens
when no name is given, so passing both can only be a mistake and is rejected.

**Run simulations:**
```shell
# Run all simulation from package
user@MBP-user gatling-fatjar % java -jar target/gatling-fatjar-1.0.0-SNAPSHOT.jar -p "com.gatling.lab.simulation"

# Run one simulation
user@MBP-user gatling-fatjar % java -jar target/gatling-fatjar-1.0.0-SNAPSHOT.jar -p "com.gatling.lab.simulation" -s "BasicSimulation1"
```

**Exit codes:**

| Code | Meaning |
| --- | --- |
| `0` | every simulation ran and Gatling reported no failure |
| `1` | at least one simulation was reported as failed by Gatling |
| `2` | usage error (unknown or contradictory options) |
| `3` | no simulation matched the requested package and name |

Gatling reports a simulation as failed when one of its **assertions** does not
hold. The simulations bundled here declare none, so a run whose requests all
fail still exits `0` — add assertions to a simulation for its failures to reach
the exit code.

Continuous integration
--------------------------------------------

`.github/workflows/ci.yml` runs on every push to `master` and on every pull
request, in two jobs:

* **compile / test / package** — `mvn compile`, `mvn test`, then `mvn package`,
  on Temurin JDK 17. The fat jar is uploaded as a build artifact.
* **e2e (fat jar)** — downloads that exact artifact and runs `e2e/run-e2e.sh`
  against it.

The e2e suite exercises the jar through `java -jar`, the way it is meant to be
used: manifest and bundled resources, `--help`, simulation discovery, a single
simulation selected with `-s`, and every simulation of a package in one run.
Each Gatling report is checked for `KO=0`.

The bundled simulations point at `http://computer-database.gatling.io`, so the
script maps that hostname to `127.0.0.1` and serves it from a local stub
(`e2e/stub-server.py`). No third-party site is involved, and the run is
deterministic.

**Run the e2e suite locally** (needs root or passwordless `sudo`, to edit
`/etc/hosts` and bind port 80):
```shell
user@MBP-user gatling-fatjar % mvn package
user@MBP-user gatling-fatjar % ./e2e/run-e2e.sh
```