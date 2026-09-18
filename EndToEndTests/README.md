# idb end-to-end tests

These tests run the `idb` CLI through `idb_companion` against a booted simulator. They cover app lifecycle, file transfers, screenshots, logs, URLs, permissions and accessibility. Tests check command output and, where available, compare results with `simctl` or files on the host. Tap and scroll tests verify the resulting navigation and visible elements. Wait tests cover existing elements, delayed navigation and timeout results.

## What the environment provides

| Variable | Meaning |
|---|---|
| `IDB_BIN` | the `idb` client to drive |
| `IDB_ARGS` | optional root arguments inserted before `--companion` |
| `IDB_SETUP_BIN` | optional client used only to prepare fixtures; defaults to `IDB_BIN` |
| `IDB_E2E_COMPANION_PATH` | the `idb_companion` binary, with its `Resources/` directory beside it |
| `IDB_E2E_RECORDER_PATH` | the built `sim-video` binary |
| `IDB_E2E_SUITE_CAPABILITY` | optional suite scope and companion readiness: `companion-process`, `accessibility-read`, or `accessibility-interaction` (the default) |
| `DEVICE_UDID` | the booted simulator to test against |
| `DEVICE_SET_PATH` | the device set `DEVICE_UDID` lives in |
| `IDB_E2E_STRICT` | `1` fails tests when `SimLaunchHostService` is unavailable; otherwise those tests skip |
| `IDB_E2E_RECORDER_ENCODING` | video encoding to record with: `h264`, `hevc`, `mjpeg`, or `auto` (the default, HEVC then JPEG) |

`IDB_BIN`, `IDB_E2E_COMPANION_PATH`, `IDB_E2E_RECORDER_PATH`, `DEVICE_UDID`, and `DEVICE_SET_PATH` are required. Everything the suite runs against is provided by its environment and none of it is discovered or defaulted, so missing variables, invalid binary paths, or a simulator that is not booted fail setup rather than skipping or selecting another target.

Use a dedicated simulator. Tests install and remove `ReplHost.app`, change its permissions and files, and launch or terminate Settings and Safari. Cleanup removes the fixture app and stops test apps; it does not restore pre-existing app state. The suite does not boot, shut down, erase or delete the simulator.

Service mutation tests also invoke the bundled guest directly. Its `dynamic-store` service snapshots and restores raw configd keys as property lists, so DNS and proxy tests put back the complete original value or its absence, retaining the original binary snapshot for restoration.

The harness starts one companion per test process with `DEVICE_SET_PATH` and a private Unix socket. Every CLI command connects to it with `--companion`. `companion-process` requires only the companion's readiness report; both accessibility capabilities additionally wait for an accessibility read through the selected client. If the companion exits, the current test reports the failure and the remaining tests stop.

Cases derive from `unittest.IsolatedAsyncioTestCase` and every `idb` invocation is awaited, so a test can read from a command that is still running rather than only inspect one that has already exited. That is what the streaming commands need. The companion is the exception: it outlives any single test, and each test gets its own event loop, so it stays on a plain subprocess.

Commands that report an unavailable `SimLaunchHostService` skip by default. Set `IDB_E2E_STRICT=1` to treat these errors as failures, as GitHub CI does.

## Running locally

From the source directory on macOS, build the distribution and provision a dedicated simulator:

```
./build.sh build all
pip install .
export DEVICE_SET_PATH="$(mktemp -d /tmp/idb-e2e-devices.XXXXXX)"
export DEVICE_UDID="$(xcrun simctl --set "$DEVICE_SET_PATH" create e2e "iPhone 16")"
xcrun simctl --set "$DEVICE_SET_PATH" boot "$DEVICE_UDID"
xcrun simctl --set "$DEVICE_SET_PATH" bootstatus "$DEVICE_UDID"
IDB_BIN="$(command -v idb)" \
IDB_E2E_COMPANION_PATH="$PWD/Build/Distribution/idb_companion" \
IDB_E2E_RECORDER_PATH="$PWD/Build/Distribution/sim-video" \
python3 -m unittest discover -s EndToEndTests -t . -v
```

Choose an iPhone model supported by your installed runtime. After testing, shut down and delete the simulator you created:

```sh
xcrun simctl --set "$DEVICE_SET_PATH" shutdown "$DEVICE_UDID"
xcrun simctl --set "$DEVICE_SET_PATH" delete "$DEVICE_UDID"
```

The CI scripts and harness tests need only Python and run without a simulator:

```sh
python3 -m unittest discover -s CI -p '*_tests.py' -t . -v
python3 -m unittest EndToEndTests.harness_tests EndToEndTests.documentation_tests -v
```

`harness_tests.py` and `documentation_tests.py` are named separately from `test_*.py` so e2e discovery does not include them. In GitHub CI, the `pure-python` job runs these tests; `mac-end-to-end` builds on the companion artifact, provisions a simulator through `CI.provision_simulator`, runs the e2e suite in strict mode, and collects diagnostics on success and failure.

