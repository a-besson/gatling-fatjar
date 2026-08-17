#!/usr/bin/env bash
#
# End-to-end tests for the packaged fat jar.
#
# These run against target/gatling-fatjar-*.jar the way a user would run it: a
# single `java -jar`, no Maven, no project classpath. That is the only way to
# catch the regressions this project is exposed to -- shading dropping a
# resource (gatling.conf, logback.xml, the Highcharts report assets),
# Reflections failing to scan simulations from inside a jar, or a dependency
# bump breaking the Gatling runtime at execution time rather than compile time.
#
# The simulations target http://computer-database.gatling.io. To keep the run
# hermetic, the script maps that hostname to 127.0.0.1 and serves it from
# e2e/stub-server.py, so nothing here depends on a third-party site being up.
#
# Requires root or passwordless sudo (for /etc/hosts and binding port 80).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly WORK_DIR="${REPO_ROOT}/target/e2e"
readonly STUB_LOG="${WORK_DIR}/stub-server.log"
readonly RUN_LOG="${WORK_DIR}/cli-run.log"
readonly STUB_HOST="computer-database.gatling.io"
readonly STUB_PORT=80
readonly HOSTS_MARKER="# added by gatling-fatjar e2e"
# Exit codes contracted by EngineCli, plus picocli's own usage exit code.
# EXIT_SIMULATION_FAILED (1) is not asserted below: it is driven by Gatling's
# own status, which depends on assertions, and none of the bundled simulations
# declares any -- so no input reaches it from the CLI.
readonly EXIT_OK=0
readonly EXIT_USAGE=2
readonly EXIT_NO_SIMULATION=3
# Requests issued by each of the bundled scenarios.
readonly EXPECTED_REQUESTS=10
# Simulations reachable from the com.gatling.lab.simulation package, sub-packages
# included: BasicSimulation, BasicSimulation1, BasicSimulation2, ui.BasicSimulation3.
readonly EXPECTED_SIMULATIONS=4

failures=0
hosts_entry_added=0

log()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
pass() { printf '    \033[32mPASS\033[0m %s\n' "$*"; }
fail() { printf '    \033[31mFAIL\033[0m %s\n' "$*"; failures=$((failures + 1)); }

# assert_rc <expected> <actual> <label>
assert_rc() {
  if [[ "$2" -eq "$1" ]]; then
    pass "$3: exit code $2"
  else
    fail "$3: exit code $2, expected $1"
  fi
}

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

cleanup() {
  as_root pkill -f 'stub-server\.py' 2>/dev/null || true
  if [[ "${hosts_entry_added}" -eq 1 ]]; then
    as_root sed -i "\|${HOSTS_MARKER}|d" /etc/hosts || true
  fi
}
trap cleanup EXIT

# Runs the fat jar with the e2e logging config, streaming output to the console
# and to $RUN_LOG. Sets `cli_rc` to the exit code of java (not of the pipe).
# errexit/pipefail are lifted around the call: several cases below expect a
# non-zero exit, and callers assert on the exit code explicitly.
run_cli() {
  set +e
  java -Dlogback.configurationFile="${REPO_ROOT}/e2e/logback-e2e.xml" \
       -jar "${JAR}" "$@" 2>&1 | tee "${RUN_LOG}"
  cli_rc="${PIPESTATUS[0]}"
  set -e
}

# assert_report <report-dir> <label>: checks a single Gatling report directory.
assert_report() {
  local report_dir="$1" label="$2" artifact

  for artifact in index.html simulation.log; do
    if [[ -s "${report_dir}/${artifact}" ]]; then
      pass "${label}: report artifact ${artifact}"
    else
      fail "${label}: report artifact missing or empty: ${artifact}"
    fi
  done

  # The Highcharts assets come from the gatling-charts-highcharts jar; a shading
  # mistake shows up here as an empty js/ directory.
  if compgen -G "${report_dir}/js/*.js" >/dev/null; then
    pass "${label}: report ships its javascript assets"
  else
    fail "${label}: report has no javascript assets (js/*.js)"
  fi
}

