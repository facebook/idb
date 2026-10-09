# FBSimulatorCodeInjection

Injects Swift into a process on an iOS Simulator. It is the Simulator's REPL capability, added onto `Simulator` from outside `FBSimulatorControl`: a consumer that does not inject code does not link it, and one that does depends on this library.

`idb-repl` is one client: the companion's `repl` method uses this library for everything it does inside the Simulator, and adds only the gRPC stream in front.

## What it provides

`simulator.repl` (`SimulatorReplCommands`) starts a REPL host with the `libRepl` shim injected. The shim binds a control socket, and each method returns a `LaunchedRepl` that names it:

- **An app.** `startApp(bundleID:reuseSession:)` launches the app with the shim injected. The socket path is derived from the Simulator and the bundle id, so a later session can reattach to an app still running with the shim instead of relaunching it. `appLaunchEnvironment(bundleID:)` is the environment that arms an ordinary launch the same way.
- **The Simulator itself.** `startSimulator()` runs the shim inside the Simulator's guest bridge process.
- **A logic-test bundle.** `startTest(bundlePath:)` runs the shim's single test inside the bundle under the logic-test runner, which is why this library depends on [`FBSimulatorXCTest`](../FBSimulatorXCTest/README.md).

Each method takes `additionalLibraries`, which are loaded into the host alongside the shim before any code is injected, so injected code can call into them.

`ReplControlClient` speaks to the shim over that socket. `connect(path:timeout:)` waits for the shim to bind it, `readGreeting()` reads the interfaces the host advertises and where its run numbering stands, and `execute(dylibPath:symbol:hostCommandHandler:)` has the host `dlopen` a compiled dylib and call its entry point, returning the result. While the injected code runs it can send host commands back -- `ReplCommand`s such as a tap or a screenshot -- which the caller's handler answers. Closing the client ends the session.

`LaunchedRepl.waitForHostToFinish()` waits for the host once the control socket is closed: a test run or the guest process exits, and an app outlives the session.

Compiling the code to inject is the caller's: `idb-repl` compiles it on the client side with `ReplCompiler` and sends the dylib to the companion, which writes it where the Simulator can read it and executes it through this library.