The harness writes companion logs to `IDB_E2E_ARTIFACTS_DIR`, falling back to `TEST_RESULT_ARTIFACTS_DIR` when available. Without either directory, logs stay at `/tmp/idb-e2e-*/companion.log`. The collector reads both layouts; `--artifacts-dir` overrides its artifact source without changing `--output`.

## Recordings and diagnostics

The harness starts one `sim-video` process alongside the companion. It uses the default variable frame rate to record when the screen or overlays change, with padded bars for the active test and command, and adds a chapter at each test boundary. A timestamped JSON-lines trace preserves full test names, commands, exit codes, timing and final test results, including cleanup failures. Screenshots are captured before test cleanup.

Recording tries hardware HEVC first, then JPEG with software encoding allowed if HEVC cannot produce frames. If neither produces frames, the recorder log explains the failure, the command trace continues, and screenshots are attempted through idb. A missing or non-executable recorder path fails setup.

The recorder finalizes before the companion stops at process exit. Successful recordings include a JSON report beside the recording, at the recording's own path with `.json` appended. A hard kill can prevent finalization. JPEG/MOV is readable by AVFoundation; browser playback support varies.

The container follows the encoding, because the recorder takes the container from the output's extension and rejects a pair it cannot write: `h264` and `hevc` are recorded as `.mp4`, `mjpeg` and `auto` as `.mov`.

All diagnostics use unique, flat names in `IDB_E2E_ARTIFACTS_DIR`, falling back to `TEST_RESULT_ARTIFACTS_DIR` or the companion's local `/tmp/idb-e2e-*` directory. Both successful and failed runs retain companion and recorder logs, command traces, screenshots, and available video. The tool's commands and line protocol are documented in [Tools/VideoRecorder](../Tools/VideoRecorder/README.md).

## Documented demos

A few tests are also the source of the demos the website publishes. `documentation.py` holds the contract: `DOCUMENTED_DEMOS` maps each published slug to the test that performs it, and `@documented_demo` on that test declares the slug, title and summary. Declaring a slug the table does not publish, or declaring one the table attributes to a different test, raises as the suite is imported, so renaming or moving a documented test fails immediately rather than leaving the website describing a test that no longer exists.

The published name of a test is the one a checkout gives it, `EndToEndTests.<module>.<class>.<method>`. A build that imports these modules by repository path declares and records the same name, so one table serves both.

Within such a test, passing `step="..."` to `idb()` publishes that command as a step of the demo. Only named commands are published, so the accessibility polling a test does around them stays out of the transcript, and the published command is the one the test really ran rather than a copy of it in markdown. Capturing stops before cleanup, so the teardown screenshot and its binary output are never published. Only a command that runs to completion can be a step: the streaming commands are read while they are still running and have no final output to publish, so a demo names the commands around them.

Both the command and its output are normalised so two runs produce identical text. Each of the run's directories keeps its own placeholder — `$DEVICE_SET`, `$IDB_E2E_DIR`, `$IDB_E2E_ARTIFACTS`, `$TMPDIR`, `$HOME` — and the target udid, other UUIDs, timestamps, pids and addresses become placeholders too. Output is truncated past 4096 characters and says so. Output that is not UTF-8 is recorded as a length and a SHA-256 digest rather than embedded as bytes.

Demos are published as `h264`, the only encoding browsers agree on, by setting `IDB_E2E_RECORDER_ENCODING=h264`. Each demo is then cut out of that recording as a clip of its own, so a demo plays only itself: the clip opens a second before the first command the demo publishes and closes a second after its test finished, held inside that one test at both ends, and every offset in it is measured from the frame the recorder reports it captured first rather than from the moment the harness noticed the recorder was up.

`python3 -m CI.generate_documentation --artifacts-dir <dir> --output <dir> --recorder <sim-video>` turns a run's artifacts into the manifest and media the website reads. `--recorder`, defaulting to `$IDB_E2E_RECORDER_PATH`, names the `sim-video` that cuts each clip with `sim-video clip`: the tool that wrote the recording is the one certain to be on the machine that holds it. It enforces the other half of the contract: a slug the table publishes that this run did not perform, or performed and failed, means nothing is written and the command fails, so a broken demo blocks publication instead of leaving stale documentation up. A run without a playable recording still produces the transcript, as does a demo whose own clip could not be cut; a publishable recording that no demo could be cut out of fails the run, since that is the slicer missing or broken rather than one unlucky demo. A run with `IDB_E2E_READ_ONLY_CLIENT=1` documents a client the website is not about, so the generator refuses it outright.

CI runs that generator after the suite and uploads its output as the `documentation` artifact, and the website is deployed from a CI run that succeeded, at the commit that run tested. The demos on the site are therefore always the ones the code being documented actually performed.