# assert_console_stats <expected-summaries>: reads the run's console summaries.
#
# Gatling 3.15 dropped js/global_stats.json from the report, so the request
# counts are only available from the summary Gatling prints per simulation:
#
#   > request count       |        10 |        10 |         -
#                            Total        OK          KO ("-" means none)
#
# One summary is emitted per simulation, so the count of matching lines also
# proves every simulation really ran.
assert_console_stats() {
  local expected_summaries="$1"
  if python3 - "${RUN_LOG}" "${EXPECTED_REQUESTS}" "${expected_summaries}" <<'PY'
import re, sys

log, expected_requests, expected_summaries = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
pattern = re.compile(r"^> request count\s+\|\s*(\S+)\s*\|\s*(\S+)\s*\|\s*(\S+)\s*$")

summaries = []
with open(log, encoding="utf-8", errors="replace") as fh:
    for line in fh:
        match = pattern.match(line.strip())
        if match:
            summaries.append(match.groups())

print(f"    console summaries (total/ok/ko): {summaries}")
if len(summaries) != expected_summaries:
    print(f"    expected {expected_summaries} summary line(s), got {len(summaries)}")
    sys.exit(1)

for total, ok, ko in summaries:
    # Gatling prints "-" rather than 0 in an empty column.
    if total != str(expected_requests) or ok != str(expected_requests) or ko not in ("-", "0"):
        sys.exit(1)
sys.exit(0)
PY
  then
    pass "${expected_summaries} summary/summaries, each ${EXPECTED_REQUESTS} requests with no KO"
  else
    fail "expected ${expected_summaries} summary/summaries of ${EXPECTED_REQUESTS} requests with no KO"
  fi
}

# --------------------------------------------------------------------------
# Locate the fat jar
# --------------------------------------------------------------------------
log "Locating the fat jar"

# The shade plugin leaves the unshaded jar behind as original-*.jar; ignore it.
mapfile -t jars < <(find "${REPO_ROOT}/target" -maxdepth 1 -name 'gatling-fatjar-*.jar' ! -name 'original-*' | sort)
if [[ "${#jars[@]}" -ne 1 ]]; then
  echo "Expected exactly one fat jar in target/, found ${#jars[@]}: ${jars[*]:-none}" >&2
  echo "Run 'mvn package' first." >&2
  exit 1
fi
readonly JAR="${jars[0]}"
info "jar: ${JAR} ($(du -h "${JAR}" | cut -f1))"

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"

# --------------------------------------------------------------------------
# 1. The jar is self-executable and carries everything the runtime needs
# --------------------------------------------------------------------------
log "Test 1: jar packaging"

manifest="$(unzip -p "${JAR}" META-INF/MANIFEST.MF)"
if grep -q '^Main-Class: com.gatling.lab.Engine' <<<"${manifest}"; then
  pass "manifest declares Main-Class: com.gatling.lab.Engine"
else
  fail "manifest is missing 'Main-Class: com.gatling.lab.Engine'"
  printf '%s\n' "${manifest}"
fi

# Resources the Gatling runtime reads off the classpath at startup. If shading
# drops or mangles them the jar still builds but blows up at run time.
for resource in gatling.conf logback.xml; do
  if unzip -l "${JAR}" "${resource}" >/dev/null 2>&1; then
    pass "bundled resource: ${resource}"
  else
    fail "bundled resource missing from the jar: ${resource}"
  fi
done

for class in \
  com/gatling/lab/Engine.class \
  com/gatling/lab/simulation/BasicSimulation.class \
  com/gatling/lab/simulation/BasicSimulation1.class \
  com/gatling/lab/simulation/BasicSimulation2.class \
  com/gatling/lab/simulation/ui/BasicSimulation3.class
do
  if unzip -l "${JAR}" "${class}" >/dev/null 2>&1; then
    pass "bundled class: ${class}"
  else
    fail "bundled class missing from the jar: ${class}"
  fi
done

# --------------------------------------------------------------------------
# 2. The CLI front-end answers
# --------------------------------------------------------------------------
log "Test 2: CLI help"

help_out="$(java -jar "${JAR}" --help 2>&1)" && help_rc=0 || help_rc=$?
printf '%s\n' "${help_out}"

if [[ "${help_rc}" -eq 0 ]]; then
  pass "--help exits 0"
else
  fail "--help exited ${help_rc}, expected 0"
