# FBSimulatorCodeInjection

Injects Swift into a process on an iOS Simulator. It is the Simulator's REPL capability, added onto `Simulator` from outside `FBSimulatorControl`: a consumer that does not inject code does not link it, and one that does depends on this library.

`idb-repl` is one client: the companion's `repl` method uses this library for everything it does inside the Simulator, and adds only the gRPC stream in front.

## What it provides

`simulator.repl` (`SimulatorReplCommands`) starts a REPL host with the `libRepl` shim injected. The shim binds a control socket, and each method returns a `LaunchedRepl` that names it:

- **An app.** `startApp(bundleID:reuseSession:)` launches the app with the shim injected. The socket path is derived from the Simulator and the bundle id, so a later session can reattach to an app still running with the shim instead of relaunching it. `appLaunchEnvironment(bundleID:)` is the environment that arms an ordinary launch the same way.
- **The Simulator itself.** `startSimulator()` runs the shim inside the Simulator's guest bridge process.
- **A logic-test bundle.** `startTest(bundlePath:)` runs the shim's single test inside the bundle under the logic-test runner, which is why this library depends on [`FBSimulatorXCTest`](../FBSimulatorXCTest/README.md).

`LaunchedRepl.waitForHostToFinish()` waits for the host once the control socket is closed: a test run or the guest process exits, and an app outlives the session.
