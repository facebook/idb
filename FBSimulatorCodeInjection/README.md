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

## Microphone injection

The library's second injection mechanism plays audio into a Simulator app's microphone input, through the same shim's audio interposer rather than its REPL. `simulator.audioInjection.appLaunchEnvironment(_:)` arms an app launch by inserting `libShimulator-iOS.dylib` into it, and `inject(from:)` then plays a 16-bit PCM WAV file into every armed app that is recording, returning when playback finishes. Failures are `AudioInjectionError`s. An app that is already running cannot be armed without a relaunch.

## Camera injection

The third plays a video into the cameras of Simulator apps, through the same shim's virtual camera. `simulator.videoInjection.inject(back:front:loop:onUpdate:)` serves the shim's `video` capability: it copies the videos beside the Simulator's socket, reports the processes whose cameras are showing them, and returns once one has shown the whole video, or runs until cancelled with `loop`. While it runs, `appLaunchEnvironment(_:)` arms an app launch that microphone injection has already given the shim, so apply it after `audioInjection`'s. Failures are `VideoInjectionError`s. Ending the injection returns every armed camera to its idle pattern.

## How it works

The shim, `libShimulator` (the one idb injects for XCTest and audio injection too, each part inert unless armed), is this library's resource: a bundle that links the library carries it, and the library finds it there or in the `Resources/` directory beside a standalone binary. It is injected into the host with `DYLD_INSERT_LIBRARIES` for an app, loaded by the guest bridge for the Simulator, and injected by the logic-test runner for a test bundle, which is why this library depends on [`FBSimulatorXCTest`](../FBSimulatorXCTest/README.md).

Inside the host, the shim binds a Unix-domain control socket and serves one connection at a time. On connect it greets the session with the host's session id and the interfaces it generated; each execute loads a dylib and calls its entry point, and a host command the injected code sends while it runs travels back over the same socket and waits for its answer. An app's socket path is derived from the Simulator and the bundle id, so a later session can find an app still serving one.

## Seeing it work

`FBSimulatorCodeInjectionSmokeTests` drives the library the way a consumer outside idb does, against a booted Simulator and through its public API alone. It injects a small prebuilt Swift payload, [`CodeInjectionPayload.swift`](../Fixtures/Source/CodeInjectionPayload/CodeInjectionPayload.swift), whose entry points read state only code inside the process can know: the Simulator the process runs on and its bundle identifier, how many views Settings' windows hold, and a count that a later session reattaching to the app sees continue. The tests are [`CodeInjectionSmokeTests.swift`](../FBSimulatorCodeInjectionTests/Tests/Smoke/CodeInjectionSmokeTests.swift).

Compiling the code to inject is the caller's: `idb-repl` compiles it on the client side with `ReplCompiler` and sends the dylib to the companion, which writes it where the Simulator can read it and executes it through this library.
