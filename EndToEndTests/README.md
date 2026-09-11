# idb end-to-end tests

These tests run the `idb` CLI through `idb_companion` against a booted simulator. They cover app lifecycle, file transfers, screenshots, logs, URLs, permissions and accessibility. Tests check command output and, where available, compare results with `simctl` or files on the host. Tap and scroll tests check command success but do not yet verify the resulting UI.

## What the environment provides

| Variable | Meaning |
|---|---|
| `IDB_BIN` | the `idb` client to drive |
| `IDB_ARGS` | optional root arguments inserted before `--companion` |
| `IDB_COMPANION_PATH` | the `idb_companion` binary, with its `Resources/` directory beside it |
| `DEVICE_UDID` | the booted simulator to test against |
| `DEVICE_SET_PATH` | the device set `DEVICE_UDID` lives in |
| `IDB_E2E_STRICT` | `1` fails tests when `SimLaunchHostService` is unavailable; otherwise those tests skip |

The first four variables are required. Missing variables, invalid binary paths and a simulator that is not booted fail setup.

Use a dedicated simulator. Tests install and remove `ReplHost.app`, change its permissions and files, and launch or terminate Settings and Safari. Cleanup removes the fixture app and stops test apps; it does not restore pre-existing app state. The suite does not boot, shut down, erase or delete the simulator.

The harness starts one companion per test process with `DEVICE_SET_PATH` and a private Unix socket. Every CLI command connects to it with `--companion`. Setup waits for accessibility reads to become available. If the companion exits, the current test reports the failure and the remaining tests stop.

Tests use `unittest.IsolatedAsyncioTestCase` to read streaming commands while they run. The companion uses `subprocess.Popen` so it can survive the event loop being replaced between tests.

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
IDB_COMPANION_PATH="$PWD/Build/Distribution/idb_companion" \
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

`harness_tests.py` is named separately from `test_*.py` so e2e discovery does not include it. In GitHub CI, the `pure-python` job runs these tests; `mac-end-to-end` builds on the companion artifact, provisions a simulator through `CI.provision_simulator`, runs the e2e suite in strict mode, and collects diagnostics on failure.