fi

for expected in 'Usage: gatling' '--path' '--simul' '--resultdir' '--ressourcedir'; do
  if grep -qF -- "${expected}" <<<"${help_out}"; then
    pass "--help documents '${expected}'"
  else
    fail "--help output is missing '${expected}'"
  fi
done

# --------------------------------------------------------------------------
# 3. Simulation discovery from inside the jar
# --------------------------------------------------------------------------
# Reflections scans the classpath, which behaves differently inside a shaded jar
# than against target/classes. This case selects a name that matches nothing, so
# it exercises the scan without running any simulation.
log "Test 3: simulation discovery (Reflections scanning inside the jar)"

run_cli -p com.gatling.lab.simulation -s NoSuchSimulation -rd "${WORK_DIR}/no-match"

if grep -qaE 'Found simulations: 0\b' "${RUN_LOG}" \
   && grep -qaF 'No Simulations Found' "${RUN_LOG}"; then
  pass "unknown simulation name: found 0 and reported 'No Simulations Found'"
else
  fail "unknown simulation name: expected 'Found simulations: 0' + 'No Simulations Found'"
fi
assert_rc "${EXIT_NO_SIMULATION}" "${cli_rc}" "unknown simulation name"

# --------------------------------------------------------------------------
# 3b. Contradictory options are rejected instead of being silently ignored
# --------------------------------------------------------------------------
log "Test 3b: --all and --simul are mutually exclusive"

run_cli -p com.gatling.lab.simulation --all -s BasicSimulation1 -rd "${WORK_DIR}/conflict"

assert_rc "${EXIT_USAGE}" "${cli_rc}" "--all with --simul"

if grep -qaF -- '--all and --simul are mutually exclusive' "${RUN_LOG}"; then
  pass "--all with --simul: reported the conflict"
else
  fail "--all with --simul: expected the conflict to be reported"
fi

if grep -qaF 'Usage: gatling' "${RUN_LOG}"; then
  pass "--all with --simul: printed the usage help"
else
  fail "--all with --simul: expected the usage help"
fi

if [[ -e "${WORK_DIR}/conflict" ]]; then
  fail "--all with --simul: a run was started despite the usage error"
else
  pass "--all with --simul: nothing was run"
fi

# --------------------------------------------------------------------------
# 4. One simulation, selected by name, run end to end against the local stub
# --------------------------------------------------------------------------
log "Test 4: single simulation run"

info "starting the HTTP stub on port ${STUB_PORT}"
as_root python3 "${REPO_ROOT}/e2e/stub-server.py" "${STUB_PORT}" >"${STUB_LOG}" 2>&1 &

if ! grep -q "${STUB_HOST}" /etc/hosts; then
  as_root bash -c "printf '127.0.0.1 %s %s\n' '${STUB_HOST}' '${HOSTS_MARKER}' >> /etc/hosts"
  hosts_entry_added=1
fi
info "$(grep "${STUB_HOST}" /etc/hosts)"

stub_up=0
for _ in $(seq 1 30); do
  if curl -sf --noproxy '*' -o /dev/null "http://${STUB_HOST}/computers?p=1"; then
    stub_up=1
    break
  fi
  sleep 1
done
if [[ "${stub_up}" -ne 1 ]]; then
  echo "The HTTP stub never came up; see ${STUB_LOG}" >&2
  cat "${STUB_LOG}" >&2
  exit 1
fi
info "stub is answering on http://${STUB_HOST}/"

# BasicSimulation1 is the richest scenario: 9 GETs, a form POST, and a group.
single_results="${WORK_DIR}/results-single"
run_cli -p com.gatling.lab.simulation -s BasicSimulation1 -rd "${single_results}"
single_rc="${cli_rc}"

if grep -qaE 'Found simulations: 1\b' "${RUN_LOG}"; then
  pass "the -s filter selected exactly one simulation"
else
  fail "expected 'Found simulations: 1'"
fi

# Gatling shuts the Logback context down at the end of every run, which is why
# simulations are forked: the runner's own start/end lines have to survive the
# runs they frame, and here they do because that shutdown happens in the child.
if grep -qaF 'Start com.gatling.lab.simulation: com.gatling.lab.simulation.BasicSimulation1' "${RUN_LOG}"; then
  pass "the runner started BasicSimulation1"
