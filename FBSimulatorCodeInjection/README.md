# FBSimulatorCodeInjection

Injects Swift into a process on an iOS Simulator. It is the Simulator's REPL capability, added onto `Simulator` from outside `FBSimulatorControl`: a consumer that does not inject code does not link it, and one that does depends on this library.

`idb-repl` is one client: the companion's `repl` method uses this library for everything it does inside the Simulator, and adds only the gRPC stream in front.

## Using it

`simulator.codeInjection` is available on a `Simulator` once this library is imported. `inject(into:)` starts a host with the shim injected and returns a `CodeInjectionSession`, which runs compiled dylibs inside it:

```swift
import FBSimulatorCodeInjection

let session = try await simulator.codeInjection.inject(into: .application(bundleID: "com.example.App"))
let output = try await session.execute(dylibAtPath: "/tmp/payload.dylib", symbol: "payload_entry")
try await session.close()
```

- **Targets.** `.application(bundleID:reattach:)` launches an app with the shim injected, or with `reattach` joins one still serving a session; the app outlives the session. `.simulator` runs the shim in the Simulator's guest bridge, and `.logicTestBundle(path:)` in a logic-test bundle; both end with the session.
- **The entry point.** The host loads the dylib and calls `symbol`, an exported function that takes no arguments and returns a `malloc`'d C string, which the host frees. `execute` returns that string, or throws `CodeInjectionError.executionFailed` when the dylib does not load or the code reports failure.
- **Host commands.** Injected code can send bytes back to the session while it runs. `execute`'s optional `hostCommands` handler answers them; without one, each is refused.
- **Additional libraries.** `additionalLibraries` are loaded into the host alongside the shim before any code is injected, so injected code can call into them. `idb-repl` uses this for the idb command API.
- **The shim.** `.bundled`, the default, is the shim this library carries; `shim: .path(...)` supplies another. `launchEnvironment(forApplication:)` is the environment that arms an ordinary app launch the same way, so a later `inject(into: .application(bundleID:reattach: true))` joins it.

## What it provides

`simulator.repl` (`SimulatorReplCommands`) starts a REPL host with the `libRepl` shim injected. The shim is this library's resource: a bundle that links the library carries it, and the library finds it there or in the `Resources/` directory beside a standalone binary. The shim binds a control socket, and each method returns a `LaunchedRepl` that names it:

- **An app.** `startApp(bundleID:reuseSession:)` launches the app with the shim injected. The socket path is derived from the Simulator and the bundle id, so a later session can reattach to an app still running with the shim instead of relaunching it. `appLaunchEnvironment(bundleID:)` is the environment that arms an ordinary launch the same way.
- **The Simulator itself.** `startSimulator()` runs the shim inside the Simulator's guest bridge process.
- **A logic-test bundle.** `startTest(bundlePath:)` runs the shim's single test inside the bundle under the logic-test runner, which is why this library depends on [`FBSimulatorXCTest`](../FBSimulatorXCTest/README.md).

Each method takes `additionalLibraries`, which are loaded into the host alongside the shim before any code is injected, so injected code can call into them.

`ReplControlClient` speaks to the shim over that socket. `connect(path:timeout:)` waits for the shim to bind it, `readGreeting()` reads the interfaces the host advertises and where its run numbering stands, and `execute(dylibPath:symbol:hostCommandHandler:)` has the host `dlopen` a compiled dylib and call its entry point, returning the result. While the injected code runs it can send host commands back -- `ReplCommand`s such as a tap or a screenshot -- which the caller's handler answers. Closing the client ends the session.

`LaunchedRepl.waitForHostToFinish()` waits for the host once the control socket is closed: a test run or the guest process exits, and an app outlives the session.

## Seeing it work

`FBSimulatorCodeInjectionSmokeTests` drives the library the way a consumer outside idb does, against a booted Simulator and through its public API alone. It injects a small prebuilt Swift payload, [`CodeInjectionPayload.swift`](../Fixtures/Source/CodeInjectionPayload/CodeInjectionPayload.swift), whose entry points read state only code inside the process can know: the Simulator the process runs on and its bundle identifier, how many views Settings' windows hold, and a count that a later session reattaching to the app sees continue. The tests are [`CodeInjectionSmokeTests.swift`](../FBSimulatorCodeInjectionTests/Tests/Smoke/CodeInjectionSmokeTests.swift).

Compiling the code to inject is the caller's: `idb-repl` compiles it on the client side with `ReplCompiler` and sends the dylib to the companion, which writes it where the Simulator can read it and executes it through this library.
