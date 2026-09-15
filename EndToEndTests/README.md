# idb end-to-end tests

These tests run the `idb` CLI through `idb_companion` against a booted simulator. They cover app lifecycle, file transfers, screenshots, logs, URLs, permissions and accessibility. Tests check command output and, where available, compare results with `simctl` or files on the host. Tap and scroll tests verify the resulting navigation and visible elements.

## What the environment provides

| Variable | Meaning |
|---|---|
| `IDB_BIN` | the `idb` client to drive |
| `IDB_ARGS` | optional root arguments inserted before `--companion` |
| `IDB_SETUP_BIN` | optional client used only to prepare fixtures; defaults to `IDB_BIN` |
| `IDB_E2E_COMPANION_PATH` | the `idb_companion` binary, with its `Resources/` directory beside it |
| `IDB_E2E_RECORDER_PATH` | the built `sim-video` binary |
| `DEVICE_UDID` | the booted simulator to test against |
| `DEVICE_SET_PATH` | the device set `DEVICE_UDID` lives in |
| `IDB_E2E_STRICT` | `1` fails tests when `SimLaunchHostService` is unavailable; otherwise those tests skip |

`IDB_BIN`, `IDB_E2E_COMPANION_PATH`, `IDB_E2E_RECORDER_PATH`, `DEVICE_UDID`, and `DEVICE_SET_PATH` are required. Everything the suite runs against is provided by its environment and none of it is discovered or defaulted, so missing variables, invalid binary paths, or a simulator that is not booted fail setup rather than skipping or selecting another target.

Use a dedicated simulator. Tests install and remove `ReplHost.app`, change its permissions and files, and launch or terminate Settings and Safari. Cleanup removes the fixture app and stops test apps; it does not restore pre-existing app state. The suite does not boot, shut down, erase or delete the simulator.

The harness starts one companion per test process with `DEVICE_SET_PATH` and a private Unix socket. Every CLI command connects to it with `--companion`. Setup waits for accessibility reads to become available. If the companion exits, the current test reports the failure and the remaining tests stop.

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
python3 -m unittest EndToEndTests.harness_tests -v
```

`harness_tests.py` is named separately from `test_*.py` so e2e discovery does not include it. In GitHub CI, the `pure-python` job runs these tests; `mac-end-to-end` builds on the companion artifact, provisions a simulator through `CI.provision_simulator`, runs the e2e suite in strict mode, and collects diagnostics on success and failure.

The harness writes companion logs to `IDB_E2E_ARTIFACTS_DIR`, falling back to `TEST_RESULT_ARTIFACTS_DIR` when available. Without either directory, logs stay at `/tmp/idb-e2e-*/companion.log`. The collector reads both layouts; `--artifacts-dir` overrides its artifact source without changing `--output`.

## Recordings and diagnostics

The harness starts one `sim-video` process alongside the companion. It records the simulator with padded bars for the active test and command, and adds a chapter at each test boundary. A timestamped JSON-lines trace preserves full test names, commands, exit codes, timing and final test results, including cleanup failures. Screenshots are captured before test cleanup.

Recording tries hardware HEVC first, then JPEG with software encoding allowed if HEVC cannot produce frames. If neither produces frames, the recorder log explains the failure, the command trace continues, and screenshots are attempted through idb. A missing or non-executable recorder path fails setup.

The recorder finalizes before the companion stops at process exit. Successful recordings include a `.mov.json` report written after AVFoundation decodes a frame and checks the duration. A hard kill can prevent finalization. JPEG/MOV is readable by AVFoundation; browser playback support varies.

All diagnostics use unique, flat names in `IDB_E2E_ARTIFACTS_DIR`, falling back to `TEST_RESULT_ARTIFACTS_DIR` or the companion's local `/tmp/idb-e2e-*` directory. Both successful and failed runs retain companion and recorder logs, command traces, screenshots, and available video. The tool's commands and line protocol are documented in [Tools/VideoRecorder](../Tools/VideoRecorder/README.md).
