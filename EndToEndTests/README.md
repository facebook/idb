# idb end-to-end tests

These tests drive the `idb` client, through an `idb_companion`, against a booted simulator. They are the check that the client, the gRPC contract and the companion agree with each other on a real target, one thin pass per command domain. Framework behaviour belongs to the `FBSimulatorControl` test suites; client parsing belongs to the python unit tests. This suite only asserts what a user of the CLI can observe: exit status, output shape, and side effects cross-checked against `xcrun simctl`.

## What the environment provides

| Variable | Meaning |
|---|---|
| `IDB_BIN` | the `idb` client to drive |
| `IDB_COMPANION_PATH` | the `idb_companion` binary, with its `Resources/` directory beside it |
| `DEVICE_UDID` | the booted simulator to test against |
| `DEVICE_SET_PATH` | the device set `DEVICE_UDID` lives in |
| `IDB_E2E_STRICT` | `1` makes a capability gap a failure instead of a skip |

The first four are required. Everything the suite runs against is provided by its environment and none of it is discovered or defaulted, so a missing variable is an error rather than a skip. A suite that quietly fell back to whatever else happened to be booted would be testing something other than the target it was pointed at.

The suite never boots a simulator. Whoever runs it boots one first, and the tests treat it as a leased resource: anything a test changes it restores, and nothing here shuts down, erases or deletes the simulator.

The harness starts one companion for the simulator on a private unix socket, pointed at `DEVICE_SET_PATH`, and connects every command to it with `--companion`.

Cases derive from `unittest.IsolatedAsyncioTestCase` and every `idb` invocation is awaited, so a test can read from a command that is still running rather than only inspect one that has already exited. That is what the streaming commands need. The companion is the exception: it outlives any single test, and each test gets its own event loop, so it stays on a plain subprocess.

Some simulator hosts cannot spawn anything inside the guest (`SimLaunchHostService` is not running). The accessibility reads need that, and skip on such a host with the reason named. Set `IDB_E2E_STRICT=1` on a host that has no such gap so the suite fails rather than skips when something is wrong.

## Running locally

From a checkout with a built distribution and the client installed:

```
./build.sh build all
pip install .
export DEVICE_SET_PATH="$HOME/Library/Developer/CoreSimulator/Devices"
export DEVICE_UDID="$(xcrun simctl --set "$DEVICE_SET_PATH" create e2e "iPhone 16")"
xcrun simctl --set "$DEVICE_SET_PATH" boot "$DEVICE_UDID"
IDB_BIN="$(command -v idb)" \
IDB_COMPANION_PATH="$PWD/Build/Distribution/idb_companion" \
python3 -m unittest discover -s EndToEndTests -t . -v
```

A temporary device set works just as well, and keeps the tests away from simulators you use by hand: pass any directory as `DEVICE_SET_PATH` and create the simulator inside it.
