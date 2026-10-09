# FBSimulatorXCTest

Runs XCTest bundles on an iOS Simulator. It is the Simulator's test capability, added onto `Simulator` from outside `FBSimulatorControl`: a consumer that does not run tests does not link [`FBXCTestCore`](../FBXCTestCore/README.md), and one that does depends on this library.

It conforms `Simulator` to `FBXCTestCore`'s `LogicTestTarget`, so the test runners in `FBXCTestCore` can drive a Simulator the same way they drive a device or the local Mac.

## What it provides

- **Application and UI tests.** `SimulatorXCTestCommands` connects to the Simulator's `testmanagerd` over the unix socket the Simulator advertises, and runs a test bundle inside an app host, reporting through an `XCTestReporter`.
- **Logic tests.** A logic test runs the `xctest` binary directly inside the Simulator, without an app host. The `subprocessLauncher` this library provides spawns it there.

How idb runs tests, and the differences between the three modes, are described in [the test execution documentation](https://www.fbidb.io/idb/test-execution).