else
  fail "the runner never logged the start of BasicSimulation1"
fi

if grep -qaF 'End com.gatling.lab.simulation: com.gatling.lab.simulation.BasicSimulation1' "${RUN_LOG}"; then
  pass "the runner returned from BasicSimulation1"
else
  fail "the runner never logged the end of BasicSimulation1"
fi

assert_console_stats 1

assert_rc "${EXIT_OK}" "${single_rc}" "successful run"

mapfile -t single_reports < <(find "${single_results}" -mindepth 1 -maxdepth 1 -type d | sort)
if [[ "${#single_reports[@]}" -eq 1 ]]; then
  pass "exactly one report directory was generated"
  info "report: ${single_reports[0]}"
  assert_report "${single_reports[0]}" "BasicSimulation1"
else
  fail "expected 1 report directory under ${single_results}, found ${#single_reports[@]}"
fi

# --------------------------------------------------------------------------
# 5. Every simulation of a package in a single run
# --------------------------------------------------------------------------
# This is the feature the project exists for ("can launch one or multiple
# simulations"): sub-packages included, one report per simulation, one JVM.
log "Test 5: all simulations of a package in one run"

all_results="${WORK_DIR}/results-all"
run_cli -p com.gatling.lab.simulation --all -rd "${all_results}"
assert_rc "${EXIT_OK}" "${cli_rc}" "run of the whole package"

if grep -qaE "Found simulations: ${EXPECTED_SIMULATIONS}\b" "${RUN_LOG}"; then
  pass "discovered ${EXPECTED_SIMULATIONS} simulations across the package tree"
else
  fail "expected 'Found simulations: ${EXPECTED_SIMULATIONS}'"
fi

mapfile -t all_reports < <(find "${all_results}" -mindepth 1 -maxdepth 1 -type d | sort)
if [[ "${#all_reports[@]}" -eq "${EXPECTED_SIMULATIONS}" ]]; then
  pass "one report per simulation (${#all_reports[@]})"
else
  fail "expected ${EXPECTED_SIMULATIONS} report directories, found ${#all_reports[@]}"
fi

for expected_report in basicsimulation basicsimulation1 basicsimulation2 basicsimulation3; do
  mapfile -t matched < <(find "${all_results}" -mindepth 1 -maxdepth 1 -type d -name "${expected_report}-*")
  if [[ "${#matched[@]}" -eq 1 ]]; then
    assert_report "${matched[0]}" "${expected_report}"
  else
    fail "expected exactly one report for ${expected_report}, found ${#matched[@]}"
  fi
done

assert_console_stats "${EXPECTED_SIMULATIONS}"

# Each simulation is forked into its own JVM; the runner's own log lines have to
# frame all of them, not just the first.
if [[ "$(grep -aco 'Start com.gatling.lab.simulation:' "${RUN_LOG}")" -eq "${EXPECTED_SIMULATIONS}" \
   && "$(grep -aco 'End com.gatling.lab.simulation:' "${RUN_LOG}")" -eq "${EXPECTED_SIMULATIONS}" ]]; then
  pass "the runner framed all ${EXPECTED_SIMULATIONS} simulations with start/end lines"
else
  fail "expected ${EXPECTED_SIMULATIONS} start and end lines from the runner"
fi

# The stub is the only server involved, so its access log is independent proof
# that the traffic really left the JVM.
stub_requests="$(grep -ac '" 200 -' "${STUB_LOG}" || true)"
expected_total=$(( EXPECTED_REQUESTS * (EXPECTED_SIMULATIONS + 1) ))
if [[ "${stub_requests}" -ge "${expected_total}" ]]; then
  pass "the stub served ${stub_requests} request(s)"
else
  fail "the stub served ${stub_requests} request(s), expected at least ${expected_total}"
fi

# --------------------------------------------------------------------------
log "Result"
if [[ "${failures}" -eq 0 ]]; then
  printf '    \033[32mAll e2e checks passed.\033[0m\n'
  exit 0
fi
printf '    \033[31m%d e2e check(s) failed.\033[0m\n' "${failures}"
exit 1
